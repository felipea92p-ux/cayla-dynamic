-- ============================================================================
-- 191_la_boleta_sabe_quien_cobra_un_monto_fijo.test.sql — migración 0250
-- ============================================================================
-- La boleta no podía distinguir dos locadores que cobran de formas opuestas:
-- a los dos les ponía «Honorarios por las horas prestadas». En quien cobra un
-- monto fijo y no marca nunca eso imprimía «(0 h) …… S/ 652.17» — cero horas
-- junto a un monto, en el papel que se le entrega a alguien externo, y
-- describiendo el acuerdo al revés.
--
-- La 0250 hace UNA cosa: que `sueldo_fijo` viaje en el JSON. Por eso la mitad de
-- esta prueba comprueba el campo nuevo y la otra mitad comprueba que NO SE MOVIÓ
-- NADA — que es lo que de verdad hay que blindar cuando una migración reescribe
-- entera una función de 39 capas.
--
-- Los montos son los mismos que midió la auditoría de la 0250 antes de aplicarla:
-- si alguno cambia, esta migración movió dinero y no debía.
--
-- Honorario 652.17, CERO jornadas, periodo del 29-jul al 28-ago. Cero horas a
-- propósito: es el caso real que destapó el defecto.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000e5', 'ZZFIJ', 'Sede de laboratorio fijo', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000e599', 'AdmFijo', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000e5', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000e598');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e598', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      tipo_vinculo, sueldo_fijo, retencion_4ta) values
  ('00000000-0000-0000-0000-00000000e501', 'Loc', 'MontoFijo',
   '00000000-0000-0000-0000-0000000000e5', 'th', '2025-01-01', 'rxh', true,  'siempre'),
  ('00000000-0000-0000-0000-00000000e502', 'Loc', 'PorHoras',
   '00000000-0000-0000-0000-0000000000e5', 'th', '2025-01-01', 'rxh', false, 'siempre'),
  ('00000000-0000-0000-0000-00000000e503', 'Testigo', 'DePlanilla',
   '00000000-0000-0000-0000-0000000000e5', 'th', '2025-01-01', 'planilla', false, null);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 652.17, '2025-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000e5'
  and id <> '00000000-0000-0000-0000-00000000e599';

-- Ni una sola jornada, a propósito.

create temp table _f on commit drop as
select (e->>'persona_id')::uuid            as pid,
       (e->>'sueldo_fijo')::boolean        as fijo,
       (e->>'horas_mes')::numeric          as horas,
       (e->>'pago_base')::numeric          as pago_base,
       (e->>'retencion_4ta')::numeric      as ret,
       (e->>'total')::numeric              as total
from jsonb_array_elements(fn_planilla_calcular('2026-07-29', '2026-08-28') -> 'filas') e;

-- ── 1 · El campo nuevo viaja, y dice la verdad de cada quien ───────────────
select ok(
  (select fijo from _f where pid = '00000000-0000-0000-0000-00000000e501'),
  'A quien cobra un monto fijo, el JSON lo dice: la boleta ya puede etiquetarlo bien');

select ok(
  not (select fijo from _f where pid = '00000000-0000-0000-0000-00000000e502'),
  'Y a quien cobra por horas, tambien: son dos locadores y cobran al reves');

-- ── 2 · Nada se movio, que es lo que hay que blindar ───────────────────────
-- Los tres montos vienen de la medicion hecha ANTES de aplicar la 0250. Si esta
-- migracion hubiera tocado el calculo al reescribir la funcion entera, cambian.
select is(
  (select pago_base from _f where pid = '00000000-0000-0000-0000-00000000e501'),
  652.17::numeric,
  'Con sueldo fijo y cero horas se sigue pagando el mes completo: 652.17');

select is(
  (select pago_base from _f where pid = '00000000-0000-0000-0000-00000000e502'),
  0.00::numeric,
  'Y sin sueldo fijo, cero horas siguen siendo cero soles');

-- ── 3 · La retencion de la 0245 sigue viva ────────────────────────────────
-- Esta funcion se reescribe entera en cada migracion. La forma en que se pierde
-- una regla no es borrarla: es copiar el cuerpo de una version anterior. Si eso
-- pasara aqui, este numero seria 0 y ninguna pantalla lo mostraria.
select is(
  (select ret from _f where pid = '00000000-0000-0000-0000-00000000e501'),
  52.17::numeric,
  'La retencion de 4ta de la 0245 sigue calculandose: 8% de 652.17');

select is(
  (select total from _f where pid = '00000000-0000-0000-0000-00000000e501'),
  600.00::numeric,
  'Y el total sigue siendo el neto: 652.17 - 52.17');

-- ── 4 · El testigo de planilla ────────────────────────────────────────────
select ok(
  not (select fijo from _f where pid = '00000000-0000-0000-0000-00000000e503'),
  'A quien esta en planilla el campo le llega igual, y en false: nadie hereda nada');

select * from finish();
rollback;
