-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 480_la_meta_de_cobertura_va_por_rangos_y_por_temporada.test.sql
-- ============================================================================
-- La meta de cobertura (0590): una predeterminada por día de la semana con sus
-- rangos de hora, y excepciones con vigencia que la reemplazan solo en los días
-- que definen; si se pisan, manda la más corta. null = sin meta; 0 = no se exige
-- a nadie. Quién la guarda (admin y DO), quién la lee (además la líder de su sede).
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000480000', 'ZZMCA', 'Sede de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000480001', 'ZZMCB', 'Sede de laboratorio B', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000480010', 'McAdmin', 'Lab', '00000000-0000-0000-0000-000000480000', 'admin', 'x',
   '00000000-0000-0000-0000-0000004800ff', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000480011', 'McLiderA', 'Lab', '00000000-0000-0000-0000-000000480000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004800fe', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000480012', 'McLiderB', 'Lab', '00000000-0000-0000-0000-000000480001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004800fd', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000480013', 'McIntegrante', 'Lab', '00000000-0000-0000-0000-000000480000', 'integrante', 'x',
   '00000000-0000-0000-0000-0000004800fc', '2024-01-01', 'activo');
set session_replication_role = origin;

-- El lunes de la semana que viene; +5 es su sábado.
create temporary table _s as select fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int) as lunes;
create temporary table _ids (clave text primary key, id uuid);

-- La meta de un día, como texto: «09:00-12:00 3/1 · 12:00-21:00 5/1».
create function pg_temp.meta_de(p_dia integer) returns text language sql as $f$
  select coalesce(string_agg(
           lpad((m.desde_min / 60)::text, 2, '0') || ':' || lpad((m.desde_min % 60)::text, 2, '0') || '-'
           || lpad((m.hasta_min / 60)::text, 2, '0') || ':' || lpad((m.hasta_min % 60)::text, 2, '0') || ' '
           || coalesce(m.personal::text, '—') || '/' || coalesce(m.lideres::text, '—'), ' · ' order by m.desde_min), 'sin meta')
    from fn_metas_cobertura('00000000-0000-0000-0000-000000480000', (select lunes from _s) + p_dia, (select lunes from _s) + p_dia) m
$f$;

-- ── 1-4 · La predeterminada ─────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004800ff', true);
insert into _ids
select 'pred', fn_guardar_meta_cobertura('00000000-0000-0000-0000-000000480000', null, null, null, null, jsonb_build_array(
  jsonb_build_object('dia', 1, 'desde_min', 540, 'hasta_min', 720,  'personal', 3, 'lideres', 1),
  jsonb_build_object('dia', 1, 'desde_min', 720, 'hasta_min', 1260, 'personal', 5, 'lideres', 1),
  jsonb_build_object('dia', 6, 'desde_min', 540, 'hasta_min', 1260, 'personal', 6, 'lideres', 2),
  jsonb_build_object('dia', 3, 'desde_min', 540, 'hasta_min', 1260, 'personal', null, 'lideres', 1)));

select is(pg_temp.meta_de(0), '09:00-12:00 3/1 · 12:00-21:00 5/1', 'el lunes rige la predeterminada, rango por rango');
select is(pg_temp.meta_de(1), 'sin meta', 'un día que la meta no define queda sin meta');
select is(pg_temp.meta_de(2), '09:00-21:00 —/1', 'personal sin meta (null) no es cero: manda lo que pide la venta');
select is(pg_temp.meta_de(5), '09:00-21:00 6/2', 'el sábado, la suya');

-- ── 5-7 · Una excepción de cuatro semanas, solo para los sábados ────────────
insert into _ids
select 'mes', fn_guardar_meta_cobertura('00000000-0000-0000-0000-000000480000', null, 'Campaña', (select lunes from _s), (select lunes from _s) + 27,
  jsonb_build_array(jsonb_build_object('dia', 6, 'desde_min', 540, 'hasta_min', 1260, 'personal', 9, 'lideres', 2)));

