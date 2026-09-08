-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 315_la_practicante_cobra_movilidad_y_educacion.test.sql
-- ============================================================================
-- Fija lo que la 0397 cambia (movilidad y educación disponibles para un
-- practicante) y lo que NO cambia (AFP, asignación familiar y gratificación
-- siguen en cero), más la garantía real: el periodo se puede cerrar con un
-- practicante dentro, por su propio grupo (0323).
--
-- Geison —el caso real que motivó esta migración— tiene con_hijos=true a
-- propósito: si algún día alguien mezclara la condición de movilidad con la
-- de asignación familiar, esta prueba lo vería como un S/113 que no debería
-- estar.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000315a0', 'ZZPRA', 'Sede practicante lab', true);

insert into parametros_laborales (clave, valor, vigente_desde, sede_codigo, sustento)
values ('movilidad_diaria', 8.00, '2020-01-01', 'ZZPRA', 'prueba 315');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000315a1', 'PraAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000315a0', 'admin', 'x',
        '00000000-0000-0000-0000-0000000315af', '2020-01-01');
set session_replication_role = origin;

-- El practicante: cobra movilidad, con_hijos=true (para probar que NO le
-- aparece asignación familiar aunque tenga hijos — esa es exclusiva de
-- trabajadores, Ley 25129).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      tipo_vinculo, practicante_modalidad, con_hijos, cobra_movilidad)
values ('00000000-0000-0000-0000-0000000315a2', 'PraGeison', 'Lab',
        '00000000-0000-0000-0000-0000000315a0', 'x', '2026-09-03',
        'practicante', 'preprofesional', true, true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000315a2', 'colibri', 1130, '2020-01-01');

-- Dos días marcados en el periodo.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000315a2', '00000000-0000-0000-0000-0000000315a0', 'entrada',      '2026-09-03T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000315a2', '00000000-0000-0000-0000-0000000315a0', 'salida_final', '2026-09-03T15:30:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000315a2', '00000000-0000-0000-0000-0000000315a0', 'entrada',      '2026-09-04T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000315a2', '00000000-0000-0000-0000-0000000315a0', 'salida_final', '2026-09-04T15:30:00-05:00');

-- Una asignación de educación vigente, con comprobante. S/80 y no S/150:
-- el tope por rango (`fn_educacion_respeta_el_tope`) es de S/90 para colibrí.
insert into asignaciones_educacion
  (persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, comprobante_url)
values
  ('00000000-0000-0000-0000-0000000315a2', 80.00, 'Instituto Practicante', 107, 75, 'trabajador',
   '2026-01-01', '2026-12-31', 'educacion/pra/1.pdf');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000315af', true);

create or replace function pg_temp.fila() returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-08-29','2026-09-27') -> 'filas') x
  where x->>'persona_id' = '00000000-0000-0000-0000-0000000315a2';
$f$;

-- La misma suma que exige chk_foto_cuadra.
create or replace function pg_temp.suma() returns numeric
language sql as $f$
  select round((x->>'pago_base')::numeric, 2)
       + round(coalesce((x->>'monto_feriados')::numeric, 0), 2)
       + round(coalesce((x->>'monto_plus')::numeric, 0), 2)
       + round(coalesce((x->>'asignacion_familiar')::numeric, 0), 2)
       + round(coalesce((x->>'monto_movilidad')::numeric, 0), 2)
       + round(coalesce((x->>'monto_educacion')::numeric, 0), 2)
       - round(coalesce((x->>'descuento_afp')::numeric, 0), 2)
       + round(coalesce((x->>'monto_sobretiempo')::numeric, 0), 2)
       + round(coalesce((x->>'bonos')::numeric, 0), 2)
       - round(coalesce((x->>'descuentos')::numeric, 0), 2)
       - round(coalesce((x->>'retencion_4ta')::numeric, 0), 2)
  from (select pg_temp.fila() as x) t;
$f$;

-- 1 · Movilidad: 2 días marcados × S/8.
select is(
  (pg_temp.fila()->>'monto_movilidad')::numeric, 16.00::numeric,
  'CAMBIO 0397 · un practicante con tarifa y asistencia cobra movilidad');

-- 2 · Educación: la asignación vigente con comprobante.
select is(
  (pg_temp.fila()->>'monto_educacion')::numeric, 80.00::numeric,
  'CAMBIO 0397 · un practicante con asignación y comprobante cobra educación');

select is(
  (pg_temp.fila()->>'instituciones_educacion')::text, 'Instituto Practicante',
  'CAMBIO 0397 · y la boleta puede nombrar la institución');

-- 3 · Lo que NO cambia: AFP sigue en cero (0322 lo dejó así, esta migración no
--     lo toca).
select is(
  (pg_temp.fila()->>'descuento_afp')::numeric, 0.00::numeric,
  'un practicante sigue sin descuento de AFP — esta migración no lo toca');

-- 4 · Y asignación familiar tampoco, aunque tenga hijos (Ley 25129 es de
--     trabajadores, no de practicantes).
select is(
  (pg_temp.fila()->>'asignacion_familiar')::numeric, 0.00::numeric,
  'un practicante con hijos sigue sin asignación familiar');

-- 5 · Y la gratificación tampoco (fn_devenga_beneficios, 0085).
select is(
  (pg_temp.fila()->>'provision_gratificacion')::numeric, 0.00::numeric,
  'un practicante sigue sin provisión de gratificación');

-- 6 · El total cuadra con sus propias líneas — el mismo invariante que
--     `chk_foto_cuadra` exige para poder congelar.
select is(
  (pg_temp.fila()->>'total')::numeric - pg_temp.suma(),
  0.00::numeric,
  'el total del practicante cuadra con movilidad y educación adentro');

-- 7 · LO QUE DE VERDAD IMPORTA: el periodo se puede cerrar con un
--     practicante dentro, por su propio grupo (0323).
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000315e1', '2026-08-29', '2026-09-27', 'abierto');

select lives_ok(
  $$select fn_planilla_congelar('00000000-0000-0000-0000-0000000315e1', 'pago',
                                '00000000-0000-0000-0000-0000000315a1', 'practicante')$$,
  'el periodo se congela con un practicante dentro, por el grupo practicante');

-- 8 · Y de verdad lo congeló, con su movilidad y su educación adentro.
select is(
  (select (fila->>'monto_movilidad')::numeric + (fila->>'monto_educacion')::numeric
     from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-0000000315e1'
      and persona_id = '00000000-0000-0000-0000-0000000315a2'),
  96.00::numeric,
  'la foto congelada trae la movilidad y la educación del practicante');

select * from finish();
rollback;
