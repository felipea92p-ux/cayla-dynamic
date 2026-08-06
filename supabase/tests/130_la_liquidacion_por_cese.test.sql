-- ============================================================================
-- 130_la_liquidacion_por_cese.test.sql
-- ============================================================================
-- La ley da 48 horas desde el cese para pagar (art. 4 del D.S. 001-97-TR). Lo
-- que este archivo vigila no es que la suma dé bien —eso lo cubren la 103 y la
-- 128— sino que la liquidación NO invente su propia versión de las cuentas que
-- la planilla ya sabe hacer:
--
--   · el sueldo pendiente tiene que ser exactamente lo que la planilla calcula
--     para ese rango parcial, al céntimo. Si un día divergen, la liquidación y
--     la boleta dirán cosas distintas sobre la misma persona y el mismo mes;
--   · las truncas tienen que ser las mismas que devuelven sus funciones;
--   · y el total, la suma de las cuatro. Ni un redondeo propio.
--
-- Más el reloj, que es lo que hoy no existe en ningún sitio: cuántas horas
-- quedan, y si ya se pasaron.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ce00', 'ZZLIQ', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ce01', 'AdminLiq', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ce00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ce09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ce09', true);

delete from feriados where fecha between '2026-06-01' and '2026-06-30';

-- Una persona con dos años y medio de casa, que cesa a mitad del periodo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000cea1', 'LiqAna', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ce00', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000cea1', 'cayla', 1500.00, '2024-01-02');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000ceaa', '2026-06-01', '2026-06-30', 'abierto');

-- Trabajó del 1 al 15 y cesa el 15.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000cea1', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;

update personas set estado = 'inactivo', fecha_cese = '2026-06-15'
 where id = '00000000-0000-0000-0000-00000000cea1';


-- ── No inventa cuentas propias ─────────────────────────────────────────────
-- Cada cifra tiene que salir de la función que ya la calcula, al céntimo.
create temp table _liq as
  select fn_liquidacion('00000000-0000-0000-0000-00000000cea1', '2026-06-15') as l;

select is(
  (select (l->'periodo'->>'monto')::numeric from _liq),
  (select round((value->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-06-01', '2026-06-15',
              '00000000-0000-0000-0000-00000000ceaa') -> 'filas') as t(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000cea1'),
  'SUELDO · el pendiente es EXACTAMENTE lo que calcula la planilla para ese rango');

select is(
  (select (l->'vacaciones_truncas'->>'monto')::numeric from _liq),
  (fn_vacaciones_truncas('00000000-0000-0000-0000-00000000cea1', '2026-06-15')->>'monto')::numeric,
  'TRUNCAS · las vacaciones son las que devuelve su función, sin recalcular');

select is(
  (select (l->'gratificacion_trunca'->>'monto')::numeric from _liq),
  (fn_grati_trunca('00000000-0000-0000-0000-00000000cea1', '2026-06-15')->>'monto')::numeric,
  'TRUNCAS · y la gratificación también');

select is(
  (select (l->'cts_trunca'->>'monto')::numeric from _liq),
  (fn_cts_trunca('00000000-0000-0000-0000-00000000cea1', '2026-06-15')->>'monto')::numeric,
  'TRUNCAS · y la CTS');

select is(
  (select (l->>'total')::numeric from _liq),
  (select round(
     (l->'periodo'->>'monto')::numeric
   + (l->'vacaciones_truncas'->>'monto')::numeric
   + (l->'gratificacion_trunca'->>'monto')::numeric
   + (l->'cts_trunca'->>'monto')::numeric, 2) from _liq),
  'TOTAL · es la suma de las cuatro líneas, sin redondeo propio de por medio');


-- ── El reloj de las 48 horas ───────────────────────────────────────────────
select is(
  (select (l->>'vence_el')::date from _liq),
  '2026-06-17'::date,
  'PLAZO · vence a las 48 horas del cese, no del día en que alguien se acuerda');

select ok(
  (select (l->>'vencido')::boolean from _liq),
  'PLAZO · un cese de junio de 2026 ya está vencido hoy, y el sistema lo dice');


-- ── Los bordes que no se pueden calcular en silencio ───────────────────────
select throws_like(
  $$ select fn_liquidacion('00000000-0000-0000-0000-00000000ce01', null) $$,
  '%no tiene fecha de cese%',
  'SIN CESE · liquidar a alguien que no ha cesado se rechaza, no devuelve cero');

-- Un cese fuera de todo periodo cargado no puede inventar un sueldo pendiente:
-- se dice que falta el dato, que no es lo mismo que decir que es cero.
update personas set fecha_cese = '2029-03-10'
 where id = '00000000-0000-0000-0000-00000000cea1';

select is(
  (fn_liquidacion('00000000-0000-0000-0000-00000000cea1', '2029-03-10')->'periodo')::text,
  'null',
  'SIN PERIODO · si el cese cae fuera de todo periodo cargado, no se inventa uno');

select ok(
  (fn_liquidacion('00000000-0000-0000-0000-00000000cea1', '2029-03-10')->>'aviso_periodo') like '%no se pudo calcular%',
  'SIN PERIODO · y lo dice: un dato que falta no es un cero');


-- ── El guard, dentro y no cerca ────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999999', true);
select throws_like(
  $$ select fn_liquidacion('00000000-0000-0000-0000-00000000cea1', '2026-06-15') $$,
  '%administrador o líder%',
  'PERMISO · una sesión sin fila en personas no obtiene la liquidación de nadie');

select * from finish();
rollback;
