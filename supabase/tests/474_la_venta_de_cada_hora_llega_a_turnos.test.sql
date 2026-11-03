-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 474_la_venta_de_cada_hora_llega_a_turnos.test.sql
-- ============================================================================
-- fn_compras_por_hora (0584) cuenta tickets completados de retail por día y
-- hora de Lima, para una sola tienda, y solo se la deja ver a admin, Líder DO
-- y la líder de equipo de esa sede. fn_cobertura_por_venta da el ritmo y el
-- mínimo de la tienda, o 1,5 y 3 si no tiene los suyos.
--
-- Ojo con el truco de esta prueba: las migraciones de ESTE repo construyen una
-- retail.ventas vieja (0220, con sede_id), que no es la de producción. Para
-- probar la cuenta de verdad, la prueba aparta esa tabla y arma, dentro de la
-- transacción, la forma que tiene producción (ventas con ubicacion_id, estado y
-- es_prueba; ubicaciones con sede_dynamic_id). Todo se deshace al final.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-000000474000', 'ZZVTA', 'Tienda de laboratorio A', true, 'tienda'),
  ('00000000-0000-0000-0000-000000474001', 'ZZVTB', 'Tienda de laboratorio B', true, 'tienda');

-- Quienes consultan tienen cuenta (auth_user_id) que no existe en auth.users.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-000000474010', 'VtaAdmin', 'Lab', '00000000-0000-0000-0000-000000474000', 'admin', 'x',
   '00000000-0000-0000-0000-0000004740ff', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000474011', 'VtaLiderA', 'Lab', '00000000-0000-0000-0000-000000474000', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004740fe', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000474012', 'VtaLiderB', 'Lab', '00000000-0000-0000-0000-000000474001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000004740fd', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000474013', 'VtaIntegrante', 'Lab', '00000000-0000-0000-0000-000000474000', 'integrante', 'x',
   '00000000-0000-0000-0000-0000004740fc', '2024-01-01', 'activo');
set session_replication_role = origin;

-- ── 1-2 · Los dos números de una tienda ─────────────────────────────────────
select is(
  (select ritmo || '/' || minimo from fn_cobertura_por_venta('00000000-0000-0000-0000-000000474000')),
  '1.5/3', 'una tienda sin números propios usa los de partida: 1,5 compras por hora y 3 en piso');

update configuracion
   set valor = valor || '{"ZZVTA": {"ritmo": 2, "minimo": 4}}'::jsonb
 where clave = 'cobertura_por_venta';
select is(
  (select ritmo || '/' || minimo from fn_cobertura_por_venta('00000000-0000-0000-0000-000000474000')),
  '2/4', 'con los suyos, la tienda usa los suyos');

-- ── 3 · Con la tabla vieja del repo, la lectura FALLA: nunca devuelve cero ──
select throws_ok(
  $$ select * from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', fn_hoy_lima() - 1, fn_hoy_lima() - 1) $$,
  null, null, 'si retail no tiene la forma esperada, la función falla en vez de decir «no hubo venta»');

-- ── La forma de producción, dentro de la transacción ────────────────────────
alter table retail.ventas rename to ventas_del_repo_474;
create table retail.ventas (
  id uuid primary key default gen_random_uuid(),
  ubicacion_id uuid not null,
  estado text not null,
  es_prueba boolean not null default false,
  created_at timestamptz not null
);
create table if not exists retail.ubicaciones (id uuid primary key, sede_dynamic_id uuid);

insert into retail.ubicaciones (id, sede_dynamic_id) values
  ('00000000-0000-0000-0000-0000004741a0', '00000000-0000-0000-0000-000000474000'),
  ('00000000-0000-0000-0000-0000004741b0', '00000000-0000-0000-0000-000000474001');

-- El día D es ayer en Lima. Las horas se escriben en Lima (-05:00).
create temporary table _d as select fn_hoy_lima() - 1 as d;
insert into retail.ventas (ubicacion_id, estado, es_prueba, created_at)
select u, e, p, ((select d from _d)::timestamp + h::interval) at time zone 'America/Lima'
  from (values
    ('00000000-0000-0000-0000-0000004741a0'::uuid, 'completada', false, '10:15'),
    ('00000000-0000-0000-0000-0000004741a0'::uuid, 'completada', false, '10:40'),
    ('00000000-0000-0000-0000-0000004741a0'::uuid, 'completada', false, '11:05'),
    ('00000000-0000-0000-0000-0000004741a0'::uuid, 'anulada',    false, '10:20'),  -- anulada: no cuenta
    ('00000000-0000-0000-0000-0000004741a0'::uuid, 'completada', true,  '10:30'),  -- de prueba: no cuenta
    ('00000000-0000-0000-0000-0000004741b0'::uuid, 'completada', false, '10:10'),  -- otra tienda
    ('00000000-0000-0000-0000-0000004741a0'::uuid, 'completada', false, '23:30'),  -- ya es otro día en UTC
    ('00000000-0000-0000-0000-0000004741a0'::uuid, 'completada', false, '33:00')   -- el día siguiente, 09:00
  ) as x(u, e, p, h);

-- ── 4-7 · La cuenta ─────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004740ff', true);

select is(
  (select string_agg(hora || ':' || compras, ' ' order by hora)
     from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', (select d from _d), (select d from _d))),
  '10:2 11:1 23:1',
  'cuenta tickets completados por hora de Lima: sin anuladas, sin las de prueba, sin otra tienda');

select is(
  (select fecha from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', (select d from _d), (select d from _d))
    where hora = 23),
  (select d from _d), 'una compra de las 23:30 es de ese día en Lima, aunque en UTC ya sea el siguiente');

select is(
  (select sum(compras)::int from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', (select d from _d), (select d from _d) + 1)),
  5, 'el rango incluye su último día');

select is(
  (select sum(compras)::int from fn_compras_por_hora('00000000-0000-0000-0000-000000474001', (select d from _d), (select d from _d))),
  1, 'la otra tienda tiene solo lo suyo');

-- ── 8-10 · Quién puede ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004740fe', true);
select lives_ok(
  $$ select * from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', fn_hoy_lima() - 1, fn_hoy_lima() - 1) $$,
  'la líder de equipo lee las compras de su tienda');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004740fd', true);
select throws_ok(
  $$ select * from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', fn_hoy_lima() - 1, fn_hoy_lima() - 1) $$,
  null, null, 'la líder de otra tienda no las lee');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004740fc', true);
select throws_ok(
  $$ select * from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', fn_hoy_lima() - 1, fn_hoy_lima() - 1) $$,
  null, null, 'una integrante no las lee');

-- ── 11-12 · Rangos que no se aceptan ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004740ff', true);
select throws_ok(
  $$ select * from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', fn_hoy_lima() - 90, fn_hoy_lima()) $$,
  null, null, 'más de 62 días de una vez no');

select throws_ok(
  $$ select * from fn_compras_por_hora('00000000-0000-0000-0000-000000474000', fn_hoy_lima(), fn_hoy_lima() - 1) $$,
  null, null, 'un rango al revés no');

-- ── 13-14 · Nadie de afuera ─────────────────────────────────────────────────
select ok(
  not has_function_privilege('anon', 'fn_compras_por_hora(uuid,date,date)', 'EXECUTE'),
  'anon no ejecuta la lectura de compras');
select ok(
  has_function_privilege('authenticated', 'fn_cobertura_por_venta(uuid)', 'EXECUTE'),
  'quien inició sesión lee el ritmo y el mínimo de su tienda');

select * from finish();
rollback;
