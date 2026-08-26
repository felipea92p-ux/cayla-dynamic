-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 240_el_descanso_medico_y_la_maternidad_exigen_aprobacion.test.sql
-- ============================================================================
-- fn_planilla_calcular pagaba descanso_medico y maternidad mirando solo
-- `anulada_at is null` — nunca `aprobada_at`. fn_aprobar_ausencia existe
-- justo para que Desarrollo Organizacional sea quien decide qué convierte
-- días en plata; antes de la 0306, esa función no gobernaba nada: el registro
-- de la encargada de sede ya pagaba.
--
-- Esto fija el arreglo de la 0306, y sus dos mitades:
--   · sin aprobación, no se paga (dmd y mat, en fn_planilla_calcular);
--   · sin aprobación, el feriado de DENTRO tampoco se pierde: sigue
--     prorrateándose por `fer` (fn_feriado_devengado) como cualquier día
--     normal, hasta que la aprobación lo pasa a cubrir el subsidio. Si esta
--     segunda mitad faltara, el día quedaría sin pagar por nadie — el mismo
--     defecto que ya mordió tres veces (0276, 0286, 0293).
--
-- La prueba sigue el viaje completo: registra sin aprobar, mide que no paga,
-- aprueba con fn_aprobar_ausencia (la RPC real, no un UPDATE a mano), y mide
-- que a partir de ahí sí paga — sin tocar a quien nunca se aprobó.
-- ============================================================================
begin;
select plan(20);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000901', 'ZZAP', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000902', 'ApAdmin', 'Lab',
        '00000000-0000-0000-0000-000000000901', 'admin', 'x',
        '00000000-0000-0000-0000-0000000009ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000000903', 'DmSinAprobar',  'Lab', '00000000-0000-0000-0000-000000000901', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000904', 'DmAprobada',    'Lab', '00000000-0000-0000-0000-000000000901', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000905', 'MatSinAprobar', 'Lab', '00000000-0000-0000-0000-000000000901', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000906', 'MatAprobada',   'Lab', '00000000-0000-0000-0000-000000000901', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-000000000907', 'ApControl',     'Lab', '00000000-0000-0000-0000-000000000901', 'x', '2024-01-01', 'taller_produccion', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1300, '2024-01-01' from personas
 where apellidos = 'Lab' and nombres like any(array['DmSinAprobar','DmAprobada','MatSinAprobar','MatAprobada','ApControl']);

-- Lunes a sábado. El domingo no es laborable.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39
from personas where apellidos = 'Lab'
 and nombres in ('DmSinAprobar','DmAprobada','MatSinAprobar','MatAprobada','ApControl');

-- El feriado que cae DENTRO de la licencia de maternidad: el nudo del caso 2.
insert into feriados (fecha, nombre) values ('2026-08-06', 'Batalla de Junín')
on conflict do nothing;

-- Descanso médico de cinco días — SIN aprobar las dos, a propósito: la
-- diferencia entre DmSinAprobar y DmAprobada nace después, con
-- fn_aprobar_ausencia, no con el registro.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000000903', 'descanso_medico', '2026-08-17', '2026-08-21', 'lab', '00000000-0000-0000-0000-000000000902'),
  ('00000000-0000-0000-0000-000000000904', 'descanso_medico', '2026-08-17', '2026-08-21', 'lab', '00000000-0000-0000-0000-000000000902');

-- Maternidad de diez días con subsidio ya entrado por DO — SIN aprobar las
-- dos. El feriado del 06/08 cae dentro de la licencia de las dos.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, subsidio_diario) values
  ('00000000-0000-0000-0000-000000000905', 'maternidad', '2026-08-01', '2026-08-10', 'lab', '00000000-0000-0000-0000-000000000902', 200.00),
  ('00000000-0000-0000-0000-000000000906', 'maternidad', '2026-08-01', '2026-08-10', 'lab', '00000000-0000-0000-0000-000000000902', 200.00);

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-000000000901', '2026-07-29', '2026-08-28', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000009ff', true);

-- Las cinco marcan EXACTAMENTE los mismos tres días, después de las dos
-- ausencias. Así ApControl, MatSinAprobar y MatAprobada llegan al cálculo del
-- feriado con la MISMA base de horas — la única diferencia posible es la
-- aprobación de la licencia.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-000000000901', m.tipo, m.ts
from personas p,
     (values ('entrada'::tipo_marca,      timestamptz '2026-08-12T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-12T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-13T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-13T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-14T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-14T15:30:00-05:00')) m(tipo, ts)
where p.apellidos = 'Lab' and p.nombres like any(array['DmSinAprobar','DmAprobada','MatSinAprobar','MatAprobada','ApControl']);

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- ── ANTES DE APROBAR: nada de esto paga ─────────────────────────────────────

-- 1 y 2 · El descanso médico sin aprobar no cuenta días ni paga.
select is((pg_temp.fila('DmSinAprobar Lab')->>'dias_descanso_medico_pagados')::int, 0,
  'sin aprobar, el descanso médico no cuenta ni un día');
select is((pg_temp.fila('DmSinAprobar Lab')->>'monto_descanso_medico')::numeric, 0.00,
  'sin aprobar, el descanso médico no paga nada');

-- 3 y 4 · DmAprobada, ANTES de aprobarla, está en la misma situación: la
--     diferencia todavía no existe, porque todavía no se aprobó nada.
select is((pg_temp.fila('DmAprobada Lab')->>'dias_descanso_medico_pagados')::int, 0,
  'antes de aprobar, tampoco cuenta días — el registro solo no basta');
