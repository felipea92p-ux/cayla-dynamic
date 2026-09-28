-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 388_una_cuenta_de_servicio_no_es_una_persona.test.sql
-- ============================================================================
-- Defiende la 0490 y la 0491. Las estaciones de caja y almacén de
-- cayla-retail son filas activas de `personas`; para Dynamic eso era alguien a
-- quien pagar (S/ 101.70 de EsSalud cada una, medido) y a quien ofrecer en el
-- terminal de marcaje.
--
-- Lo que más importa defender es el lado contrario: marcar a una persona REAL
-- como cuenta de servicio la saca de la planilla sin que nada falle. Por eso
-- la mitad de estas aserciones son negativas de la puerta.
--
-- OJO CON EL `session_replication_role`: el fixture se monta con `replica` y
-- se devuelve a `origin` ANTES de simular nada, o el trigger que se defiende
-- estaría apagado (lección de la 232 y la 271).
-- ============================================================================
begin;
select plan(15);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000038801', 'ZZ388', 'Sede de laboratorio 388', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000003881a', 'liderdo-388@local'),
  ('00000000-0000-0000-0000-00000003881b', 'supervisor-388@local'),
  ('00000000-0000-0000-0000-00000003881c', 'caja-388@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000038811', 'LiderDO',    'Autoriza',                  '00000000-0000-0000-0000-000000038801',
   'lider_do',        'activo', 'x', '00000000-0000-0000-0000-00000003881a', '2024-01-01'),
  ('00000000-0000-0000-0000-000000038812', 'Supervisor', 'Sede',                      '00000000-0000-0000-0000-000000038801',
   'supervisor_sede', 'activo', 'x', '00000000-0000-0000-0000-00000003881b', '2024-01-01'),
  ('00000000-0000-0000-0000-000000038813', 'ESTACIÓN —', 'Caja Lab (no es persona)',  '00000000-0000-0000-0000-000000038801',
   'integrante',      'activo', 'x', '00000000-0000-0000-0000-00000003881c', '2026-09-01'),
  ('00000000-0000-0000-0000-000000038814', 'Marcela',    'Trabaja',                   '00000000-0000-0000-0000-000000038801',
   'integrante',      'activo', 'x', null,                                    '2026-01-01');
insert into jornadas (persona_id, fecha) values ('00000000-0000-0000-0000-000000038814', '2026-09-10');
set session_replication_role = origin;

-- ── 1-2 · El candado: ni update ni insert directos ─────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003881a', true);
set role authenticated;
select throws_ok(
  $$ update personas set cuenta_de_servicio = true where id = '00000000-0000-0000-0000-000000038813' $$,
  'La cuenta de servicio se cambia con fn_set_cuenta_de_servicio, no con un update directo.',
  'BLOQUEADO · el update directo no marca, aunque lo pida un líder de DO');
select throws_ok(
  $$ insert into personas (nombres, apellidos, sede_base_id, pin_hash, cuenta_de_servicio)
     values ('Nace', 'Marcada', '00000000-0000-0000-0000-000000038801', 'x', true) $$,
  'Una persona nace como persona. Para marcarla como cuenta de servicio usa fn_set_cuenta_de_servicio.',
  'BLOQUEADO · una fila no puede nacer marcada y saltarse las comprobaciones');
reset role;

-- ── 3 · Solo admin o líder DO ──────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003881b', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000038813', true) $$,
  'Solo un administrador o líder DO puede marcar una cuenta de servicio.',
  'BLOQUEADO · una líder de equipo no marca cuentas de servicio');
reset role;

-- ── 4-5 · La puerta desconfía: nunca a quien trabaja ni a quien administra ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003881a', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000038814', true) $$,
  'Esta ficha tiene marcajes: alguien trabajó con ella. Una cuenta de servicio no marca asistencia, y marcarla así la sacaría de la planilla.',
  'BLOQUEADO · no se esconde a una persona que tiene jornadas: dejaría de cobrar');
select throws_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000038812', true) $$,
  'Una cuenta de servicio no puede tener rol de líder ni de administración. Cámbiale el rol a integrante primero.',
  'BLOQUEADO · una cuenta con rol de líder no se marca');

-- ── 6-7 · Lo que sí funciona, y deja rastro ────────────────────────────────
select lives_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000038813', true) $$,
  'PERMITIDO · un líder de DO marca la estación');
reset role;
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000038813'
      and campo_modificado = 'personas.cuenta_de_servicio'
      and valor_anterior = 'false' and valor_nuevo = 'true'
      and corregido_por = '00000000-0000-0000-0000-000000038811'),
  1,
  'RASTRO · el marcado quedó en correcciones_auditoria, firmado por quien lo hizo');

-- ── 8-11 · Marcada, sale de lo que Dynamic calcula (0491) ──────────────────
-- La planilla se pide sin `set role`: `authenticated` no ejecuta
-- fn_planilla_calcular directo (igual que en la 101 y la 109).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003881a', true);
select is(
  (select count(*)::int
     from jsonb_array_elements(fn_planilla_calcular('2026-08-29'::date, '2026-09-28'::date)->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-000000038813'),
  0,
  'PLANILLA · la estación ya no tiene fila (antes: S/ 101.70 de EsSalud por el piso de la RMV)');
select is(
  (select count(*)::int
     from jsonb_array_elements(fn_planilla_calcular('2026-08-29'::date, '2026-09-28'::date)->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-000000038814'),
  1,
  'PLANILLA · y la persona real de la misma sede sigue ahí');
select ok(
  '00000000-0000-0000-0000-000000038813'::uuid not in (select fn_poblacion_obligada()),
  'REGLAMENTO · la estación no está en la población a la que hay que entregárselo');
select ok(
  position('cuenta_de_servicio' in pg_get_viewdef('public.terminal_roster'::regclass, true)) > 0,
  'TERMINAL · el roster de marcaje excluye las cuentas de servicio en su definición');

-- ── 12-13 · Desmarcar no tiene condiciones, y la devuelve ──────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003881a', true);
set role authenticated;
select lives_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000038813', false, 'Era una persona') $$,
  'PERMITIDO · desmarcar siempre se puede: devolver a alguien a la planilla no esconde nada');
reset role;
select is(
  (select count(*)::int
     from jsonb_array_elements(fn_planilla_calcular('2026-08-29'::date, '2026-09-28'::date)->'filas') f
    where f->>'persona_id' = '00000000-0000-0000-0000-000000038813'),
  1,
  'CONTROL · desmarcada, vuelve a la planilla — la exclusión venía de la columna y de nada más');

-- ── 14 · El motivo escrito a mano queda en el rastro ───────────────────────
select is(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000038813'
      and campo_modificado = 'personas.cuenta_de_servicio' and valor_nuevo = 'false'),
  'Era una persona',
  'RASTRO · el motivo que se escribió es el que queda');

-- ── 15 · El registro es el de esta migración, no otra con su número ────────
select is(
  (select nombre from migraciones_aplicadas where numero = 490),
  'una_cuenta_de_servicio_no_es_una_persona',
  'REGISTRO · la 490 es esta migración');

select * from finish();
rollback;
