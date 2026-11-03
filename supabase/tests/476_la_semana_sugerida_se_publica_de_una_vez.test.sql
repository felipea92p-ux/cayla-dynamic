-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 476_la_semana_sugerida_se_publica_de_una_vez.test.sql
-- ============================================================================
-- fn_publicar_semana (0586) guarda una semana entera de turnos, todo o nada,
-- solo días que todavía no llegan, y deja que la líder de equipo se publique su
-- propio turno si manda su semana completa y suma su jornada.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000476000', 'ZZPSA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000476001', 'ZZPSB', 'Sede de laboratorio B', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, jornada_semanal_horas)
values
  ('00000000-0000-0000-0000-000000476010', 'PubAdmin', 'Lab', '00000000-0000-0000-0000-000000476000', 'admin', 'x',
   '00000000-0000-0000-0000-0000004760ff', '2024-01-01', 'activo', null),
  ('00000000-0000-0000-0000-000000476011', 'PubLiderA', 'Lab', '00000000-0000-0000-0000-000000476000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004760fe', '2024-01-01', 'activo', 45),
  ('00000000-0000-0000-0000-000000476012', 'PubLiderB', 'Lab', '00000000-0000-0000-0000-000000476001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004760fd', '2024-01-01', 'activo', 45),
  ('00000000-0000-0000-0000-000000476013', 'PubIntegrante', 'Lab', '00000000-0000-0000-0000-000000476000', 'integrante', 'x',
   '00000000-0000-0000-0000-0000004760fc', '2024-01-01', 'activo', 45),
  ('00000000-0000-0000-0000-000000476014', 'PubLiderSinJornada', 'Lab', '00000000-0000-0000-0000-000000476000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004760fb', '2024-01-01', 'activo', null);
set session_replication_role = origin;

-- La líder A almuerza 60 minutos.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values ('00000000-0000-0000-0000-000000476011', '2024-01-01', '09:00', '17:30', 60, 60, array[1,2,3,4,5,6], 45);

-- El lunes de la semana que viene: todos sus días todavía no llegan.
create temporary table _s as select fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int) as lunes;

-- Su semana: seis días de 09:00 a 17:30 (8,5 h − 1 h de refrigerio = 7,5 h) y un descanso = 45 h.
create function pg_temp.semana_lider(p_salida text) returns jsonb language sql as $f$
  select jsonb_agg(jsonb_build_object(
           'persona_id', '00000000-0000-0000-0000-000000476011',
           'fecha', (select lunes from _s) + i,
           'entrada', case when i < 6 then '09:00' end,
           'salida',  case when i < 6 then p_salida end))
    from generate_series(0, 6) i
$f$;

-- ── 1-3 · Admin publica dos días de una integrante ──────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004760ff', true);
select is(
  fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s), jsonb_build_array(
    jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s), 'entrada', '10:00', 'salida', '18:30'),
    jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s) + 1, 'entrada', null, 'salida', null))),
  2, 'publica los dos días');
select is(
  (select string_agg(case when es_descanso then 'descanso' else to_char(hora_entrada, 'HH24:MI') || '-' || to_char(hora_salida, 'HH24:MI') end, ' ' order by fecha)
     from turnos where persona_id = '00000000-0000-0000-0000-000000476013'),
  '10:00-18:30 descanso', 'quedan el turno y el descanso');
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000476013' and campo_modificado = 'turnos.horario'),
  2, 'cada día que cambia deja su rastro');

-- ── 4 · Todo o nada ─────────────────────────────────────────────────────────
select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s), jsonb_build_array(
       jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s) + 2, 'entrada', '09:00', 'salida', '17:00'),
       jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s) + 9, 'entrada', '09:00', 'salida', '17:00'))) $$,
  null, null, 'un día fuera de la semana tumba toda la publicación');
select is(
  (select count(*)::int from turnos where persona_id = '00000000-0000-0000-0000-000000476013' and fecha = (select lunes from _s) + 2),
  0, 'y no queda nada a medias');

-- ── 5-8 · La líder de su sede, y su propio turno ────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004760fe', true);
select lives_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s), jsonb_build_array(
       jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s) + 3, 'entrada', '12:00', 'salida', '20:30'))) $$,
  'la líder publica el turno de su equipo');

select lives_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s), pg_temp.semana_lider('17:30')) $$,
  'la líder se publica su propia semana si suma su jornada (45 h)');
select ok(
  exists (select 1 from correcciones_auditoria
           where persona_id = '00000000-0000-0000-0000-000000476011' and motivo like 'Turno del __/__/____ (su propio turno)%'),
  'y el rastro dice que fue su propio turno, dentro de su jornada');

select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s), pg_temp.semana_lider('16:30')) $$,
  null, null, 'si su semana no suma su jornada (39 h de 45), se niega');

select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s),
       (select jsonb_agg(e) from jsonb_array_elements(pg_temp.semana_lider('17:30')) with ordinality as t(e, n) where n <= 3)) $$,
  null, null, 'su propio turno va con la semana completa');

-- ── 9 · Sin jornada fijada no se publica a sí misma ─────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004760fb', true);
select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s),
       (select jsonb_agg(jsonb_set(e, '{persona_id}', '"00000000-0000-0000-0000-000000476014"')) from jsonb_array_elements(pg_temp.semana_lider('17:30')) e)) $$,
  null, null, 'una líder sin jornada fijada no se publica su propio turno');

-- ── 10-11 · Quién no puede ──────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004760fd', true);
select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s), jsonb_build_array(
       jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s) + 4, 'entrada', '09:00', 'salida', '17:00'))) $$,
  null, null, 'la líder de otra sede no publica aquí');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004760fc', true);
select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s), jsonb_build_array(
       jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s) + 4, 'entrada', '09:00', 'salida', '17:00'))) $$,
  null, null, 'una integrante no publica');

-- ── 12-13 · Fechas que no se aceptan ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004760ff', true);
select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', (select lunes from _s) + 1, jsonb_build_array(
       jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', (select lunes from _s) + 1, 'entrada', '09:00', 'salida', '17:00'))) $$,
  null, null, 'la semana se publica desde su lunes');

select throws_ok(
  $$ select fn_publicar_semana('00000000-0000-0000-0000-000000476000', fn_hoy_lima() - (extract(isodow from fn_hoy_lima())::int - 1), jsonb_build_array(
       jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000476013', 'fecha', fn_hoy_lima(), 'entrada', '09:00', 'salida', '17:00'))) $$,
  null, null, 'un día que ya llegó no se publica');

-- ── 14 · Nadie de afuera ────────────────────────────────────────────────────
select ok(
  not has_function_privilege('anon', 'fn_publicar_semana(uuid,date,jsonb,text)', 'EXECUTE'),
  'anon no publica');

select * from finish();
rollback;
