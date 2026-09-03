-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 271_la_sede_tambien_se_cambia_por_una_puerta.test.sql
-- ============================================================================
-- Defiende la 0342. Antes de esa migración, `equipo/page.tsx` escribía
-- `sede_base_id` con un UPDATE directo desde el navegador: sin rastro en
-- `correcciones_auditoria`, y sin que nada distinguiera «lo pidió admin» de
-- «lo pidió cualquiera con la fila abierta». Es la misma familia de defecto
-- que la 232 defiende para `rol`.
--
-- OJO CON EL `session_replication_role`. Igual que en la 232: montar el
-- fixture con `= replica` y no devolverlo a `origin` ANTES de simular el
-- ataque apaga en silencio todos los triggers de la sesión, incluido el que
-- esta prueba defiende.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000027101', 'ZZ271', 'Sede de laboratorio A', true),
  ('00000000-0000-0000-0000-000000027102', 'YY271', 'Sede de laboratorio B', true),
  ('00000000-0000-0000-0000-000000027103', 'XX271', 'Sede de laboratorio inactiva', false);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000002711a', 'liderdo-271@local'),
  ('00000000-0000-0000-0000-00000002711b', 'supervisor-271@local'),
  ('00000000-0000-0000-0000-00000002711c', 'admin-271@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese) values
  ('00000000-0000-0000-0000-000000027111', 'LiderDO',     'Autoriza',  '00000000-0000-0000-0000-000000027101',
   'lider_do',      'activo',   'x', '00000000-0000-0000-0000-00000002711a', '2024-01-01', null),
  ('00000000-0000-0000-0000-000000027112', 'Supervisor',  'Sede',      '00000000-0000-0000-0000-000000027101',
   'supervisor_sede','activo',  'x', '00000000-0000-0000-0000-00000002711b', '2024-01-01', null),
  ('00000000-0000-0000-0000-000000027113', 'Integrante',  'Base',      '00000000-0000-0000-0000-000000027101',
   'integrante',    'activo',   'x', null,                                    '2024-01-01', null),
  ('00000000-0000-0000-0000-000000027114', 'Cesada',      'YaSeFue',   '00000000-0000-0000-0000-000000027101',
   'integrante',    'inactivo', 'x', null,                                    '2024-01-01', '2026-06-30'),
  ('00000000-0000-0000-0000-000000027115', 'Admin',       'Real',      '00000000-0000-0000-0000-000000027101',
   'admin',         'activo',   'x', '00000000-0000-0000-0000-00000002711c', '2024-01-01', null);
set session_replication_role = origin;

-- ── 1 · EL ATAQUE ORIGINAL: update directo, aunque sea con permiso real ────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000002711a', true);
set role authenticated;
select throws_ok(
  $$ update personas set sede_base_id = '00000000-0000-0000-0000-000000027102'
      where id = '00000000-0000-0000-0000-000000027113' $$,
  'La sede se cambia con fn_set_sede_base, no con un update directo.',
  'BLOQUEADO · el update directo a sede_base_id ya no funciona, aunque lo pida un líder de DO');
reset role;

-- ── 2 · fn_set_sede_base rechaza a quien no es admin ni líder ──────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000002711b', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_sede_base('00000000-0000-0000-0000-000000027113', '00000000-0000-0000-0000-000000027102') $$,
  'Solo un administrador o líder puede cambiar la sede.',
  'BLOQUEADO · un supervisor_sede no puede cambiar la sede de nadie, aunque opere el equipo en pantalla');
reset role;

-- ── 3 · fn_set_sede_base rechaza una sede inactiva ─────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000002711a', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_sede_base('00000000-0000-0000-0000-000000027113', '00000000-0000-0000-0000-000000027103') $$,
  'Sede inválida o inactiva.',
  'BLOQUEADO · no se puede mandar a nadie a una sede inactiva');

-- ── 4 · fn_set_sede_base rechaza a quien ya cesó ────────────────────────────
select throws_ok(
  $$ select fn_set_sede_base('00000000-0000-0000-0000-000000027114', '00000000-0000-0000-0000-000000027102') $$,
  'No se puede cambiar la sede de una persona ya cesada: su liquidación se calculó con la sede anterior.',
  'BLOQUEADO · no se cambia la sede de quien ya fue liquidado');

-- ── 5-6 · Lo que SÍ tiene que seguir funcionando ────────────────────────────
select lives_ok(
  $$ select fn_set_sede_base('00000000-0000-0000-0000-000000027113', '00000000-0000-0000-0000-000000027102') $$,
  'PERMITIDO · un líder de DO sí puede cambiar la sede de un integrante');

select is(
  (select sede_base_id from personas where id = '00000000-0000-0000-0000-000000027113'),
  '00000000-0000-0000-0000-000000027102'::uuid,
  'Y EL CAMBIO SE ESCRIBIÓ · no se quedó en una excepción que nadie ve');
reset role;

-- ── 7 · El rastro que antes no existía ──────────────────────────────────────
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000027113'
      and campo_modificado = 'personas.sede_base_id'
      and valor_anterior = 'ZZ271' and valor_nuevo = 'YY271'),
  1,
  'RASTRO · el cambio de sede quedó anotado en correcciones_auditoria, con los códigos correctos');

-- ── 8 · Y a quien no cambia nada, no se le ensucia la auditoría ────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000002711a', true);
set role authenticated;
select fn_set_sede_base('00000000-0000-0000-0000-000000027113', '00000000-0000-0000-0000-000000027102');
reset role;

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000027113'
      and campo_modificado = 'personas.sede_base_id'),
  1,
  'SIN RUIDO · pedir la misma sede otra vez no agrega una segunda fila');

-- ── 9 · admin también pasa por la puerta (no es exclusivo de lider_do) ─────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000002711c', true);
set role authenticated;
select lives_ok(
  $$ select fn_set_sede_base('00000000-0000-0000-0000-000000027112', '00000000-0000-0000-0000-000000027102') $$,
  'PERMITIDO · un admin también puede cambiar la sede de un supervisor de sede');
reset role;

select * from finish();
rollback;
