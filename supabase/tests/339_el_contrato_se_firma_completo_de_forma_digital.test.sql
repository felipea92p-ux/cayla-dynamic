-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 339_el_contrato_se_firma_completo_de_forma_digital.test.sql — 0429
-- ============================================================================
-- Defiende el ciclo completo de la firma digital del contrato: confirmar la
-- primera vez fecha el contrato, reconfirmar no vuelve a fecharlo, el candado
-- de "un solo documento sin firmar por tipo" deja de confundir un contrato
-- firmado-sin-escaneo con un borrador de verdad, adjuntar un escaneo después
-- nunca corre la fecha legal de firma, y editar un contrato ya firmado
-- digitalmente (sin escaneo) se rechaza igual que uno firmado con escaneo.
-- ============================================================================
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000339000', 'ZZ339', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
-- Filas REALES en auth.users, no solo bypasear la FK al insertar: esta
-- prueba hace que fn_confirmar_mi_firma_contrato ACTUALICE personas (para
-- recalcular fecha_fin_contrato), y esa actualización sí revalida
-- personas_auth_user_id_fkey aunque no toque esa columna — bypasear la FK
-- solo en el insert no alcanza. Mismo patrón que 271_la_sede_tambien...
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000339011', 'firmante-339@local'),
  ('00000000-0000-0000-0000-000000339013', 'admin-339@local');
-- fecha_ingreso ANTES del inicio del contrato de prueba (2026-01-01): la
-- tabla exige fecha_fin_contrato >= fecha_ingreso, y sin esto el default
-- (hoy) habría quedado después de cualquier fecha_fin que fijemos.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000339001', 'Prueba', 'Firmante339',
   (select id from sedes where codigo = 'ZZ339'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000339011', '2025-01-01'),
  ('00000000-0000-0000-0000-000000339003', 'Prueba', 'Admin339',
   (select id from sedes where codigo = 'ZZ339'), 'admin', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000339013', '2025-01-01');
set session_replication_role = origin;

insert into firmas_escaneadas (persona_id, imagen, tipo)
values ('00000000-0000-0000-0000-000000339001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen');

insert into contratos_generados (
  id, persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin, generado_por, documento_html
) values (
  '00000000-0000-0000-0000-000000339021', '00000000-0000-0000-0000-000000339001',
  'renovacion', 'Integrante de prueba', (select id from sedes where codigo = 'ZZ339'), 1500,
  '2026-01-01', '2026-06-30', '00000000-0000-0000-0000-000000339003', '<p>contrato de prueba</p>'
);

-- ── 1 · Confirmar la firma, la primera vez, fecha el contrato ──────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000339011', true);
select lives_ok(
  $$ select fn_confirmar_mi_firma_contrato('00000000-0000-0000-0000-000000339021') $$,
  'OK · confirmar la firma con la firma ya configurada');

select is(
  (select fecha_firma from contratos_generados where id = '00000000-0000-0000-0000-000000339021'),
  fn_hoy_lima(),
  'FECHADO · la primera confirmación digital pone fecha_firma en hoy');

select is(
  (select registrado_por from contratos_generados where id = '00000000-0000-0000-0000-000000339021'),
  '00000000-0000-0000-0000-000000339001'::uuid,
  'REGISTRADO · registrado_por queda con la propia persona, no con un admin');

select is(
  (select storage_path from contratos_generados where id = '00000000-0000-0000-0000-000000339021'),
  null,
  'SIN ESCANEO · queda firmado sin que haga falta storage_path');

-- ── 2 · Reconfirmar (p. ej. para corregir la imagen) NO vuelve a fechar ────
select fn_confirmar_mi_firma_contrato('00000000-0000-0000-0000-000000339021');
select is(
  (select fecha_firma from contratos_generados where id = '00000000-0000-0000-0000-000000339021'),
  fn_hoy_lima(),
  'ESTABLE · reconfirmar no cambia una fecha_firma que ya existía (aquí coincide con hoy por construcción)');

-- ── 3 · El candado de "un solo documento sin firmar por tipo" ya no confunde
--        un contrato firmado-sin-escaneo con un borrador de verdad ─────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000339013', true);
select lives_ok(
  $$ select fn_contrato_registrar(
       p_persona_id => '00000000-0000-0000-0000-000000339001', p_tipo => 'renovacion',
       p_cargo => 'Integrante de prueba', p_sede_id => (select id from sedes where codigo = 'ZZ339'),
       p_remuneracion_mensual => 1600, p_fecha_inicio => '2026-07-01', p_fecha_fin => '2026-12-31',
       p_documento_html => '<p>renovación</p>') $$,
  'CANDADO 1 · con el anterior firmado digitalmente (sin escaneo), sí se puede generar la renovación');

-- ── 4 · Adjuntar un escaneo después nunca corre la fecha legal de firma ────
select is(
  (select count(*)::int from contratos_generados
    where persona_id = '00000000-0000-0000-0000-000000339001' and tipo = 'renovacion' and anulado_at is null),
  2,
  'DOS · la renovación nueva convive con la ya firmada, no la reemplazó');

select lives_ok(
  $$ select fn_contrato_registrar(
       p_id => '00000000-0000-0000-0000-000000339021',
       p_storage_path => 'contratos/00000000-0000-0000-0000-000000339021.pdf',
       p_fecha_firma => '2026-09-01') $$,
  'OK · adjuntar un escaneo de respaldo a un contrato ya firmado digitalmente');

select is(
  (select fecha_firma from contratos_generados where id = '00000000-0000-0000-0000-000000339021'),
  fn_hoy_lima(),
  'PROTEGIDA · la fecha legal de firma sigue siendo la de la confirmación digital, no la del escaneo (2026-09-01)');

select is(
  (select storage_path from contratos_generados where id = '00000000-0000-0000-0000-000000339021'),
  'contratos/00000000-0000-0000-0000-000000339021.pdf',
  'ARCHIVADO · el escaneo de respaldo sí queda guardado');

-- ── 5 · Editar un contrato ya firmado digitalmente (sin escaneo) se rechaza
--        igual que uno firmado con escaneo — con su contraste ────────────────
select lives_ok(
  $$ select fn_contrato_editar(
       p_id => (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-000000339001'
                  and tipo = 'renovacion' and fecha_inicio = '2026-07-01'),
       p_tipo => 'renovacion', p_cargo => 'Otro cargo', p_remuneracion_mensual => 1700,
       p_fecha_inicio => '2026-07-01', p_fecha_fin => '2026-12-31', p_documento_html => '<p>x</p>') $$,
  'CONTRASTE · la renovación nueva SÍ se puede editar: todavía no está firmada');

select throws_ok(
  $$ select fn_contrato_editar(
       p_id => '00000000-0000-0000-0000-000000339021', p_tipo => 'renovacion',
       p_cargo => 'Otro cargo', p_remuneracion_mensual => 1700,
       p_fecha_inicio => '2026-01-01', p_fecha_fin => '2026-06-30', p_documento_html => '<p>x</p>') $$,
  null, null,
  'CANDADO · un contrato firmado digitalmente (sin escaneo) tampoco se edita');

-- ── 6 · El constraint sigue rechazando un escaneo sin fecha de firma ───────
select throws_ok(
  $$ update contratos_generados set storage_path = 'contratos/nuevo.pdf'
      where persona_id = '00000000-0000-0000-0000-000000339001'
        and tipo = 'renovacion' and fecha_inicio = '2026-07-01' $$,
  null, null,
  'CONSTRAINT · un contrato sin fecha_firma no puede llevar storage_path');

select * from finish();
rollback;
