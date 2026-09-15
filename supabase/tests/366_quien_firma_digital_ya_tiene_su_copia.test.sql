-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 366_quien_firma_digital_ya_tiene_su_copia.test.sql — 0462
-- ============================================================================
-- Defiende que confirmar la firma en /mio/contrato entregue también la copia
-- (mismo momento que fecha el contrato, 0430), que reconfirmar no la vuelva a
-- fechar, y que el camino del escaneo —que sí tiene un papel físico real que
-- entregar— siga exigiendo el trámite manual de siempre, sin que esta
-- migración lo toque.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000366000', 'ZZ366', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000366011', 'firmante-366@local'),
  ('00000000-0000-0000-0000-000000366012', 'escaneada-366@local'),
  ('00000000-0000-0000-0000-000000366013', 'admin-366@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000366001', 'Prueba', 'FirmaDigital366',
   (select id from sedes where codigo = 'ZZ366'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000366011', '2025-01-01'),
  ('00000000-0000-0000-0000-000000366002', 'Prueba', 'FirmaEscaneo366',
   (select id from sedes where codigo = 'ZZ366'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000366012', '2025-01-01'),
  ('00000000-0000-0000-0000-000000366003', 'Prueba', 'Admin366',
   (select id from sedes where codigo = 'ZZ366'), 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000366013', '2025-01-01');
set session_replication_role = origin;

insert into firmas_escaneadas (persona_id, imagen, tipo)
values ('00000000-0000-0000-0000-000000366001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen');

-- Contrato de quien va a firmar DIGITAL, sin escaneo.
insert into contratos_generados (
  id, persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin, generado_por, documento_html
) values (
  '00000000-0000-0000-0000-000000366021', '00000000-0000-0000-0000-000000366001',
  'renovacion', 'Integrante de prueba', (select id from sedes where codigo = 'ZZ366'), 1500,
  '2026-01-01', '2027-06-30', '00000000-0000-0000-0000-000000366003', '<p>contrato firmado en pantalla</p>'
);

-- ── 1 · Confirmar la firma, la primera vez, entrega la copia al mismo tiempo
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000366011', true);
select lives_ok(
  $$ select fn_confirmar_mi_firma_contrato('00000000-0000-0000-0000-000000366021') $$,
  'OK · confirmar la firma con la firma ya configurada');

select is(
  (select fecha_firma from contratos_generados where id = '00000000-0000-0000-0000-000000366021'),
  fn_hoy_lima(),
  'FECHADO · la confirmación digital sigue fechando el contrato (0430, sin cambios)');

select is(
  (select copia_entregada_at from contratos_generados where id = '00000000-0000-0000-0000-000000366021'),
  fn_hoy_lima(),
  'ENTREGADA · la misma confirmación digital deja la copia entregada en hoy (0462)');

-- ── 2 · Reconfirmar (p. ej. para corregir la imagen) no la vuelve a fechar ──
select fn_confirmar_mi_firma_contrato('00000000-0000-0000-0000-000000366021');
select is(
  (select copia_entregada_at from contratos_generados where id = '00000000-0000-0000-0000-000000366021'),
  fn_hoy_lima(),
  'ESTABLE · reconfirmar no cambia una copia_entregada_at que ya existía (aquí coincide con hoy por construcción)');

-- ── 3 · El camino del escaneo sigue sin auto-entregar la copia ─────────────
-- Un contrato que DO registra con escaneo (sin que la persona haya confirmado
-- antes) es el caso donde SÍ hay un papel físico real de por medio — esta
-- migración no debe tocar ese camino.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000366013', true);
select lives_ok(
  $$ select fn_contrato_registrar(
       p_persona_id => '00000000-0000-0000-0000-000000366002', p_tipo => 'nuevo',
       p_cargo => 'Integrante de prueba', p_sede_id => (select id from sedes where codigo = 'ZZ366'),
       p_remuneracion_mensual => 1500, p_fecha_inicio => '2026-01-01', p_fecha_fin => '2027-06-30',
       p_documento_html => '<p>contrato para escanear</p>') $$,
  'OK · genera el borrador del contrato que se firmará por escaneo');

select lives_ok(
  $$ select fn_contrato_registrar(
       p_id => (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-000000366002'),
       p_storage_path => 'contratos/' || (select id::text from contratos_generados where persona_id = '00000000-0000-0000-0000-000000366002') || '.pdf',
       p_fecha_firma => fn_hoy_lima()) $$,
  'OK · adjunta el escaneo firmado');

select is(
  (select copia_entregada_at from contratos_generados where persona_id = '00000000-0000-0000-0000-000000366002'),
  null,
  'SIGUE MANUAL · un contrato firmado por escaneo NO entrega su copia sola — sigue siendo un trámite aparte');

-- ── 4 · Ese trámite manual (0287) sigue vivo y sin cambios ─────────────────
select lives_ok(
  $$ select fn_contrato_marcar_tramite(
       (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-000000366002'),
       'copia') $$,
  'OK · el trámite manual de siempre sigue registrando la entrega para el camino de escaneo');

select is(
  (select copia_entregada_at from contratos_generados where persona_id = '00000000-0000-0000-0000-000000366002'),
  fn_hoy_lima(),
  'REGISTRADA · y esta vez sí queda, porque alguien de DO lo anotó a mano');

select * from finish();
rollback;
