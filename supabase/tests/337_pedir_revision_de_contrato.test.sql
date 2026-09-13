-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 337_pedir_revision_de_contrato.test.sql — 0427
-- ============================================================================
-- Defiende el ciclo completo de "pedir revisión de mi contrato": llega a
-- admin/líder (no a cualquiera), no se duplica si se pide dos veces antes de
-- que la atiendan, y exige tener un contrato registrado —a diferencia de
-- fn_pedir_revision_movilidad (0425), que no lo exige—.
--
-- Copia el molde de 336_pedir_revision_de_movilidad a propósito: mismos tres
-- verbos (pedir, listar, atender), mismo criterio de visibilidad.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000337000', 'ZZ337', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  ('00000000-0000-0000-0000-000000337001', 'Prueba', 'Firmante337',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000337011'),
  ('00000000-0000-0000-0000-000000337002', 'Prueba', 'SinContrato337',
   (select id from sedes where codigo = 'AQP'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000337012'),
  ('00000000-0000-0000-0000-000000337003', 'Prueba', 'Admin337',
   '00000000-0000-0000-0000-000000337000', 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000337013');
set session_replication_role = origin;

insert into contratos_generados (
  id, persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, generado_por, documento_html
) values (
  '00000000-0000-0000-0000-000000337021', '00000000-0000-0000-0000-000000337001',
  'indefinido', 'Integrante de prueba', (select id from sedes where codigo = 'TRU'), 1200,
  '2026-09-01', '00000000-0000-0000-0000-000000337003', '<p>contrato de prueba</p>'
);

-- ── 1 · Sin contrato registrado, no se puede pedir revisión ────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000337012', true);
select throws_ok(
  $$ select fn_pedir_revision_contrato('Mi sueldo está mal') $$,
  null, null,
  'RECHAZADO · sin un contrato registrado, no hay nada que pedir revisar');

-- ── 2 · Pedir revisión: valida el motivo ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000337011', true);
select throws_ok(
  $$ select fn_pedir_revision_contrato('mm') $$,
  null, null,
  'RECHAZADO · el motivo necesita al menos 5 caracteres, igual que revisiones_pedidas (0257)');

select lives_ok(
  $$ select fn_pedir_revision_contrato('Mi cargo aparece mal escrito') $$,
  'OK · con un motivo real y un contrato registrado, queda pedida');

-- ── 3 · Un no-admin no puede atender, aunque conozca el id ─────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000337012', true);
select throws_ok(
  $$ select fn_atender_revision_contrato(
       (select id from contrato_revisiones_pedidas
         where persona_id = '00000000-0000-0000-0000-000000337001' limit 1),
       'me la adjudico') $$,
  null, null,
  'RECHAZADO · solo admin/líder puede atender una revisión de contrato');

-- ── 4 · Ese no-admin tampoco ve la solicitud ajena en el listado ───────────
select is(
  (select fn_contrato_revisiones_pedidas(true)),
  '[]'::jsonb,
  'AISLADA · quien no es admin ni es la dueña de la solicitud no ve nada');

-- ── 5 · Admin sí la ve, con nombre y sede ya resueltos ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000337013', true);
select is(
  (select jsonb_array_length(fn_contrato_revisiones_pedidas(true))),
  1,
  'ADMIN · ve exactamente una solicitud pendiente');

select is(
  (select fn_contrato_revisiones_pedidas(true)->0->>'nombre'),
  'Prueba Firmante337',
  'ADMIN · el nombre viene resuelto, no un uuid a secas');

select is(
  (select fn_contrato_revisiones_pedidas(true)->0->>'sede'),
  'TRU',
  'ADMIN · la sede también viene resuelta');

-- ── 6 · Pedir de nuevo ANTES de que la atiendan reabre la misma fila ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000337011', true);
select fn_pedir_revision_contrato('En realidad es la fecha de inicio');
select is(
  (select count(*)::int from contrato_revisiones_pedidas
    where persona_id = '00000000-0000-0000-0000-000000337001'),
  1,
  'REABRE · pedir dos veces sin respuesta todavía es UNA sola fila, no dos');

-- ── 7 · Admin atiende, con una respuesta ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000337013', true);
select lives_ok(
  $$ select fn_atender_revision_contrato(
       (select id from contrato_revisiones_pedidas
         where persona_id = '00000000-0000-0000-0000-000000337001' limit 1),
       'Corregido, gracias por avisar') $$,
  'OK · admin atiende sin problema');

select is(
  (select fn_contrato_revisiones_pedidas(true)),
  '[]'::jsonb,
  'ATENDIDA · ya no aparece entre las pendientes');

select * from finish();
rollback;
