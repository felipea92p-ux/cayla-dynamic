-- ============================================================================
-- 121_el_libro_de_desembolsos.test.sql
-- ============================================================================
-- Esta tabla vivió meses solo en producción, creada a mano y sin ninguna
-- protección: `anon` con TRUNCATE, `authenticated` con INSERT, UPDATE y DELETE.
-- La 0153 la cerró allá y la 0155 la trajo al repositorio.
--
-- Lo que este archivo defiende son las dos mitades que se rompen por separado:
--
--   1. Que siga cerrada. Es un libro de plata entregada a personas; que el
--      terminal de una tienda pueda leerlo o borrarlo no es aceptable.
--   2. Que sus reglas sigan siendo las de producción. Si alguien "ordena" la
--      lista de ventanas o afloja el rango de años, el laboratorio deja de
--      parecerse a producción y el comparador empieza a mentir.
--
-- Las cinco ventanas no son una lista arbitraria: son los momentos en que la
-- ley peruana obliga a entregar algo. Cambiarlas es cambiar el negocio.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000de00', 'ZZDES', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000de01', 'DesemAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000de00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000de09');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000de02', 'DesemPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000de00', 'test-hash');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000de09', true);

-- ── 1 · Sigue cerrada ───────────────────────────────────────────────────────
select ok(
  (select relrowsecurity from pg_class where relname = 'desembolsos_beneficios'),
  'LLAVE · la tabla tiene RLS activo');

select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_name = 'desembolsos_beneficios' and grantee = 'authenticated'
      and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')),
  0,
  'LLAVE · ninguna sesión con login puede escribirla');

select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_name = 'desembolsos_beneficios' and grantee = 'anon'),
  0,
  'LLAVE · y sin sesión no se ve nada — antes `anon` tenía hasta TRUNCATE');

set local role authenticated;
select throws_ok(
  $$ delete from desembolsos_beneficios $$,
  null, null,
  'TERMINAL · una sesión con login no puede borrar el libro');
reset role;

-- ── 2 · Sus reglas son las de producción ────────────────────────────────────
select lives_ok(
  $$ insert into desembolsos_beneficios
       (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-00000000de02', 'cts_may', 2026, 1130.00,
             '2026-05-15', 'transferencia') $$,
  'REGLAS · un desembolso normal de CTS de mayo entra');

select throws_ok(
  $$ insert into desembolsos_beneficios
       (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-00000000de02', 'aguinaldo', 2026, 500,
             '2026-05-15', 'transferencia') $$,
  null, null,
  'REGLAS · una ventana inventada se rechaza: son cinco y las fija la ley');

select throws_ok(
  $$ insert into desembolsos_beneficios
       (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-00000000de02', 'cts_nov', 2026, 0,
             '2026-11-15', 'transferencia') $$,
  null, null,
  'REGLAS · un desembolso de cero no es un desembolso');

select throws_ok(
  $$ insert into desembolsos_beneficios
       (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-00000000de02', 'grati_s1', 2019, 500,
             '2019-07-15', 'transferencia') $$,
  null, null,
  'REGLAS · un año anterior a 2020 se rechaza: CAYLA no operaba con este sistema');

select throws_ok(
  $$ insert into desembolsos_beneficios
       (persona_id, ventana, anio, monto, fecha_pago, origen)
     values ('00000000-0000-0000-0000-00000000de02', 'grati_s2', 2026, 500,
             '2026-12-15', 'efectivo') $$,
  null, null,
  'REGLAS · un origen fuera de la lista se rechaza: plame, transferencia u otro');

select * from finish();
rollback;
