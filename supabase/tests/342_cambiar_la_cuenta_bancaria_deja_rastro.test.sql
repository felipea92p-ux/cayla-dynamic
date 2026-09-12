-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 342_cambiar_la_cuenta_bancaria_deja_rastro.test.sql
-- ============================================================================
-- Defiende la 0433. Antes de esa migración, fn_set_datos_personales sobrescribía
-- entidad_bancaria/numero_cuenta sin dejar rastro de qué cambió ni desde qué
-- valor — a diferencia de una corrección de marcaje, de salario, de sede o de
-- régimen de pensión, que sí lo exigen.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000034201', 'ZZ342', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000003421a', 'liderdo-342@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000034211', 'LiderDO',    'Autoriza', '00000000-0000-0000-0000-000000034201',
   'lider_do',   'activo', 'x', '00000000-0000-0000-0000-00000003421a', '2024-01-01'),
  ('00000000-0000-0000-0000-000000034212', 'Integrante', 'Base',     '00000000-0000-0000-0000-000000034201',
   'integrante', 'activo', 'x', null,                                   '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000003421a', true);
set role authenticated;

-- ── 1 · Primera carga: no hay "antes", no debe fallar por eso ──────────────
select lives_ok(
  $$ select fn_set_datos_personales(
       p_persona_id := '00000000-0000-0000-0000-000000034212',
       p_entidad_bancaria := 'BCP', p_numero_cuenta := '191-1234567-0-01') $$,
  'PERMITIDO · la primera carga de cuenta bancaria no revienta por no tener valor anterior');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034212'
      and campo_modificado = 'datos_personales.entidad_bancaria'
      and valor_anterior is null and valor_nuevo = 'BCP'),
  1,
  'RASTRO · la primera carga también queda anotada (null → BCP no es "nada que auditar")');

-- ── 2 · Cambiarla de verdad deja las dos filas (banco Y cuenta) ────────────
select fn_set_datos_personales(
  p_persona_id := '00000000-0000-0000-0000-000000034212',
  p_entidad_bancaria := 'BBVA', p_numero_cuenta := '011-9876543-0-02');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034212'
      and campo_modificado = 'datos_personales.entidad_bancaria'
      and valor_anterior = 'BCP' and valor_nuevo = 'BBVA'),
  1,
  'RASTRO · el cambio de entidad quedó anotado con el valor anterior correcto');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034212'
      and campo_modificado = 'datos_personales.numero_cuenta'
      and valor_anterior = '191-1234567-0-01' and valor_nuevo = '011-9876543-0-02'),
  1,
  'RASTRO · el cambio de número de cuenta quedó anotado con el valor anterior correcto');

-- ── 3 · Y a quien no cambia nada, no se le ensucia la auditoría ────────────
select fn_set_datos_personales(
  p_persona_id := '00000000-0000-0000-0000-000000034212',
  p_entidad_bancaria := 'BBVA', p_numero_cuenta := '011-9876543-0-02',
  p_celular := '999888777');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000034212'
      and campo_modificado in ('datos_personales.entidad_bancaria', 'datos_personales.numero_cuenta')),
  4,
  'SIN RUIDO · pedir la misma cuenta otra vez (aunque cambie el celular) no agrega más filas');

-- ── 4 · El valor sigue guardándose de verdad, con o sin auditoría de más ───
select is(
  (select row(entidad_bancaria, numero_cuenta, celular)::text from datos_personales
    where persona_id = '00000000-0000-0000-0000-000000034212'),
  row('BBVA', '011-9876543-0-02', '999888777')::text,
  'Y LA FICHA QUEDÓ ESCRITA · la auditoría no reemplaza el guardado, lo acompaña');

reset role;
select * from finish();
rollback;
