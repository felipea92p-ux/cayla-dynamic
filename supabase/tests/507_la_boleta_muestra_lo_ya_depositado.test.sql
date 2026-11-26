-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- ============================================================================
-- 507 — La boleta muestra lo ya depositado (0622)
-- ============================================================================
-- Tres cosas: que devuelve solo lo del periodo, que cada persona ve lo suyo y
-- nada más, y que no deja salir la nota interna de DO.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000507fa', 'ZZ507', 'Sede de laboratorio 507', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000507a1', 'Admin507', 'Lab', '00000000-0000-0000-0000-0000000507fa',
   'admin', 'h', '00000000-0000-0000-0000-0000000507a9', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000507b1', 'Integrante507', 'Lab', '00000000-0000-0000-0000-0000000507fa',
   'integrante', 'h', '00000000-0000-0000-0000-0000000507b9', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000507c1', 'Otra507', 'Lab', '00000000-0000-0000-0000-0000000507fa',
   'integrante', 'h', '00000000-0000-0000-0000-0000000507c9', '2024-01-15', 'planilla');

-- La CTS de noviembre y su regularización de mayo, el 14-nov (dentro del
-- periodo 29-oct → 28-nov), y la CTS de mayo, el 15-may (fuera).
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen, nota) values
  ('00000000-0000-0000-0000-0000000507b1', 'cts_nov', 2026, 331.23, '2026-11-14', 'transferencia', 'NOTA INTERNA'),
  ('00000000-0000-0000-0000-0000000507b1', 'cts_may', 2026, 164.79, '2026-11-14', 'transferencia', 'NOTA INTERNA'),
  ('00000000-0000-0000-0000-0000000507b1', 'cts_may', 2026, 141.25, '2026-05-15', 'plame', null),
  ('00000000-0000-0000-0000-0000000507c1', 'cts_nov', 2026, 200.00, '2026-11-14', 'transferencia', null);
set session_replication_role = origin;

-- ── Como admin ──────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000507a9', true);

select is((select count(*)::int from fn_boleta_depositos('00000000-0000-0000-0000-0000000507b1', '2026-10-29', '2026-11-28')),
          2, 'PERIODO · trae los dos pagos del 14-nov y deja fuera el de mayo');
select is((select sum(monto) from fn_boleta_depositos('00000000-0000-0000-0000-0000000507b1', '2026-10-29', '2026-11-28')),
          496.02::numeric, 'PERIODO · por S/ 496.02');
select is((select string_agg(ventana, ',') from fn_boleta_depositos('00000000-0000-0000-0000-0000000507b1', '2026-10-29', '2026-11-28')),
          'cts_may,cts_nov', 'ORDEN · mismo día: siempre en el mismo orden');
select is((select count(*)::int from fn_boleta_depositos('00000000-0000-0000-0000-0000000507b1', '2026-04-29', '2026-05-28')),
          1, 'MAYO · la boleta de mayo muestra la CTS de mayo');

-- La nota interna no viaja por ningún lado de la respuesta.
select ok(not exists (select 1 from fn_boleta_depositos('00000000-0000-0000-0000-0000000507b1', '2026-10-29', '2026-11-28') x
                       where x::text like '%NOTA INTERNA%'),
          'PRIVACIDAD · la nota interna de DO no sale en la boleta');

-- ── Como la propia integrante ───────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000507b9', true);

select is((select count(*)::int from fn_boleta_depositos('00000000-0000-0000-0000-0000000507b1', '2026-10-29', '2026-11-28')),
          2, 'LO MÍO · cada persona ve lo depositado a su nombre');

select throws_ok($$ select * from fn_boleta_depositos('00000000-0000-0000-0000-0000000507c1', '2026-10-29', '2026-11-28') $$,
                 'P0001', 'Solo puedes ver lo depositado a tu nombre.',
                 'LO MÍO · y no lo de una compañera');

select * from finish();
rollback;
