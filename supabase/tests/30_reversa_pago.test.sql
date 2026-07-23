-- ============================================================================
-- 30_reversa_pago.test.sql — Blindaje de la RED DE SEGURIDAD (reabrir un pago)
-- ============================================================================
-- Reabrir un periodo ya pagado toca dinero. La regla (mig 0066) es: solo un
-- admin/líder puede hacerlo, siempre con un motivo, y siempre deja rastro de
-- quién, cuándo y por qué. Esta prueba verifica que esas cerraduras funcionan.
--
-- fn_revertir_pago SÍ exige sesión de admin, así que aquí simulamos una:
--   · creamos una persona admin y le enlazamos un usuario de sesión. Saltamos el
--     chequeo de la llave foránea a auth.users (esquema que no controlamos) con
--     session_replication_role = replica, un modo de superusuario para cargar
--     datos sin disparar las restricciones. Se restaura enseguida.
--   · set_config de request.jwt.claim.sub hace que auth.uid() devuelva ese
--     usuario, y con eso el sistema reconoce al admin.
-- Todo dentro de begin/rollback: no queda nada, no toca datos reales.
-- ============================================================================
begin;
select plan(9);

-- ── Semilla ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

-- Un periodo PAGADO (el que vamos a revertir) y uno ABIERTO (para probar rechazo)
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at) values
  ('00000000-0000-0000-0000-0000000000c1', '2026-06-01', '2026-06-30', 'pagado', now()),
  ('00000000-0000-0000-0000-0000000000c2', '2026-05-01', '2026-05-30', 'abierto', null);

-- Persona admin, con un usuario de sesión enlazado. session_replication_role
-- salta la llave foránea personas.auth_user_id → auth.users solo para este insert.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('00000000-0000-0000-0000-0000000000aa', 'AdminPrueba', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'admin',
        '00000000-0000-0000-0000-0000000000ab');
set session_replication_role = origin;

-- ── 1) Sin sesión de admin, revertir un pago se rechaza (la cerradura existe) ─
select throws_like(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-0000000000c1'::uuid, 'motivo de prueba valido') $$,
  '%administrador%',
  'Sin sesión de admin/líder, revertir un pago se rechaza');

-- ── Simulamos la sesión del admin: auth.uid() pasa a ser su usuario ──────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000ab', true);

-- ── 2) Aun siendo admin, el motivo es obligatorio (mínimo 4 caracteres) ──────
select throws_like(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-0000000000c1'::uuid, 'ab') $$,
  '%motivo%',
  'Revertir sin un motivo válido se rechaza aunque seas admin');

-- ── 3) No se puede revertir un periodo que no está pagado ────────────────────
select throws_like(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-0000000000c2'::uuid, 'motivo válido de prueba') $$,
  '%pagado%',
  'Revertir un periodo abierto (no pagado) se rechaza');

-- ── 4) Con sesión de admin y motivo válido, la reversa procede ───────────────
select lives_ok(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-0000000000c1'::uuid, 'Corrección de monto de prueba') $$,
  'El admin puede revertir un pago con un motivo válido');

-- ── 5) El periodo volvió a estar ABIERTO ─────────────────────────────────────
select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-0000000000c1'),
  'abierto', 'Tras revertir, el periodo vuelve a estado abierto');

-- ── 6) ...y se le quitó la marca de pagado ───────────────────────────────────
select is(
  (select pagado_at from periodos_planilla where id = '00000000-0000-0000-0000-0000000000c1'),
  null::timestamptz, 'Tras revertir, el periodo ya no tiene fecha de pago');

-- ── 7) Quedó RASTRO: una fila en reversas_pago con el motivo exacto ──────────
select is(
  (select motivo from reversas_pago where periodo_id = '00000000-0000-0000-0000-0000000000c1'),
  'Corrección de monto de prueba', 'La reapertura deja rastro con el motivo escrito');

-- ── 8) El rastro registra QUIÉN reabrió (el admin de la sesión) ──────────────
select is(
  (select revertido_por from reversas_pago where periodo_id = '00000000-0000-0000-0000-0000000000c1'),
  '00000000-0000-0000-0000-0000000000aa'::uuid, 'El rastro registra quién reabrió el pago');

-- ── 9) El esquema hace IMPOSIBLE registrar una reapertura sin motivo ─────────
select col_not_null('reversas_pago', 'motivo',
  'El motivo es obligatorio a nivel de esquema: nunca hay reapertura sin razón');

select * from finish();
rollback;