select is(pg_temp.meta_de(5), '09:00-21:00 9/2', 'en la campaña, el sábado manda la excepción');
select is(pg_temp.meta_de(0), '09:00-12:00 3/1 · 12:00-21:00 5/1', 'y el lunes, que la excepción no define, sigue con la predeterminada');
select is(pg_temp.meta_de(33), '09:00-21:00 6/2', 'pasada la campaña, el sábado vuelve a la predeterminada');

-- ── 8-9 · Un solo día dentro de la campaña: manda la más corta ──────────────
insert into _ids
select 'dia', fn_guardar_meta_cobertura('00000000-0000-0000-0000-000000480000', null, 'Inventario', (select lunes from _s) + 5, (select lunes from _s) + 5,
  jsonb_build_array(jsonb_build_object('dia', 6, 'desde_min', 600, 'hasta_min', 1200, 'personal', 0, 'lideres', 1)));

select is(pg_temp.meta_de(5), '10:00-20:00 0/1', 'el día suelto gana sobre su campaña, y un cero es un cero');
select is(pg_temp.meta_de(12), '09:00-21:00 9/2', 'el sábado siguiente sigue en campaña');

-- ── 10-11 · Quitar una excepción ────────────────────────────────────────────
select fn_anular_meta_cobertura((select id from _ids where clave = 'dia'));
select is(pg_temp.meta_de(5), '09:00-21:00 9/2', 'quitado el día suelto, vuelve a mandar la campaña');
select throws_ok(
  $$ select fn_anular_meta_cobertura((select id from _ids where clave = 'pred')) $$,
  null, null, 'la predeterminada no se quita: se cambia');

-- ── 12-14 · Lo que la base no deja guardar ──────────────────────────────────
select throws_ok(
  $$ select fn_guardar_meta_cobertura('00000000-0000-0000-0000-000000480000', null, null, null, null, jsonb_build_array(
       jsonb_build_object('dia', 1, 'desde_min', 540, 'hasta_min', 780, 'personal', 3),
       jsonb_build_object('dia', 1, 'desde_min', 720, 'hasta_min', 900, 'personal', 4))) $$,
  null, null, 'dos rangos del mismo día que se cruzan no se guardan');
select is(pg_temp.meta_de(0), '09:00-12:00 3/1 · 12:00-21:00 5/1', 'y la meta queda como estaba (todo o nada)');
select throws_ok(
  $$ select fn_guardar_meta_cobertura('00000000-0000-0000-0000-000000480000', null, 'Al revés', (select lunes from _s) + 3, (select lunes from _s),
       '[]'::jsonb) $$,
  null, null, 'una excepción que termina antes de empezar no se guarda');

-- ── 15-17 · Quién guarda y quién lee ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004800fe', true);
select throws_ok(
  $$ select fn_guardar_meta_cobertura('00000000-0000-0000-0000-000000480000', null, null, null, null, '[]'::jsonb) $$,
  null, null, 'la líder de equipo no cambia la meta (admin y DO, como antes)');

set local role authenticated;
select ok(
  (select count(*) from fn_metas_cobertura('00000000-0000-0000-0000-000000480000', (fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int)), (fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int)) + 6)) > 0,
  'pero la líder de su sede sí la lee');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004800fd', true);
select is(
  (select count(*)::int from fn_metas_cobertura('00000000-0000-0000-0000-000000480000', (fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int)), (fn_hoy_lima() + (8 - extract(isodow from fn_hoy_lima())::int)) + 6)),
  0, 'y la de otra sede no ve nada');
reset role;

-- ── 18 · Nadie de afuera ────────────────────────────────────────────────────
select ok(
  not has_function_privilege('anon', 'fn_metas_cobertura(uuid,date,date)', 'EXECUTE')
  and not has_function_privilege('anon', 'fn_guardar_meta_cobertura(uuid,uuid,text,date,date,jsonb)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.metas_cobertura_rangos', 'INSERT'),
  'anon no lee ni guarda, y nadie escribe las tablas directo');

select * from finish();
rollback;