select is((pg_temp.fila('DmAprobada Lab')->>'monto_descanso_medico')::numeric, 0.00,
  'antes de aprobar, tampoco paga — el registro solo no basta');

-- 5 y 6 · La maternidad sin aprobar tampoco paga el subsidio.
select is((pg_temp.fila('MatSinAprobar Lab')->>'dias_subsidio_maternidad')::int, 0,
  'sin aprobar, la maternidad no cuenta días de subsidio');
select is((pg_temp.fila('MatSinAprobar Lab')->>'monto_subsidio_maternidad')::numeric, 0.00,
  'sin aprobar, la maternidad no paga el subsidio');
select is((pg_temp.fila('MatAprobada Lab')->>'monto_subsidio_maternidad')::numeric, 0.00,
  'antes de aprobar, la otra tampoco — mismo registro, mismo cero');

-- 7, 8 y 9 · Y EL PUNTO QUE MÁS FÁCIL SE ROMPE: el feriado de DENTRO de la
--     licencia sin aprobar NO desaparece. Sigue prorrateándose por `fer` como
--     si la licencia no existiera — exactamente igual que ApControl, que no
--     tiene ninguna ausencia. Si esto fallara, el día quedaría sin pagar por
--     nadie: ni el subsidio (sin aprobar) ni el feriado (excluido de más).
select is((pg_temp.fila('MatSinAprobar Lab')->>'monto_feriados')::numeric,
          (pg_temp.fila('ApControl Lab')->>'monto_feriados')::numeric,
  'con la licencia sin aprobar, el feriado de dentro se paga igual que si no hubiera licencia');
select is((pg_temp.fila('MatAprobada Lab')->>'monto_feriados')::numeric,
          (pg_temp.fila('ApControl Lab')->>'monto_feriados')::numeric,
  'la otra igual: antes de aprobar, las dos cobran el feriado completo');
select cmp_ok((pg_temp.fila('ApControl Lab')->>'monto_feriados')::numeric, '>', 0::numeric,
  'y ese feriado compartido vale algo — si no, las igualdades de arriba no probarían nada');

-- ── SE APRUEBAN, CON LA RPC REAL — no con un update a mano ──────────────────
select lives_ok(
  $$select fn_aprobar_ausencia((select id from ausencias
     where persona_id = '00000000-0000-0000-0000-000000000904' and tipo = 'descanso_medico'))$$,
  'DO aprueba el descanso médico con fn_aprobar_ausencia');

select lives_ok(
  $$select fn_aprobar_ausencia((select id from ausencias
     where persona_id = '00000000-0000-0000-0000-000000000906' and tipo = 'maternidad'))$$,
  'DO aprueba la maternidad con fn_aprobar_ausencia');

-- ── DESPUÉS DE APROBAR: paga quien se aprobó, nadie más ─────────────────────

-- 12 · DmSinAprobar sigue en cero: aprobar a otra persona no le paga la suya.
select is((pg_temp.fila('DmSinAprobar Lab')->>'dias_descanso_medico_pagados')::int, 0,
  'quien nunca se aprobó sigue sin cobrar, después de aprobar a otra persona');

-- 13 y 14 · DmAprobada, ahora sí, cobra.
select cmp_ok((pg_temp.fila('DmAprobada Lab')->>'dias_descanso_medico_pagados')::int, '>', 0,
  'aprobada con fn_aprobar_ausencia, el descanso médico ya cuenta días');
select cmp_ok((pg_temp.fila('DmAprobada Lab')->>'monto_descanso_medico')::numeric, '>', 0::numeric,
  'aprobada con fn_aprobar_ausencia, el descanso médico ya paga');

-- 15 · MatSinAprobar sigue sin cobrar el subsidio.
select is((pg_temp.fila('MatSinAprobar Lab')->>'monto_subsidio_maternidad')::numeric, 0.00,
  'la maternidad que nunca se aprobó sigue sin subsidio');

-- 16 y 17 · MatAprobada, ahora sí, cobra el subsidio.
select cmp_ok((pg_temp.fila('MatAprobada Lab')->>'dias_subsidio_maternidad')::int, '>', 0,
  'aprobada, la maternidad ya cuenta días de subsidio');
select cmp_ok((pg_temp.fila('MatAprobada Lab')->>'monto_subsidio_maternidad')::numeric, '>', 0::numeric,
  'aprobada, la maternidad ya paga el subsidio');

-- 18 · Y AHORA SÍ el feriado de dentro deja de devengarse por `fer` — lo cubre
--     el subsidio, y el otro lado de la guarda (fn_feriado_devengado) tiene
--     que haber aprendido la misma aprobación o este número no baja.
select cmp_ok((pg_temp.fila('MatAprobada Lab')->>'monto_feriados')::numeric, '<',
              (pg_temp.fila('ApControl Lab')->>'monto_feriados')::numeric,
  'aprobada, el feriado de dentro deja de pagarse por fer — ya lo cubre el subsidio');

-- 19 · Y quien nunca se aprobó lo sigue cobrando entero, sin cambios.
select is((pg_temp.fila('MatSinAprobar Lab')->>'monto_feriados')::numeric,
          (pg_temp.fila('ApControl Lab')->>'monto_feriados')::numeric,
  'quien nunca se aprobó sigue cobrando el feriado completo, sin cambios');

select * from finish();
rollback;
