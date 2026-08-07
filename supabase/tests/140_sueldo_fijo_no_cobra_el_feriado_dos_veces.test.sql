-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 140_sueldo_fijo_no_cobra_el_feriado_dos_veces.test.sql
-- ============================================================================
-- fn_planilla_calcular paga el feriado en tres partes: las horas marcadas ese
-- día (ya dentro de pago_base), esas horas otra vez (la sobretasa del art. 8 del
-- D. Leg. 713) y el día de feriado prorrateado (7.5 * horas_mes / base_horas).
--
-- Para quien cobra por horas las tres son correctas. Para quien tiene
-- `sueldo_fijo`, pago_base es su salario mensual COMPLETO marque o no (rama de
-- la 0047), y ese salario ya contiene los feriados del mes: la tercera parte se
-- los pagaba una segunda vez. Medido antes de la 0173: S/314 en un solo periodo
-- sobre un sueldo de S/4,500, sin haber trabajado ninguno de los dos feriados.
--
-- Estas pruebas fijan las dos mitades de la regla, porque es fácil arreglar una
-- rompiendo la otra:
--   · sueldo fijo NO recibe el día prorrateado — ni trabajando el feriado;
--   · sueldo fijo SÍ conserva la sobretasa si lo trabajó (no se le puede quitar
--     un derecho por su forma de pago);
--   · quien cobra por horas no se mueve un centavo.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000f1', 'ZZFIJ', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000f2', 'FijAdmin', 'Lab', '00000000-0000-0000-0000-0000000000f1', 'admin', 'x', '00000000-0000-0000-0000-00000000ff02', '2024-01-01');
set session_replication_role = origin;

-- Tres personas, mismo salario, mismo horario y las mismas horas marcadas.
-- Lo único que las distingue es `sueldo_fijo` y si vinieron el feriado.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo)
values
  ('00000000-0000-0000-0000-0000000000f3', 'FijNoVino',  'Lab', '00000000-0000-0000-0000-0000000000f1', 'x', '2024-01-01', true),
  ('00000000-0000-0000-0000-0000000000f4', 'FijSiVino',  'Lab', '00000000-0000-0000-0000-0000000000f1', 'x', '2024-01-01', true),
  ('00000000-0000-0000-0000-0000000000f5', 'PorHoras',   'Lab', '00000000-0000-0000-0000-0000000000f1', 'x', '2024-01-01', false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 3000.00, '2024-01-01'
from personas where id in (
  '00000000-0000-0000-0000-0000000000f3',
  '00000000-0000-0000-0000-0000000000f4',
  '00000000-0000-0000-0000-0000000000f5');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '18:00', array[1,2,3,4,5]
from personas where id in (
  '00000000-0000-0000-0000-0000000000f3',
  '00000000-0000-0000-0000-0000000000f4',
  '00000000-0000-0000-0000-0000000000f5');

insert into feriados (fecha, nombre)
values ('2026-08-06', 'Feriado de laboratorio')
on conflict (fecha) do nothing;

-- Todos marcan 8 h de lunes a viernes de agosto. FijNoVino se salta el feriado.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 8.0, 'cerrada'
from personas p,
     generate_series('2026-08-01'::date, '2026-08-31'::date, '1 day') d
where p.id in ('00000000-0000-0000-0000-0000000000f3',
               '00000000-0000-0000-0000-0000000000f4',
               '00000000-0000-0000-0000-0000000000f5')
  and extract(dow from d)::int between 1 and 5
  and not (p.id = '00000000-0000-0000-0000-0000000000f3' and d::date = '2026-08-06');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ff02', true);

create temp table calc as
select f->>'nombre' as nombre,
       (f->>'pago_base')::numeric      as pago_base,
       (f->>'monto_feriados')::numeric as feriados,
       (jsonb_path_query_first(f, '$.feriados_detalle[*] ? (@.fecha == "2026-08-06")')
         ->>'proporcional_horas')::numeric as prorrateo
from (select jsonb_array_elements(fn_planilla_calcular('2026-08-01','2026-08-31')->'filas') f) x
where f->>'nombre' like '%Lab';

-- ── sueldo fijo: el día prorrateado desaparece ──────────────────────────────
select is(
  (select prorrateo from calc where nombre = 'FijNoVino Lab'),
  0::numeric,
  'Sueldo fijo que NO trabajó el feriado: el día prorrateado es 0 (ya está en su sueldo)'
);

select is(
  (select feriados from calc where nombre = 'FijNoVino Lab'),
  0::numeric,
  'Sueldo fijo que NO trabajó el feriado: no cobra NADA extra por ese feriado'
);

select is(
  (select prorrateo from calc where nombre = 'FijSiVino Lab'),
  0::numeric,
  'Sueldo fijo que SÍ trabajó el feriado: tampoco cobra el día prorrateado'
);

-- ── … pero conserva la sobretasa, que sí le corresponde ─────────────────────
select ok(
  (select feriados from calc where nombre = 'FijSiVino Lab') > 0,
  'Sueldo fijo que SÍ trabajó el feriado: conserva la sobretasa del art. 8'
);

-- ── quien cobra por horas no se mueve ───────────────────────────────────────
select ok(
  (select prorrateo from calc where nombre = 'PorHoras Lab') > 0,
  'Quien cobra por horas sigue recibiendo el día de feriado prorrateado'
);

select ok(
  (select feriados from calc where nombre = 'PorHoras Lab')
  > (select feriados from calc where nombre = 'FijSiVino Lab'),
  'Con las mismas horas y el mismo salario, quien cobra por horas recibe más feriado que quien tiene sueldo fijo'
);

select * from finish();
rollback;
