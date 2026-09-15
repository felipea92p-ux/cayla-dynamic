-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 349_el_horario_tambien_se_cambia_por_una_puerta.test.sql
-- ============================================================================
-- Defiende la 0440. Antes de esa migración, `fn_set_horario_semanal` no
-- pedía motivo ni dejaba rastro en `correcciones_auditoria` — y además
-- `horarios_asignados` tenía una policy de escritura sin `FOR` que dejaba a
-- cualquier admin o líder de DO escribirla directo por PostgREST, saltándose
-- el candado de periodo pagado, el recorte retroactivo y el recálculo de
-- jornadas. Misma familia de defecto que la 271 defiende para `sede_base_id`
-- y la 232 para `rol`.
--
-- OJO CON EL `session_replication_role`. Igual que en la 271: montar el
-- fixture con `= replica` y no devolverlo a `origin` ANTES de simular el
-- ataque apaga en silencio todos los triggers de la sesión, incluido el que
-- esta prueba defiende.
--
-- ACTUALIZADA POR LA 0444 (historial de horarios): la fecha fija original
-- ('2026-09-01') ya cayó en el pasado real, y fn_set_horario_semanal desde la
-- 0444 ya no acepta una fecha pasada. Nada de lo que esta prueba defiende es
-- sobre QUÉ día se usa, así que las siete ocurrencias se volvieron
-- fn_hoy_lima() — el caso normal de "asignar hacia adelante" que 0444 nunca
-- tocó.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000034901', 'ZZ349', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000349aa', 'admin-349@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000034911', 'Admin',       'Horario', '00000000-0000-0000-0000-000000034901',
   'admin',      'activo', 'x', '00000000-0000-0000-0000-0000000349aa', '2024-01-01'),
  ('00000000-0000-0000-0000-000000034912', 'Integrante',  'Horario', '00000000-0000-0000-0000-000000034901',
   'integrante', 'activo', 'x', null,                                    '2024-01-01');
set session_replication_role = origin;

-- ── 1-2 · Motivo obligatorio: rechaza vacío/corto y nulo ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000349aa', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-000000034912', fn_hoy_lima(),
       '{"1":{"e":"08:00","s":"18:00","r":60}}'::jsonb, 'hi') $$,
  'Escribe el motivo del cambio de horario (mínimo 3 caracteres).',
  'BLOQUEADO · un motivo de menos de 3 caracteres no pasa');

select throws_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-000000034912', fn_hoy_lima(),
       '{"1":{"e":"08:00","s":"18:00","r":60}}'::jsonb, null) $$,
  'Escribe el motivo del cambio de horario (mínimo 3 caracteres).',
  'BLOQUEADO · un motivo nulo tampoco pasa');

-- ── 3-6 · Con motivo real, funciona y deja rastro completo ──────────────────
select lives_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-000000034912', fn_hoy_lima(),
       '{"1":{"e":"08:00","s":"18:00","r":60}}'::jsonb, 'Asignación inicial de horario.') $$,
  'PERMITIDO · con un motivo real, un admin sí puede asignar el horario');

select is(
  (select hora_entrada from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000034912' and vigente_desde = fn_hoy_lima()),
  '08:00'::time,
  'Y EL HORARIO SE ESCRIBIÓ · no se quedó en una excepción que nadie ve');

select is(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034912' and campo_modificado = 'horarios_asignados'),
  'Asignación inicial de horario.',
  'RASTRO · el motivo escrito quedó en correcciones_auditoria');

select is(
  (select (valor_anterior, corregido_por) from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034912' and campo_modificado = 'horarios_asignados'),
  row('sin horario previo'::text, '00000000-0000-0000-0000-000000034911'::uuid),
  'RASTRO · quedó anotado que no había horario previo, y quién hizo el cambio');
reset role;

-- ── 7-9 · La puerta trasera: insert/update/delete directos, bloqueados ──────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000349aa', true);
set role authenticated;
select throws_ok(
  $$ update horarios_asignados set hora_entrada = '07:00'
      where persona_id = '00000000-0000-0000-0000-000000034912' and vigente_desde = fn_hoy_lima() $$,
  'Los horarios se cambian con fn_set_horario_semanal, no con un insert/update/delete directo.',
  'BLOQUEADO · el update directo a horarios_asignados ya no funciona, aunque lo pida un admin');

select throws_ok(
  $$ insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
      values ('00000000-0000-0000-0000-000000034912', '2026-10-01', '08:00', '18:00', array[1,2,3,4,5]) $$,
  'Los horarios se cambian con fn_set_horario_semanal, no con un insert/update/delete directo.',
  'BLOQUEADO · el insert directo a horarios_asignados ya no funciona');

select throws_ok(
  $$ delete from horarios_asignados
      where persona_id = '00000000-0000-0000-0000-000000034912' and vigente_desde = fn_hoy_lima() $$,
  'Los horarios se cambian con fn_set_horario_semanal, no con un insert/update/delete directo.',
  'BLOQUEADO · el delete directo a horarios_asignados tampoco funciona');
reset role;

-- ── 10 · Y a pesar de los intentos de arriba, el tramo real sigue intacto ───
select is(
  (select hora_entrada from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000034912' and vigente_desde = fn_hoy_lima()),
  '08:00'::time,
  'INTACTO · ninguno de los ataques directos alcanzó a tocar el tramo real');

select * from finish();
rollback;
