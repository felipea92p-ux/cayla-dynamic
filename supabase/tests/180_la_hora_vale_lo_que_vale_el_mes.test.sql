-- ============================================================================
-- 180_la_hora_vale_lo_que_vale_el_mes.test.sql
-- ============================================================================
-- Lo que vigila: que el divisor del pago por horas salga de la longitud del
-- PERIODO y no de la del rango que se consulta.
--
-- El 2026-08-13 una liquidación por cese pagó casi el doble del sueldo del
-- periodo. `fn_planilla_calcular` hacía `v_dias := (p_fin - p_ini) + 1`, y
-- `fn_liquidacion` es el único llamador que le pasa un rango corto —del inicio
-- del periodo a la fecha de cese—, así que la hora se encarecía justo ahí.
--
-- La prueba 130 no podía cazarlo: compara la liquidación contra la planilla
-- **del mismo rango parcial**, o sea las dos con el mismo divisor. Por eso este
-- archivo compara contra el PERIODO ENTERO, que es la referencia buena.
--
-- Cesar a mitad de mes tiene que bajar las HORAS, no subir el precio de la
-- hora. Si alguien vuelve a atar el divisor al rango, aquí se entera.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000b400', 'ZZDIV', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000b401', 'AdminDiv', 'Laboratorio',
        '00000000-0000-0000-0000-00000000b400', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000b409', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b409', true);

delete from feriados where fecha between '2026-06-01' and '2026-06-30';

-- Mismo montaje que la 130, para que las dos hablen del mismo caso: sueldo de
-- S/1,500, periodo de 30 días, trabaja la primera mitad y cesa el día 15.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000b4a1', 'DivAna', 'Laboratorio',
        '00000000-0000-0000-0000-00000000b400', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000b4a1', 'cayla', 1500.00, '2024-01-02');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000b4aa', '2026-06-01', '2026-06-30', 'abierto');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000b4a1', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;

update personas set estado = 'inactivo', fecha_cese = '2026-06-15'
 where id = '00000000-0000-0000-0000-00000000b4a1';


-- ── El divisor ─────────────────────────────────────────────────────────────
select is(
  (fn_planilla_calcular('2026-06-01', '2026-06-15',
     '00000000-0000-0000-0000-00000000b4aa') ->> 'dias')::int,
  30,
  'DIVISOR · un rango parcial divide por los 30 días del periodo, no por sus 15');

select is(
  (fn_planilla_calcular('2026-06-01', '2026-06-15',
     '00000000-0000-0000-0000-00000000b4aa') ->> 'base_horas')::numeric,
  195.0,
  'DIVISOR · y por tanto la base de horas es 6,5 × 30, no 6,5 × 15');


-- ── El importe ─────────────────────────────────────────────────────────────
-- No tiene marcas después del día 15, así que el rango del cese y el periodo
-- entero recogen exactamente las mismas horas. Si dan distinto, lo que cambió
-- fue el precio de la hora, que es justo lo que no puede pasar.
select is(
  (select round((value->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-06-01', '2026-06-15',
              '00000000-0000-0000-0000-00000000b4aa') -> 'filas') as t(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000b4a1'),
  (select round((value->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-06-01', '2026-06-30',
              '00000000-0000-0000-0000-00000000b4aa') -> 'filas') as t(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000b4a1'),
  'IMPORTE · sin marcas posteriores al cese, el rango parcial paga lo mismo que el periodo');

-- 97,5 h × 1500 ÷ (6,5 × 30) = 750,00. El número a mano, para que la prueba no
-- se limite a comparar la función consigo misma.
select is(
  (select round((value->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-06-01', '2026-06-15',
              '00000000-0000-0000-0000-00000000b4aa') -> 'filas') as t(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000b4a1'),
  750.00::numeric,
  'IMPORTE · y ese pago es 97,5 h × 1500 ÷ (6,5 × 30) = 750,00');


-- ── La excepción, que es deliberada ────────────────────────────────────────
-- `fn_simular_planilla` pasa `null` como periodo porque simula un rango libre
-- que no es el trozo de ningún periodo. Ahí el divisor sigue siendo el del
-- rango, y tiene que seguir siéndolo: si alguien "arregla" también este caso,
-- la simulación empezaría a mentir sobre rangos que no son de nadie.
select is(
  (fn_simular_planilla('2026-06-01', '2026-06-15') ->> 'dias')::int,
  15,
  'SIMULACIÓN · un rango libre sin periodo declarado sigue dividiendo por sus propios días');

select * from finish();
rollback;
