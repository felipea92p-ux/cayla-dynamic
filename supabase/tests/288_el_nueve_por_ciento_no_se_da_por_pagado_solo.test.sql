-- ============================================================================
-- 288_el_nueve_por_ciento_no_se_da_por_pagado_solo.test.sql
-- ============================================================================
-- El caso real, medido contra el Postgres local el 2026-09-04:
--
--   Una persona con S/585.51 de gratificación devengada del primer semestre
--   tenía S/52.70 pendientes del 9% de la Ley 30334. Al registrar SOLO el
--   movimiento de «Gratificación» —el camino manual que la 0346 habilitó, sin
--   agregar el 9% aparte— la pantalla de Provisiones pasaba a decir S/0.00
--   pendientes de bonificación extraordinaria. Se le debían S/52.70 y ninguna
--   pantalla volvía a mencionarlos.
--
--   Hasta la 0346 eso era correcto por convención: el 9% viajaba DENTRO del
--   monto de «Gratificación», así que gratificación pagada ⇒ 9% pagado. La 0346
--   separó los dos movimientos a propósito (lo pidió el contador) y nadie
--   actualizó `fn_provisiones`.
--
-- CÓMO ESTÁ ESCRITO ESTE ARCHIVO
--   No afirma montos absolutos: primero LEE lo que la persona tiene pendiente
--   sin registrar nada, y después comprueba qué le hace a ese número cada forma
--   de pagar. Así la prueba mide la regla que la 0362 cambió —cuándo el 9% se
--   da por saldado— y no la fórmula del devengado, que es de otra migración.
--
-- LAS CINCO REGLAS QUE DEFIENDE, y que se rompen por separado:
--   1. registrar solo la gratificación NO salda el 9%          (el defecto)
--   2. registrar los dos movimientos SÍ lo salda               (el camino feliz)
--   3. una gratificación anterior al 2026-09-03 lo salda igual (no se reclama
--      hacia atrás: decisión de Felipe del 2026-09-03)
--   4. el libro de desembolsos sigue bajándolo en proporción   (lo conservado)
--   5. el total de la columna es la suma de sus dos ventanas
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000be90', 'ZZBE9', 'Sede laboratorio 9%', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000be91', 'BeAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000be90', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000be99', '2025-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000be92', 'BePersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000be90', 'test-hash', '2025-01-01');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000be92', 'colibri', 1300, '2025-01-01');

-- Jornadas del primer semestre de 2026: es lo que devenga la grati_s1, que se
-- paga el 15/07/2026.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000be92', d::date, 8, 'cerrada'
from generate_series('2026-02-02'::date, '2026-06-26'::date, interval '1 day') d
where extract(dow from d) <> 0;

-- El periodo que contiene el 15/07/2026, que es donde la función busca el pago.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000be9a', '2026-06-29', '2026-07-28', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000be99', true);

-- ── Lo que se debe SIN registrar nada. Todo lo demás se mide contra esto. ──
create temporary table _base on commit drop as
select round((e->'grati_s1')::numeric, 2) as grati_s1,
       round((e->'be_s1')::numeric, 2)    as be_s1,
       round((e->'tasa_be')::numeric, 4)  as tasa
from jsonb_array_elements(fn_provisiones('2026-09-04')->'personas') e
where e->>'persona_id' = '00000000-0000-0000-0000-00000000be92';

select cmp_ok((select be_s1 from _base), '>', 0::numeric,
  'PUNTO DE PARTIDA · sin registrar nada, el 9% del primer semestre está pendiente');

select ok(
  (select abs(be_s1 - round(grati_s1 * tasa, 2)) <= 0.01 from _base),
  'PUNTO DE PARTIDA · y vale el 9% de la gratificación devengada');

-- ── 1. EL DEFECTO · registrar SOLO la gratificación no salda el 9% ──────────
select fn_agregar_movimiento(
  '00000000-0000-0000-0000-00000000be9a', '00000000-0000-0000-0000-00000000be92',
  'bono', 'Gratificación Fiestas Patrias 2026', 250.00, 'gratificacion');

create temporary table _solo_grati on commit drop as
select round((e->'grati_s1')::numeric, 2) as grati_s1,
       round((e->'be_s1')::numeric, 2)    as be_s1
from jsonb_array_elements(fn_provisiones('2026-09-04')->'personas') e
where e->>'persona_id' = '00000000-0000-0000-0000-00000000be92';

