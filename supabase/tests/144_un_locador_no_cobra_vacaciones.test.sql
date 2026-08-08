-- ============================================================================
-- 144_un_locador_no_cobra_vacaciones.test.sql
-- ============================================================================
-- La 0177 arregló que un día de vacaciones se pagara como día trabajado. Al
-- hacerlo abrió un agujero que antes no podía existir: el bloque que acredita
-- esos días comprueba que exista el registro y que ese día tocara trabajar, y
-- NO mira el vínculo. Antes daba igual —valían S/0 para todo el mundo—; después,
-- un locador con vacaciones registradas cobra.
--
-- Medido en producción el 2026-08-08: Carlos Espejo, `rxh`, `en_planilla` false,
-- con siete días dentro del periodo que se paga el 28/08. Contra el Postgres
-- local, con un locador idéntico: S/858.83 contra S/426.92 — S/431.91 de más.
--
-- Lo caro no son los S/431: es que la planilla del periodo dejaría ESCRITO un
-- pago de vacaciones a un asesor por honorarios. Pagar un beneficio laboral es
-- un indicio de subordinación más fuerte que el cargo, el área o el rango.
--
-- Este archivo fija las dos mitades del arreglo y —lo que más importa— que el
-- caso legítimo siga cobrando: una prueba que solo comprobara «el locador cobra
-- cero» pasaría también si alguien apagara las vacaciones para todo el mundo.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000010c0', 'ZZLOC', 'Lab', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000010ca', 'AdminLoc', 'Lab',
        '00000000-0000-0000-0000-0000000010c0', 'admin', 'h',
        '00000000-0000-0000-0000-0000000010cb', '2020-01-01');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000010c1', 'Locadora', 'Lab',
   '00000000-0000-0000-0000-0000000010c0', 'h', '2024-01-01', 'rxh'),
  ('00000000-0000-0000-0000-0000000010c2', 'Trabajadora', 'Lab',
   '00000000-0000-0000-0000-0000000010c0', 'h', '2024-01-01', 'planilla');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000010cb', true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'cayla', 1500.00, '2024-01-01'
from unnest(array['00000000-0000-0000-0000-0000000010c1'::uuid,
                  '00000000-0000-0000-0000-0000000010c2'::uuid]) p;

insert into horarios_asignados (persona_id, vigente_desde, dias_laborables, hora_entrada, hora_salida)
select p, '2024-01-01', '{1,2,3,4,5,6}', '09:00', '18:00'
from unnest(array['00000000-0000-0000-0000-0000000010c1'::uuid,
                  '00000000-0000-0000-0000-0000000010c2'::uuid]) p;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000010cf', '2026-07-29', '2026-08-28', 'abierto');

insert into marcajes (client_uuid, persona_id, tipo, timestamp_marca, sede_id)
select gen_random_uuid(), p, t.tipo::tipo_marca, (d.d + t.h)::timestamptz,
       '00000000-0000-0000-0000-0000000010c0'
from unnest(array['00000000-0000-0000-0000-0000000010c1'::uuid,
                  '00000000-0000-0000-0000-0000000010c2'::uuid]) p
cross join generate_series(date '2026-07-29', date '2026-08-03', interval '1 day') d(d)
cross join (values ('entrada','09:00'::time),('salida_final','18:00'::time)) t(tipo,h)
where extract(dow from d.d)::int <> 0;


-- ── El candado de la base ──────────────────────────────────────────────────
select throws_ok(
  $$insert into vacaciones (persona_id, fecha_inicio, fecha_fin, observacion, creado_por)
    values ('00000000-0000-0000-0000-0000000010c1','2026-08-04','2026-08-10','x',
            '00000000-0000-0000-0000-0000000010ca')$$,
  '23514', null,
  'CANDADO · a un «rxh» la base no deja registrarle vacaciones');

select lives_ok(
  $$insert into vacaciones (persona_id, fecha_inicio, fecha_fin, observacion, creado_por)
    values ('00000000-0000-0000-0000-0000000010c2','2026-08-04','2026-08-10','x',
            '00000000-0000-0000-0000-0000000010ca')$$,
  'CANDADO · a quien está en planilla sí, que es de quien son las vacaciones');

-- El candado es SOLO para vacaciones. Saber quién no vino es operación, no un
-- beneficio: si esto se rompiera, DO se quedaría sin poder anotar un permiso.
select lives_ok(
  $$insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por)
    values ('00000000-0000-0000-0000-0000000010c1','permiso_personal','2026-08-20','2026-08-20','x',
            '00000000-0000-0000-0000-0000000010ca')$$,
  'SOLO VACACIONES · un permiso sí se le puede registrar a un locador');

select ok(
  (select count(*) from pg_trigger
    where tgname = 'trg_ausencia_solo_planilla' and not tgisinternal) = 1,
  'EXISTE · el candado vive en la base, no en una pantalla que se puede saltar');


-- ── Y lo que de verdad se estaba pagando ───────────────────────────────────
-- Los registros de la locadora entran por debajo del trigger, igual que
-- entraron los de Carlos antes de que el candado existiera. Ese es el caso real
-- que hay que cubrir: filas que YA están.
set session_replication_role = replica;
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por)
values ('00000000-0000-0000-0000-0000000010c1','vacaciones','2026-08-04','2026-08-10','ya estaba',
        '00000000-0000-0000-0000-0000000010ca');
set session_replication_role = origin;

create temp table pl as
select f from jsonb_array_elements(
  fn_planilla_calcular('2026-07-29','2026-08-28','00000000-0000-0000-0000-0000000010cf') -> 'filas') f;

select is(
  (select (f->>'dias_vacaciones_pagados')::int from pl
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000010c1'),
  0,
  'LOCADORA · cero días de vacaciones pagados, aunque el registro exista');

select is(
  (select (f->>'monto_vacaciones')::numeric from pl
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000010c1'),
  0::numeric,
  'LOCADORA · y cero soles por ellos');

-- La que impide «arreglarlo» apagando las vacaciones para todo el mundo.
select cmp_ok(
  (select (f->>'dias_vacaciones_pagados')::int from pl
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000010c2'),
  '>', 0,
  'TRABAJADORA · sigue cobrando los suyos: el arreglo no apagó la 0177');

select cmp_ok(
  (select (f->>'monto_vacaciones')::numeric from pl
    where f->>'persona_id' = '00000000-0000-0000-0000-0000000010c2'),
  '>', 0::numeric,
  'TRABAJADORA · y con monto, no solo días');

-- El registro histórico no se toca. Borrarlo no cambia lo que pasó y destruye
-- lo que alguien va a necesitar para explicarlo.
select is(
  (select count(*)::int from ausencias
    where persona_id = '00000000-0000-0000-0000-0000000010c1' and tipo = 'vacaciones'),
  1,
  'HISTORIA · el registro que ya existía sigue ahí: se cortó el pago, no el dato');

select * from finish();
rollback;
