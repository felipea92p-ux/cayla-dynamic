-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 357_eliminar_un_periodo_deja_rastro.test.sql — prueba de la 0452
-- ============================================================================
-- Eliminar el último periodo se llevaba en cascada los bonos, los descuentos y
-- las reversas de pago sin dejar nada. Desde la 0452 queda una fila en
-- periodos_eliminados con quién, cuándo, qué periodo y la foto de lo borrado.
--
-- Lo que se prueba, y por qué en este orden:
--   b) sin sesión de admin se rechaza y NO queda rastro;
--   c) con un grupo pagado se rechaza y NO queda rastro — se prueba ANTES del
--      borrado bueno sobre el mismo periodo, para que el rechazo sea por el
--      candado de pagado y no por «periodo inexistente»;
--   a) el borrado bueno deja UNA fila con la foto completa y el autor;
--   y que el rastro no se puede editar ni borrar.
--
-- Los periodos van en 2099 para ser, con seguridad, los ÚLTIMOS de la tabla:
-- el Postgres local es compartido y puede tener periodos de otras sesiones.
-- Todo dentro de begin/rollback.
-- ============================================================================
begin;
select plan(14);

select has_table('public', 'periodos_eliminados', 'Existe la tabla del rastro');

-- ── Semilla ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000357a00', 'ZZ357', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-000000357a01', 'Admin357', 'Laboratorio',
        '00000000-0000-0000-0000-000000357a00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000357a09');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-000000357a02', 'Integrante357', 'Laboratorio',
        '00000000-0000-0000-0000-000000357a00', 'test-hash');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000357b01', '2099-10-29', '2099-11-28', 'abierto'),
  ('00000000-0000-0000-0000-000000357b02', '2099-11-29', '2099-12-28', 'abierto');

-- Un descuento «ya pagado fuera de planilla» y un bono en el periodo a borrar.
-- El bono es de categoría 'cts' para no pasar por el candado de bono regular.
insert into movimientos_planilla (id, periodo_id, persona_id, tipo, categoria, concepto, monto) values
  ('00000000-0000-0000-0000-000000357c01', '00000000-0000-0000-0000-000000357b02',
   '00000000-0000-0000-0000-000000357a02', 'descuento', 'otros',
   'Ya pagado el 15/12 — fuera de planilla', 300.00),
  ('00000000-0000-0000-0000-000000357c02', '00000000-0000-0000-0000-000000357b02',
   '00000000-0000-0000-0000-000000357a02', 'bono', 'cts',
   'Bono de laboratorio', 120.50);

insert into reversas_pago (id, periodo_id, motivo, tipo) values
  ('00000000-0000-0000-0000-000000357d01', '00000000-0000-0000-0000-000000357b02',
   'Reapertura de laboratorio', 'reapertura');

-- ── b) Sin sesión de admin: rechazo, y ningún rastro ────────────────────────
select throws_like(
  $$ select fn_eliminar_periodo('00000000-0000-0000-0000-000000357b02'::uuid) $$,
  '%administrador%',
  'b · sin sesión de admin/líder, eliminar un periodo se rechaza');

select is(
  (select count(*)::int from periodos_eliminados where periodo_id = '00000000-0000-0000-0000-000000357b02'),
  0, 'b · el intento rechazado no deja rastro');

-- Desde aquí, sesión de admin.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000357a09', true);

-- ── c) Un grupo pagado: rechazo, y ningún rastro ────────────────────────────
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at)
values ('00000000-0000-0000-0000-000000357b02', 'rxh', 'pagado', now());

select throws_like(
  $$ select fn_eliminar_periodo('00000000-0000-0000-0000-000000357b02'::uuid) $$,
  '%pagado no se elimina%',
  'c · con un grupo pagado, el periodo no se elimina aunque seas admin');

select is(
  (select count(*)::int from periodos_eliminados where periodo_id = '00000000-0000-0000-0000-000000357b02'),
  0, 'c · el intento rechazado por grupo pagado no deja rastro');