select is((select grati_s1 from _solo_grati), 0.00::numeric,
  'LA CONVENCIÓN DE LA 0158 SIGUE · la planilla, al ver el pago, da la gratificación por saldada');

select is(
  (select be_s1 from _solo_grati), (select be_s1 from _base),
  'EL DEFECTO ARREGLADO · registrar solo «Gratificación» ya NO da por pagado el 9%');

-- ── 2. EL CAMINO FELIZ · registrar también el 9% sí lo salda ────────────────
select fn_agregar_movimiento(
  '00000000-0000-0000-0000-00000000be9a', '00000000-0000-0000-0000-00000000be92',
  'bono', 'Bonificación extraordinaria 9% (Ley 30334) — Fiestas Patrias 2026',
  22.50, 'bonificacion_extraordinaria');

select is(
  (select round((e->'be_s1')::numeric, 2)
     from jsonb_array_elements(fn_provisiones('2026-09-04')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-00000000be92'),
  0.00::numeric,
  'EL CAMINO FELIZ · con su movimiento propio registrado, el 9% queda saldado');

-- ── 3. NO SE RECLAMA HACIA ATRÁS ───────────────────────────────────────────
-- Se quitan los dos movimientos y se deja solo una gratificación registrada
-- ANTES del 2026-09-03, que es cuando el 9% todavía viajaba dentro de su monto.
delete from movimientos_planilla
 where persona_id = '00000000-0000-0000-0000-00000000be92';

insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria, created_at)
values ('00000000-0000-0000-0000-00000000be9a', '00000000-0000-0000-0000-00000000be92',
        'bono', 'Gratificación Fiestas Patrias 2026 (pagada a la antigua)', 250.00,
        'gratificacion', '2026-08-15 10:00:00-05');

select is(
  (select round((e->'be_s1')::numeric, 2)
     from jsonb_array_elements(fn_provisiones('2026-09-04')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-00000000be92'),
  0.00::numeric,
  'NO SE RECLAMA HACIA ATRÁS · una gratificación anterior al 2026-09-03 lleva el 9% dentro');

-- ── 4. EL LIBRO SIGUE BAJÁNDOLO EN PROPORCIÓN ──────────────────────────────
-- Sin ningún movimiento de planilla, un depósito anotado en el libro por la
-- MITAD de la gratificación devengada deja pendiente la mitad del 9%. Es el
-- comportamiento que ya existía y que esta migración conserva.
delete from movimientos_planilla
 where persona_id = '00000000-0000-0000-0000-00000000be92';

insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
select '00000000-0000-0000-0000-00000000be92', 'grati_s1', 2026,
       round(grati_s1 / 2, 2), '2026-07-15', 'transferencia'
from _base;

select ok(
  (select abs(
     (select round((e->'be_s1')::numeric, 2)
        from jsonb_array_elements(fn_provisiones('2026-09-04')->'personas') e
       where e->>'persona_id' = '00000000-0000-0000-0000-00000000be92')
     - round((select be_s1 from _base) / 2, 2)) <= 0.02),
  'EL LIBRO SE CONSERVA · medio depósito anotado deja pendiente medio 9%');

-- ── 5. EL TOTAL ES LA SUMA DE SUS DOS VENTANAS ─────────────────────────────
select ok(
  (select abs(((e->'be_total')::numeric)
            - (((e->'be_s1')::numeric) + ((e->'be_s2')::numeric))) <= 0.01
     from jsonb_array_elements(fn_provisiones('2026-09-04')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-00000000be92'),
  'EL TOTAL CUADRA · be_total es exactamente be_s1 + be_s2');

-- Y el gran total sigue sumando las cuatro columnas que la pantalla muestra.
select ok(
  (select abs(((e->'gran_total')::numeric)
            - (((e->'grati_total')::numeric) + ((e->'be_total')::numeric)
             + ((e->'cts_total')::numeric)  + ((e->'vac')::numeric))) <= 0.01
     from jsonb_array_elements(fn_provisiones('2026-09-04')->'personas') e
    where e->>'persona_id' = '00000000-0000-0000-0000-00000000be92'),
  'EL GRAN TOTAL CUADRA · sigue siendo la suma de las cuatro columnas visibles');

select * from finish();
rollback;
