-- ============================================================================
-- 142_el_cargo_no_toca_los_permisos.test.sql — fn_set_cargo (migración 0182)
-- ============================================================================
-- El cargo existe para que la pantalla pueda decir «Socia» o «Asesor» sin tocar
-- lo que esa persona puede abrir. Toda esta prueba defiende esa frontera, porque
-- la alternativa que se descartó —agregar «socio» y «asesor» al enum de roles—
-- habría dejado a un locador sin el acceso que su trabajo necesita, y porque
-- mezclar «qué eres» con «qué puedes ver» es el enredo que este campo separa.
--
-- Lo que se blinda:
--   1 · escribir un cargo NO cambia el rol ni ningún permiso;
--   2 · vacío y solo-espacios se guardan como NULL, no como cadena vacía: en
--       pantalla se ven igual y solo una se comporta como «sin cargo»;
--   3 · deja rastro en auditoría, porque cambiar cómo se nombra a alguien no
--       debe ser silencioso aunque no mueva un céntimo;
--   4 · es idempotente: repetir el mismo cargo no ensucia la auditoría;
--   5 · solo admin o líder DO pueden escribirlo.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ca', 'ZZCARGO', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000ca90', 'CargoAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ca', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000ca900');
set session_replication_role = origin;

-- Una locadora con rol de mando: el caso real que originó la migración.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000ca01', 'CargoSocia', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ca', 'test-hash', 'supervisor_sede', 'rxh');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ca900', true);

-- ── De partida ──────────────────────────────────────────────────────────────
select is(
  (select cargo from personas where id = '00000000-0000-0000-0000-00000000ca01'),
  null, 'DE PARTIDA · nadie tiene cargo: la pantalla muestra la etiqueta del rol');

-- ── 1 · El cargo se escribe y el permiso no se mueve ────────────────────────
select lives_ok(
  $$ select fn_set_cargo('00000000-0000-0000-0000-00000000ca01', 'Socia') $$,
  'Un admin puede fijar el cargo');

select is(
  (select cargo from personas where id = '00000000-0000-0000-0000-00000000ca01'),
  'Socia', 'El cargo quedó escrito');

-- La aserción que da sentido a toda la migración.
select is(
  (select rol::text from personas where id = '00000000-0000-0000-0000-00000000ca01'),
  'supervisor_sede',
  'EL ROL NO SE MOVIÓ · el cargo dice qué es, el rol sigue diciendo qué abre');

select is(
  (select tipo_vinculo from personas where id = '00000000-0000-0000-0000-00000000ca01'),
  'rxh',
  'Y el tipo de vínculo tampoco: el cargo no decide si alguien está en planilla');

-- ── 2 · Vacío y solo-espacios vuelven a NULL ────────────────────────────────
-- Una cadena vacía se ve igual que «sin cargo» en pantalla y se comporta
-- distinto en cualquier consulta que pregunte `cargo is null`.
select lives_ok(
  $$ select fn_set_cargo('00000000-0000-0000-0000-00000000ca01', '   ') $$,
  'Se acepta borrar el cargo con espacios');

select is(
  (select cargo from personas where id = '00000000-0000-0000-0000-00000000ca01'),
  null, 'Solo espacios se guarda como NULL, no como cadena vacía');

-- ── 3 y 4 · Rastro en auditoría, y solo cuando algo cambia ──────────────────
select fn_set_cargo('00000000-0000-0000-0000-00000000ca01', 'Asesora');
select fn_set_cargo('00000000-0000-0000-0000-00000000ca01', 'Asesora');  -- repetido

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-00000000ca01' and campo_modificado = 'cargo'),
  3,
  'Tres cambios reales dejan tres filas; repetir el mismo cargo no ensucia la auditoría');

-- ── 5 · El guard ────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ca999', true);

select throws_like(
  $$ select fn_set_cargo('00000000-0000-0000-0000-00000000ca01', 'Gerente General') $$,
  '%administrador o líder%',
  'Sin sesión de admin nadie cambia cómo se nombra a otra persona');

select * from finish();
rollback;
