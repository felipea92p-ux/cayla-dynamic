-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 340_aprobar_una_ausencia_tambien_respeta_el_periodo_pagado.test.sql
-- ============================================================================
-- Lo que vigila (0431): que `fn_aprobar_ausencia` —la tercera puerta que
-- convierte una ausencia en dinero, junto a registrar y anular— rechace
-- aprobar una ausencia cuyas fechas caen en un periodo ya pagado, en las DOS
-- formas en que un periodo puede estar pagado hoy: el agregado de antes de la
-- 0323 (sin ninguna fila en `periodo_grupo_pago`) y el grupo de la 0323 en
-- adelante (`periodo_grupo_pago` por `tipo_vinculo`).
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000b10a', 'ZZAPA', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b20a', 'ApaAdmin', 'Lab', '00000000-0000-0000-0000-00000000b10a', 'admin', 'x', '00000000-0000-0000-0000-00000000ba0a', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, tipo_vinculo, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b30a', 'ApaMedico', 'Lab', '00000000-0000-0000-0000-00000000b10a', 'planilla', 'x', '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ba0a', true);

-- Se registra un descanso médico dentro de agosto — todavía no hay ningún
-- periodo cargado, así que el registro entra sin que nada lo bloquee.
select lives_ok($$ select fn_registrar_ausencia(
    '00000000-0000-0000-0000-00000000b30a', 'descanso_medico', '2026-08-10', '2026-08-12',
    'gripe', 'Dra. Lab', 'CMP 99999', '2026-08-10') $$,
  'DE PARTIDA · el descanso médico se registra sin problema, el periodo todavía no existe');

-- ── Caso 1 · periodo pagado AL AGREGADO (compatibilidad, antes de la 0323) ──
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('b0b0b0b0-0000-0000-0000-000000000101', '2026-08-01', '2026-08-31', 'pagado');

select throws_ok($$
    select fn_aprobar_ausencia(
      (select id from ausencias where persona_id = '00000000-0000-0000-0000-00000000b30a'
        and tipo = 'descanso_medico' and fecha_inicio = '2026-08-10')
    )
  $$, null, null,
  'AGREGADO · no se aprueba una ausencia de un periodo ya pagado (sin periodo_grupo_pago)');

select is((select aprobada_at is null from ausencias
           where persona_id = '00000000-0000-0000-0000-00000000b30a' and tipo = 'descanso_medico'),
          true, 'AGREGADO · y de verdad sigue sin aprobar — el throw no dejó nada a medias');

-- ── Caso 2 · periodo pagado POR GRUPO (0323 en adelante) ────────────────────
-- Un segundo periodo, esta vez con el grupo 'planilla' pagado de verdad y el
-- resto del acumulado sin cerrar — el caso que la 0323 vino a distinguir.
-- La fila se inserta DIRECTO (no vía fn_registrar_ausencia): registrar con el
-- grupo ya pagado activaría el candado de la 0327, que es otra prueba (la
-- 102) — acá interesa solo fn_aprobar_ausencia en aislamiento.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('b0b0b0b0-0000-0000-0000-000000000102', '2026-09-01', '2026-09-30', 'abierto');
insert into periodo_grupo_pago (periodo_id, grupo, estado)
values ('b0b0b0b0-0000-0000-0000-000000000102', 'planilla', 'pagado');

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, doc_profesional, doc_colegiatura, doc_fecha, registrada_por)
values ('00000000-0000-0000-0000-00000000b30a', 'descanso_medico', '2026-09-10', '2026-09-11',
        'Dra. Lab', 'CMP 99999', '2026-09-10', '00000000-0000-0000-0000-00000000b20a');

select throws_ok($$
    select fn_aprobar_ausencia(
      (select id from ausencias where persona_id = '00000000-0000-0000-0000-00000000b30a'
        and tipo = 'descanso_medico' and fecha_inicio = '2026-09-10')
    )
  $$, null, null,
  'GRUPO · tampoco se aprueba cuando el grupo (tipo_vinculo) de la persona ya está pagado');

select * from finish();
rollback;
