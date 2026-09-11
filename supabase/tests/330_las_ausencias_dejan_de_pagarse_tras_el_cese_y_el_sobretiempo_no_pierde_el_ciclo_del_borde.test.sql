-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 330_las_ausencias_dejan_de_pagarse_tras_el_cese_y_el_sobretiempo_no_pierde_el_ciclo_del_borde.test.sql
-- ============================================================================
-- Fija los dos casos que la 0418 corrige, más un control de cada uno para
-- probar que el arreglo no se pasó de la raya:
--
--   · una persona cesada con vacaciones registradas ANTES de cesar sigue
--     cobrando esos días (el candado es por FECHA, no por persona cesada);
--   · una persona activa con las MISMAS fechas de vacaciones sigue cobrando
--     normal (el candado no le hace nada a quien no tiene fecha_cese);
--   · una racha de sobretiempo que NO cruza el borde del periodo (ya cubierta
--     por la prueba 275) no se toca aquí para no duplicar cobertura — este
--     archivo solo fija el caso de borde nuevo.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000330', 'ZZ330', 'Sede prueba 330', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000003300', 'P330Admin', 'Lab', '00000000-0000-0000-0000-000000000330', 'admin', 'x', '00000000-0000-0000-0000-000000003300', '2020-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000003300', true);

-- ── Caso 1 · vacaciones POSTERIORES al cese, ya no se pagan ────────────────
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, estado, fecha_cese)
values ('00000000-0000-0000-0000-000000003301', 'P330CesaDespues', 'Lab', '00000000-0000-0000-0000-000000000330', 'x', '2020-01-01', 'taller_produccion', 'inactivo', '2026-09-05');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000003301', 'colibri', 1200, '2020-01-01');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables)
values ('00000000-0000-0000-0000-000000003301', '2020-01-01', '09:00', '17:00', 0, 0, array[0,1,2,3,4,5,6]);

-- Trabajó del 1 al 4 de septiembre (antes del cese) — así `pers` la incluye.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000003301', d::date, 8.0, 'cerrada'
from generate_series('2026-09-01'::date, '2026-09-04'::date, '1 day') d;

-- Vacaciones registradas ENTERAMENTE después del cese (08→12 sep, cesó el 05).
insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por)
values ('00000000-0000-0000-0000-000000003301', '2026-09-08', '2026-09-12', '00000000-0000-0000-0000-000000003300');

-- ── Caso 2 (control) · MISMAS fechas de vacaciones, pero SIN cesar ─────────
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion)
values ('00000000-0000-0000-0000-000000003302', 'P330SigueActiva', 'Lab', '00000000-0000-0000-0000-000000000330', 'x', '2020-01-01', 'taller_produccion');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000003302', 'colibri', 1200, '2020-01-01');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables)
values ('00000000-0000-0000-0000-000000003302', '2020-01-01', '09:00', '17:00', 0, 0, array[0,1,2,3,4,5,6]);

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000003302', d::date, 8.0, 'cerrada'
from generate_series('2026-09-01'::date, '2026-09-04'::date, '1 day') d;

insert into vacaciones (persona_id, fecha_inicio, fecha_fin, creado_por)
values ('00000000-0000-0000-0000-000000003302', '2026-09-08', '2026-09-12', '00000000-0000-0000-0000-000000003300');

-- ── Caso 3 · sobretiempo de una racha que cruza el borde del periodo ───────
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo)
values ('00000000-0000-0000-0000-000000003303', 'P330Borde', 'Lab', '00000000-0000-0000-0000-000000000330', 'x', '2020-01-01', 'taller_produccion', 'planilla', false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000003303', 'colibri', 1130, '2020-01-01');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables)
values ('00000000-0000-0000-0000-000000003303', '2020-01-01', '09:00', '17:00', 0, 0, array[0,1,2,3,4,5,6]);

-- Racha real de 14 días seguidos, 8h/día: 2026-08-22 → 2026-09-04. El periodo
-- de la prueba empieza el 2026-09-01, así que 10 días caen ANTES y 4 dentro.
-- El ciclo real de 7 días que arranca el 2026-08-29 se completa el 2026-09-04
-- (56h, 8h de exceso ese día: 2h al 25% + 6h al 35%).
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000003303', d::date, 8.0, 'cerrada'
from generate_series('2026-08-22'::date, '2026-09-04'::date, '1 day') d;

create or replace function pg_temp.fila(p_id uuid) returns jsonb
language sql as $f$
  select f from (select jsonb_array_elements(fn_planilla_calcular('2026-09-01','2026-09-27') -> 'filas') f) x
  where (f->>'persona_id')::uuid = p_id;
$f$;

-- 1-2 · CAMBIO 0418 · vacaciones posteriores al cese ya no se pagan.
select is(
  (pg_temp.fila('00000000-0000-0000-0000-000000003301')->>'dias_vacaciones_pagados')::int, 0,
  'CAMBIO 0418 · una persona cesada no cobra días de vacaciones posteriores a su cese');

select is(
  (pg_temp.fila('00000000-0000-0000-0000-000000003301')->>'monto_vacaciones')::numeric, 0.00::numeric,
  'CAMBIO 0418 · y el monto de esos días es S/0,00, no solo el conteo');

-- 3-4 · CONTROL · la misma persona sin cesar SÍ cobra esos mismos 5 días.
select is(
  (pg_temp.fila('00000000-0000-0000-0000-000000003302')->>'dias_vacaciones_pagados')::int, 5,
  'CONTROL · quien NO cesó cobra los 5 días de vacaciones normalmente');

select cmp_ok(
  (pg_temp.fila('00000000-0000-0000-0000-000000003302')->>'monto_vacaciones')::numeric, '>', 0.00::numeric,
  'CONTROL · y el monto de esos 5 días es mayor a cero — el candado es por fecha, no por persona');

-- 5-7 · CAMBIO 0418 · el ciclo de sobretiempo que cruza el borde ya no se pierde.
select is(
  (pg_temp.fila('00000000-0000-0000-0000-000000003303')->>'monto_sobretiempo')::numeric, 16.74::numeric,
  'CAMBIO 0418 · una racha de 14 días que cruza el borde del periodo paga su exceso');

select is(
  (pg_temp.fila('00000000-0000-0000-0000-000000003303')->>'horas_sobretiempo_25')::numeric, 2.00::numeric,
  'CAMBIO 0418 · 2 de las 8 h de exceso caen en el tramo del 25 %');

select is(
  (pg_temp.fila('00000000-0000-0000-0000-000000003303')->>'horas_sobretiempo_35')::numeric, 6.00::numeric,
  'CAMBIO 0418 · y 6 h en el tramo del 35 %, el mismo reparto que fija la 275 dentro de un ciclo cualquiera');

select * from finish();
rollback;
