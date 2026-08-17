-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 204_una_comunicacion_verbal_se_declara_pero_no_abre_la_firma.test.sql
-- ============================================================================
-- La 0266 deja registrar una comunicación de cargos que ya ocurrió, con su
-- fecha real. Es un atajo legítimo —evita repetir un trámite ya hecho— y por
-- eso mismo es el sitio exacto donde alguien, con prisa, podría convertirlo en
-- «firmar sin escuchar».
--
-- Lo que fija esta prueba es la frontera: la fecha se puede declarar, el plazo
-- NO se puede saltar. Una comunicación declarada ayer sigue frenando la firma
-- hoy, igual que si se hubiera comunicado ayer de verdad — porque es lo mismo.
--
-- Los hechos van con fechas fijas de 2025 a propósito: así quedan siempre antes
-- de cualquier versión del Reglamento, y el guard del numeral 60.5 no se mete
-- en medio con su propio error dentro de un año.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000006c1', 'ZZDC', 'Sede de laboratorio DC', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('ee000000-0000-0000-0000-0000000006ff',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.dc@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000006c2', 'DcAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000006c1', 'admin', 'x',
        'ee000000-0000-0000-0000-0000000006ff', '2024-01-01'),
       ('00000000-0000-0000-0000-0000000006c3', 'DcTarde', 'Lab',
        '00000000-0000-0000-0000-0000000006c1', 'integrante', 'x', null, '2024-01-01');

-- Tres borradores idénticos de suspensión. Cambia solo lo que se declara.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
   suspension_dias, suspension_desde, suspension_hasta, creado_por)
select v.id, '00000000-0000-0000-0000-0000000006c3', 'tardanza', 'suspension', 'borrador',
       date '2025-01-05', date '2025-01-10',
       '[{"fecha":"2025-01-07","minutos":7}]'::jsonb,
       2, current_date + 10, current_date + 11,
       '00000000-0000-0000-0000-0000000006c2'
from (values
  ('00000000-0000-0000-0000-0000000006d1'::uuid),
  ('00000000-0000-0000-0000-0000000006d2'::uuid),
  ('00000000-0000-0000-0000-0000000006d3'::uuid)) as v(id);
set session_replication_role = origin;

set local role authenticated;
set local request.jwt.claims = '{"sub":"ee000000-0000-0000-0000-0000000006ff","role":"authenticated"}';

-- ── 1 · Sin declarar nada, la firma sigue frenada donde estaba ──────────────
select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000006d1') $$,
  '%comunicar los cargos%',
  'sin cargos comunicados no se firma');

-- ── 2 · Una fecha futura no se declara ──────────────────────────────────────
select throws_like(
  $$ select fn_expediente_declarar_cargos_comunicados(
       '00000000-0000-0000-0000-0000000006d1', now() + interval '1 day',
       'Se lo dijo la encargada delante del equipo') $$,
  '%todavía no llega%',
  'una comunicación futura no se puede declarar');

-- ── 3 · Ni una anterior a los hechos que imputa ─────────────────────────────
select throws_like(
  $$ select fn_expediente_declarar_cargos_comunicados(
       '00000000-0000-0000-0000-0000000006d1', timestamptz '2024-12-01 10:00-05',
       'Se lo dijo la encargada delante del equipo') $$,
  '%anterior%',
  'no se comunican cargos antes de que ocurran los hechos');

-- ── 4 · Sin decir cómo consta, tampoco ──────────────────────────────────────
select throws_like(
  $$ select fn_expediente_declarar_cargos_comunicados(
       '00000000-0000-0000-0000-0000000006d1', now() - interval '5 days', 'verbal') $$,
  '%cómo consta%',
  'una constancia de una palabra no vale como constancia');

-- ── 5 · Declarada ayer, el plazo AÚN NO VENCIÓ y la firma sigue frenada ─────
-- Es el corazón de la prueba: declarar la fecha real no adelanta el plazo.
select lives_ok(
  $$ select fn_expediente_declarar_cargos_comunicados(
       '00000000-0000-0000-0000-0000000006d2', now() - interval '1 day',
       'Se lo dijo la encargada de sede en el taller, delante de dos compañeras') $$,
  'una comunicación de ayer se declara sin problema');

select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000006d2') $$,
  '%plazo de descargo vence%',
  'declarada ayer, el plazo todavía corre y la firma sigue frenada');

-- ── 6 · Declarada hace diez días, el plazo venció… y aun así falta valorar ──
select lives_ok(
  $$ select fn_expediente_declarar_cargos_comunicados(
       '00000000-0000-0000-0000-0000000006d3', now() - interval '10 days',
       'Se lo dijo la encargada de sede en el taller, delante de dos compañeras') $$,
  'una comunicación de hace diez días se declara con su fecha');

select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000006d3') $$,
  '%valorar por escrito el descargo%',
  'con el plazo vencido sigue faltando dejar por escrito qué pasó con el descargo');

-- ── 7 · Y no se declara dos veces ───────────────────────────────────────────
select throws_like(
  $$ select fn_expediente_declarar_cargos_comunicados(
       '00000000-0000-0000-0000-0000000006d3', now() - interval '3 days',
       'Otra versión distinta de lo mismo, escrita después') $$,
  '%ya constan comunicados%',
  'la fecha declarada no se puede reescribir');

select * from finish();
rollback;
