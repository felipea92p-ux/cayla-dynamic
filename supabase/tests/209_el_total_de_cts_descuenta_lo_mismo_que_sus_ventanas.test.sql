-- ============================================================================
-- 209_el_total_de_cts_descuenta_lo_mismo_que_sus_ventanas.test.sql
-- ============================================================================
-- El caso real que lo destapa: una fila de Provisiones mostraba CTS de mayo
-- "pagado" (un depósito directo, fuera de planilla, registrado en
-- `desembolsos_beneficios`), CTS de noviembre con un monto, y un `cts_total`
-- que no era la suma de lo que se veía arriba — porque `cts_total` nunca
-- restaba ese depósito, aunque `cts_may` sí lo hacía desde la 0158.
--
-- Esta prueba no afirma montos absolutos: mide que `cts_total` se mantenga
-- pegado a `cts_may + cts_nov`, con o sin depósito directo. Es la relación que
-- la 0271 restaura, y la que hace que el "Gran total" de la pantalla —que se
-- arma sumando esos tres campos en el cliente— vuelva a ser correcto.
--
-- La comparación tolera hasta 1 centavo: `cts_total` se redondea en UNA sola
-- pasada sobre la suma sin redondear de sus dos ventanas, mientras que
-- `cts_may` y `cts_nov` se redondean cada una por separado — redondear la
-- suma y sumar los redondeos no siempre coinciden en el último centavo, y esa
-- diferencia no es el bug que esta prueba persigue (que era de decenas de
-- soles: el devengado completo de una ventana, no un centavo de redondeo).
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000c600', 'ZZCTS', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c601', 'CtsAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c600', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000c609', '2025-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c602', 'CtsPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c600', 'test-hash', '2025-01-01');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000c602', 'colibri', 1300, '2025-01-01');

-- Jornadas dentro de las dos ventanas de CTS (nov 2025 – abr 2026 y may – oct
-- 2026), para que ambas acumulen algo que descontar.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000c602', d::date, 8, 'cerrada'
from generate_series('2026-01-05'::date, '2026-01-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000c602', d::date, 8, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-26'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c609', true);

-- ── 1 · Sin ningún desembolso, cts_total ya es cts_may + cts_nov ───────────
-- (Con la fórmula vieja esto también pasaba: la diferencia solo aparece con
-- un depósito directo. Sirve como línea de partida.)
select cmp_ok(
  abs((select ((e -> 'cts_total')::numeric)
         from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
        where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602')
    - (select ((e -> 'cts_may')::numeric) + ((e -> 'cts_nov')::numeric)
         from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
        where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602')),
  '<=', 0.01::numeric,
  'DE PARTIDA · sin desembolsos, el total ya es la suma de sus ventanas (±1 centavo de redondeo)');

-- ── 2 · Con un depósito directo PARCIAL de CTS-mayo, la relación se mantiene ─
-- Este es el caso que el bug rompía: `cts_may` bajaba con el depósito, pero
-- `cts_total` seguía contando el devengado completo de esa ventana.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
select '00000000-0000-0000-0000-00000000c602', 'cts_may', 2026,
       round(((e -> 'cts_may')::numeric) / 2, 2), '2026-05-15', 'plame'
from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602';

select cmp_ok(
  abs((select ((e -> 'cts_total')::numeric)
         from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
        where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602')
    - (select ((e -> 'cts_may')::numeric) + ((e -> 'cts_nov')::numeric)
         from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
        where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602')),
  '<=', 0.01::numeric,
  'DEPÓSITO PARCIAL · el total sigue siendo cts_may + cts_nov, no el devengado sin descontar (±1 centavo)');

-- ── 3 · Y también con CTS-noviembre depositada ──────────────────────────────
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
select '00000000-0000-0000-0000-00000000c602', 'cts_nov', 2026,
       round(((e -> 'cts_nov')::numeric) / 3, 2), '2026-11-15', 'plame'
from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602';

select cmp_ok(
  abs((select ((e -> 'cts_total')::numeric)
         from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
        where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602')
    - (select ((e -> 'cts_may')::numeric) + ((e -> 'cts_nov')::numeric)
         from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
        where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602')),
  '<=', 0.01::numeric,
  'DOS DEPÓSITOS · el total sigue cuadrando con la suma de sus dos ventanas (±1 centavo)');

-- ── 4 · El total es estrictamente menor que antes del bug (comprobación con
--        signo): no puede seguir contando lo ya depositado. ────────────────
select cmp_ok(
  (select ((e -> 'cts_total')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602'),
  '<',
  (select ((e -> 'cts_may')::numeric) + ((e -> 'cts_nov')::numeric)
     + (select sum(monto) from desembolsos_beneficios where persona_id = '00000000-0000-0000-0000-00000000c602')
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c602'),
  'SANIDAD · el total con depósitos es menor que si se sumaran de más (regresión del bug original)');

select * from finish();
rollback;
