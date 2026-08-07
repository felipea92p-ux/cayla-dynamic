-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 138_las_vacaciones_se_pagan.test.sql
-- ============================================================================
-- fn_planilla_calcular paga horas marcadas. Quien está de vacaciones no marca,
-- así que esos días valían S/0 — y encima, como bajaban sus horas del mes, le
-- recortaban el feriado del periodo, que se prorratea sobre ellas. Medido antes
-- de la 0177: S/431.91 sobre un sueldo de S/1,800 por tomarse 5 días.
--
-- La 0177 acredita cada día de vacaciones con el PROMEDIO de lo que se le pagó
-- por día trabajado (art. 15 del D. Leg. 713: «la remuneración que hubiera
-- percibido de continuar laborando»).
--
-- Estas pruebas fijan las cuatro mitades de la regla, porque cada una se puede
-- romper arreglando otra:
--   · quien tomó vacaciones cobra esos días;
--   · el monto es proporcional a SU jornada, no a una jornada estándar;
--   · los domingos dentro del rango NO se pagan (no los habría trabajado);
--   · quien no tomó vacaciones no se mueve un centavo.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000e1', 'ZZVAC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000e2', 'VacAdmin', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'admin', 'x', '00000000-0000-0000-0000-00000000ee02', '2024-01-01');
set session_replication_role = origin;

-- Cuatro personas con el MISMO salario. Cambia la jornada y si tomaron vacaciones.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo)
values
  ('00000000-0000-0000-0000-0000000000e3', 'VacSi',    'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', false),
  ('00000000-0000-0000-0000-0000000000e4', 'VacNo',    'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', false),
  ('00000000-0000-0000-0000-0000000000e5', 'VacMedio', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', false),
  ('00000000-0000-0000-0000-0000000000e6', 'VacFijo',  'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1800.00, '2024-01-01' from personas
where id in ('00000000-0000-0000-0000-0000000000e3','00000000-0000-0000-0000-0000000000e4',
             '00000000-0000-0000-0000-0000000000e5','00000000-0000-0000-0000-0000000000e6');

-- Todas L-V. VacMedio hace media jornada: sirve para probar la proporcionalidad.
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-01-01', '09:00', '18:00', array[1,2,3,4,5] from personas
where id in ('00000000-0000-0000-0000-0000000000e3','00000000-0000-0000-0000-0000000000e4',
             '00000000-0000-0000-0000-0000000000e5','00000000-0000-0000-0000-0000000000e6');

-- Agosto 2026 completo. Las que tienen vacaciones no marcan del 10 al 16
-- (7 días CALENDARIO: 5 laborables + sábado + domingo).
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date,
       case when p.id = '00000000-0000-0000-0000-0000000000e5' then 4.0 else 8.0 end,
       'cerrada'
from personas p, generate_series('2026-08-01'::date, '2026-08-31'::date, '1 day') d
where p.id in ('00000000-0000-0000-0000-0000000000e3','00000000-0000-0000-0000-0000000000e4',
               '00000000-0000-0000-0000-0000000000e5','00000000-0000-0000-0000-0000000000e6')
  and extract(dow from d)::int between 1 and 5
  and not (p.id in ('00000000-0000-0000-0000-0000000000e3',
                    '00000000-0000-0000-0000-0000000000e5',
                    '00000000-0000-0000-0000-0000000000e6')
           and d::date between '2026-08-10' and '2026-08-16');

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por)
select id, 'vacaciones', '2026-08-10', '2026-08-16', 'prueba',
       '00000000-0000-0000-0000-0000000000e2'
from personas p
where p.id in ('00000000-0000-0000-0000-0000000000e3',
               '00000000-0000-0000-0000-0000000000e5',
               '00000000-0000-0000-0000-0000000000e6');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee02', true);

create temp table calc as
select f->>'nombre' as nombre,
       (f->>'pago_base')::numeric               as pago_base,
       (f->>'monto_vacaciones')::numeric        as monto_vac,
       (f->>'dias_vacaciones_pagados')::int     as dias_vac,
       (f->>'horas_mes')::numeric               as horas_mes,
       (f->>'monto_feriados')::numeric          as feriado
from (select jsonb_array_elements(fn_planilla_calcular('2026-08-01','2026-08-31')->'filas') f) x
where f->>'nombre' like '%Lab';

-- ── se pagan, y solo los días laborables ───────────────────────────────────
select ok(
  (select monto_vac from calc where nombre = 'VacSi Lab') > 0,
  'Quien tomó vacaciones cobra esos días (antes valían S/0)'
);

select is(
  (select dias_vac from calc where nombre = 'VacSi Lab'),
  5,
  'Del 10 al 16 (7 días calendario) se pagan 5: el sábado y el domingo no se habrían trabajado'
);

-- ── el monto es el promedio de SU propio día, no una jornada estándar ──────
select is(
  (select round(monto_vac / nullif(dias_vac, 0), 2) from calc where nombre = 'VacMedio Lab'),
  (select round(monto_vac / nullif(dias_vac, 0), 2) / 2 from calc where nombre = 'VacSi Lab'),
  'Quien hace media jornada cobra la mitad por día de vacaciones: es proporcional a su jornada real'
);

-- ── quien no tomó vacaciones no se mueve ───────────────────────────────────
select is(
  (select monto_vac from calc where nombre = 'VacNo Lab'),
  0::numeric,
  'Quien NO tomó vacaciones no recibe ningún monto por este concepto'
);

select is(
  (select dias_vac from calc where nombre = 'VacNo Lab'),
  0,
  'Quien NO tomó vacaciones tiene cero días de vacaciones pagados'
);

-- ── sueldo fijo ya cobra el periodo completo: no se le suma encima ─────────
select is(
  (select monto_vac from calc where nombre = 'VacFijo Lab'),
  0::numeric,
  'Sueldo fijo no suma vacaciones: su remuneración del periodo ya las contiene'
);

-- ── la propiedad que da sentido a todo: quedar igual que si hubiera venido ──
select is(
  (select round(pago_base, 2) from calc where nombre = 'VacSi Lab'),
  (select round(pago_base, 2) from calc where nombre = 'VacNo Lab'),
  'Con la misma jornada y el mismo salario, tomarse vacaciones ya no hace cobrar menos'
);

-- ── el feriado tampoco se recorta: es el mismo día, no puede ser «trabajado»
-- ── para el sueldo y «no trabajado» para el prorrateo del feriado ──────────
select is(
  (select round(feriado, 2) from calc where nombre = 'VacSi Lab'),
  (select round(feriado, 2) from calc where nombre = 'VacNo Lab'),
  'Tomarse vacaciones ya no recorta el feriado del periodo'
);

select ok(
  (select horas_mes from calc where nombre = 'VacSi Lab')
  < (select horas_mes from calc where nombre = 'VacNo Lab'),
  'Y lo anterior NO es porque se hayan inventado horas marcadas: horas_mes sigue contando solo lo que se marcó'
);

select * from finish();
rollback;
