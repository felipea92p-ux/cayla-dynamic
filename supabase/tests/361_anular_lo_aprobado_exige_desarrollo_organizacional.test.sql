-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 361_anular_lo_aprobado_exige_desarrollo_organizacional.test.sql
-- ============================================================================
-- Lo que vigila (0442), sin prueba hasta hoy: fn_anular_ausencia rechaza a la
-- encargada de sede que intenta deshacer sola una ausencia que YA aprobó
-- Desarrollo Organizacional (un tipo con requiere_aprobacion = true) — y
-- confirma la excepción que el propio encabezado de la 0442 marca como la que
-- NO se quiso tocar: vacaciones paga pero requiere_aprobacion = false, así que
-- nace aprobada sola y la encargada sigue pudiendo anularla sin pedirle nada
-- a nadie.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000fa2a0001', 'ZZDO', 'Sede de laboratorio DO', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000fa2a00fa',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'admin.fa2@laboratorio.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000fa2a00fb',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'encargada.fa2@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-0000fa2a0002', 'FaAdminDO', 'Lab',
   '00000000-0000-0000-0000-0000fa2a0001', 'admin', 'x',
   '00000000-0000-0000-0000-0000fa2a00fa', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-0000fa2a0003', 'FaEncargada', 'Lab',
   '00000000-0000-0000-0000-0000fa2a0001', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000fa2a00fb', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-0000fa2a0004', 'FaColaboradora', 'Lab',
   '00000000-0000-0000-0000-0000fa2a0001', 'integrante', 'x', null, '2024-01-01', 'activo');
set session_replication_role = origin;

-- Ausencia A · descanso médico, YA aprobado por DO (requiere_aprobacion = true).
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por, aprobada_at, aprobada_por)
values ('00000000-0000-0000-0000-0000fa2a0004', 'descanso_medico', '2025-04-10', '2025-04-11',
        '00000000-0000-0000-0000-0000fa2a0002', now(), '00000000-0000-0000-0000-0000fa2a0002');

-- Ausencia B · vacaciones, con aprobada_at puesto (nace aprobada sola: 0101),
-- pero requiere_aprobacion = false — la excepción que la 0442 no quiso tocar.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por, aprobada_at, aprobada_por)
values ('00000000-0000-0000-0000-0000fa2a0004', 'vacaciones', '2025-05-05', '2025-05-09',
        '00000000-0000-0000-0000-0000fa2a0002', now(), '00000000-0000-0000-0000-0000fa2a0002');

-- ── Como la encargada de sede (no DO) ────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000fa2a00fb","role":"authenticated"}';

select throws_like(
  $$ select fn_anular_ausencia(
       (select id from ausencias where persona_id = '00000000-0000-0000-0000-0000fa2a0004'
         and tipo = 'descanso_medico'), 'me equivoqué de tipo') $$,
  '%Desarrollo Organizacional%',
  '0442 · la encargada no puede anular sola un descanso médico ya aprobado por DO');

select is(
  (select anulada_at is null from ausencias
    where persona_id = '00000000-0000-0000-0000-0000fa2a0004' and tipo = 'descanso_medico'),
  true,
  '0442 · y de verdad sigue vigente — el throw no dejó nada a medias');

select lives_ok(
  $$ select fn_anular_ausencia(
       (select id from ausencias where persona_id = '00000000-0000-0000-0000-0000fa2a0004'
         and tipo = 'vacaciones'), 'se registró la fecha equivocada') $$,
  '0442 · pero SÍ puede anular unas vacaciones aprobadas solas (requiere_aprobacion = false)');

-- ── Como DO (admin) ──────────────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000fa2a00fa","role":"authenticated"}';

select lives_ok(
  $$ select fn_anular_ausencia(
       (select id from ausencias where persona_id = '00000000-0000-0000-0000-0000fa2a0004'
         and tipo = 'descanso_medico'), 'DO decide revertirlo') $$,
  '0442 · un admin sí puede anular el descanso médico que su propia DO aprobó');

select * from finish();
rollback;
