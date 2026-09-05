-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 277_el_historial_no_salta_meses_ni_permisos.test.sql
-- ============================================================================
-- fn_objetivos_historial (0350) alimenta el gráfico de tendencia de
-- /admin/objetivos. Su riesgo no es el cálculo —solo lee objetivos_mensuales,
-- que ya sincroniza la 0032— es la SERIE: que un mes sin checklist no
-- desaparezca de la ventana (si desapareciera, el gráfico dibujaría 11 meses
-- pegados como si fueran consecutivos, mintiendo sobre cuándo pasó cada cosa),
-- y que la ventana respete las mismas reglas de visibilidad que el resto del
-- checklist.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000f1', 'ZZHI1', 'Sede de laboratorio', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000f2', 'HiIntegrante', 'Lab', '00000000-0000-0000-0000-0000000000f1', 'x');

-- Objetivos en agosto (2/2) y en junio (1/3) de 2026 — julio queda sin checklist a propósito.
insert into objetivos_items (persona_id, anio, mes, descripcion, orden, cumplido) values
  ('00000000-0000-0000-0000-0000000000f2', 2026, 6, 'Meta junio 1', 1, true),
  ('00000000-0000-0000-0000-0000000000f2', 2026, 8, 'Meta agosto 1', 1, true),
  ('00000000-0000-0000-0000-0000000000f2', 2026, 8, 'Meta agosto 2', 2, true);
insert into objetivos_items (persona_id, anio, mes, descripcion, orden, cumplido) values
  ('00000000-0000-0000-0000-0000000000f2', 2026, 6, 'Meta junio 2', 2, false),
  ('00000000-0000-0000-0000-0000000000f2', 2026, 6, 'Meta junio 3', 3, false);
select fn_objetivos_sync_mes('00000000-0000-0000-0000-0000000000f2', 2026, 6);
select fn_objetivos_sync_mes('00000000-0000-0000-0000-0000000000f2', 2026, 8);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000f3', 'HiAdmin', 'Lab', '00000000-0000-0000-0000-0000000000f1', 'admin', 'x', '00000000-0000-0000-0000-00000000ff03');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff03', true); -- admin

-- ── 1 · Una ventana de 3 meses (jun/jul/ago) trae exactamente 3 filas ───────
select is(
  jsonb_array_length(fn_objetivos_historial('00000000-0000-0000-0000-0000000000f2', 2026, 8, 3)),
  3,
  'VENTANA · pedir 3 meses hasta agosto trae junio, julio y agosto — julio no se salta aunque esté vacío');

-- ── 2 · Julio (el mes vacío) entra con total=0, no desaparece ni miente ────
select is(
  (select (e->>'total')::int from jsonb_array_elements(
     fn_objetivos_historial('00000000-0000-0000-0000-0000000000f2', 2026, 8, 3)) e
   where (e->>'anio')::int = 2026 and (e->>'mes')::int = 7),
  0,
  'HUECO · julio entra en la serie con total=0 — un mes sin checklist no es un 0% cumplido, es "sin dato"');

-- ── 3 · Junio trae su cumplidos/total real (1 de 3) ─────────────────────────
select is(
  (select jsonb_build_object('cumplidos', e->'cumplidos', 'total', e->'total') from jsonb_array_elements(
     fn_objetivos_historial('00000000-0000-0000-0000-0000000000f2', 2026, 8, 3)) e
   where (e->>'anio')::int = 2026 and (e->>'mes')::int = 6),
  jsonb_build_object('cumplidos', to_jsonb(1), 'total', to_jsonb(3)),
  'DATO REAL · junio trae 1 de 3, tal cual quedó sincronizado por fn_objetivos_sync_mes');

-- ── 4 · p_meses se acota: pedir 999 no da una serie de 999 filas ───────────
select is(
  jsonb_array_length(fn_objetivos_historial('00000000-0000-0000-0000-0000000000f2', 2026, 8, 999)),
  24,
  'TOPE · p_meses se acota a 24, aunque se pida una ventana absurdamente larga');

-- ── 5 · Sin permiso: la propia persona SÍ ve su historial ───────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff03', true); -- vuelve a admin de paso

select is(
  jsonb_array_length(fn_objetivos_historial('00000000-0000-0000-0000-0000000000f2', 2026, 8, 3)),
  3,
  'PERMISO · admin ve el historial de cualquiera (repite la 1, confirma que no se rompió arriba)');

-- ── 6 · Otra sede, sin permiso: la ventana vuelve vacía, no un error ────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000f4', 'ZZHI2', 'Sede de laboratorio B', true);
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000f5', 'HiEncargadaAjena', 'Lab', '00000000-0000-0000-0000-0000000000f4', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000ff05');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff05', true);

select is(
  jsonb_array_length(fn_objetivos_historial('00000000-0000-0000-0000-0000000000f2', 2026, 8, 3)),
  0,
  'PERMISO · la encargada de otra sede no ve nada de este historial — vacío, no un raise exception');

select * from finish();
rollback;
