-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 483_el_borrador_de_la_semana.test.sql
-- ============================================================================
-- El borrador de la semana (0593): uno vivo por sede y semana, que guardar
-- reemplaza; para quien es RxH solo cabe una nota; lo ven admin, DO y la líder
-- de esa sede; y publicar exige que lo publicado sea lo del borrador, lo
-- publica con fn_publicar_semana (0586) y lo deja marcado.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000483000', 'ZZBSA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000483001', 'ZZBSB', 'Sede de laboratorio B', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values
  ('00000000-0000-0000-0000-000000483010', 'BorAdmin', 'Lab', '00000000-0000-0000-0000-000000483000', 'admin', 'x',
   '00000000-0000-0000-0000-0000004830ff', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000483011', 'BorLiderA', 'Lab', '00000000-0000-0000-0000-000000483000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004830fe', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000483012', 'BorLiderB', 'Lab', '00000000-0000-0000-0000-000000483001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004830fd', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000483013', 'BorIntegrante', 'Lab', '00000000-0000-0000-0000-000000483000', 'integrante', 'x',
   '00000000-0000-0000-0000-0000004830fc', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000483014', 'BorRxH', 'Lab', '00000000-0000-0000-0000-000000483000', 'integrante', 'x',
   null, '2024-01-01', 'activo', 'rxh');
set session_replication_role = origin;

-- El lunes de la semana que viene: todos sus días todavía no llegan.
create temporary table _s as select fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int) as lunes;

create function pg_temp.dia(p_persona text, p_mas integer, p_entrada text, p_salida text) returns jsonb language sql as $f$
  select jsonb_build_object('persona_id', p_persona, 'fecha', (select lunes from _s) + p_mas, 'entrada', p_entrada, 'salida', p_salida)
$f$;

