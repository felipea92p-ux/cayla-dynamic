-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 373_el_mtpe_ya_no_es_tramite_para_nadie.test.sql — 0470
-- ============================================================================
-- La 0347 eximió al indefinido de `comunicado_mtpe_at`, pero dejó la
-- exigencia puesta para plazo fijo ('nuevo') y convenio de prácticas — el
-- Decreto Legislativo N.° 1246 (vigente desde 2016-11-11) eliminó esa
-- comunicación a la AAT para TODOS, no solo el indefinido. Esta prueba cuida
-- que `fn_contratos_tablero` ya no la exija a ninguno de los dos:
--   1. Un 'nuevo' (plazo fijo) firmado y con copia entregada llega a 'ok' sin
--      que nadie marque `comunicado_mtpe_at`.
--   2. Un 'convenio_practicas' en las mismas condiciones, igual.
--   3. El indefinido (0347) sigue llegando a 'ok' igual que antes — control
--      de que esta migración no le cambió nada a él.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000372000', 'ZZ372', 'Sede de laboratorio 372', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000372aa0', 'Jefa', 'Lab372',
        '00000000-0000-0000-0000-000000372000', 'admin', 'h',
        '00000000-0000-0000-0000-000000372aff', '2025-01-02');
set session_replication_role = origin;

-- Sujeto 1: plazo fijo ('nuevo').
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000372001', 'Rosa', 'PlazoFijo372',
        '00000000-0000-0000-0000-000000372000', 'h', '2026-01-05');

-- Sujeto 2: practicante con convenio. Fechas después de "hoy" a propósito —
-- `gobierna` usa la más temprana entre `fecha_fin_contrato` y el tope legal
-- de 12 meses desde el ingreso (0336); un convenio ya vencido da 'vencido',
-- no lo que esta prueba quiere medir.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000372002', 'Mimi', 'Practicante372',
        '00000000-0000-0000-0000-000000372000', 'h', '2026-09-01', 'practicante');

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000372aff', true);
end $sesion$;

-- ── 1 · Plazo fijo: firmado + copia entregada, SIN comunicado_mtpe_at ──────
do $nuevo$
declare v_id uuid;
begin
  v_id := fn_contrato_registrar(
    p_persona_id := '00000000-0000-0000-0000-000000372001', p_tipo := 'nuevo',
    p_cargo := 'Asesora', p_sede_id := '00000000-0000-0000-0000-000000372000',
    p_remuneracion_mensual := 1130,
    p_fecha_inicio := '2026-01-05', p_fecha_fin := '2027-01-05',
    p_documento_html := '<p>plazo fijo 372</p>');
  perform fn_contrato_registrar(p_id := v_id,
    p_storage_path := 'contratos/' || v_id::text || '.pdf', p_fecha_firma := '2026-01-06');
  perform fn_contrato_marcar_tramite(v_id, 'copia');
end $nuevo$;

select is(
  (select estado from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000372001'),
  'ok',
  'plazo fijo firmado + copia entregada llega a "ok" sin comunicado_mtpe_at — el D. Leg. 1246 eliminó esa obligación (art. 73, D.S. 003-97-TR)');

select ok(
  (select comunicado_mtpe_at from contratos_generados where documento_html = '<p>plazo fijo 372</p>') is null,
  'y llega a "ok" con comunicado_mtpe_at de verdad en NULL — nadie lo marcó');

-- ── 2 · Convenio de prácticas: mismo caso ──────────────────────────────────
do $convenio$
declare v_id uuid;
begin
  v_id := fn_contrato_registrar(
    p_persona_id := '00000000-0000-0000-0000-000000372002', p_tipo := 'convenio_practicas',
    p_cargo := 'Practicante de Marketing', p_sede_id := '00000000-0000-0000-0000-000000372000',
    p_remuneracion_mensual := 700,
    p_fecha_inicio := '2026-09-01', p_fecha_fin := '2027-03-01',
    p_documento_html := '<p>convenio 372</p>');
  perform fn_contrato_registrar(p_id := v_id,
    p_storage_path := 'contratos/' || v_id::text || '.pdf', p_fecha_firma := '2026-09-02');
  perform fn_contrato_marcar_tramite(v_id, 'copia');
end $convenio$;

select is(
  (select estado from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000372002'),
  'ok',
  'convenio de prácticas firmado + copia entregada llega a "ok" sin comunicado_mtpe_at — el D. Leg. 1246 derogó el último párrafo del art. 46, Ley 28518');

-- ── 3 · Control: el indefinido (0347) no cambió ────────────────────────────
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000372003', 'Ana', 'Indefinida372',
        '00000000-0000-0000-0000-000000372000', 'h', '2026-01-05');

do $indefinido$
declare v_id uuid;
begin
  v_id := fn_contrato_registrar(
    p_persona_id := '00000000-0000-0000-0000-000000372003', p_tipo := 'indefinido',
    p_cargo := 'Gerenta', p_sede_id := '00000000-0000-0000-0000-000000372000',
    p_remuneracion_mensual := 2500,
    p_fecha_inicio := '2026-01-05', p_fecha_fin := null,
    p_documento_html := '<p>indefinido 372</p>');
  perform fn_contrato_registrar(p_id := v_id,
    p_storage_path := 'contratos/' || v_id::text || '.pdf', p_fecha_firma := '2026-01-06');
  perform fn_contrato_marcar_tramite(v_id, 'copia');
end $indefinido$;

select is(
  (select estado from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000372003'),
  'ok',
  'control: el indefinido (0347) sigue llegando a "ok" igual que antes de esta migración');

select * from finish();
rollback;
