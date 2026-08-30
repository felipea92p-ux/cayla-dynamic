-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 258_un_marcaje_sin_revisar_tampoco_cierra_el_mes.test.sql — 0326
-- ============================================================================
-- `pendiente_revision` (0001) vive en `marcajes`, no en `jornadas`, y se sella
-- cuando una secuencia entrada/salida no cuadra (`fn_dia_incoherente`, 0082) —
-- un problema distinto al de la 0284, donde la hora la inventó el sistema.
-- Antes de esta migración, ese marcaje quedaba señalado en `/admin/
-- correcciones` pero no impedía cerrar el mes: sus horas se pagaban con la
-- secuencia rota tal cual.
--
-- El fixture pone `estado_revision = 'pendiente_revision'` con un update
-- directo, a propósito: lo que se prueba es el FRENO que lee esa bandera, no
-- `fn_dia_incoherente`, que ya tiene sus propias pruebas.
--
-- Las 1 a 6 prueban el freno mismo, igual que la 220 para la 0284. Las 7 a 9
-- prueban el alcance: SOLO el periodo que se cierra, ni arrastre de otro
-- periodo ni bloqueo del retroactivo. Las 10 y 11 prueban que usa
-- `fn_fecha_de_jornada` (0307) y no el reloj — un turno que cruza medianoche
-- se cuenta en el periodo de SU jornada, no en el del calendario.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000025800', 'ZZREV', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000025801', 'PenAdmin', 'Lab',
        '00000000-0000-0000-0000-000000025800', 'admin', 'x',
        '00000000-0000-0000-0000-0000000258ff', '2024-01-01', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo)
values ('00000000-0000-0000-0000-000000025802', 'PenRevisa', 'Lab',
        '00000000-0000-0000-0000-000000025800', 'x', '2024-01-01', 'taller_produccion', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000025802', 'colibri', 1950, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-000000025802', '2024-01-01', '09:00', '15:30', 0, 0,
        array[1,2,3,4,5,6], 39,
        '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
          "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
          "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000258ff', true);

-- Un día limpio en el periodo A (04/05) y uno en el B (02/06).
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000025802', '00000000-0000-0000-0000-000000025800', 'entrada',      '2026-05-04T09:00:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000025802', '00000000-0000-0000-0000-000000025800', 'salida_final', '2026-05-04T15:30:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000025802', '00000000-0000-0000-0000-000000025800', 'entrada',      '2026-06-02T09:00:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000025802', '00000000-0000-0000-0000-000000025800', 'salida_final', '2026-06-02T15:30:00-05:00');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000002580a1', '2026-04-29', '2026-05-28', 'abierto'),
       ('00000000-0000-0000-0000-0000002580b1', '2026-05-29', '2026-06-28', 'abierto');

-- El día 04/05 queda con una secuencia que el sistema no pudo leer.
update marcajes set estado_revision = 'pendiente_revision'
 where persona_id = '00000000-0000-0000-0000-000000025802'
   and timestamp_marca = '2026-05-04T15:30:00-05:00';


-- ── 1 a 3 · Con un marcaje sin revisar, el mes no cierra ────────────────────

select throws_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580a1', 'pago', null) $$,
  null, null,
  'Congelar se niega mientras haya un marcaje sin revisar en el periodo');

select is(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-0000002580a1'),
  0,
  'Y no congela nada a medias: la foto del periodo sigue vacía');

select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-0000002580a1'),
  'abierto',
  'El periodo sigue ABIERTO, que es lo que promete el mensaje');


-- ── 4 · El mensaje nombra a quién hay que ir a buscar ───────────────────────

select throws_like(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580a1', 'pago', null) $$,
  '%PenRevisa%',
  'El mensaje dice de quién es el marcaje, no solo que hay uno');


-- ── 5 · La puerta de arriba tampoco deja pasar ──────────────────────────────

select throws_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-0000002580a1', true) $$,
  null, null,
  'Marcar el periodo como pagado tampoco pasa: hereda el freno del congelado');


-- ── 6 · Revisado el marcaje, el mes cierra con normalidad ───────────────────

update marcajes set estado_revision = 'revisada'
 where persona_id = '00000000-0000-0000-0000-000000025802'
   and timestamp_marca = '2026-05-04T15:30:00-05:00';

select lives_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580a1', 'pago', null) $$,
  'Revisado el marcaje, el freno se levanta y el periodo cierra');


-- ── 7 y 8 · El freno mira SOLO el periodo que se cierra ─────────────────────
-- Un pendiente en el periodo B no puede frenar el cierre de A, y viceversa:
-- si frenara por cualquier pendiente sin importar la fecha, esta prueba lo
-- encuentra.

update marcajes set estado_revision = 'pendiente_revision'
 where persona_id = '00000000-0000-0000-0000-000000025802'
   and timestamp_marca = '2026-06-02T15:30:00-05:00';

select lives_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580a1', 'pago', null) $$,
  'Un marcaje pendiente en OTRO periodo no frena este — nada de arrastre');

select throws_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580b1', 'pago', null) $$,
  null, null,
  'Pero sí frena el periodo al que de verdad pertenece');


-- ── 9 · La foto retroactiva NO se frena ─────────────────────────────────────
-- Misma razón que la 0244 y la 0284: abortar en 'retroactivo' rompe
-- fn_planilla_congelar_pendientes y deja los periodos históricos sin foto
-- para siempre. Acá solo avisa.

select lives_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580b1', 'retroactivo', null) $$,
  'Una foto retroactiva con marcajes sin revisar avisa pero no aborta');

update marcajes set estado_revision = 'revisada'
 where persona_id = '00000000-0000-0000-0000-000000025802'
   and timestamp_marca = '2026-06-02T15:30:00-05:00';


-- ── 10 y 11 · Manda la jornada, no el reloj ──────────────────────────────────
-- Un turno que entra el 28/05 (periodo A) y cierra a las 00:30 del 29/05
-- (calendario del periodo B) tiene que contarse en A, igual que ya hace el
-- candado de la 0307 — reusa `fn_fecha_de_jornada`, no un cálculo aparte.

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000025802', '00000000-0000-0000-0000-000000025800', 'entrada',      '2026-05-28T22:00:00-05:00'),
       (gen_random_uuid(), '00000000-0000-0000-0000-000000025802', '00000000-0000-0000-0000-000000025800', 'salida_final', '2026-05-29T00:30:00-05:00');

update marcajes set estado_revision = 'pendiente_revision', fecha_jornada = '2026-05-28'
 where persona_id = '00000000-0000-0000-0000-000000025802'
   and timestamp_marca = '2026-05-29T00:30:00-05:00';

select throws_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580a1', 'pago', null) $$,
  null, null,
  'La salida de un turno nocturno cuenta para la jornada del 28 (periodo A), no para el calendario del 29');

select lives_ok(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-0000002580b1', 'pago', null) $$,
  'Y por eso mismo NO cuenta para el periodo B, aunque su reloj marque el 29');


select * from finish();
rollback;
