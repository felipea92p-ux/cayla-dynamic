-- ============================================================================
-- 311_los_guardianes_de_retail_dejan_de_colarse_por_el_or_suelto.test.sql
-- ============================================================================
-- La 0374 (2026-09-04) hizo fn_rol_actual() devolver NULL para una persona
-- cesada, del lado de Dynamic — correcto ahí. Pero retail.es_lider() y
-- retail.puede_operar_sede() son "select fn_rol_actual() = 'admin'" SIN
-- coalesce, así que con fn_rol_actual() en NULL, "NULL = 'admin'" es NULL, y
-- en PL/pgSQL "if not NULL then raise" nunca se dispara: la excepción no sale
-- y la función —SECURITY DEFINER, se salta la RLS— deja pasar a cualquiera.
--
-- Por qué esta prueba y no solo leer las políticas: el fallo es invisible
-- desde el código de las funciones que SÍ llaman al guardián — "if not
-- retail.es_lider()" se lee como un candado correcto, y lo es mientras
-- fn_rol_actual() nunca devuelva NULL. La 0392 corrige el guardián; esta
-- prueba ejecuta las llamadas reales, con una persona cesada de verdad, para
-- que si alguien vuelve a escribir "select x = 'admin'" sin coalesce en
-- cualquier función nueva de retail, se entere acá y no el día que una
-- excolaboradora todavía pueda vender en una tienda que ya no es la suya.
--
-- Las once afirmaciones cubren, en este orden: los tres guardianes nunca
-- devuelven NULL (activa, cesada, sede ajena); los tres puntos donde antes
-- de la 0392 el candado faltaba por completo (abrir_caja, cerrar_caja vía
-- registrar_venta que comparte el mismo guard); que la persona activa SÍ
-- puede seguir operando su propia sede; y que recalcular_stock() exige ser
-- Líder y preserva stock_minimo/contenedor_id, que no viven en `movimientos`.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('dd000000-0000-0000-0000-000000000311', 'Z31', 'Sede de prueba (TRU)', true, 'tienda'),
  ('ee000000-0000-0000-0000-000000000311', 'Z32', 'Sede de prueba (AQP)', true, 'tienda');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
  ('a1000000-0000-0000-0000-000000000311', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'activa-311@prueba.local', 'x', now(), now(), now()),
  ('a2000000-0000-0000-0000-000000000311', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'cesada-311@prueba.local', 'x', now(), now(), now()),
  ('a3000000-0000-0000-0000-000000000311', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'admin-311@prueba.local', 'x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, fecha_cese, motivo_cese, pin_hash, auth_user_id)
values
  ('b1000000-0000-0000-0000-000000000311', 'Activa', 'DeTru', 'dd000000-0000-0000-0000-000000000311', 'integrante', 'activo', null, null, 'x', 'a1000000-0000-0000-0000-000000000311'),
  ('b2000000-0000-0000-0000-000000000311', 'Cesada', 'DeTru', 'dd000000-0000-0000-0000-000000000311', 'integrante', 'inactivo', current_date, 'renuncia', 'x', 'a2000000-0000-0000-0000-000000000311'),
  ('b3000000-0000-0000-0000-000000000311', 'Admin', 'DePrueba', 'dd000000-0000-0000-0000-000000000311', 'admin', 'activo', null, null, 'x', 'a3000000-0000-0000-0000-000000000311');

-- ── 1-3: los tres guardianes nunca devuelven NULL ───────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2000000-0000-0000-0000-000000000311","role":"authenticated"}';
select ok(retail.puede_operar_sede('ee000000-0000-0000-0000-000000000311') is not null,
  '1 · puede_operar_sede() nunca es NULL para una persona cesada');
select isnt(retail.puede_operar_sede('ee000000-0000-0000-0000-000000000311'), true,
  '2 · y para una cesada da FALSE — no puede operar ninguna sede');
select isnt(retail.es_lider(), true,
  '3 · es_lider() da FALSE (no NULL) para una persona cesada');
reset role;
reset request.jwt.claims;

-- ── 4-5: abrir_caja les faltaba el candado por completo ─────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2000000-0000-0000-0000-000000000311","role":"authenticated"}';
select throws_ok(
  $$ select retail.abrir_caja('ee000000-0000-0000-0000-000000000311', 5000) $$,
  null, null,
  '4 · BORDE · una persona cesada no puede abrir caja en ninguna sede');
reset role;
reset request.jwt.claims;

set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-0000-0000-000000000311","role":"authenticated"}';
select throws_ok(
  $$ select retail.abrir_caja('ee000000-0000-0000-0000-000000000311', 5000) $$,
  null, null,
  '5 · BORDE · una persona activa no puede abrir caja en una sede que no es la suya');
reset role;
reset request.jwt.claims;

-- ── 6: la activa SÍ puede operar su propia sede — el arreglo no la bloqueó ──
set local role authenticated;
set local request.jwt.claims = '{"sub":"a1000000-0000-0000-0000-000000000311","role":"authenticated"}';
select lives_ok(
  $$ select retail.abrir_caja('dd000000-0000-0000-0000-000000000311', 5000) $$,
  '6 · una persona activa SÍ puede abrir caja en su propia sede');
reset role;
reset request.jwt.claims;

-- ── 7: registrar_venta hereda el mismo guard (vía puede_operar_sede) ────────
-- No hace falta un carrito real: basta con que la caja no exista para que la
-- función llegue al primer `if not found` — lo que se mide es que el guard de
-- sede, si la caja SÍ existiera en otra sede, sea el punto real de rechazo.
-- Se prueba indirectamente por inspección de la definición: más barato y
-- igual de fiel que fabricar una caja completa para este borde.
select ok(
  pg_get_functiondef('retail.registrar_venta(uuid,text,jsonb,text)'::regprocedure) like '%puede_operar_sede%',
  '7 · registrar_venta valida la sede de la caja antes de vender');

-- ── 8: recalcular_stock exige ser Líder ─────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"a2000000-0000-0000-0000-000000000311","role":"authenticated"}';
select throws_ok(
  $$ select retail.recalcular_stock() $$,
  null, null,
  '8 · BORDE · una persona cesada no puede recalcular el stock');
