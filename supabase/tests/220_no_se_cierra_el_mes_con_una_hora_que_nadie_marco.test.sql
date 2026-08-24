-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 220_no_se_cierra_el_mes_con_una_hora_que_nadie_marco.test.sql
-- ============================================================================
-- Cuando alguien olvida marcar su salida, el proceso automático cierra el día
-- con una hora que calcula el sistema. `fn_recalcular_jornada` se niega a medir
-- tardanza o salida temprana contra ella —«esa hora la inventó el sistema y
-- medir contra ella sería acusar con un dato falso», 0249— pero esa misma hora
-- entra a `horas_trabajadas` y de ahí al ciclo de 48 h que paga recargo.
--
-- Medido en producción el 2026-08-23: 49 auto-cierres en cinco semanas, 12 de
-- ellos anulados, y CERO sin revisar. O sea: hoy el agujero lo tapa una persona
-- que entra a Correcciones todos los días, no el sistema. Esta prueba fija que
-- lo tape el sistema.
--
-- El fixture pone la jornada en `auto_cerrada_pendiente` con un update directo
-- a propósito: lo que se prueba es el FRENO, que lee ese estado, no el proceso
-- que lo produce. La cadena marcaje → jornada ya la cubren otras pruebas.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000021900', 'ZZPEN', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000021901', 'PenAdmin', 'Lab',
        '00000000-0000-0000-0000-000000021900', 'admin', 'x',
        '00000000-0000-0000-0000-0000000219ff', '2024-01-01', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo)
values ('00000000-0000-0000-0000-000000021902', 'PenOlvida', 'Lab',
        '00000000-0000-0000-0000-000000021900', 'x', '2024-01-01', 'taller_produccion', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000021902', 'colibri', 1950, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-000000021902', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39,
        '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
          "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
          "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000219ff', true);

-- Dos días trabajados en el periodo A y uno en el B.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000021902', '00000000-0000-0000-0000-000000021900', 'entrada',      '2026-05-04T09:00:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000021902', '00000000-0000-0000-0000-000000021900', 'salida_final', '2026-05-04T15:30:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000021902', '00000000-0000-0000-0000-000000021900', 'entrada',      '2026-05-05T09:00:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000021902', '00000000-0000-0000-0000-000000021900', 'salida_final', '2026-05-05T15:30:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000021902', '00000000-0000-0000-0000-000000021900', 'entrada',      '2026-06-02T09:00:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000021902', '00000000-0000-0000-0000-000000021900', 'salida_final', '2026-06-02T15:30:00-05:00');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000002190a1', '2026-04-29', '2026-05-28', 'abierto'),
       ('00000000-0000-0000-0000-0000002190b1', '2026-05-29', '2026-06-28', 'abierto');

-- El día 04/05 queda con la salida puesta por la máquina y sin confirmar.
update jornadas set estado = 'auto_cerrada_pendiente'
 where persona_id = '00000000-0000-0000-0000-000000021902' and fecha = '2026-05-04';


-- ── 1 · El dato en el que se apoya el freno existe y cuenta bien ────────────

select is(
  (select (f->>'dias_pendientes')::int
     from jsonb_array_elements(
            fn_planilla_calcular('2026-04-29', '2026-05-28',
                                 '00000000-0000-0000-0000-0000002190a1')->'filas') f
    where (f->>'persona_id')::uuid = '00000000-0000-0000-0000-000000021902'),
  1,
  'El cálculo ya cuenta ese día como pendiente — el freno no necesita consulta nueva');


-- ── 2 a 4 · Con un día sin confirmar, el mes no cierra ──────────────────────

select throws_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002190a1', 'pago', null) $$,
  null, null,
  'Congelar se niega mientras haya una salida que puso el sistema y nadie confirmó');

select is(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-0000002190a1'),
  0,
  'Y no congela nada a medias: la foto del periodo sigue vacía');

select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-0000002190a1'),
  'abierto',
  'El periodo sigue ABIERTO, que es lo que promete el mensaje');


-- ── 5 · La puerta de arriba tampoco deja pasar ──────────────────────────────
-- fn_periodo_pagado congela antes de marcar pagado (0096), así que hereda el
-- freno. Si algún día dejara de llamarla, esta prueba lo dice.

select throws_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-0000002190a1', true) $$,
  null, null,
  'Marcar el periodo como pagado tampoco pasa: hereda el freno del congelado');


-- ── 6 · El mensaje nombra a quién hay que ir a buscar ───────────────────────

select throws_like(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002190a1', 'pago', null) $$,
  '%PenOlvida%',
  'El mensaje dice de quién es el día, no solo que hay uno');


-- ── 7 · Confirmado el día, el mes cierra con normalidad ─────────────────────

update jornadas set estado = 'revisada'
 where persona_id = '00000000-0000-0000-0000-000000021902' and fecha = '2026-05-04';

select lives_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002190a1', 'pago', null) $$,
  'Confirmada la salida, el freno se levanta y el periodo cierra');


-- ── 8 · La foto retroactiva NO se frena ─────────────────────────────────────
-- Es la lección de la 0244: abortar en 'retroactivo' rompe
-- fn_planilla_congelar_pendientes y deja los periodos históricos sin foto para
-- siempre. Acá solo avisa.

update jornadas set estado = 'auto_cerrada_pendiente'
 where persona_id = '00000000-0000-0000-0000-000000021902' and fecha = '2026-06-02';

select lives_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002190b1', 'retroactivo', null) $$,
  'Una foto retroactiva con días sin revisar avisa pero no aborta: si no, no habría historia');


select * from finish();
rollback;
