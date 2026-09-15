-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 363_politica_salarial_republicar_categoria_y_historico.test.sql
-- ============================================================================
-- Defiende las tres piezas del rediseño de Política salarial:
--   · 0456 — republicar sin cambios de contenido no crea versión nueva ni
--     reinicia constancias (el incidente "v3 quemada" no puede repetirse).
--   · 0457 — fn_set_categoria también cambia salario_declarado.
--   · 0458 — fn_acuses_politica_salarial puede mirar una versión histórica.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000a10001', 'ZZPOL', 'Sede de laboratorio política salarial', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values
  ('a1000000-0000-0000-0000-0000000000c1',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'do.politica@laboratorio.local', '', now(), now()),
  ('a1000000-0000-0000-0000-0000000000c2',
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
   'conacuse.politica@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash,
                      auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-000000a10002', 'DoPol', 'Lab',
        '00000000-0000-0000-0000-000000a10001', 'lider_do', 'x',
        'a1000000-0000-0000-0000-0000000000c1', '2020-01-01', 'activo', 'planilla');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values
  ('00000000-0000-0000-0000-000000a10003', 'ConAcuse', 'Lab',
   '00000000-0000-0000-0000-000000a10001', 'x',
   'a1000000-0000-0000-0000-0000000000c2', '2020-01-01', 'activo', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000a10003', 'support', 1260.00, '2020-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-0000000000c1', true);

-- ── 1 · Publicar por primera vez crea la version 1 ──────────────────────────
select is(
  (select (fn_publicar_politica_salarial('{"titulo":"t","fecha":"2026-09-15","secciones":[]}', null) ->> 'version')::int),
  1, '0456 · primera publicacion crea la version 1');

-- ── 2 · Volver a publicar el MISMO contenido, con OTRA fecha, no crea version
select is(
  (select fn_publicar_politica_salarial('{"titulo":"t","fecha":"2026-09-16","secciones":[]}', null) ->> 'nueva'),
  'false', '0456 · republicar el mismo contenido con otra fecha no marca "nueva"');

select is(
  (select (fn_publicar_politica_salarial('{"titulo":"t","fecha":"2026-09-17","secciones":[]}', null) ->> 'version')::int),
  1, '0456 · y devuelve la MISMA version (sigue siendo la 1)');

select is(
  (select count(*)::int from politica_salarial),
  1, '0456 · no se inserto ninguna fila nueva en politica_salarial');

-- ── 3 · Publicar contenido REALMENTE distinto si crea version nueva ─────────
select is(
  (select (fn_publicar_politica_salarial('{"titulo":"t2","fecha":"2026-09-18","secciones":[]}', null) ->> 'version')::int),
  2, '0456 · un cambio real de contenido si crea la version 2');

select is(
  (select fn_publicar_politica_salarial('{"titulo":"t2","fecha":"2026-09-19","secciones":[]}', null) ->> 'nueva'),
  'false', '0456 · y republicar ESE contenido tampoco crea una tercera version');

-- ── 4 · fn_set_categoria tambien cambia salario_declarado ───────────────────
select fn_set_categoria('colibri', 'Proposito de prueba', 'Funciones de prueba',
  'Requisitos de prueba', 'Criterio de prueba', 1234.56);

select is(
  (select salario_declarado from categorias_laborales where rango = 'colibri'),
  1234.56::numeric, '0457 · fn_set_categoria actualiza salario_declarado');

-- ── 5 · fn_acuses_politica_salarial mira una version historica ──────────────
-- ConAcuse deja constancia de la version 1 (nunca de la 2).
insert into politica_salarial_acuses (persona_id, version, nombre_declarado)
values ('00000000-0000-0000-0000-000000a10003', 1, 'Con Acuse');

select ok(
  exists (
    select 1 from jsonb_array_elements(
      (select fn_acuses_politica_salarial(1)) -> 'personas'
    ) el
    where (el ->> 'persona_id') = '00000000-0000-0000-0000-000000a10003'
      and (el ->> 'acusado_at') is not null
  ),
  '0458 · fn_acuses_politica_salarial(1) muestra el acuse historico de la version 1');

select ok(
  exists (
    select 1 from jsonb_array_elements(
      (select fn_acuses_politica_salarial(2)) -> 'personas'
    ) el
    where (el ->> 'persona_id') = '00000000-0000-0000-0000-000000a10003'
      and (el ->> 'acusado_at') is null
  ),
  '0458 · fn_acuses_politica_salarial(2) muestra a la misma persona como pendiente de la vigente');

-- ── 6 · fn_mi_rango_actual devuelve el rango de QUIEN CONSULTA, no cualquiera ──
select set_config('request.jwt.claim.sub', 'a1000000-0000-0000-0000-0000000000c2', true);
select is(
  (select fn_mi_rango_actual()),
  'support', '0459 · fn_mi_rango_actual devuelve el rango de la persona que tiene la sesion abierta');

select * from finish();
rollback;
