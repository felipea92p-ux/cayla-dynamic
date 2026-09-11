-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 331_los_feriados_de_la_pantalla_usan_el_periodo_no_el_mes_calendario.test.sql
-- ============================================================================
-- Defiende la migración 0419: `fn_feriados_laborados` (la pantalla de
-- Feriados) calcula la sobretasa sobre el PERIODO de planilla (29→28) que
-- contiene el feriado — la misma base que `fn_feriado_devengado_nucleo` usa
-- para lo que de verdad paga la planilla — y no sobre el mes calendario del
-- feriado, que es lo que hacía hasta la 0238.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000419', 'ZZ419', 'Sede de laboratorio', true);

set session_replication_role = replica;

insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000491', 'CuatroUnoNueveAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000000419', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000000591', '2020-01-01');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000492', 'CuatroUnoNueveIntegrante', 'Laboratorio',
        '00000000-0000-0000-0000-000000000419', 'test-hash', '2020-01-01');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-000000000492', '2020-01-01', '09:00', '18:00', '{0,1,2,3,4,5,6}');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000000492', 'colibri', 3000.00, '2020-01-01');

-- Fiestas Patrias 2026: cae en el periodo 29/06→28/07 (30 días), NO en julio
-- calendario (31 días) — el caso que mide el hallazgo #5.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
values ('00000000-0000-0000-0000-000000000492', '2026-07-28', 8.00, 'cerrada');

set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000591', true);

-- 1 · Con el periodo real registrado, la pantalla coincide EXACTO con lo que
-- de verdad paga fn_feriado_devengado_nucleo — no con el mes calendario.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000419aa', '2026-06-29', '2026-07-28', 'pagado');

select is(
  (select sobretasa from fn_feriados_laborados('2026-07-01', '2026-07-31')
    where persona_id = '00000000-0000-0000-0000-000000000492' and fecha_feriado = '2026-07-28'),
  round((fn_feriado_devengado_nucleo(
      '00000000-0000-0000-0000-000000000492'::uuid, '2026-06-29'::date, '2026-07-28'::date, 30
    ) ->> 'sobretasa')::numeric, 2),
  'La pantalla coincide con lo que de verdad paga fn_feriado_devengado_nucleo'
);

-- 2 · Sin fila en periodos_planilla (una fecha para la que aún no se abrió
-- periodo), el respaldo reconstruye el mismo bloque 29→28 y da el mismo monto.
delete from periodos_planilla where id = '00000000-0000-0000-0000-0000000419aa';

select is(
  (select sobretasa from fn_feriados_laborados('2026-07-01', '2026-07-31')
    where persona_id = '00000000-0000-0000-0000-000000000492' and fecha_feriado = '2026-07-28'),
  123.08::numeric,
  'Sin periodo registrado, el respaldo reconstruye el mismo bloque 29→28 y da el mismo monto'
);

-- 3 · Control: el 1 de enero cae en un periodo (29/dic→28/ene) que en este
-- caso tiene el MISMO largo que su mes calendario (los dos, 31 días): el
-- número no debe moverse con el cambio.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
values ('00000000-0000-0000-0000-000000000492', '2027-01-01', 8.00, 'cerrada');

select is(
  (select sobretasa from fn_feriados_laborados('2027-01-01', '2027-01-31')
    where persona_id = '00000000-0000-0000-0000-000000000492' and fecha_feriado = '2027-01-01'),
  round(8.00 * 3000.00 / (6.5 * 31), 2),
  'Cuando el periodo y el mes calendario tienen el mismo largo, el monto no cambia'
);

-- 4 · Quien no marcó ese feriado no aparece en absoluto en el listado.
select is(
  (select count(*) from fn_feriados_laborados('2026-07-01', '2026-07-31')
    where persona_id = '00000000-0000-0000-0000-000000000491'),
  0::bigint,
  'Quien no marcó ese día no aparece en el listado'
);

select * from finish();
rollback;
