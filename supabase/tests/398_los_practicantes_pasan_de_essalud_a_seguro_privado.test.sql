-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 398_los_practicantes_pasan_de_essalud_a_seguro_privado.test.sql
-- ============================================================================
-- Fija lo que la 0504 cambia (un practicante ya no genera aporte de EsSalud) y
-- lo que NO cambia: una persona de planilla sigue generando el suyo, y el
-- practicante sigue cobrando su movilidad (0397 no se toca).
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000398a0', 'ZZSEG', 'Sede seguro practicante lab', true);

insert into parametros_laborales (clave, valor, vigente_desde, sede_codigo, sustento)
values ('movilidad_diaria', 8.00, '2020-01-01', 'ZZSEG', 'prueba 398');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000398a1', 'SegAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000398a0', 'admin', 'x',
        '00000000-0000-0000-0000-0000000398af', '2020-01-01');
set session_replication_role = origin;

-- El practicante.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      tipo_vinculo, practicante_modalidad, cobra_movilidad)
values ('00000000-0000-0000-0000-0000000398a2', 'SegPracticante', 'Lab',
        '00000000-0000-0000-0000-0000000398a0', 'x', '2026-09-03',
        'practicante', 'profesional', true);

-- La persona de planilla de control.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000398a3', 'SegPlanilla', 'Lab',
        '00000000-0000-0000-0000-0000000398a0', 'x', '2020-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000398a2', 'colibri', 1230, '2020-01-01'),
       ('00000000-0000-0000-0000-0000000398a3', 'colibri', 1230, '2020-01-01');

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p, '00000000-0000-0000-0000-0000000398a0', t::tipo_marca, ts::timestamptz
  from (values
    ('00000000-0000-0000-0000-0000000398a2'::uuid, 'entrada',      '2026-09-03T09:00:00-05:00'),
    ('00000000-0000-0000-0000-0000000398a2'::uuid, 'salida_final', '2026-09-03T15:30:00-05:00'),
    ('00000000-0000-0000-0000-0000000398a3'::uuid, 'entrada',      '2026-09-03T09:00:00-05:00'),
    ('00000000-0000-0000-0000-0000000398a3'::uuid, 'salida_final', '2026-09-03T15:30:00-05:00')
  ) v(p, t, ts);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000398af', true);

create or replace function pg_temp.fila(p_persona uuid) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-08-29','2026-09-27') -> 'filas') x
  where x->>'persona_id' = p_persona::text;
$f$;

-- 1 · Precondición: sin una tasa de EsSalud vigente, la prueba 3 pasaría por
--     la razón equivocada (todo daría cero). Se dice en voz alta.
select cmp_ok(
  (pg_temp.fila('00000000-0000-0000-0000-0000000398a3')->>'essalud_tasa')::numeric,
  '>', 0::numeric,
  'hay una tasa de EsSalud vigente (si no, esta prueba no prueba nada)');

-- 2 · LO QUE CAMBIA: el practicante ya no genera aporte de EsSalud.
select is(
  (pg_temp.fila('00000000-0000-0000-0000-0000000398a2')->>'aporte_essalud')::numeric,
  0.00::numeric,
  'CAMBIO 0504 · un practicante ya no genera aporte de EsSalud');

-- 3 · LO QUE NO CAMBIA: la persona de planilla sí sigue generándolo.
select cmp_ok(
  (pg_temp.fila('00000000-0000-0000-0000-0000000398a3')->>'aporte_essalud')::numeric,
  '>', 0::numeric,
  'una persona de planilla sigue generando su aporte de EsSalud');

-- 4 · Y es el piso de la RMV por la tasa, como siempre.
select is(
  (pg_temp.fila('00000000-0000-0000-0000-0000000398a3')->>'aporte_essalud')::numeric,
  round((pg_temp.fila('00000000-0000-0000-0000-0000000398a3')->>'base_essalud')::numeric
        * (pg_temp.fila('00000000-0000-0000-0000-0000000398a3')->>'essalud_tasa')::numeric, 2),
  'el aporte de planilla sigue siendo base de EsSalud × tasa');

-- 5 · La movilidad del practicante (0397) no se tocó: 1 día × S/8.
select is(
  (pg_temp.fila('00000000-0000-0000-0000-0000000398a2')->>'monto_movilidad')::numeric,
  8.00::numeric,
  'el practicante sigue cobrando su movilidad: la 0397 no se toca');

-- 6 · AFP sigue en cero para el practicante.
select is(
  (pg_temp.fila('00000000-0000-0000-0000-0000000398a2')->>'descuento_afp')::numeric,
  0.00::numeric,
  'el practicante sigue sin descuento de AFP');

-- 7 · El aviso de auditoría ya no promete EsSalud al pasar a alguien a practicante.
select fn_set_tipo_vinculo('00000000-0000-0000-0000-0000000398a3', 'practicante');

select ok(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-0000000398a3'
      and campo_modificado = 'personas.tipo_vinculo'
    order by corregido_at desc, id desc limit 1) like '%No genera EsSalud%'
  and
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-0000000398a3'
      and campo_modificado = 'personas.tipo_vinculo'
    order by corregido_at desc, id desc limit 1) not like '%SÍ genera EsSalud%',
  'el motivo de auditoría de pasar a practicante dice que NO genera EsSalud');

-- 8 · El freno de la migración no se disparó por una versión vieja: la función
--     conserva el filtro de cuentas de servicio de la 0495.
select ok(
  (select position('cuenta_de_servicio' in prosrc) > 0
     from pg_proc where proname = 'fn_planilla_calcular_nucleo'),
  'la función conserva el filtro de cuentas de servicio de la 0495');

select * from finish();
rollback;
