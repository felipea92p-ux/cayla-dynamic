-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 351_anular_lo_aprobado_exige_desarrollo_organizacional.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. Una encargada de sede NO puede anular una ausencia de un tipo que YA
--      fue aprobado por Desarrollo Organizacional.
--   2. Pero SÍ puede anular una ausencia PENDIENTE de aprobar (todavía no es
--      una decisión de DO — nada que deshacer sin su permiso).
--   3. Y SÍ puede anular unas VACACIONES, aunque pagan y nacen "aprobadas":
--      requiere_aprobacion = false, así que nunca pasaron por una decisión
--      real de DO. Este es el caso que casi se rompe si el candado mirara
--      solo `aprobada_at` en vez de `requiere_aprobacion` también.
--   4. Un admin sí puede anular lo que DO ya aprobó.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000c10a', 'ZZDOA', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c20a', 'DoaAdmin', 'Lab', '00000000-0000-0000-0000-00000000c10a', 'admin', 'x', '00000000-0000-0000-0000-00000000ca0a', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c21a', 'DoaEncargada', 'Lab', '00000000-0000-0000-0000-00000000c10a', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000cb0a', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c30a', 'DoaPersona', 'Lab', '00000000-0000-0000-0000-00000000c10a', 'x', '2024-01-01');

-- Todo lo que crea datos lo hace el admin, para no mezclar con lo que se
-- prueba (si la encargada pudiera registrar no probaría nada distinto).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ca0a', true);

-- A: vacaciones — paga, pero requiere_aprobacion = false: nace "aprobada" sin
-- que DO haya decidido nada.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000c30a', 'vacaciones', '2026-10-01', '2026-10-01');

-- B: descanso médico — requiere_aprobacion = true. Nace SIN aprobar y el
-- admin la aprueba de inmediato: esta es la que DO sí decidió.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000c30a', 'descanso_medico', '2026-10-05', '2026-10-05',
  'gripe', 'Dra. Lab', 'CMP 90001', '2026-10-05');
select fn_aprobar_ausencia((select id from ausencias
  where persona_id = '00000000-0000-0000-0000-00000000c30a' and fecha_inicio = '2026-10-05'));

select is((select aprobada_at is not null from ausencias
           where persona_id = '00000000-0000-0000-0000-00000000c30a' and fecha_inicio = '2026-10-05'),
          true, 'DE PARTIDA · el descanso médico del 05 quedó aprobado por DO antes de probar nada');

-- C: descanso médico — registrado, pero SIN aprobar todavía.
select fn_registrar_ausencia('00000000-0000-0000-0000-00000000c30a', 'descanso_medico', '2026-10-10', '2026-10-10',
  'gripe', 'Dra. Lab', 'CMP 90001', '2026-10-10');

-- ── Ahora actúa la encargada de sede ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cb0a', true);

select throws_ok($$ select fn_anular_ausencia(
    (select id from ausencias where persona_id = '00000000-0000-0000-0000-00000000c30a' and fecha_inicio = '2026-10-05'),
    'me equivoqué') $$,
  null, null, 'APROBADA · la encargada NO puede anular el descanso médico que DO ya aprobó');

select lives_ok($$ select fn_anular_ausencia(
    (select id from ausencias where persona_id = '00000000-0000-0000-0000-00000000c30a' and fecha_inicio = '2026-10-01'),
    'se pidió mal la fecha') $$,
  'VACACIONES · la encargada SÍ puede anularlas: paga, pero nunca pasó por una decisión de DO');

select lives_ok($$ select fn_anular_ausencia(
    (select id from ausencias where persona_id = '00000000-0000-0000-0000-00000000c30a' and fecha_inicio = '2026-10-10'),
    'se registró el tipo equivocado') $$,
  'PENDIENTE · la encargada SÍ puede anular lo que todavía no aprobó nadie');

-- ── Y un admin sí puede deshacer lo que DO ya aprobó ────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ca0a', true);

select lives_ok($$ select fn_anular_ausencia(
    (select id from ausencias where persona_id = '00000000-0000-0000-0000-00000000c30a' and fecha_inicio = '2026-10-05'),
    'lo autorizo yo, se registró de más') $$,
  'ADMIN · sí puede anular lo que DO ya aprobó');

select * from finish();
rollback;
