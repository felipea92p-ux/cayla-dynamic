-- ============================================================================
-- 124_las_provisiones_descuentan_lo_depositado.test.sql
-- ============================================================================
-- El caso real, medido en producción el 2026-08-05:
--
--   El 15 de mayo se depositó CTS a cinco personas por PLAME —S/1.155,62 a sus
--   cuentas CTS del banco— y tres meses después las provisiones seguían
--   diciendo `cts_may_pagada: false` y acumulando S/1.774,80 por esa ventana.
--
--   La causa: hasta la 0158, la única forma de que el sistema supiera que algo
--   se pagó era encontrar un MOVIMIENTO DE PLANILLA. Un depósito al banco no
--   pasa por la planilla.
--
-- CÓMO ESTÁ ESCRITO ESTE ARCHIVO, y por qué importa.
--
-- No afirma montos absolutos. Primero LEE cuánto acumula la persona sin ningún
-- desembolso, y después comprueba que cada desembolso baja la provisión en
-- exactamente ese monto. Así la prueba mide lo que la 0158 cambió —la resta— y
-- no la fórmula del acumulado, que es de otra migración y tiene otros dueños.
-- Si algún día cambia el factor de CTS, esta prueba sigue siendo cierta.
--
-- Las cuatro decisiones de Felipe que defiende, y que se rompen por separado:
--   · se RESTA el monto (no un sí/no que salta a cero)
--   · se toma el MAYOR de las dos fuentes, nunca la suma
--   · el negativo SE MUESTRA
--   · NO hay arrastre de una ventana a la otra
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000c500', 'ZZPRV', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c501', 'ProvAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c500', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000c509', '2025-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c502', 'ProvPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c500', 'test-hash', '2025-01-01');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000c502', 'colibri', 1300, '2025-01-01');

-- Jornadas dentro de la ventana de la CTS de mayo (nov 2025 – abr 2026), para
-- que haya algo acumulado que descontar.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000c502', d::date, 8, 'cerrada'
from generate_series('2026-01-05'::date, '2026-01-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c509', true);

-- Lo que acumula SIN ningún desembolso. Todo lo demás se mide contra esto.
create temporary table _base on commit drop as
select ((e -> 'cts_may')::numeric) as cts_may,
       ((e -> 'cts_nov')::numeric) as cts_nov,
       ((e -> 'grati_s2')::numeric) as grati_s2
from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502';

select cmp_ok((select cts_may from _base), '>', 0::numeric,
  'DE PARTIDA · sin desembolsos, la persona acumula CTS de mayo');

-- ── 1 · Un depósito PARCIAL baja la provisión en ese monto exacto ───────────
-- El monto sale del PROPIO acumulado, no de un número escrito a mano. La
-- primera versión usaba S/50 fijos y el acumulado del fixture resultó ser
-- S/49,47: aquello no era un pago parcial sino un sobrepago, y la comprobación
-- pasaba midiendo algo distinto de lo que su nombre decía.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
select '00000000-0000-0000-0000-00000000c502', 'cts_may', 2026,
       round(cts_may / 2, 2), '2026-05-15', 'plame'
from _base;

select is(
  (select ((e -> 'cts_may')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502'),
  (select round(cts_may - round(cts_may / 2, 2), 2) from _base),
  'PARCIAL · la provisión baja exactamente lo depositado, no salta a cero');

select is(
  (select ((e ->> 'cts_may_pagada')::boolean)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502'),
  true,
  'PARCIAL · y consta que algo se pagó');

-- ── 2 · Sin arrastre: lo de mayo no toca noviembre ─────────────────────────
select is(
  (select ((e -> 'cts_nov')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502'),
  (select cts_nov from _base),
  'SIN ARRASTRE · un depósito de mayo no reduce la ventana de noviembre');

-- ── 3 · Un depósito por el TOTAL deja la provisión en cero ─────────────────
update desembolsos_beneficios set monto = (select cts_may from _base)
 where persona_id = '00000000-0000-0000-0000-00000000c502' and ventana = 'cts_may';

select is(
  (select ((e -> 'cts_may')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502'),
  0::numeric,
  'TOTAL · depositado todo, no queda nada por provisionar');

-- ── 4 · Si se depositó DE MÁS, el negativo se ve ───────────────────────────
update desembolsos_beneficios set monto = (select cts_may + 100 from _base)
 where persona_id = '00000000-0000-0000-0000-00000000c502' and ventana = 'cts_may';

select is(
  (select ((e -> 'cts_may')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502'),
  -100.00::numeric,
  'DE MÁS · el excedente sale en negativo, no se esconde en un cero');

-- ── 5 · Anotado en los DOS sitios, se descuenta UNA vez ────────────────────
-- Es el error caro: sumar las dos fuentes dejaría la provisión corta.
update desembolsos_beneficios
   set monto = (select round(cts_may / 2, 2) from _base)
 where persona_id = '00000000-0000-0000-0000-00000000c502' and ventana = 'cts_may';

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000c5aa', '2026-05-01', '2026-05-31', 'pagado');
insert into movimientos_planilla (periodo_id, persona_id, concepto, monto, categoria, tipo)
values ('00000000-0000-0000-0000-00000000c5aa', '00000000-0000-0000-0000-00000000c502',
        'CTS mayo', (select round(cts_may / 2, 2) from _base), 'cts', 'bono');

-- La planilla, cuando detecta el pago, asume el acumulado COMPLETO. Como es
-- mayor que la mitad que dice el libro, manda ella — y el resultado es cero, no
-- un descuento doble que dejaría la provisión en negativo.
select is(
  (select ((e -> 'cts_may')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502'),
  0::numeric,
  'DOS FUENTES · se descuenta una sola vez: manda la mayor, no la suma');

-- ── 6 · La gratificación no se tocó ────────────────────────────────────────
select is(
  (select ((e -> 'grati_s2')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c502'),
  (select grati_s2 from _base),
  'INTACTA · la gratificación sigue con su regla de siempre: no se tocó');

select * from finish();
rollback;
