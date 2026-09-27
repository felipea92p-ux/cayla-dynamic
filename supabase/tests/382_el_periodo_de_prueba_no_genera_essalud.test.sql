-- ============================================================================
-- 382_el_periodo_de_prueba_no_genera_essalud.test.sql — migración 0484
-- ============================================================================
-- Hasta la 0484, `tipo_vinculo = 'prueba'` generaba EsSalud igual que
-- `'planilla'` (la condición era `pe.en_planilla`, que agrupa a los dos).
-- Alguien que ingresó y cesó DENTRO del mismo periodo de prueba —sin llegar
-- a trabajar más que unos días, o ni una hora— generaba igual el piso
-- completo de la RMV: S/101,70, sin prorratear.
--
-- Caso real que lo disparó (cierre «Prueba» del 29/08–27/09/2026): 6 personas
-- con ingreso y cese dentro del mismo periodo, S/610,20 de EsSalud en total,
-- una de ellas (Angie, acá "CeroHoras") sin una sola hora marcada.
--
-- POR QUÉ TRES PERSONAS Y NO UNA. Dos casos de prueba —CON horas reales
-- (como Geison, 32 h en 4 días) y SIN ninguna (como Angie, ingreso=cese el
-- mismo día)— porque las dos debían dar cero, y un solo caso no separa "se
-- excluyó tipo_vinculo" de "se excluyó por horas". Y un TESTIGO de planilla
-- con el periodo completo trabajado, que es la mitad del valor de esta
-- prueba: apagarle EsSalud a 'prueba' y de paso apagárselo a 'planilla' sería
-- mucho peor que el defecto que se vino a arreglar.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000e5', 'ZZE5', 'Sede de laboratorio essalud', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000e599', 'AuditAdmin', 'Essalud',
        '00000000-0000-0000-0000-0000000000e5', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000e598');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e598', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, fecha_cese,
                      tipo_vinculo, con_hijos, sueldo_base_legal, estado) values
  ('00000000-0000-0000-0000-00000000e501', 'Prueba', 'ConHoras',
   '00000000-0000-0000-0000-0000000000e5', 'test-hash', '2026-09-03', '2026-09-27', 'prueba', false, 1130.00, 'inactivo'),
  ('00000000-0000-0000-0000-00000000e502', 'Prueba', 'CeroHoras',
   '00000000-0000-0000-0000-0000000000e5', 'test-hash', '2026-09-24', '2026-09-24', 'prueba', false, 1130.00, 'inactivo'),
  ('00000000-0000-0000-0000-00000000e503', 'Testigo', 'DePlanilla',
   '00000000-0000-0000-0000-0000000000e5', 'test-hash', '2026-01-01', null, 'planilla', false, 1130.00, 'activo');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values
  ('00000000-0000-0000-0000-00000000e501', 'colibri', 1130, '2026-09-03'),
  ('00000000-0000-0000-0000-00000000e502', 'colibri', 1130, '2026-09-24'),
  ('00000000-0000-0000-0000-00000000e503', 'colibri', 1130, '2026-01-01');

-- La de "prueba" con horas: 4 días de 8 h, como Geison en el caso real.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000e501', d::date, 8, 'cerrada'
from generate_series('2026-09-03'::date, '2026-09-06'::date, interval '1 day') d;

-- El testigo de planilla trabaja el periodo entero, para que el piso SI se
-- le siga aplicando (o su base real, según toque) sin que nada lo mueva.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000000e503', d::date, 8, 'cerrada'
from generate_series('2026-08-29'::date, '2026-09-27'::date, interval '1 day') d;

create temp table _c on commit drop as
select (e->>'persona_id')::uuid                  as pid,
       (e->>'aporte_essalud')::numeric           as essalud
from jsonb_array_elements(
       fn_planilla_calcular_nucleo('2026-08-29', '2026-09-27') -> 'filas'
     ) e
where (e->>'persona_id')::uuid in (
  '00000000-0000-0000-0000-00000000e501',
  '00000000-0000-0000-0000-00000000e502',
  '00000000-0000-0000-0000-00000000e503'
);

-- ── 1 · Prueba CON horas reales: cero EsSalud ───────────────────────────────
select is(
  (select essalud from _c where pid = '00000000-0000-0000-0000-00000000e501'),
  0::numeric,
  'Quien está en período de prueba ya no genera EsSalud, aunque haya trabajado días reales');

-- ── 2 · Prueba SIN ninguna hora: también cero (ya lo era, y sigue siéndolo) ─
select is(
  (select essalud from _c where pid = '00000000-0000-0000-0000-00000000e502'),
  0::numeric,
  'Y tampoco quien ingresó y cesó el mismo día sin marcar una sola hora');

-- ── 3 · El testigo de planilla NO se mueve — la mitad del valor de esta prueba
select isnt(
  (select essalud from _c where pid = '00000000-0000-0000-0000-00000000e503'),
  0::numeric,
  'A quien SI está en planilla se le sigue calculando EsSalud: el cambio no se contagia');

select cmp_ok(
  (select essalud from _c where pid = '00000000-0000-0000-0000-00000000e503'),
  '>=', 101.70::numeric,
  'Y nunca por debajo del piso legal de la RMV, que sigue vigente para planilla');

-- ── 4 · Las tres existen en el cálculo (nadie desapareció de la planilla) ───
select is(
  (select count(*) from _c)::int,
  3,
  'Las tres personas del caso siguen apareciendo en el cálculo del periodo');

select * from finish();
rollback;