-- El candado de «solo el último» sigue igual, y tampoco deja rastro.
select throws_like(
  $$ select fn_eliminar_periodo('00000000-0000-0000-0000-000000357b01'::uuid) $$,
  '%ÚLTIMO%',
  'c · un periodo que no es el último sigue sin poder eliminarse');

-- Se quita el grupo pagado (como superusuario de la prueba) para el caso bueno.
delete from periodo_grupo_pago where periodo_id = '00000000-0000-0000-0000-000000357b02';

-- ── a) El borrado bueno deja UNA fila con la foto y el autor ────────────────
select lives_ok(
  $$ select fn_eliminar_periodo('00000000-0000-0000-0000-000000357b02'::uuid) $$,
  'a · el admin elimina el último periodo sin pagar');

select is(
  (select count(*)::int from periodos_planilla where id = '00000000-0000-0000-0000-000000357b02')
  + (select count(*)::int from movimientos_planilla where periodo_id = '00000000-0000-0000-0000-000000357b02')
  + (select count(*)::int from reversas_pago where periodo_id = '00000000-0000-0000-0000-000000357b02'),
  0, 'a · el borrado sigue haciendo lo mismo: periodo, movimientos y reversas ya no están');

select is(
  (select count(*)::int from periodos_eliminados where periodo_id = '00000000-0000-0000-0000-000000357b02'),
  1, 'a · queda exactamente una fila de rastro');

select is(
  (select row(eliminado_por, fecha_ini, fecha_fin, estado)::text
     from periodos_eliminados where periodo_id = '00000000-0000-0000-0000-000000357b02'),
  row('00000000-0000-0000-0000-000000357a01'::uuid, '2099-11-29'::date, '2099-12-28'::date, 'abierto'::text)::text,
  'a · el rastro dice quién lo borró y qué periodo era');

select is(
  (select (select jsonb_agg(jsonb_build_object('id', e->>'id', 'persona_id', e->>'persona_id',
                                               'tipo', e->>'tipo', 'categoria', e->>'categoria',
                                               'concepto', e->>'concepto', 'monto', (e->>'monto')::numeric)
                            order by e->>'id')
             from jsonb_array_elements(movimientos) e)
     from periodos_eliminados where periodo_id = '00000000-0000-0000-0000-000000357b02'),
  jsonb_build_array(
    jsonb_build_object('id', '00000000-0000-0000-0000-000000357c01', 'persona_id', '00000000-0000-0000-0000-000000357a02',
                       'tipo', 'descuento', 'categoria', 'otros',
                       'concepto', 'Ya pagado el 15/12 — fuera de planilla', 'monto', 300.00),
    jsonb_build_object('id', '00000000-0000-0000-0000-000000357c02', 'persona_id', '00000000-0000-0000-0000-000000357a02',
                       'tipo', 'bono', 'categoria', 'cts',
                       'concepto', 'Bono de laboratorio', 'monto', 120.50)),
  'a · la foto guarda los dos movimientos borrados, con persona, tipo, concepto y monto');

select is(
  (select reversas->0->>'id' || ' | ' || (reversas->0->>'motivo')
     from periodos_eliminados where periodo_id = '00000000-0000-0000-0000-000000357b02'),
  '00000000-0000-0000-0000-000000357d01 | Reapertura de laboratorio',
  'a · la foto guarda la reversa de pago borrada');

-- ── El rastro no se toca ────────────────────────────────────────────────────
select throws_like(
  $$ update periodos_eliminados set estado = 'pagado' where periodo_id = '00000000-0000-0000-0000-000000357b02' $$,
  '%no se modifica ni se borra%',
  'el rastro no se puede editar');

select throws_like(
  $$ delete from periodos_eliminados where periodo_id = '00000000-0000-0000-0000-000000357b02' $$,
  '%no se modifica ni se borra%',
  'el rastro no se puede borrar');

select * from finish();
rollback;
