-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 449_la_etiqueta_de_prueba_tiene_fecha_de_corte.test.sql — la 0557
-- ============================================================================
-- Defiende lo que la 0557 le promete a «Parámetros» y a Equipo:
--   1. Es un parámetro OPERATIVO y EDITABLE, con topes (un tecleo no lo desborda).
--   2. `fn_prueba_etiqueta_desde()` entrega la fecha que diga la tabla, y un valor
--      ilegible (20261340) o ausente cae en la de partida: nunca revienta ni
--      rotula a nadie por un dato raro.
--   3. Cambiarlo pasa por la puerta de Parámetros: con motivo, con rastro, solo
--      admin/DO; un UPDATE directo desde el navegador se rechaza.
--   4. NO toca nada de plata: el cambio no mueve ninguna jornada ni planilla (la
--      0557 no reescribe ninguna función de pago).
-- ============================================================================
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000044901', 'ZZ449', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000004491c', 'do-449@local'),
  ('00000000-0000-0000-0000-00000004491e', 'raso-449@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000044913', 'Lider',  'DO',   '00000000-0000-0000-0000-000000044901',
   'lider_do', 'activo', 'x', '00000000-0000-0000-0000-00000004491c', '2024-01-01', null, 'planilla'),
  ('00000000-0000-0000-0000-000000044915', 'Raso',   'Raso', '00000000-0000-0000-0000-000000044901',
   'integrante', 'activo', 'x', '00000000-0000-0000-0000-00000004491e', '2024-01-01', null, 'planilla');
set session_replication_role = origin;

-- ── 1 · La fila del catálogo ────────────────────────────────────────────────
select is(
  (select clase || ' · ' || editable::text || ' · ' || valor_min || '-' || valor_max || ' · ' || unidad
     from parametros_catalogo where parametro = 'prueba_etiqueta_desde'),
  'operativo · true · 20260101-20301231 · fecha',
  'Es operativo, editable, con topes y se dibuja como fecha');

select ok((select valor is not null from configuracion where clave = 'prueba_etiqueta_desde'),
  'Su clave existe en configuracion (la migración la siembra)');

-- ── 2 · La función ──────────────────────────────────────────────────────────
-- Por defecto la siembra es «hoy en Lima» al pegar; aquí se fija un valor conocido.
select set_config('cayla.parametro_actor', '00000000-0000-0000-0000-000000044913', true);
select set_config('cayla.parametro_motivo', 'laboratorio', true);
update configuracion set valor = to_jsonb(20261026) where clave = 'prueba_etiqueta_desde';
select is(fn_prueba_etiqueta_desde(), date '2026-10-26', 'Entrega la fecha que dice la tabla');

update configuracion set valor = to_jsonb(20260726) where clave = 'prueba_etiqueta_desde';
select is(fn_prueba_etiqueta_desde(), date '2026-07-26', 'Llevada atrás, entrega la fecha atrasada');

-- Un dato raro cae en la de partida, nunca revienta ni corre la fecha.
-- (El trigger de la 0552 exige 20260101–20301231; el valor imposible 20261340 sí cabe en ese rango.)
update configuracion set valor = to_jsonb(20261340) where clave = 'prueba_etiqueta_desde';
select is(fn_prueba_etiqueta_desde(), date '2026-10-26',
  'Una fecha imposible (20261340) cae en la de partida, no se corre al año siguiente');

update configuracion set valor = to_jsonb(20260230) where clave = 'prueba_etiqueta_desde';
select is(fn_prueba_etiqueta_desde(), date '2026-10-26', 'Un 30 de febrero tampoco se acepta ni se corre a marzo');

delete from configuracion where clave = 'prueba_etiqueta_desde';
select is(fn_prueba_etiqueta_desde(), date '2026-10-26', 'Sin la clave, cae en la de partida');
insert into configuracion (clave, valor, descripcion)
  values ('prueba_etiqueta_desde', to_jsonb(20261026), 'laboratorio');

-- ── 3 · La puerta ───────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004491c', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar('prueba_etiqueta_desde', 20260726, 'Rotular a todo el que lleva menos de tres meses') $$,
  'DO puede mover la fecha, con motivo');
select is(fn_prueba_etiqueta_desde(), date '2026-07-26', 'Y la función ya entrega la nueva');
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_etiqueta_desde', 20620726, 'Un tecleo') $$,
  'P0001', null,
  'Un 2062 por un 2026 se rechaza por el tope');
select throws_ok(
  $$ update configuracion set valor = to_jsonb(20260101) where clave = 'prueba_etiqueta_desde' $$,
  'Este valor se cambia desde Parámetros, no con una escritura directa a la tabla.',
  'BLOQUEADO · un UPDATE directo desde el navegador');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004491e', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar('prueba_etiqueta_desde', 20260901, 'Quiero cambiarlo') $$,
  'P0001', null,
  'Una integrante sin cargo no puede mover la fecha');
reset role;

-- ── 4 · Deja rastro ─────────────────────────────────────────────────────────
select is(
  (select count(*)::int from parametros_historial
    where parametro = 'prueba_etiqueta_desde' and origen = 'pantalla'
      and motivo = 'Rotular a todo el que lleva menos de tres meses'),
  1, 'El cambio de DO quedó en el historial de Parámetros');

select * from finish();
rollback;
