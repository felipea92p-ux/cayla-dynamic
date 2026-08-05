-- ============================================================================
-- 115_la_planilla_suma_la_educacion.test.sql
-- ============================================================================
-- Los tres agujeros que la 0150 cierra, cada uno con su caso y su cifra. Los
-- tres se midieron contra el Postgres local antes de escribir la migración:
--
--   A · Ana estudia un diplomado (S/200/mes) y su hija va al colegio
--       (S/200/mes). Son dos filas de S/150. Antes cobraba S/150: la planilla
--       hacía `limit 1` y descartaba la otra sin decir nada. Ahora cobra S/300.
--
--   B · Beto tiene su asignación registrada pero el comprobante todavía no
--       llegó. Antes devengaba igual. Ahora cobra S/0 hasta que el papel esté
--       cargado — que es lo único que sostiene que esto no sea remuneración.
--
--   C · Carla termina su ciclo el 15 de junio. Antes cobraba S/0 ese mes,
--       habiendo estudiado y pagado la pensión de junio, porque la condición
--       exigía seguir vigente el ÚLTIMO día del periodo. Ahora cobra el mes
--       completo.
--
--   D · Delia se matricula el 10 de junio, con el periodo ya empezado. Cobra
--       S/0 en junio y empieza en julio. Es el borde que la regla «vigente al
--       iniciar» deja abierto A PROPÓSITO, y esta prueba lo fija para que no
--       cambie por accidente: si mañana se decide pagarlo, hay que venir acá.
--
-- Rango aurora en las cuatro: techo S/360, así que S/300 cabe y nada choca con
-- el candado de la 0149.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ef00', 'ZZEDP', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ef01', 'AdminEdu', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ef00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ef09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ef09', true);

delete from feriados where fecha between '2026-06-01' and '2026-06-30';

-- `en_planilla` es una columna generada desde `tipo_vinculo`: no se inserta,
-- se deriva. Por eso el locador de la última prueba se hace cambiando el vínculo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000efa1', 'EduAna',   'Laboratorio', '00000000-0000-0000-0000-00000000ef00', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000efa2', 'EduBeto',  'Laboratorio', '00000000-0000-0000-0000-00000000ef00', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000efa3', 'EduCarla', 'Laboratorio', '00000000-0000-0000-0000-00000000ef00', 'test-hash', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-00000000efa4', 'EduDelia', 'Laboratorio', '00000000-0000-0000-0000-00000000ef00', 'test-hash', '2020-01-01', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select p, 'aurora', 1500.00, '2020-01-01'
from unnest(array['00000000-0000-0000-0000-00000000efa1'::uuid,
                  '00000000-0000-0000-0000-00000000efa2'::uuid,
                  '00000000-0000-0000-0000-00000000efa3'::uuid,
                  '00000000-0000-0000-0000-00000000efa4'::uuid]) p;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 6.5, 'cerrada'
from unnest(array['00000000-0000-0000-0000-00000000efa1'::uuid,
                  '00000000-0000-0000-0000-00000000efa2'::uuid,
                  '00000000-0000-0000-0000-00000000efa3'::uuid,
                  '00000000-0000-0000-0000-00000000efa4'::uuid]) p,
     generate_series('2026-06-01'::date, '2026-06-30'::date, interval '1 day') d;

