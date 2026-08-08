-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 143_el_sobretiempo_se_mide_por_ciclo.test.sql
-- ============================================================================
-- El sobretiempo de la 0185 tiene cuatro decisiones que se pueden "simplificar"
-- sin que nada se rompa a la vista, y cada una cuesta plata o cuesta una multa:
--
--   1. Se mide contra 48 h SEMANALES, no contra 8 h diarias. El taller de Lima
--      trabaja 5 días de 9 h: medido por día generaría sobretiempo TODAS las
--      semanas, haciendo tres horas menos que el máximo legal.
--   2. El ciclo se corta a los 7 días. Sin corte, doce días seguidos de 8 h
--      darían 48 h de exceso en vez de 8: seis veces más, y convertiría un tope
--      semanal en un tope por racha, que no existe en la norma.
--   3. Se suma solo el RECARGO, no la hora completa — las horas ya están dentro
--      de pago_base. Es exactamente el error que la 0173 corrigió con el feriado.
--   4. El tramo del 25 % es POR DÍA. Aplicarlo una vez por ciclo pagaría de menos
--      cuando el exceso se reparte en varios días.
--
-- Estas pruebas fijan las cuatro. También fijan las dos exclusiones —RxH y
-- sueldo fijo— porque devolverlas es un renglón y sale caro: a un RxH pagarle
-- horas extras es indicio de laboralidad.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000e1', 'ZZOTT', 'Sede de laboratorio OT', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000e0', 'OtAdmin', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'admin', 'x', '00000000-0000-0000-0000-00000000ee00', '2024-01-01');
set session_replication_role = origin;

-- Seis personas idénticas salvo en lo que cada prueba quiere aislar.
-- Salario S/1130. El periodo 29-jul → 28-ago-2026 tiene 31 días, así que
-- v_base = 6.5 × 31 = 201.5 h y el valor de la hora es S/5.60794…
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo)
values ('00000000-0000-0000-0000-0000000000e2', 'OtLima',   'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000e3', 'OtTope',   'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000e4', 'OtExceso', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000e5', 'OtRacha',  'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000e6', 'OtRxh',    'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'rxh',      false),
       ('00000000-0000-0000-0000-0000000000e7', 'OtFijo',   'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1130, '2024-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000e1' and nombres <> 'OtAdmin';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables)
select id, '2024-01-01', '09:00', '17:00', 0, 0, array[1,2,3,4,5,6]
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000e1' and nombres <> 'OtAdmin';

-- ── Las jornadas ────────────────────────────────────────────────────────────
-- Una sola semana dentro del periodo (lunes 3 a sábado 8 de agosto de 2026) para
-- que el número esperado se pueda calcular a mano y no dependa de cuántos ciclos
-- entren en el mes.

-- Lima: 5 días de 9 h = 45 h. Por debajo de 48.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000e2', d::date, 9.0, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-07'::date, '1 day') d;

-- Tope: 6 días de 8 h = 48 h exactas.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000e3', d::date, 8.0, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-08'::date, '1 day') d;

-- Exceso: 6 días de 8.5 h = 51 h. Se pasa por 3, y las 3 caen en el sábado 8.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000e4', d::date, 8.5, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-08'::date, '1 day') d;

-- Racha: doce días seguidos de 8 h. Dos ciclos, de 7 y 5 días → 56 h y 40 h.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000e5', d::date, 8.0, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-14'::date, '1 day') d;

-- RxH y sueldo fijo: la misma jornada que Exceso, 51 h. Deben quedar en cero.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8.5, 'cerrada'
from unnest(array['00000000-0000-0000-0000-0000000000e6',
                  '00000000-0000-0000-0000-0000000000e7']::uuid[]) p,
     generate_series('2026-08-03'::date, '2026-08-08'::date, '1 day') d;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee00', true);

