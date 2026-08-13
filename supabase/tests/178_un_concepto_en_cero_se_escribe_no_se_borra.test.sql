-- ============================================================================
-- 178_un_concepto_en_cero_se_escribe_no_se_borra.test.sql
-- ============================================================================
-- Los dos datos que la 0236 le da a la boleta para explicar un cero, y la
-- promesa de que no movieron ni un céntimo.
--
-- POR QUÉ EXISTEN. El 2026-08-12 siete integrantes cobraron S/0 de educación
-- teniendo su asignación vigente y su comprobante cargado. Lo arregló la 0233.
-- Lo que la 0233 no arregló es por qué estuvo un mes sin que nadie lo viera: la
-- boleta pintaba el concepto bajo `educacion > 0`, así que un monto en cero no
-- imprimía «S/0.00» — no imprimía nada. Un concepto que desaparece cuando falla
-- no se puede ni preguntar.
--
-- Los cuatro casos que fijan la regla:
--
--   · Paula cobra: registrada sí, sin comprobante no. La fila normal.
--   · Berta tiene la asignación pero el papel no llegó: cobra S/0 y la boleta
--     tiene que poder decir CUÁL de los dos ceros es.
--   · Nadia no estudia: `educacion_registrada` en false, y la boleta no dibuja
--     nada. Una línea en cero para quien no estudia sería ruido.
--   · Lucas es locador: aunque tenga la fila cargada, sale en false. A quien no
--     le corresponde un concepto laboral no se le explica por qué no lo cobra.
--
-- Y la última comprobación es la que importa de verdad: los montos salen
-- idénticos a los de la 176. Esta migración solo cuenta filas.
--
-- Todo en begin/rollback y en fechas de 2027, lejos de cualquier dato real.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000ce000', 'ZZCER', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000ce001', 'AdminCero', 'Laboratorio',
        '00000000-0000-0000-0000-0000000ce000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000ce009', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ce009', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000ce0a1', 'CeroPaula', 'Laboratorio', '00000000-0000-0000-0000-0000000ce000', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ce0a2', 'CeroBerta', 'Laboratorio', '00000000-0000-0000-0000-0000000ce000', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ce0a3', 'CeroNadia', 'Laboratorio', '00000000-0000-0000-0000-0000000ce000', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ce0a4', 'CeroLucas', 'Laboratorio', '00000000-0000-0000-0000-0000000ce000', 'test-hash', '2020-01-01', 'rxh');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'aurora', 1500.00, '2020-01-01'
from unnest(array['00000000-0000-0000-0000-0000000ce0a1'::uuid,'00000000-0000-0000-0000-0000000ce0a2'::uuid,
                  '00000000-0000-0000-0000-0000000ce0a3'::uuid,'00000000-0000-0000-0000-0000000ce0a4'::uuid]) p;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 6.5, 'cerrada'
from unnest(array['00000000-0000-0000-0000-0000000ce0a1'::uuid,'00000000-0000-0000-0000-0000000ce0a2'::uuid,
                  '00000000-0000-0000-0000-0000000ce0a3'::uuid,'00000000-0000-0000-0000-0000000ce0a4'::uuid]) p,
     generate_series('2027-07-29'::date, '2027-08-28'::date, interval '1 day') d;

insert into asignaciones_educacion
  (persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   beneficiario_nombre, vigente_desde, vigente_hasta, comprobante_url) values
  ('00000000-0000-0000-0000-0000000ce0a1', 90.00, 'Con papel', 120, 75, 'trabajador', null,
   '2027-08-01', '2027-09-15', 'educacion/p/1.pdf'),
  ('00000000-0000-0000-0000-0000000ce0a2', 90.00, 'Sin papel', 120, 75, 'trabajador', null,
   '2027-08-01', '2027-09-15', null),
  ('00000000-0000-0000-0000-0000000ce0a4', 90.00, 'Del locador', 120, 75, 'trabajador', null,
   '2027-08-01', '2027-09-15', 'educacion/l/1.pdf');

create temp table _ago as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2027-07-29'::date, '2027-08-28'::date) -> 'filas');


-- ── Paula · la fila normal ─────────────────────────────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a1'),
  90.00::numeric,
  'PAULA · cobra sus S/90, la 0236 no movio ningun monto');

select ok(
  (select (fila->>'educacion_registrada')::boolean from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a1'),
  'PAULA · educacion_registrada en true');

select ok(
  (select not (fila->>'educacion_sin_comprobante')::boolean from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a1'),
  'PAULA · y sin_comprobante en false: su papel esta cargado');


-- ── Berta · el cero que SÍ hay que explicar ────────────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a2'),
  0.00::numeric,
  'BERTA · cobra S/0 porque falta el comprobante (regla de la 0150, intacta)');

select ok(
  (select (fila->>'educacion_registrada')::boolean from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a2'),
  'BERTA · pero educacion_registrada en true: la boleta tiene que dibujar la fila');

select ok(
  (select (fila->>'educacion_sin_comprobante')::boolean from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a2'),
  'BERTA · y sin_comprobante en true: la boleta sabe CUAL de los dos ceros es');


-- ── Nadia · el cero que NO hay que explicar ────────────────────────────────
select ok(
  (select not (fila->>'educacion_registrada')::boolean from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a3'),
  'NADIA · no estudia, asi que la boleta no dibuja ninguna linea de educacion');


-- ── Lucas · a un locador no se le explica un concepto laboral ──────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a4'),
  0.00::numeric,
  'LOCADOR · sigue sin cobrar educacion (regla de la 0120, intacta)');

select ok(
  (select not (fila->>'educacion_registrada')::boolean from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ce0a4'),
  'LOCADOR · y tampoco se le explica: no le corresponde el concepto');


-- ── Que los campos existan siempre, tambien en quien no tiene nada ─────────
-- Si faltaran, la boleta leeria undefined y `?? false` la haria comportarse como
-- antes de la 0236 sin que nada fallara. Un campo ausente se lee igual que un
-- false, y por eso hay que exigirlo aca y no confiar en el valor.
select ok(
  (select bool_and(fila ? 'educacion_registrada' and fila ? 'educacion_sin_comprobante')
     from _ago),
  'TODAS · los dos campos vienen en cada fila, no solo en las que tienen asignacion');

select * from finish();
rollback;