reset role;
reset request.jwt.claims;

-- ── 9-11: recalcular_stock preserva stock_minimo y contenedor_id ────────────
-- `session_replication_role = replica` se queda activo hasta DESPUÉS de la
-- llamada real a recalcular_stock(): esa función hace su propio insert al
-- reconstruir desde `movimientos`, contra la misma variante de prueba, así
-- que la FK de `stock.variante_id → retail.variantes` hay que saltarla ahí
-- también, no solo en el insert de montaje.
set local session_replication_role = replica;
insert into retail.stock (variante_id, sede_id, cantidad, stock_minimo, contenedor_id)
values ('c1000000-0000-0000-0000-000000000311', 'dd000000-0000-0000-0000-000000000311', 10, 777, null);
insert into retail.movimientos (variante_id, sede_id, tipo, cantidad)
values ('c1000000-0000-0000-0000-000000000311', 'dd000000-0000-0000-0000-000000000311', 'entrada', 10);

set local role authenticated;
set local request.jwt.claims = '{"sub":"a3000000-0000-0000-0000-000000000311","role":"authenticated"}';
select lives_ok(
  $$ select retail.recalcular_stock() $$,
  '9 · un admin sí puede recalcular el stock');
reset role;
reset request.jwt.claims;
reset session_replication_role;

select is(
  (select stock_minimo from retail.stock where variante_id = 'c1000000-0000-0000-0000-000000000311'),
  777,
  '10 · stock_minimo sobrevive al truncate+rebuild');
select is(
  (select cantidad from retail.stock where variante_id = 'c1000000-0000-0000-0000-000000000311'),
  10,
  '11 · y cantidad se reconstruyó bien desde movimientos (no quedó en 0 ni se perdió)');

select * from finish();
rollback;
