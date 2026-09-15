-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 362_ausentismo_separa_pagado_y_excluye_pendiente.test.sql
-- ============================================================================
-- Lo que vigila (0443), sin prueba hasta hoy: fn_ausencias_resumen deja de
-- sumar una ausencia que exige aprobación de DO mientras siga pendiente, y
-- separa lo que sí cuenta en `dias_pagados`/`dias_no_pagados` sin perder nada
-- en `dias_total`.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000fa3a0001', 'ZZAU', 'Sede de laboratorio AU', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('00000000-0000-0000-0000-0000fa3a00fa',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.fa3@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values
  ('00000000-0000-0000-0000-0000fa3a0002', 'FaAdminAU', 'Lab',
   '00000000-0000-0000-0000-0000fa3a0001', 'admin', 'x',
   '00000000-0000-0000-0000-0000fa3a00fa', '2024-01-01', 'activo'),
  ('00000000-0000-0000-0000-0000fa3a0003', 'FaAusente', 'Lab',
   '00000000-0000-0000-0000-0000fa3a0001', 'integrante', 'x', null, '2024-01-01', 'activo');
set session_replication_role = origin;

-- Descanso médico (paga, requiere_aprobacion) · 3 días · TODAVÍA pendiente.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por)
values ('00000000-0000-0000-0000-0000fa3a0003', 'descanso_medico', '2025-06-10', '2025-06-12',
        '00000000-0000-0000-0000-0000fa3a0002');

-- Permiso personal (no paga, sin aprobación) · 2 días · nace vigente.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por, aprobada_por, aprobada_at)
values ('00000000-0000-0000-0000-0000fa3a0003', 'permiso_personal', '2025-06-20', '2025-06-21',
        '00000000-0000-0000-0000-0000fa3a0002', '00000000-0000-0000-0000-0000fa3a0002', now());

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000fa3a00fa","role":"authenticated"}';

-- ── Antes de aprobar el descanso médico ─────────────────────────────────────
select is(
  (select dias_total from fn_ausencias_resumen('2025-06-01', '2025-06-30')
    where persona_id = '00000000-0000-0000-0000-0000fa3a0003'),
  2,
  '0443 · con el descanso médico pendiente, solo cuentan los 2 días del permiso personal');

select is(
  (select dias_pagados from fn_ausencias_resumen('2025-06-01', '2025-06-30')
    where persona_id = '00000000-0000-0000-0000-0000fa3a0003'),
  0,
  '0443 · dias_pagados en 0: lo pendiente no suma aunque su tipo SÍ pague');

-- ── DO aprueba el descanso médico ────────────────────────────────────────────
set local role postgres;
update ausencias set aprobada_at = now(), aprobada_por = '00000000-0000-0000-0000-0000fa3a0002'
 where persona_id = '00000000-0000-0000-0000-0000fa3a0003' and tipo = 'descanso_medico';
set local role authenticated;

select is(
  (select dias_pagados from fn_ausencias_resumen('2025-06-01', '2025-06-30')
    where persona_id = '00000000-0000-0000-0000-0000fa3a0003'),
  3,
  '0443 · aprobado, los 3 días del descanso médico pasan a dias_pagados');

select is(
  (select dias_no_pagados from fn_ausencias_resumen('2025-06-01', '2025-06-30')
    where persona_id = '00000000-0000-0000-0000-0000fa3a0003'),
  2,
  '0443 · y dias_no_pagados sigue en 2 — nada se contamina entre las dos columnas');

select * from finish();
rollback;
