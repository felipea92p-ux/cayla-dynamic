-- ============================================================================
-- 176_la_educacion_se_paga_una_vez_y_a_tiempo.test.sql
-- ============================================================================
-- La regla que dejó la 0233: se cobran las asignaciones vigentes en el DÍA DE
-- REFERENCIA — el primer día del periodo en que la persona tiene alguna vigente.
--
-- Los dos casos que la obligan, los dos medidos antes de escribir la migración:
--
--   A · Danitza tiene su asignación desde el 1 de agosto y el periodo de agosto
--       empieza el 29 de JULIO. Con la regla vieja («vigente al iniciar») cobraba
--       S/0 — y así estaban las siete filas de la pantalla el 2026-08-12, todas
--       en cero sin que la boleta lo dijera. Ahora cobra.
--
--   B · Beatriz renueva a mitad de periodo: el ciclo I vence el 20/08 y el
--       ciclo II arranca el 21/08. Los dos se solapan con el periodo, así que el
--       arreglo fácil —cambiar `p_ini` por `p_fin`, que es lo que la 0150 dejó
--       anotado— le pagaría los DOS: S/180 por un mes de estudio. El día de
--       referencia cae en el ciclo I, y cobra uno.
--
--       No es un caso de laboratorio: en agosto de 2026 seis de las siete
--       asignaciones vivas vencían entre el 31/08 y el 15/09 y se renovaban al
--       día siguiente. Por eso está fijado acá.
--
-- Y las tres reglas de la 0150 que la 0233 NO toca, para que no se caigan de
-- lado al mover esto: dos cursos simultáneos suman, sin comprobante no se paga,
-- y un ciclo que termina a mitad cobra el mes completo. La 115 ya las prueba
-- contra un periodo de mes calendario; acá se repiten contra un periodo del 29
-- al 28, que es la forma real y la que destapó el defecto.
--
-- Todo en begin/rollback y en fechas de 2027, lejos de cualquier dato real.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000ed700', 'ZZED7', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000ed701', 'AdminEdu7', 'Laboratorio',
        '00000000-0000-0000-0000-0000000ed700', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000ed709', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ed709', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000ed7a1', 'EduDanitza', 'Laboratorio', '00000000-0000-0000-0000-0000000ed700', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ed7a2', 'EduBeatriz', 'Laboratorio', '00000000-0000-0000-0000-0000000ed700', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ed7a3', 'EduSimul',   'Laboratorio', '00000000-0000-0000-0000-0000000ed700', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ed7a4', 'EduCorto',   'Laboratorio', '00000000-0000-0000-0000-0000000ed700', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ed7a5', 'EduSinPapel','Laboratorio', '00000000-0000-0000-0000-0000000ed700', 'test-hash', '2020-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'aurora', 1500.00, '2020-01-01'
from unnest(array['00000000-0000-0000-0000-0000000ed7a1'::uuid,'00000000-0000-0000-0000-0000000ed7a2'::uuid,
                  '00000000-0000-0000-0000-0000000ed7a3'::uuid,'00000000-0000-0000-0000-0000000ed7a4'::uuid,
                  '00000000-0000-0000-0000-0000000ed7a5'::uuid]) p;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 6.5, 'cerrada'
from unnest(array['00000000-0000-0000-0000-0000000ed7a1'::uuid,'00000000-0000-0000-0000-0000000ed7a2'::uuid,
                  '00000000-0000-0000-0000-0000000ed7a3'::uuid,'00000000-0000-0000-0000-0000000ed7a4'::uuid,
                  '00000000-0000-0000-0000-0000000ed7a5'::uuid]) p,
     generate_series('2027-07-29'::date, '2027-09-28'::date, interval '1 day') d;

