-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 232_el_rol_ya_no_se_asigna_solo.test.sql
-- ============================================================================
-- Defiende la 0295 y la 0296. Quien lleva Desarrollo Organizacional podía
-- entrar a su propia ficha en /admin/equipo, abrir el desplegable de Rol
-- —que ofrece «Admin» igual que ofrece «Integrante»— y guardarse a sí misma
-- como Admin. Sin autorización de nadie más y sin dejar rastro.
--
-- Medido antes de escribir esta prueba, en el Postgres local: un lider_do
-- lograba ponerse rol='admin' con un UPDATE directo. Con las dos migraciones
-- aplicadas, el mismo UPDATE da "El rol se cambia con fn_set_rol, no con un
-- update directo."
--
-- OJO CON EL `session_replication_role`. Montar el fixture con
-- `= replica` y no devolverlo a `origin` antes de simular el ataque apaga en
-- silencio TODOS los triggers de la sesión, incluido el que esta prueba
-- defiende — un falso negativo que parece "no hay bug" y es justo lo
-- contrario. Por eso el `set local session_replication_role = origin;`
-- de la línea de abajo no es cosmético.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000023200', 'ZZ232', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000023201', 'LiderDO',    'Atacante', '00000000-0000-0000-0000-000000023200',
   'lider_do',   'x', '00000000-0000-0000-0000-0000000232a1', '2024-01-01'),
  ('00000000-0000-0000-0000-000000023202', 'Admin',      'Real',     '00000000-0000-0000-0000-000000023200',
   'admin',      'x', '00000000-0000-0000-0000-0000000232a2', '2024-01-01'),
  ('00000000-0000-0000-0000-000000023203', 'Integrante', 'Base',     '00000000-0000-0000-0000-000000023200',
   'integrante', 'x', null,                                    '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000232a1', true);
set role authenticated;

-- ── 1 · EL ATAQUE ORIGINAL: update directo, dándose Admin a sí misma ───────
select throws_ok(
  $$ update personas set rol = 'admin'
      where id = '00000000-0000-0000-0000-000000023201' $$,
  'El rol se cambia con fn_set_rol, no con un update directo.',
  'BLOQUEADO · el update directo a rol ya no funciona, aunque sea sobre la fila propia');

-- ── 2 · La MISMA autopromoción, ahora por la puerta nueva ──────────────────
select throws_ok(
  $$ select fn_set_rol('00000000-0000-0000-0000-000000023201', 'admin') $$,
  'No puedes cambiar el rol de esa persona.',
  'BLOQUEADO · fn_set_rol tampoco deja que un lider_do se asigne un rol igual al suyo');

-- ── 3 · Ni degradar al Admin real (el incidente que ya pasó una vez) ───────
select throws_ok(
  $$ select fn_set_rol('00000000-0000-0000-0000-000000023202', 'supervisor_sede') $$,
  'No puedes cambiar el rol de esa persona.',
  'BLOQUEADO · un lider_do no alcanza a un admin, ni para degradarlo');

reset role;

-- ── 4-5 · Lo que SÍ tiene que seguir funcionando ────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000232a1', true);
set role authenticated;

select lives_ok(
  $$ select fn_set_rol('00000000-0000-0000-0000-000000023203', 'supervisor_sede') $$,
  'PERMITIDO · un lider_do sí puede promover a un integrante, como siempre');

select is(
  (select rol::text from personas where id = '00000000-0000-0000-0000-000000023203'),
  'supervisor_sede',
  'Y EL CAMBIO SE ESCRIBIÓ · no se quedó en una excepción que nadie ve');

reset role;

-- ── 6 · El rastro que antes no existía ──────────────────────────────────────
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023203'
      and campo_modificado = 'personas.rol'
      and valor_anterior = 'integrante' and valor_nuevo = 'supervisor_sede'),
  1,
  'RASTRO · el cambio de rol quedó anotado en correcciones_auditoria');

-- ── 7 · Y a quien no cambia nada, no se le ensucia la auditoría ────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000232a1', true);
set role authenticated;
select fn_set_rol('00000000-0000-0000-0000-000000023203', 'supervisor_sede');
reset role;

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023203'
      and campo_modificado = 'personas.rol'),
  1,
  'SIN RUIDO · pedir el mismo rol otra vez no agrega una segunda fila');

select * from finish();
rollback;