-- ── El resultado, calculado una sola vez ────────────────────────────────────
create temp table ot as
select f->>'nombre'                       as nombre,
       (f->>'horas_sobretiempo')::numeric as horas,
       (f->>'monto_sobretiempo')::numeric as monto,
       f->>'sobretiempo_desde'            as desde,
       f->>'sobretiempo_hasta'            as hasta
from (select jsonb_array_elements(
        fn_planilla_calcular('2026-07-29', '2026-08-28')->'filas') f) x
where f->>'nombre' like 'Ot%';

-- ── 1 · El umbral es semanal, no diario ─────────────────────────────────────
select is(
  (select horas from ot where nombre = 'OtLima Lab'), 0::numeric,
  '5 días de 9 h son 45 h semanales: cero sobretiempo, aunque cada día pase de 8'
);

select is(
  (select monto from ot where nombre = 'OtLima Lab'), 0::numeric,
  'y por lo tanto no se paga nada — medir por día crearía un pasivo cada semana'
);

-- ── 2 · Las 48 son el tope, no el punto de partida ──────────────────────────
select is(
  (select horas from ot where nombre = 'OtTope Lab'), 0::numeric,
  '48 h exactas no generan sobretiempo: el exceso empieza en la hora 49'
);

-- ── 3 · El exceso y su recargo ──────────────────────────────────────────────
select is(
  (select horas from ot where nombre = 'OtExceso Lab'), 3.0::numeric,
  '6 días de 8.5 h son 51 h: 3 h de exceso'
);

-- 3 h en un solo día = 2 h al 25 % + 1 h al 35 % = 0.85 h de recargo.
-- 0.85 × (1130 / 201.5) = S/4.77
select is(
  (select monto from ot where nombre = 'OtExceso Lab'), 4.77::numeric,
  'se paga el RECARGO (2 h al 25 % + 1 h al 35 %), no la hora completa'
);

-- Pagar la hora entera además del recargo darían 3.85 h → S/21.59.
select ok(
  (select monto from ot where nombre = 'OtExceso Lab') < 10,
  'sumar la hora completa además del recargo la pagaría dos veces (serían S/21.59)'
);

-- ── 4 · El ciclo se corta a los 7 días ──────────────────────────────────────
-- Doce días de 8 h: ciclo de 7 días = 56 h → 8 h de exceso; ciclo de 5 = 40 h → 0.
select is(
  (select horas from ot where nombre = 'OtRacha Lab'), 8.0::numeric,
  'doce días seguidos de 8 h dan 8 h de exceso, no 48: el ciclo se corta a los 7'
);

-- El acumulado llega a 48 el sexto día y el séptimo (9-ago) lo lleva a 56: las
-- 8 h caen todas en ese día → 2 h al 25 % + 6 h al 35 % = 2.6 h de recargo.
-- 2.6 × 5.60794 = S/14.58
select is(
  (select monto from ot where nombre = 'OtRacha Lab'), 14.58::numeric,
  'el recargo se calcula por día: 2 h al 25 % y 6 h al 35 % en el séptimo día'
);

-- ── 5 · Las exclusiones ─────────────────────────────────────────────────────
select is(
  (select monto from ot where nombre = 'OtRxh Lab'), 0::numeric,
  'un RxH no cobra sobretiempo: no tiene jornada, y pagárselo sería indicio de laboralidad'
);

select is(
  (select monto from ot where nombre = 'OtFijo Lab'), 0::numeric,
  'sueldo fijo tampoco: el art. 5 del D.S. 007-2002-TR lo excluye de la jornada máxima'
);

-- ── 6 · El detalle que va a la boleta ───────────────────────────────────────
select is(
  (select desde from ot where nombre = 'OtExceso Lab'), '2026-08-08',
  'la boleta sabe en qué día empezó el exceso'
);

select is(
  (select hasta from ot where nombre = 'OtExceso Lab'), '2026-08-08',
  'y en cuál terminó — el mismo, cuando el exceso no se reparte'
);

select * from finish();
rollback;
