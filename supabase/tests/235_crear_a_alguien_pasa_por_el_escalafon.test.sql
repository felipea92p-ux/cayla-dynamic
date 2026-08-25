-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 235_crear_a_alguien_pasa_por_el_escalafon.test.sql
-- ============================================================================
-- Defiende la 0300. `fn_crear_persona` exigía `fn_es_admin_o_lider()` para dar
-- de alta a alguien, y después aceptaba CUALQUIERA de los cuatro roles —
-- incluido 'admin'— sin mirar quién los estaba dando. Un lider_do podía crear
-- una cuenta NUEVA directamente como Admin, sin pasar por ninguna de las dos
-- puertas que la 0295/0296 ya habían cerrado para el rol de alguien que YA
-- existía.
--
-- Medido antes de escribir esta prueba, en el Postgres local: un lider_do
-- lograba `fn_crear_persona(..., p_rol => 'admin', ...)` sin ningún error.
-- Con la 0300 aplicada, la misma llamada da "No puedes crear una persona con
-- un rol igual o superior al tuyo."
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000023500', 'ZZ235', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000023501', 'LiderDO', 'Atacante', '00000000-0000-0000-0000-000000023500',
   'lider_do', 'x', '00000000-0000-0000-0000-0000000235a1', '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000235a1', true);
set role authenticated;

-- ── 1 · EL ATAQUE: crear una cuenta NUEVA directamente como Admin ─────────
select throws_ok(
  $$ select fn_crear_persona('Complice', 'Nueva', '00000000-0000-0000-0000-000000023500',
                             'admin', 'calidad_servicio', null, 'x') $$,
  'No puedes crear una persona con un rol igual o superior al tuyo.',
  'BLOQUEADO · un lider_do no puede crear una cuenta nueva como Admin');

-- ── 2 · Ni crear a un par (otro lider_do) ───────────────────────────────────
select throws_ok(
  $$ select fn_crear_persona('Otro', 'LiderDO', '00000000-0000-0000-0000-000000023500',
                             'lider_do', 'calidad_servicio', null, 'x') $$,
  'No puedes crear una persona con un rol igual o superior al tuyo.',
  'BLOQUEADO · tampoco puede crear a un par de su propio rango');

-- ── 3 · Lo que SÍ tiene que seguir funcionando: crear por debajo ───────────
select lives_ok(
  $$ select fn_crear_persona('Nueva', 'Integrante', '00000000-0000-0000-0000-000000023500',
                             'integrante', 'calidad_servicio', null, 'x') $$,
  'PERMITIDO · un lider_do sí puede crear a alguien como integrante, como siempre');

select lives_ok(
  $$ select fn_crear_persona('Nueva', 'Encargada', '00000000-0000-0000-0000-000000023500',
                             'supervisor_sede', 'calidad_servicio', null, 'x') $$,
  'PERMITIDO · y también como supervisor_sede, que sigue por debajo de lider_do');

reset role;

-- ── 5 · Las cinco validaciones de siempre no se movieron ───────────────────
-- Un rol fuera del catálogo sigue fallando con SU mensaje propio, no con el
-- del escalafón — confirma que el orden de las comprobaciones no se rompió.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000235a1', true);
set role authenticated;
select throws_ok(
  $$ select fn_crear_persona('Malo', 'Rol', '00000000-0000-0000-0000-000000023500',
                             'gerente', 'calidad_servicio', null, 'x') $$,
  'Rol inválido: gerente',
  'SIN ROMPER LO VIEJO · un rol fuera del catálogo sigue dando su propio error');

reset role;
select * from finish();
rollback;
