-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 360_un_borrador_de_falta_no_se_firma_si_una_ausencia_ya_la_justifica.test.sql
-- ============================================================================
-- Lo que vigila (0455): fn_expediente_firmar rechaza firmar un borrador de
-- FALTA cuando, después de generarse, alguien registró una ausencia sin
-- anular que cubre uno de sus días — y confirma las dos excepciones que la
-- 0455 documenta a propósito:
--
--   · una TARDANZA con una ausencia el mismo día se firma igual: fn_tardanzas_
--     resumen no mira `ausencias`, así que bloquear ahí contradiría a la base.
--   · una ausencia ya ANULADA no cuenta: solo protege lo vigente.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000fa1a0001', 'ZZFA', 'Sede de laboratorio FA', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('00000000-0000-0000-0000-0000fa1a00ff',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.fa@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-0000fa1a0002', 'FaAdmin', 'Lab',
        '00000000-0000-0000-0000-0000fa1a0001', 'admin', 'x',
        '00000000-0000-0000-0000-0000fa1a00ff', '2024-01-01', 'activo'),
       ('00000000-0000-0000-0000-0000fa1a0003', 'FaFaltona', 'Lab',
        '00000000-0000-0000-0000-0000fa1a0001', 'integrante', 'x', null, '2024-01-01', 'activo');
set session_replication_role = origin;

-- Sin política de descargo previo exigida: esta prueba mira el candado de la
-- 0455, no el trámite del art. 55.2 (esa es la 205).
insert into configuracion (clave, valor, descripcion)
values ('disciplina_descargo_previo', 'false'::jsonb, 'relevado a propósito para esta prueba')
on conflict (clave) do update set valor = 'false'::jsonb;

-- Ausencia VIGENTE que cubre el 2025-01-07 — el mismo día que citan los
-- borradores de falta y de tardanza de abajo.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por)
values ('00000000-0000-0000-0000-0000fa1a0003', 'permiso_personal', '2025-01-07', '2025-01-07',
        '00000000-0000-0000-0000-0000fa1a0002');

-- Ausencia ANULADA que cubre el 2025-03-03 — para probar que una anulada no
-- protege nada.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, registrada_por,
                       anulada_at, anulada_por, anulada_motivo)
values ('00000000-0000-0000-0000-0000fa1a0003', 'permiso_personal', '2025-03-03', '2025-03-03',
        '00000000-0000-0000-0000-0000fa1a0002',
        now(), '00000000-0000-0000-0000-0000fa1a0002', 'de prueba: se anula para el caso de control');

set session_replication_role = replica;
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, creado_por)
values
  -- 1 · FALTA citando el día que la ausencia vigente cubre — debe frenar.
  ('00000000-0000-0000-0000-0000fa1a0011', '00000000-0000-0000-0000-0000fa1a0003',
   'falta', 'amonestacion', 'borrador', '2025-01-01', '2025-01-31',
   '[{"fecha":"2025-01-07"}]'::jsonb, '00000000-0000-0000-0000-0000fa1a0002'),
  -- 2 · FALTA de control, ningún día tiene ausencia — debe firmarse.
  ('00000000-0000-0000-0000-0000fa1a0012', '00000000-0000-0000-0000-0000fa1a0003',
   'falta', 'amonestacion', 'borrador', '2025-02-01', '2025-02-28',
   '[{"fecha":"2025-02-20"}]'::jsonb, '00000000-0000-0000-0000-0000fa1a0002'),
  -- 3 · TARDANZA el MISMO día que la ausencia vigente — debe firmarse igual:
  --     fn_tardanzas_resumen no excluye por ausencia (ver encabezado 0455).
  ('00000000-0000-0000-0000-0000fa1a0013', '00000000-0000-0000-0000-0000fa1a0003',
   'tardanza', 'amonestacion', 'borrador', '2025-01-01', '2025-01-31',
   '[{"fecha":"2025-01-07","minutos":14}]'::jsonb, '00000000-0000-0000-0000-0000fa1a0002'),
  -- 4 · FALTA citando el día que solo cubre la ausencia ANULADA — debe
  --     firmarse: lo anulado no protege.
  ('00000000-0000-0000-0000-0000fa1a0014', '00000000-0000-0000-0000-0000fa1a0003',
   'falta', 'amonestacion', 'borrador', '2025-03-01', '2025-03-31',
   '[{"fecha":"2025-03-03"}]'::jsonb, '00000000-0000-0000-0000-0000fa1a0002');
set session_replication_role = origin;

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000fa1a00ff","role":"authenticated"}';

-- ── 1 · La falta cubierta por una ausencia vigente no se firma ──────────────
select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000fa1a0011') $$,
  '%ausencia registrada que los justifica%',
  '0455 · una falta con un día ya cubierto por una ausencia vigente no se firma');

select is(
  (select estado from expediente_disciplinario where id = '00000000-0000-0000-0000-0000fa1a0011'),
  'borrador',
  '0455 · y de verdad sigue en borrador — el throw no dejó nada a medias');

-- ── 2 · Control: una falta sin ninguna ausencia se firma normal ─────────────
select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000fa1a0012') $$,
  '0455 · una falta sin ausencia que la cubra se firma sin problema');

-- ── 3 · Una tardanza el mismo día de una ausencia vigente SÍ se firma ───────
-- (fn_tardanzas_resumen no mira `ausencias`; bloquear acá contradiría a la
-- base, que es la única autoridad real sobre qué cuenta.)
select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000fa1a0013') $$,
  '0455 · una tardanza no se frena aunque haya una ausencia el mismo día');

-- ── 4 · Una ausencia ANULADA no protege nada ────────────────────────────────
select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000fa1a0014') $$,
  '0455 · una falta cuyo único día lo cubre una ausencia ANULADA sí se firma');

select * from finish();
rollback;