-- Se insertan directo y no por fn_educacion_registrar: acá se prueba cómo LEE
-- la planilla, no cómo escribe la pantalla. Eso lo cubre la prueba 114.
insert into asignaciones_educacion
  (persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   beneficiario_nombre, vigente_desde, vigente_hasta, comprobante_url) values
  -- A · dos vigentes, las dos con papel
  ('00000000-0000-0000-0000-00000000efa1', 150.00, 'Diplomado', 200, 75, 'trabajador', null,
   '2026-01-01', '2026-12-31', 'educacion/a/1.pdf'),
  ('00000000-0000-0000-0000-00000000efa1', 150.00, 'Colegio',   200, 75, 'hijo', 'Hija de Ana',
   '2026-01-01', '2026-12-31', 'educacion/a/2.pdf'),
  -- B · registrada, sin comprobante
  ('00000000-0000-0000-0000-00000000efa2', 150.00, 'Instituto sin papel', 200, 75, 'trabajador', null,
   '2026-01-01', '2026-12-31', null),
  -- C · el ciclo termina a mitad del periodo
  ('00000000-0000-0000-0000-00000000efa3', 150.00, 'Ciclo corto', 200, 75, 'trabajador', null,
   '2026-01-01', '2026-06-15', 'educacion/c/1.pdf'),
  -- D · se matricula con el periodo ya empezado
  ('00000000-0000-0000-0000-00000000efa4', 150.00, 'Matricula tardia', 200, 75, 'trabajador', null,
   '2026-06-10', '2026-12-31', 'educacion/d/1.pdf');


-- `fn_planilla_calcular` devuelve UN jsonb con el arreglo `filas` adentro, no una
-- tabla: se desarma con jsonb_array_elements, igual que en la prueba 20. Se
-- rearma en cada punto del guion porque el cálculo se rehace después de cada
-- cambio, y una foto vieja mentiría.
create temp table _jun as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date) -> 'filas');


-- ── A · Las dos se suman ────────────────────────────────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _jun
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa1'),
  300.00::numeric,
  'SUMA · Ana cobra S/300: las dos asignaciones, no la mas reciente');

select ok(
  (select (fila->>'instituciones_educacion') like '%Diplomado%'
      and (fila->>'instituciones_educacion') like '%Colegio%'
     from _jun where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa1'),
  'SUMA · y la boleta puede nombrar las dos instituciones de donde sale');


-- ── B · Sin papel no se paga ────────────────────────────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _jun
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa2'),
  0.00::numeric,
  'SIN PAPEL · Beto cobra S/0: la asignacion existe pero el comprobante no llego');


-- ── C · El ciclo que termina a mitad paga el mes completo ──────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _jun
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa3'),
  150.00::numeric,
  'CICLO CORTO · Carla termina el 15 y cobra el mes completo: ya pago esa pension');


-- ── D · El borde que se deja abierto a proposito ───────────────────────────
select is(
  (select (fila->>'monto_educacion')::numeric from _jun
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa4'),
  0.00::numeric,
  'MATRICULA TARDIA · Delia empieza el 10 y NO cobra junio (regla: vigente al iniciar)');


-- ── Julio: la vigencia manda en los dos sentidos ───────────────────────────
create temp table _jul as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-07-01'::date, '2026-07-31'::date) -> 'filas');

select is(
  (select (fila->>'monto_educacion')::numeric from _jul
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa3'),
  0.00::numeric,
  'CICLO CORTO · pero en julio ya no: la vigencia termino y no se arrastra');

select is(
  (select (fila->>'monto_educacion')::numeric from _jul
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa4'),
  150.00::numeric,
  'MATRICULA TARDIA · y empieza a cobrar en julio, el primer periodo que la encuentra vigente');


-- ── El candado no es un rechazo permanente: llega el papel y paga ──────────
update asignaciones_educacion set comprobante_url = 'educacion/b/1.pdf'
 where persona_id = '00000000-0000-0000-0000-00000000efa2';

create temp table _jun2 as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date) -> 'filas');

select is(
  (select (fila->>'monto_educacion')::numeric from _jun2
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa2'),
  150.00::numeric,
  'SIN PAPEL · subido el comprobante, la misma fila ya paga S/150');


-- ── Y un locador sigue sin cobrarla ────────────────────────────────────────
update personas set tipo_vinculo = 'rxh' where id = '00000000-0000-0000-0000-00000000efa1';

create temp table _jun3 as
  select value as fila
  from jsonb_array_elements(fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date) -> 'filas');

select is(
  (select (fila->>'monto_educacion')::numeric from _jun3
    where (fila->>'persona_id')::uuid = '00000000-0000-0000-0000-00000000efa1'),
  0.00::numeric,
  'LOCADOR · quien no esta en planilla no cobra educacion, sumar no rompio eso');

select * from finish();
rollback;
