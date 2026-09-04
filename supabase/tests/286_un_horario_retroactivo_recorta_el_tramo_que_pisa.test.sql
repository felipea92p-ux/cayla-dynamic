-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 286_un_horario_retroactivo_recorta_el_tramo_que_pisa.test.sql
-- ============================================================================
-- Cubre la 0360. `fn_set_horario_semanal` solo sabía cerrar el tramo ABIERTO;
-- una fecha de vigencia que caía dentro de un tramo ya cerrado dejaba ese
-- tramo intacto y el candado `horarios_sin_solape` (0309) reventaba con un
-- error en inglés. Esta prueba fija las tres cosas que la 0360 promete:
--
--   · el caso que fallaba (fecha dentro de un tramo cerrado) ahora pasa, y el
--     tramo cerrado queda recortado hasta la víspera;
--   · lo que ya funcionaba sigue igual: cerrar el tramo abierto, y borrar los
--     que empiezan en o después de la fecha nueva;
--   · un tramo cerrado que terminó ANTES de la fecha no se toca.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000028600', 'ZZHRT', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000286ad', 'HrtAdmin', 'Lab',
        '00000000-0000-0000-0000-000000028600', 'admin', 'x',
        '00000000-0000-0000-0000-0000000286ff', '2024-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000286ff', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000028601', 'HrtPersona', 'Lab',
        '00000000-0000-0000-0000-000000028600', 'x', '2024-01-01');

-- Tres tramos, como los deja una persona con historia:
--   V · 1 al 30 de junio, cerrado, terminó antes de todo → no debe tocarse.
--   A · 1 al 14 de agosto, cerrado.
--   B · desde el 15 de agosto, abierto.
insert into horarios_asignados
  (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values
  ('00000000-0000-0000-0000-000000028601', '2026-06-01', '2026-06-30', '08:00', '14:30', 0, 0, array[1,2,3,4,5,6], 39),
  ('00000000-0000-0000-0000-000000028601', '2026-08-01', '2026-08-14', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39),
  ('00000000-0000-0000-0000-000000028601', '2026-08-15', null,         '10:00', '18:00', 0, 0, array[1,2,3,4,5,6], 39);

-- ── 1 · El caso que reventaba: una fecha DENTRO del tramo cerrado A ─────────
select lives_ok(
  $$ select fn_set_horario_semanal(
       '00000000-0000-0000-0000-000000028601', '2026-08-05',
       '{"1":{"e":"09:30","s":"16:00","r":0},"2":{"e":"09:30","s":"16:00","r":0},
         "3":{"e":"09:30","s":"16:00","r":0},"4":{"e":"09:30","s":"16:00","r":0},
         "5":{"e":"09:30","s":"16:00","r":0},"6":{"e":"09:30","s":"16:00","r":0}}'::jsonb) $$,
  'Corregir desde el 5 de agosto, dentro de un tramo ya cerrado, ya no revienta con horarios_sin_solape');

-- ── 2 · A quedó recortado hasta la víspera ──────────────────────────────────
select is(
  (select vigente_hasta from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000028601' and vigente_desde = '2026-08-01'),
  '2026-08-04'::date,
  'El tramo cerrado que pisaba la fecha nueva termina el 4 de agosto, la víspera');

-- ── 3 · El nuevo rige desde el 5, abierto ───────────────────────────────────
select is(
  (select vigente_hasta from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000028601' and vigente_desde = '2026-08-05'),
  null,
  'El tramo nuevo empieza el 5 de agosto y queda abierto');

select is(
  (select hora_entrada from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000028601' and vigente_desde = '2026-08-05'),
  '09:30'::time,
  'y lleva el horario que se pidió, no el del tramo que recortó');

-- ── 4 · B, que empezaba después, se reemplazó (semántica de siempre) ────────
select is(
  (select count(*)::int from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000028601' and vigente_desde = '2026-08-15'),
  0,
  'El tramo que empezaba después de la fecha nueva se reemplaza, como siempre hizo esta función');

-- ── 5 · V, que terminó antes, no se tocó ────────────────────────────────────
select is(
  (select vigente_hasta from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000028601' and vigente_desde = '2026-06-01'),
  '2026-06-30'::date,
  'Un tramo cerrado que terminó antes de la fecha nueva queda exactamente igual');

-- ── 6 · Ningún día queda cubierto por dos tramos ────────────────────────────
select is(
  (select count(*)::int
     from horarios_asignados a
     join horarios_asignados b
       on b.persona_id = a.persona_id and b.id <> a.id
    where a.persona_id = '00000000-0000-0000-0000-000000028601'
      and daterange(a.vigente_desde, coalesce(a.vigente_hasta, 'infinity'::date), '[]')
       && daterange(b.vigente_desde, coalesce(b.vigente_hasta, 'infinity'::date), '[]')),
  0,
  'Después de la corrección no hay ningún par de tramos que se pise');

-- ── 7 · Lo de siempre sigue igual: cerrar el tramo abierto ──────────────────
select lives_ok(
  $$ select fn_set_horario_semanal(
       '00000000-0000-0000-0000-000000028601', '2026-09-01',
       '{"1":{"e":"11:00","s":"19:00","r":45}}'::jsonb) $$,
  'Un horario desde una fecha posterior al tramo abierto sigue entrando sin problema');

select is(
  (select vigente_hasta from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000028601' and vigente_desde = '2026-08-05'),
  '2026-08-31'::date,
  'y el tramo que estaba abierto se cierra la víspera, como antes de la 0360');

select * from finish();
rollback;
