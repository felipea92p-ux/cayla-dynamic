-- ============================================================================
-- 473_el_almacen_es_solo_de_las_tiendas.test.sql
-- ============================================================================
-- Lo que defiende (migración 0583, pedido de Felipe del 2026-11-03):
-- «Voy a almacén» es solo de las tiendas. `fn_registrar_cambio_ubicacion` se
-- niega si la sede donde se registra no es `tienda`, o si la sede base de la
-- persona no lo es — desde el terminal y desde el panel. Lo de tienda sigue
-- funcionando igual que con la 0580 (eso lo cubre además la prueba 469).
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000a2a00', 'ZZTIE', 'Tienda de laboratorio',  true, 'tienda'),
  ('00000000-0000-0000-0000-0000000a2b00', 'ZZCEN', 'Central de laboratorio', true, 'central'),
  ('00000000-0000-0000-0000-0000000a2c00', 'ZZTAL', 'Taller de laboratorio',  true, 'taller');

set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, auth_user_id, activo) values
  ('00000000-0000-0000-0000-0000000a2a0e', '00000000-0000-0000-0000-0000000a2a00', 'Mac mini tienda',
   '00000000-0000-0000-0000-0000000a2a09', true),
  ('00000000-0000-0000-0000-0000000a2b0e', '00000000-0000-0000-0000-0000000a2b00', 'Mac mini central',
   '00000000-0000-0000-0000-0000000a2b09', true),
  ('00000000-0000-0000-0000-0000000a2c0e', '00000000-0000-0000-0000-0000000a2c00', 'Mac mini taller',
   '00000000-0000-0000-0000-0000000a2c09', true);
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000a2dd1', 'AdminLab', 'Lab', '00000000-0000-0000-0000-0000000a2b00', 'admin', 'x',
   '00000000-0000-0000-0000-0000000a2dd9');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, visible_todas_sedes) values
  ('00000000-0000-0000-0000-0000000a2001', 'DeTienda',  'Lab', '00000000-0000-0000-0000-0000000a2a00', 'x', false),
  ('00000000-0000-0000-0000-0000000a2002', 'DeCentral', 'Lab', '00000000-0000-0000-0000-0000000a2b00', 'x', true),
  ('00000000-0000-0000-0000-0000000a2003', 'DelTaller', 'Lab', '00000000-0000-0000-0000-0000000a2c00', 'x', false);

-- ── Desde el terminal ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a2a09', true);
select lives_ok($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2001', 'almacen', now(),
    gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a2a0e')
$$, 'TIENDA · alguien de la tienda, en el terminal de la tienda: se registra');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2002', 'almacen', now(),
    gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a2a0e')
$$, '%solo para el equipo de tienda%', 'TIENDA · alguien de Central de visita en la tienda: no va «al almacén»');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a2b09', true);
select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2002', 'almacen', now(),
    gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a2b0e')
$$, '%esta sede no es tienda%', 'CENTRAL · su terminal no registra almacén');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a2c09', true);
select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2003', 'almacen', now(),
    gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a2c0e')
$$, '%esta sede no es tienda%', 'TALLER · su terminal no registra almacén');

-- ── Desde el panel ─────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a2dd9', true);
select lives_ok($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2001', 'tienda', now(),
    gen_random_uuid(), 'panel', null, null, '00000000-0000-0000-0000-0000000a2a00')
$$, 'PANEL · en la tienda, admin registra');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2003', 'almacen', now(),
    gen_random_uuid(), 'panel', null, null, '00000000-0000-0000-0000-0000000a2c00')
$$, '%esta sede no es tienda%', 'PANEL · ni admin registra almacén en el taller');

-- ── Lo guardado no se pierde ───────────────────────────────────────────────
-- Un reintento de la cola con el mismo client_uuid sigue contestando, aunque la
-- sede haya dejado de ser tienda después: la idempotencia va antes que la regla.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a2a09', true);
select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2001', 'almacen', now(),
  '00000000-0000-0000-0000-0000000a2c11', 'terminal', '00000000-0000-0000-0000-0000000a2a0e');
update sedes set tipo = 'central' where id = '00000000-0000-0000-0000-0000000a2a00';
select lives_ok($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a2001', 'almacen', now(),
    '00000000-0000-0000-0000-0000000a2c11', 'terminal', '00000000-0000-0000-0000-0000000a2a0e')
$$, 'COLA · el reintento de algo ya guardado no se rechaza');
select is((select count(*)::int from cambios_ubicacion where client_uuid = '00000000-0000-0000-0000-0000000a2c11'),
  1, 'COLA · y no duplica');

select * from finish();
rollback;
