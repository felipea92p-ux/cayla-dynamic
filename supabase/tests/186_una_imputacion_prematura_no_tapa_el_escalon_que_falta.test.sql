-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 186_una_imputacion_prematura_no_tapa_el_escalon_que_falta.test.sql
-- ============================================================================
-- Sale de un expediente de verdad: sede Arequipa, agosto de 2026. Amonestación
-- el 22 de julio, PRIMERA suspensión de un día el 30, e imputación de cargos el
-- 10 de agosto — sin la segunda suspensión del literal d), porque el sistema
-- todavía tenía tres escalones.
--
-- El criterio recibido fue cerrar esa imputación sin despido y resolver con la
-- suspensión que falta. Simulado contra la base, el sistema hacía lo contrario:
-- tras archivar volvía a proponer IMPUTACIÓN, y quien siguiera el botón habría
-- emitido el documento equivocado, perpetuando el defecto.
--
-- La regla que fija esta prueba: una imputación mantiene arriba de la escalera
-- SOLO SI el legajo acredita las dos suspensiones que exige el numeral 19.6 (i)
-- —«la amonestación escrita del literal b) y las dos suspensiones de los
-- literales c) y d), todas notificadas y obrantes en el legajo»—. Con menos,
-- toca la suspensión que falta.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000f91', 'ZZIMP', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-000000000f01', 'AdminImp', 'Lab',
        '00000000-0000-0000-0000-000000000f91', 'admin', 'x',
        '00000000-0000-0000-0000-000000000e01', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000000f02', 'EscaleraRota',    'Lab', '00000000-0000-0000-0000-000000000f91', 'x', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000000f03', 'EscaleraCompleta','Lab', '00000000-0000-0000-0000-000000000f91', 'x', '2024-01-01', 'activo', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000e01', true);

create function pg_temp.doc(p_persona uuid, p_nivel text, p_dias int, p_hace int, p_corr text)
returns uuid language sql as $$
  insert into expediente_disciplinario
    (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
     suspension_dias, suspension_desde, suspension_hasta,
     firmante_id, firmado_at, medio_entrega, entregado_at, correlativo, creado_por)
  values (p_persona, 'tardanza', p_nivel, 'entregado',
          fn_hoy_lima() - p_hace, fn_hoy_lima() - p_hace, '[]'::jsonb,
          p_dias,
          case when p_dias is not null then fn_hoy_lima() - p_hace + 1 end,
          case when p_dias is not null then fn_hoy_lima() - p_hace + p_dias end,
          '00000000-0000-0000-0000-000000000f01', now() - (p_hace || ' days')::interval,
          'fisico', now() - (p_hace || ' days')::interval,
          p_corr, '00000000-0000-0000-0000-000000000f01')
  returning id;
$$;

-- ── El caso de Arequipa: amonestación, UNA suspensión, imputación ───────────
select pg_temp.doc('00000000-0000-0000-0000-000000000f02', 'amonestacion', null, 22, 'T-A/01');
select pg_temp.doc('00000000-0000-0000-0000-000000000f02', 'suspension',      1, 14, 'T-A/02');
create temp table _imp as
  select pg_temp.doc('00000000-0000-0000-0000-000000000f02', 'imputacion', null, 3, 'T-A/03') as id;

select ok((select bloqueado from fn_tardanza_escalon('00000000-0000-0000-0000-000000000f02')),
          'SIN RESOLVER · con la imputación abierta la escala bloquea: decide Gerencia');

select lives_ok(
  format($$ select fn_expediente_resolver(%L, 'archivado',
    'Evaluado el descargo, no amerita extinción: falta el escalón del literal d).') $$,
    (select id from _imp)),
  'Se archiva sin despido, con su motivo');

-- ── Y aquí estaba el defecto ───────────────────────────────────────────────
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-000000000f02')),
          'suspension',
          '19.6 (i) · con UNA sola suspensión en el legajo, toca la SEGUNDA — no otra imputación');

select is((select suspension_previa_dias from fn_tardanza_escalon('00000000-0000-0000-0000-000000000f02')),
          1, '19.2 d) · y sabe que la primera duró un día, para que la segunda sea mayor');

select is((select minimo from fn_tardanza_escalon('00000000-0000-0000-0000-000000000f02')),
          1, '19.2 d) · basta una tardanza nueva');

-- ── Con la escalera COMPLETA, el principio se conserva ──────────────────────
-- Es lo que fija la prueba 160: una imputación resuelta no baja de la escalera.
-- Pero solo cuando de verdad hubo escalera debajo.
select pg_temp.doc('00000000-0000-0000-0000-000000000f03', 'amonestacion', null, 40, 'T-B/01');
select pg_temp.doc('00000000-0000-0000-0000-000000000f03', 'suspension',      1, 30, 'T-B/02');
select pg_temp.doc('00000000-0000-0000-0000-000000000f03', 'suspension',      2, 20, 'T-B/03');
create temp table _imp2 as
  select pg_temp.doc('00000000-0000-0000-0000-000000000f03', 'imputacion', null, 5, 'T-B/04') as id;

select lives_ok(
  format($$ select fn_expediente_resolver(%L, 'archivado', 'Evaluados los descargos, se archiva.') $$,
    (select id from _imp2)),
  'La segunda persona también se archiva sin despido');

select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-000000000f03')),
          'imputacion',
          'DE AHÍ NO SE BAJA · con las DOS suspensiones obrantes, la imputación archivada mantiene arriba');

select * from finish();
rollback;
