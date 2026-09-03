-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 275_la_boleta_desglosa_sobretiempo_25_35.test.sql
-- ============================================================================
-- La 0349 expone, además del recargo TOTAL del sobretiempo, cuánto es al 25 %
-- y cuánto al 35 % — lo pidió el contador para conciliar contra los códigos
-- 0105/0106 de la PLAME. Estas pruebas fijan dos cosas:
--
--   1. El desglose en sí, con los mismos dos escenarios de la 143 (exceso en
--      un solo día, y exceso repartido tras un ciclo de 7 días cortado).
--   2. EL CANDADO: 25 % + 35 % siempre suma EXACTO el total ya fijado por la
--      143 — nunca un centavo de más ni de menos. La migración calcula el
--      35 % como "total menos 25 %" precisamente para garantizar esto; si
--      alguien lo reescribe como su propia fórmula redondeada, esta prueba
--      es la que lo detecta (con OtExceso: 1 h × 0.35 × S/5.60794 redondea a
--      S/1.96 por su cuenta, pero el total exige S/1.97).
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000e1', 'ZZOTT', 'Sede de laboratorio OT', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000e0', 'OtAdmin', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'admin', 'x', '00000000-0000-0000-0000-00000000ee00', '2024-01-01');
set session_replication_role = origin;

-- Salario S/1130. El periodo 29-jul → 28-ago-2026 tiene 31 días, así que
-- v_base = 6.5 × 31 = 201.5 h y el valor de la hora es S/5.60794…
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo)
values ('00000000-0000-0000-0000-0000000000e4', 'OtExceso', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000e5', 'OtRacha',  'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000e3', 'OtTope',   'Lab', '00000000-0000-0000-0000-0000000000e1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1130, '2024-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000e1' and nombres <> 'OtAdmin';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables)
select id, '2024-01-01', '09:00', '17:00', 0, 0, array[1,2,3,4,5,6]
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000e1' and nombres <> 'OtAdmin';

-- Exceso: 6 días de 8.5 h = 51 h → 3 h de exceso, todas el sábado 8:
-- 2 h al 25 % + 1 h al 35 %. Recargo total ya fijado por la 143: S/4.77.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000e4', d::date, 8.5, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-08'::date, '1 day') d;

-- Racha: doce días de 8 h → ciclo de 7 días cortado (56 h → 8 h de exceso,
-- todas el séptimo día): 2 h al 25 % + 6 h al 35 %. Total fijado por la 143: S/14.58.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000e5', d::date, 8.0, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-14'::date, '1 day') d;

-- Tope: 6 días de 8 h = 48 h exactas. Cero sobretiempo, cero desglose.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000e3', d::date, 8.0, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-08'::date, '1 day') d;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee00', true);

create temp table ot as
select f->>'nombre'                          as nombre,
       (f->>'monto_sobretiempo')::numeric    as total,
       (f->>'horas_sobretiempo_25')::numeric as h25,
       (f->>'horas_sobretiempo_35')::numeric as h35,
       (f->>'monto_sobretiempo_25')::numeric as m25,
       (f->>'monto_sobretiempo_35')::numeric as m35
from (select jsonb_array_elements(
        fn_planilla_calcular('2026-07-29', '2026-08-28')->'filas') f) x
where f->>'nombre' like 'Ot%';

-- ── El desglose en sí ────────────────────────────────────────────────────
select is((select h25 from ot where nombre = 'OtExceso Lab'), 2.0::numeric,
  'OtExceso: 2 de las 3 h de exceso caen en el tramo del 25 %');
select is((select h35 from ot where nombre = 'OtExceso Lab'), 1.0::numeric,
  'y 1 h en el tramo del 35 % — el tramo se cuenta por día, no por ciclo');
select is((select m25 from ot where nombre = 'OtExceso Lab'), 2.80::numeric,
  '2 h × 25 % × S/5.60794 = S/2.80');

select is((select h25 from ot where nombre = 'OtRacha Lab'), 2.0::numeric,
  'OtRacha: el ciclo cortado a 7 días también reparte 2 h al 25 %...');
select is((select h35 from ot where nombre = 'OtRacha Lab'), 6.0::numeric,
  '...y 6 h al 35 %, todas en el séptimo día, donde cae el exceso entero');

select is((select h25 from ot where nombre = 'OtTope Lab'), 0::numeric,
  'sin exceso (48 h exactas), el desglose también sale en cero, no null');

-- ── EL CANDADO: 25 % + 35 % nunca se despega del total ya fijado por la 143 ─
select is(
  (select m25 + m35 from ot where nombre = 'OtExceso Lab'),
  (select total from ot where nombre = 'OtExceso Lab'),
  'OtExceso: 25 % + 35 % = total exacto (S/1.97, no los S/1.96 que daría redondear el 35 % por su cuenta)'
);
select is(
  (select m25 + m35 from ot where nombre = 'OtRacha Lab'),
  (select total from ot where nombre = 'OtRacha Lab'),
  'OtRacha: 25 % + 35 % = total exacto'
);
select is(
  (select m25 + m35 from ot where nombre = 'OtTope Lab'),
  (select total from ot where nombre = 'OtTope Lab'),
  'OtTope: 0 + 0 = 0'
);

select * from finish();
rollback;