-- Se insertan directo y no por fn_educacion_registrar: acá se prueba cómo LEE
-- la planilla, no cómo escribe la pantalla. Eso lo cubre la prueba 114.
insert into asignaciones_educacion
  (persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   beneficiario_nombre, vigente_desde, vigente_hasta, comprobante_url) values
  -- A · registrada el día 1, con el periodo empezado el 29 del mes anterior
  ('00000000-0000-0000-0000-0000000ed7a1', 90.00, 'Florencia', 120, 75, 'trabajador', null,
   '2027-08-01', '2027-09-15', 'educacion/a/1.pdf'),
  -- B · renovación que corta dentro del periodo. Las dos vigencias NO se solapan
  --     entre sí, así que el candado del techo de la 0149 las deja convivir.
  ('00000000-0000-0000-0000-0000000ed7a2', 90.00, 'Ciclo I',  120, 75, 'trabajador', null,
   '2027-07-20', '2027-08-20', 'educacion/b/1.pdf'),
  ('00000000-0000-0000-0000-0000000ed7a2', 90.00, 'Ciclo II', 120, 75, 'trabajador', null,
   '2027-08-21', '2027-09-20', 'educacion/b/2.pdf'),
  -- C · dos cursos de verdad simultáneos
  ('00000000-0000-0000-0000-0000000ed7a3', 90.00, 'Diplomado', 120, 75, 'trabajador', null,
   '2027-01-01', '2027-12-31', 'educacion/c/1.pdf'),
  ('00000000-0000-0000-0000-0000000ed7a3', 60.00, 'Colegio',   80,  75, 'hijo', 'Hija de Simul',
   '2027-01-01', '2027-12-31', 'educacion/c/2.pdf'),
  -- D · ciclo que termina a los pocos días de empezar el periodo
  ('00000000-0000-0000-0000-0000000ed7a4', 90.00, 'Ciclo corto', 120, 75, 'trabajador', null,
   '2027-01-01', '2027-08-05', 'educacion/d/1.pdf'),
  -- E · sin comprobante, aunque la vigencia solape de sobra
  ('00000000-0000-0000-0000-0000000ed7a5', 90.00, 'Sin papel', 120, 75, 'trabajador', null,
   '2027-08-01', '2027-12-31', null);

-- El periodo REAL: del 29 al 28. Es la forma que destapó el defecto; con un mes
-- calendario ninguno de estos casos falla, y por eso la 115 no lo veía.
create temp table _ago as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2027-07-29'::date, '2027-08-28'::date) -> 'filas');


-- ── A · El caso que destapó todo ───────────────────────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a1'),
  90.00::numeric,
  'DIA 1 · vigente desde el 01/08 y el periodo abre el 29/07: cobra (antes daba S/0)');

select ok(
  (select (fila->>'instituciones_educacion') = 'Florencia' from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a1'),
  'DIA 1 · y la boleta puede nombrar de donde sale ese dinero');


-- ── B · Una renovación no se cobra dos veces ───────────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a2'),
  90.00::numeric,
  'RENOVACION · ciclo I hasta el 20/08 y ciclo II desde el 21/08: cobra S/90, no S/180');

select ok(
  (select (fila->>'instituciones_educacion') = 'Ciclo I' from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a2'),
  'RENOVACION · y el que cobra es el ciclo vivo al abrir el periodo, no el que entra despues');


-- ── C, D, E · Lo que la 0233 no toca ───────────────────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a3'),
  150.00::numeric,
  'SIMULTANEOS · dos cursos a la vez siguen sumando (regla de la 0150, intacta)');

select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a4'),
  90.00::numeric,
  'CICLO CORTO · termina el 05/08 y cobra el mes completo (regla de la 0150, intacta)');

select is(
  (select (fila->>'monto_educacion')::numeric from _ago
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a5'),
  0.00::numeric,
  'SIN PAPEL · solapa de sobra y aun asi no paga (regla de la 0150, intacta)');


-- ── Y el mes siguiente: el ciclo II cobra cuando le toca, una sola vez ─────
create temp table _sep as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2027-08-29'::date, '2027-09-28'::date) -> 'filas');

select is(
  (select (fila->>'monto_educacion')::numeric from _sep
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-0000000ed7a2'),
  90.00::numeric,
  'RENOVACION · en septiembre cobra el ciclo II, y tambien una sola vez');

select * from finish();
rollback;
