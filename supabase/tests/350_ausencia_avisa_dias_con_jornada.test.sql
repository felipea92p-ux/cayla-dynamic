-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 350_ausencia_avisa_dias_con_jornada.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. Un día con jornada trabajada (horas_trabajadas > 0) dentro del rango
--      aparece en el aviso.
--   2. Un día con jornada pero SIN horas (abierta, o 0 h) no aparece — no es
--      el caso que 0286 paga como trabajado.
--   3. Un día fuera del rango pedido no aparece.
--   4. Quien no tiene permiso para registrar una ausencia de esa persona
--      (fn_verificar_corrector) tampoco puede ver si tiene marcajes.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000b10a', 'ZZJOR', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b20a', 'JorAdmin', 'Lab', '00000000-0000-0000-0000-00000000b10a', 'admin', 'x', '00000000-0000-0000-0000-00000000bb0a', '2024-01-01');
set session_replication_role = origin;

-- Otra sede, para probar que una encargada ajena no puede consultar.
insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000b11a', 'ZZJOR2', 'Sede ajena', true, 'tienda');
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b21a', 'JorAjena', 'Lab', '00000000-0000-0000-0000-00000000b11a', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000bc0a', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b30a', 'JorPersona', 'Lab', '00000000-0000-0000-0000-00000000b10a', 'x', '2024-01-01');

-- Tres días de jornadas: una trabajada dentro del rango, una sin horas (abierta)
-- dentro del rango, y una trabajada FUERA del rango.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
values
  ('00000000-0000-0000-0000-00000000b30a', '2026-09-10', 7.5, 'cerrada'),
  ('00000000-0000-0000-0000-00000000b30a', '2026-09-11', null, 'abierta'),
  ('00000000-0000-0000-0000-00000000b30a', '2026-09-20', 8.0, 'cerrada');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bb0a', true);

-- ── El día trabajado dentro del rango aparece ───────────────────────────────
select is(
  (select count(*)::int from fn_ausencia_dias_con_jornada(
    '00000000-0000-0000-0000-00000000b30a', '2026-09-08', '2026-09-14')),
  1, 'AVISO · un día con horas_trabajadas > 0 dentro del rango aparece');

select is(
  (select fecha from fn_ausencia_dias_con_jornada(
    '00000000-0000-0000-0000-00000000b30a', '2026-09-08', '2026-09-14')),
  '2026-09-10'::date, 'AVISO · y es justo el día trabajado, no el de la jornada abierta');

-- ── La jornada sin horas no cuenta como "vino a trabajar" ───────────────────
select is(
  (select count(*)::int from fn_ausencia_dias_con_jornada(
    '00000000-0000-0000-0000-00000000b30a', '2026-09-11', '2026-09-11')),
  0, 'SIN HORAS · una jornada abierta (horas_trabajadas null) no dispara el aviso');

-- ── Fuera del rango no aparece ───────────────────────────────────────────────
select is(
  (select count(*)::int from fn_ausencia_dias_con_jornada(
    '00000000-0000-0000-0000-00000000b30a', '2026-09-08', '2026-09-14')
   where fecha = '2026-09-20'),
  0, 'RANGO · el día trabajado del 20 no aparece al pedir el rango del 8 al 14');

-- ── Quien no puede registrar la ausencia tampoco puede ver el cruce ─────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000bc0a', true);
select throws_ok($$ select * from fn_ausencia_dias_con_jornada(
    '00000000-0000-0000-0000-00000000b30a', '2026-09-08', '2026-09-14') $$,
  null, null, 'PERMISO · una encargada de otra sede no puede consultar el cruce de esta persona');

select * from finish();
rollback;