-- ── 1-3 · La líder guarda su borrador; guardar otra vez lo reemplaza ────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004830fe', true);
select isnt(
  fn_turnos_borrador_guardar('00000000-0000-0000-0000-000000483000', (select lunes from _s),
    jsonb_build_array(pg_temp.dia('00000000-0000-0000-0000-000000483013', 0, '10:00', '18:30'),
                      pg_temp.dia('00000000-0000-0000-0000-000000483013', 1, null, null)),
    jsonb_build_array(jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000483014', 'nota', 'Se la necesita el sábado de 12 a 16')),
    'sugerido'),
  null, 'la líder guarda el borrador de su sede: un turno, un descanso y una nota');

select fn_turnos_borrador_guardar('00000000-0000-0000-0000-000000483000', (select lunes from _s),
  jsonb_build_array(pg_temp.dia('00000000-0000-0000-0000-000000483013', 0, '10:00', '18:30')), '[]'::jsonb, 'manual');
select is(
  (select count(*)::int from turnos_borradores where sede_id = '00000000-0000-0000-0000-000000483000' and publicado_at is null and descartado_at is null),
  1, 'guardar otra vez no crea otro: hay un solo borrador vivo');
select is(
  (select count(*)::int from turnos_borrador_dias d join turnos_borradores b on b.id = d.borrador_id
    where b.sede_id = '00000000-0000-0000-0000-000000483000')
  + (select count(*)::int from turnos_borrador_notas n join turnos_borradores b on b.id = n.borrador_id
    where b.sede_id = '00000000-0000-0000-0000-000000483000'),
  1, 'y lo deja exactamente como se mandó (un día, sin la nota)');

-- ── 4-6 · Lo que no entra ───────────────────────────────────────────────────
select throws_ok(
  $$ select fn_turnos_borrador_guardar('00000000-0000-0000-0000-000000483000', (select lunes from _s),
       jsonb_build_array(pg_temp.dia('00000000-0000-0000-0000-000000483014', 5, '12:00', '16:00'))) $$,
  null, null, 'a quien es RxH no se le pone turno: solo nota');
select throws_ok(
  $$ select fn_turnos_borrador_guardar('00000000-0000-0000-0000-000000483000', (select lunes from _s),
       jsonb_build_array(pg_temp.dia('00000000-0000-0000-0000-000000483013', 9, '10:00', '18:00'))) $$,
  null, null, 'un día fuera de la semana no entra');
select is(
  (select count(*)::int from turnos_borrador_dias d join turnos_borradores b on b.id = d.borrador_id
    where b.sede_id = '00000000-0000-0000-0000-000000483000'),
  1, 'y lo rechazado no toca el borrador (todo o nada)');

-- ── 7-8 · Quién no lo toca ──────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004830fd', true);
select throws_ok(
  $$ select fn_turnos_borrador_guardar('00000000-0000-0000-0000-000000483000', (select lunes from _s), '[]'::jsonb) $$,
  null, null, 'la líder de otra sede no toca este borrador');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004830fc', true);
select throws_ok(
  $$ select fn_turnos_borrador_guardar('00000000-0000-0000-0000-000000483000', (select lunes from _s), '[]'::jsonb) $$,
  null, null, 'una integrante no tiene borrador');

-- ── 9-11 · Quién lo ve ──────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004830fe', true);
select is((select count(*)::int from turnos_borrador_dias), 1, 'la líder de la sede ve su borrador');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004830fd', true);
select is((select count(*)::int from turnos_borradores), 0, 'la de otra sede no lo ve');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004830fc', true);
select is((select count(*)::int from turnos_borrador_dias), 0, 'una integrante no lo ve');
reset role;

-- ── 12-15 · Publicar: lo del borrador, y nada más ───────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004830fe', true);
select throws_ok(
  $$ select fn_turnos_borrador_publicar('00000000-0000-0000-0000-000000483000', (select lunes from _s),
       jsonb_build_array(pg_temp.dia('00000000-0000-0000-0000-000000483013', 0, '09:00', '17:30'))) $$,
  null, null, 'no se publica algo distinto de lo que tiene el borrador');
select is(
  fn_turnos_borrador_publicar('00000000-0000-0000-0000-000000483000', (select lunes from _s),
    jsonb_build_array(pg_temp.dia('00000000-0000-0000-0000-000000483013', 0, '10:00', '18:30'))),
  1, 'lo del borrador se publica');
select is(
  (select to_char(hora_entrada, 'HH24:MI') || '-' || to_char(hora_salida, 'HH24:MI') from turnos
    where persona_id = '00000000-0000-0000-0000-000000483013' and fecha = (select lunes from _s)),
  '10:00-18:30', 'y queda en turnos, como un turno publicado cualquiera');
select is(
  (select count(*)::int from turnos_borradores where sede_id = '00000000-0000-0000-0000-000000483000'
      and publicado_at is not null and publicado_por = '00000000-0000-0000-0000-000000483011'),
  1, 'el borrador queda marcado como publicado, con quién lo hizo');

-- ── 16-17 · Después: uno nuevo, y descartarlo ───────────────────────────────
select fn_turnos_borrador_guardar('00000000-0000-0000-0000-000000483000', (select lunes from _s),
  '[]'::jsonb, jsonb_build_array(jsonb_build_object('persona_id', '00000000-0000-0000-0000-000000483014', 'nota', 'El domingo de 10 a 14')));
select is(
  fn_turnos_borrador_descartar('00000000-0000-0000-0000-000000483000', (select lunes from _s)),
  true, 'un borrador nuevo de la misma semana se puede descartar');
select is(
  fn_turnos_borrador_descartar('00000000-0000-0000-0000-000000483000', (select lunes from _s)),
  false, 'y descartado no queda ninguno vivo');

-- ── 18 · Nadie de afuera ────────────────────────────────────────────────────
select ok(
  not has_function_privilege('anon', 'fn_turnos_borrador_guardar(uuid,date,jsonb,jsonb,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'fn_turnos_borrador_publicar(uuid,date,jsonb,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'fn_turnos_borrador_puede(uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.turnos_borrador_dias', 'INSERT'),
  'anon no guarda ni publica, y nadie escribe las tablas directo');

select * from finish();
rollback;
