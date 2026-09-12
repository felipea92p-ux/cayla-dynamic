-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 341_el_cese_tambien_se_cambia_por_una_puerta.test.sql
-- ============================================================================
-- Defiende la 0432. Misma familia de defecto que la 271 (sede) y la 232 (rol):
-- antes de esta migración, `estado`/`fecha_cese`/`motivo_cese`/`tipo_vinculo`
-- se podían cambiar con un UPDATE directo desde el navegador, saltándose
-- fn_cesar_persona / fn_reactivar_persona / fn_set_tipo_vinculo y sin dejar
-- rastro en correcciones_auditoria.
--
-- OJO CON EL `session_replication_role`. Igual que en la 271: montar el
-- fixture con `= replica` y no devolverlo a `origin` ANTES de simular el
-- ataque apaga en silencio todos los triggers de la sesión, incluido el que
-- esta prueba defiende.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000034101', 'ZZ341', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000003411a', 'liderdo-341@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, tipo_vinculo, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000034111', 'LiderDO',    'Autoriza', '00000000-0000-0000-0000-000000034101',
   'lider_do',   'activo', 'planilla', 'x', '00000000-0000-0000-0000-00000003411a', '2024-01-01'),
  ('00000000-0000-0000-0000-000000034112', 'Integrante', 'Base',     '00000000-0000-0000-0000-000000034101',
   'integrante', 'activo', 'planilla', 'x', null,                                    '2024-01-01');
set session_replication_role = origin;

-- ── 1 · EL ATAQUE ORIGINAL: cesar con un update directo ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003411a', true);
set role authenticated;
select throws_ok(
  $$ update personas set estado = 'inactivo', fecha_cese = '2026-06-30', motivo_cese = 'renuncia'
      where id = '00000000-0000-0000-0000-000000034112' $$,
  'El cese y el tipo de vínculo se cambian con fn_cesar_persona / fn_reactivar_persona / fn_set_tipo_vinculo, no con un update directo.',
  'BLOQUEADO · el update directo a estado/fecha_cese/motivo_cese ya no funciona, aunque lo pida un líder de DO');
reset role;

-- ── 2 · Y por el mismo trigger, tampoco tipo_vinculo por su cuenta ─────────
set role authenticated;
select throws_ok(
  $$ update personas set tipo_vinculo = 'rxh' where id = '00000000-0000-0000-0000-000000034112' $$,
  'El cese y el tipo de vínculo se cambian con fn_cesar_persona / fn_reactivar_persona / fn_set_tipo_vinculo, no con un update directo.',
  'BLOQUEADO · el update directo a tipo_vinculo tampoco funciona — mismo trigger, misma puerta');
reset role;

-- ── 3 · Lo que SÍ tiene que seguir funcionando: fn_cesar_persona ───────────
set role authenticated;
select lives_ok(
  $$ select fn_cesar_persona('00000000-0000-0000-0000-000000034112', '2026-06-30', 'renuncia') $$,
  'PERMITIDO · un líder de DO sí puede cesar por la puerta correcta');
reset role;

select is(
  (select row(estado, fecha_cese, motivo_cese)::text from personas where id = '00000000-0000-0000-0000-000000034112'),
  row('inactivo', '2026-06-30'::date, 'renuncia')::text,
  'Y EL CESE SE ESCRIBIÓ · no se quedó en una excepción que nadie ve');

-- ── 4 · fn_set_tipo_vinculo también sigue funcionando ──────────────────────
set role authenticated;
select lives_ok(
  $$ select fn_set_tipo_vinculo('00000000-0000-0000-0000-000000034111', 'prueba') $$,
  'PERMITIDO · fn_set_tipo_vinculo sigue pudiendo cambiar el vínculo por su puerta');
reset role;

select is(
  (select tipo_vinculo from personas where id = '00000000-0000-0000-0000-000000034111'),
  'prueba',
  'Y EL CAMBIO DE VÍNCULO SE ESCRIBIÓ · el trigger no bloquea a la función guardián');

select * from finish();
rollback;
