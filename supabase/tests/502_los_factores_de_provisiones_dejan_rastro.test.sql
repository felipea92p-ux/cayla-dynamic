-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 502_los_factores_de_provisiones_dejan_rastro.test.sql — la 0617
-- ============================================================================
-- Fija:
--   · Los cuatro factores de planilla_provisiones están en Parámetros, en solo
--     lectura y como normativos (solo la dirección).
--   · Un cambio hecho como `postgres` (el SQL Editor) deja su fila en el
--     historial, marcada «base».
--   · Una escritura directa de una admin desde el navegador queda rechazada.
--     Sin la 0617 pasaba: medido el 2026-11-13, una fila escrita y ningún rastro.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000502a01', 'ZZ502', 'Sede de laboratorio 502', true);
set session_replication_role = replica;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000502a1d', 'admin-502@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000502b14', 'Direccion', 'Admin', '00000000-0000-0000-0000-000000502a01',
        'admin', 'activo', 'x', '00000000-0000-0000-0000-000000502a1d', '2024-01-01', 'planilla');
set session_replication_role = origin;

select is(
  (select count(*)::int from parametros_catalogo
    where parametro in ('provision_gratificacion', 'provision_cts', 'provision_sexto_cts', 'provision_vacaciones')
      and clase = 'normativo' and not editable and almacen_clave = 'planilla_provisiones'
      and roles_cambia = array['admin']),
  4, 'Los cuatro factores están en Parámetros, normativos y en solo lectura');

select is(
  (select array_agg(ruta[1] order by orden) from parametros_catalogo where parametro like 'provision\_%'),
  array['gratificacion', 'cts', 'sexto_cts', 'vacaciones'],
  'Cada uno apunta a su campo de planilla_provisiones');

-- El SQL Editor corre como postgres: el cambio pasa, y queda escrito.
update configuracion set valor = valor || '{"sexto_cts": 0.111}'::jsonb where clave = 'planilla_provisiones';
select is(
  (select origen || ' · ' || valor_nuevo::text from parametros_historial
    where parametro = 'provision_sexto_cts' order by cambiado_at desc, id desc limit 1),
  'base · 0.111',
  'Un cambio desde el SQL Editor deja su fila en el historial, marcada «base»');

-- Una admin desde el navegador: rechazada.
select set_config('request.jwt.claims',
  json_build_object('sub', '00000000-0000-0000-0000-000000502a1d', 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000502a1d', true);
set local role authenticated;
select throws_ok(
  $$update configuracion set valor = valor || '{"cts": 0.5}'::jsonb where clave = 'planilla_provisiones'$$,
  'P0001', 'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.',
  'Una escritura directa desde el navegador sobre los factores queda rechazada');
reset role;

select is(
  (select (valor->>'cts')::numeric from configuracion where clave = 'planilla_provisiones') <> 0.5,
  true, 'Y el factor de la CTS no se movió');

select * from finish();
rollback;
