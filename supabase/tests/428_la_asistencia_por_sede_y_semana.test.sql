-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 428_la_asistencia_por_sede_y_semana.test.sql — defiende la 0534
-- ============================================================================
-- QUÉ DEFIENDE
--
--   Que `fn_asistencia_serie` cuente por (sede, semana, día de la semana):
--   los días trabajados, las faltas sin justificar (las de `fn_faltas`, sin
--   reescribir «qué le tocaba») y los minutos de la entrada frente a la
--   esperada; que NO cuente a quien `fn_faltas` tampoco cuenta (sueldo fijo);
--   que el líder de equipo vea solo su sede; y que una integrante no vea nada.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000042800', 'ZZ4281', 'Sede de laboratorio 428 A', true),
  ('00000000-0000-0000-0000-000000042801', 'ZZ4282', 'Sede de laboratorio 428 B', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values
  ('00000000-0000-0000-0000-000000042810', 'Admin428', 'Lab', '00000000-0000-0000-0000-000000042800', 'admin', 'x', '00000000-0000-0000-0000-000000042890', '2024-01-01'),
  ('00000000-0000-0000-0000-000000042811', 'LiderB428', 'Lab', '00000000-0000-0000-0000-000000042801', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000042891', '2024-01-01'),
  ('00000000-0000-0000-0000-000000042812', 'Integrante428', 'Lab', '00000000-0000-0000-0000-000000042800', 'integrante', 'x', '00000000-0000-0000-0000-000000042892', '2024-01-01');
set session_replication_role = origin;

-- Tres personas medibles y una de sueldo fijo, todas con horario lunes a viernes 09:00.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
values
  ('00000000-0000-0000-0000-000000042820', 'A1', 'Lab', '00000000-0000-0000-0000-000000042800', 'x', '2026-01-05', 'planilla', false),
  ('00000000-0000-0000-0000-000000042821', 'A2', 'Lab', '00000000-0000-0000-0000-000000042800', 'x', '2026-01-05', 'planilla', false),
  ('00000000-0000-0000-0000-000000042822', 'B1', 'Lab', '00000000-0000-0000-0000-000000042801', 'x', '2026-01-05', 'planilla', false),
  ('00000000-0000-0000-0000-000000042823', 'Fija', 'Lab', '00000000-0000-0000-0000-000000042800', 'x', '2026-01-05', 'planilla', true);

insert into horarios_asignados (persona_id, hora_entrada, hora_salida, dias_laborables, vigente_desde)
select id, '09:00', '18:00', array[1,2,3,4,5], '2026-01-05'
from personas where nombres in ('A1', 'A2', 'B1', 'Fija');

-- Semana del lunes 2026-02-02. A1: lunes 08:55 (−5), martes 09:10 (+10), miércoles no marca (falta).
-- A2: lunes 09:00 (0), martes 09:00 (0), miércoles 09:00 (0). B1: lunes 09:30 (+30).
-- Fija (sueldo fijo) marca el lunes y NO debe contar.
set session_replication_role = replica;
insert into jornadas (persona_id, fecha, sede_id, entrada_ts, estado, horario_aplicado)
select p.id, d.fecha, p.sede_base_id, (d.fecha || ' ' || d.hora || '-05')::timestamptz, 'cerrada',
       '{"entrada":"09:00:00","salida":"18:00:00","es_descanso":false,"fuente":"horarios_asignados"}'::jsonb
from (values
  ('A1', date '2026-02-02', '08:55'), ('A1', date '2026-02-03', '09:10'),
  ('A2', date '2026-02-02', '09:00'), ('A2', date '2026-02-03', '09:00'), ('A2', date '2026-02-04', '09:00'),
  ('B1', date '2026-02-02', '09:30'),
  ('Fija', date '2026-02-02', '09:00')
) as d(nombre, fecha, hora)
join personas p on p.nombres = d.nombre;
set session_replication_role = origin;

-- ── Como admin ──────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000042890', true);

select is((select dias_trabajados from fn_asistencia_serie('2026-02-02', '2026-02-04')
            where sede_codigo = 'ZZ4281' and dia_semana = 1),
          2, 'LUNES · en la sede A trabajaron A1 y A2: 2 días — la de sueldo fijo NO cuenta');

select is((select offsets from fn_asistencia_serie('2026-02-02', '2026-02-04')
            where sede_codigo = 'ZZ4281' and dia_semana = 1),
          array[-5, 0], 'LUNES · los minutos frente a la hora esperada, ordenados: A1 llegó 5 antes, A2 a la hora');

select is((select offsets from fn_asistencia_serie('2026-02-02', '2026-02-04')
            where sede_codigo = 'ZZ4281' and dia_semana = 2),
          array[0, 10], 'MARTES · A1 llegó 10 minutos tarde, A2 a la hora');

select is((select faltas from fn_asistencia_serie('2026-02-02', '2026-02-04')
            where sede_codigo = 'ZZ4281' and dia_semana = 3),
          1, 'MIÉRCOLES · A1 no marcó y le tocaba: 1 falta sin justificar, sacada de fn_faltas');

select is((select count(distinct sede_codigo)::int from fn_asistencia_serie('2026-02-02', '2026-02-04', '00000000-0000-0000-0000-000000042801')),
          1, 'FILTRO · pidiendo la sede B solo vuelve la sede B');

select is((select semana from fn_asistencia_serie('2026-02-02', '2026-02-04') where sede_codigo = 'ZZ4281' and dia_semana = 1),
          date '2026-02-02', 'SEMANA · la semana es el lunes que la abre');

-- ── Como líder de la sede B: solo ve la suya ───────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000042891', true);

select is((select array_agg(distinct sede_codigo) from fn_asistencia_serie('2026-02-02', '2026-02-04')),
          array['ZZ4282']::text[], 'LÍDER · el líder de la sede B no ve la sede A, ni aunque no pida filtro');

-- ── Como integrante: nada ──────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000042892', true);

select is((select count(*)::int from fn_asistencia_serie('2026-02-02', '2026-02-04')),
          0, 'INTEGRANTE · una integrante no ve el tablero de asistencia, ni siquiera el de su propia sede');

-- ── Fecha futura: no revienta y no inventa filas ───────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000042890', true);

select is((select count(*)::int from fn_asistencia_serie(current_date + 5, current_date + 10)),
          0, 'FUTURO · un rango que aún no ocurrió no devuelve filas (hoy no se cierra hasta que termina)');

select * from finish();
rollback;
