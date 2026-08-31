-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 267_el_tablero_avisa_el_tope_de_12_meses.test.sql — 0336
-- ============================================================================
-- El quinto y último pendiente de Practicantes: que `fn_contratos_tablero`
-- avise antes de que una practicante llegue a los 12 meses continuos de
-- modalidad formativa (Ley 28518, art. 30), medido desde `fecha_ingreso`
-- (decisión de Felipe, no sumando convenios — ver la 0336).
--
-- Las cuatro fechas usan `fn_hoy_lima()` como ancla, no fechas fijas: la
-- prueba tiene que seguir siendo verdad sea cual sea "hoy".
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000267000', 'ZZ267', 'Sede de laboratorio 267', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000267aa0', 'Jefa', 'Lab267',
        '00000000-0000-0000-0000-000000267000', 'admin', 'h',
        '00000000-0000-0000-0000-000000267aff', '2020-01-01');
set session_replication_role = origin;

-- A · SIN convenio registrado en el sistema, a 11 meses de ingresar. Sigue
-- siendo "sin_contrato" (esa prioridad no cambia — conseguir el documento
-- sigue siendo lo primero), pero la fecha que ya muestra ese estado
-- (`estadoSinContrato` en la pantalla) pasa a ser el tope, no un vacío.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, funcion)
values ('00000000-0000-0000-0000-000000267a01', 'Ana', 'SinFecha267',
        '00000000-0000-0000-0000-000000267000', 'h',
        (select (fn_hoy_lima() - interval '11 months')::date), 'practicante', 'calidad_servicio');

-- B · CON convenio firmado que dice una fecha MÁS ALLÁ del tope de 12 meses
-- (se generó antes de la 0336, o se editó a mano en Equipo) → el tope manda
-- igual, y con documento ya registrado sí llega a por_vencer/vencido.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, fecha_fin_contrato, funcion)
values ('00000000-0000-0000-0000-000000267b01', 'Bea', 'MasAlla267',
        '00000000-0000-0000-0000-000000267000', 'h',
        (select (fn_hoy_lima() - interval '11 months')::date),
        'practicante', (select (fn_hoy_lima() + interval '3 months')::date), 'calidad_servicio');

-- C · su convenio vence ANTES del tope (el caso normal) → manda su propio
-- documento, el tope no interviene.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, fecha_fin_contrato, funcion)
values ('00000000-0000-0000-0000-000000267c01', 'Cris', 'Normal267',
        '00000000-0000-0000-0000-000000267000', 'h',
        (select (fn_hoy_lima() - interval '2 months')::date),
        'practicante', (select (fn_hoy_lima() + interval '10 days')::date), 'calidad_servicio');

-- D · alguien en planilla con la misma antigüedad que A y CON convenio
-- firmado más allá de 12 meses — el tope de 12 meses es de un convenio de
-- modalidad formativa, no de un contrato de trabajo, y no le corresponde.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, fecha_fin_contrato, funcion)
values ('00000000-0000-0000-0000-000000267d01', 'Dora', 'Planilla267',
        '00000000-0000-0000-0000-000000267000', 'h',
        (select (fn_hoy_lima() - interval '11 months')::date),
        'planilla', (select (fn_hoy_lima() + interval '3 months')::date), 'calidad_servicio');

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000267aff', true);
end $sesion$;

-- A Bea y a Dora se les registra y firma un convenio/contrato, para que
-- `fn_contratos_tablero` deje de verlas como "sin_contrato" y llegue a
-- evaluar la fecha efectiva contra el tope.
do $doc$
declare v_id uuid;
begin
  v_id := fn_contrato_registrar(
    p_persona_id := '00000000-0000-0000-0000-000000267b01', p_tipo := 'convenio_practicas',
    p_cargo := 'Practicante', p_sede_id := '00000000-0000-0000-0000-000000267000',
    p_remuneracion_mensual := 1130,
    p_fecha_inicio := (select (fn_hoy_lima() - interval '11 months')::date),
    p_fecha_fin := (select (fn_hoy_lima() + interval '3 months')::date),
    p_documento_html := '<p>bea</p>');
  perform fn_contrato_registrar(p_id := v_id,
    p_storage_path := 'contratos/' || v_id::text || '.pdf', p_fecha_firma := (fn_hoy_lima() - 1));

  v_id := fn_contrato_registrar(
    p_persona_id := '00000000-0000-0000-0000-000000267d01', p_tipo := 'renovacion',
    p_cargo := 'Asesora', p_sede_id := '00000000-0000-0000-0000-000000267000',
    p_remuneracion_mensual := 1130,
    p_fecha_inicio := (select (fn_hoy_lima() - interval '11 months')::date),
    p_fecha_fin := (select (fn_hoy_lima() + interval '3 months')::date),
    p_documento_html := '<p>dora</p>');
  perform fn_contrato_registrar(p_id := v_id,
    p_storage_path := 'contratos/' || v_id::text || '.pdf', p_fecha_firma := (fn_hoy_lima() - 1));
end $doc$;

-- ── 1 · Ana (A): sin convenio registrado, sigue siendo "sin_contrato" ──────
-- Esa prioridad no cambia — conseguir el documento sigue siendo lo primero.
select is(
  (select estado from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000267a01'),
  'sin_contrato',
  'sin ningún convenio registrado en el sistema, sigue apareciendo como sin_contrato');

-- ── 2 · Pero la fecha que ya muestra ese estado es el tope, no un vacío ────
select is(
  (select fecha_fin_contrato from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000267a01'),
  (select (fecha_ingreso + interval '12 months')::date from personas where id = '00000000-0000-0000-0000-000000267a01'),
  'la fecha efectiva es fecha_ingreso + 12 meses, calculada, no una fecha puesta a mano');

-- ── 3 · Bea (B): su convenio firmado dice más allá del tope — el tope manda igual ──
select is(
  (select fecha_fin_contrato from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000267b01'),
  (select (fecha_ingreso + interval '12 months')::date from personas where id = '00000000-0000-0000-0000-000000267b01'),
  'con fecha en el convenio MÁS ALLÁ del tope, la fecha efectiva sigue siendo el tope — nunca la del papel');

select is(
  (select estado from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000267b01'),
  'por_vencer',
  'y por eso Bea sale por_vencer, aunque su convenio firmado diga que le quedan 3 meses');

-- ── 4 · Cris (C): su convenio vence antes del tope — manda su documento ────
select is(
  (select fecha_fin_contrato from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000267c01'),
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-000000267c01'),
  'con el convenio venciendo antes del tope, la fecha efectiva es la del propio documento');

-- ── 5 · Dora (D): en planilla, con contrato firmado más allá de 12 meses ───
-- desde su ingreso — el tope no le corresponde, manda su propio contrato.
select is(
  (select fecha_fin_contrato from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000267d01'),
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-000000267d01'),
  'alguien en planilla no tiene tope de 12 meses — manda su propio contrato, aunque supere el año');

select * from finish();
rollback;
