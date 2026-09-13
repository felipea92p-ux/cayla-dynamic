-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 343_con_hijos_tambien_deja_rastro.test.sql
-- ============================================================================
-- Defiende la 0434. Antes de esa migración, fn_set_con_hijos cambiaba la
-- asignación familiar (S/113/mes) sin dejar ningún rastro de quién lo hizo,
-- cuándo, ni desde qué valor.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000034301', 'ZZ343', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000003431a', 'liderdo-343@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, con_hijos, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000034311', 'LiderDO',    'Autoriza', '00000000-0000-0000-0000-000000034301',
   'lider_do',   'activo', false, 'x', '00000000-0000-0000-0000-00000003431a', '2024-01-01'),
  ('00000000-0000-0000-0000-000000034312', 'Integrante', 'Base',     '00000000-0000-0000-0000-000000034301',
   'integrante', 'activo', false, 'x', null,                                    '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003431a', true);
set role authenticated;

-- ── 1 · Marcarla con hijos deja rastro con el valor anterior correcto ──────
select lives_ok(
  $$ select fn_set_con_hijos('00000000-0000-0000-0000-000000034312', true) $$,
  'PERMITIDO · un líder de DO puede marcar la asignación familiar');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034312'
      and campo_modificado = 'personas.con_hijos'
      and valor_anterior = 'false' and valor_nuevo = 'true'),
  1,
  'RASTRO · el cambio quedó anotado con el valor anterior correcto');

-- ── 2 · Repetir el mismo valor no ensucia la auditoría ─────────────────────
select fn_set_con_hijos('00000000-0000-0000-0000-000000034312', true);

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034312'
      and campo_modificado = 'personas.con_hijos'),
  1,
  'SIN RUIDO · pedir el mismo valor otra vez no agrega una segunda fila');

-- ── 3 · Y el valor sigue guardándose de verdad ─────────────────────────────
select is(
  (select con_hijos from personas where id = '00000000-0000-0000-0000-000000034312'),
  true,
  'Y EL VALOR QUEDÓ ESCRITO · la auditoría no reemplaza el guardado, lo acompaña');

reset role;
select * from finish();
rollback;
