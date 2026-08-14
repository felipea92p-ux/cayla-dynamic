-- ============================================================================
-- 183_un_locador_no_tiene_base_imponible.test.sql — migración 0242
-- ============================================================================
-- A un locador CAYLA no le retiene aporte previsional ni le paga asignación
-- familiar. Hasta la 0242 le hacía las dos cosas, y el monto de la primera lo
-- decidía un DEFAULT de columna.
--
-- POR QUÉ CUATRO LOCADORAS Y NO UNA. Los dos defectos entraban por caminos
-- distintos y una sola persona no los distingue:
--
--   · `sueldo_base_legal` con el DEFAULT 1130.00 (0103) le daba básica, y con
--     básica había retención — S/154.02 medidos. Con la columna en NULL, no.
--   · `con_hijos` le sumaba S/113 a la base aunque no tuviera básica — S/14.60.
--
--   Así que las cuatro combinaciones tienen que dar el MISMO resultado. Que sean
--   iguales entre sí es la propiedad que se blinda: el pago de un locador no
--   puede depender de esas dos columnas.
--
-- Y LO QUE NO DEBE MOVERSE, que es la mitad del valor de esta prueba: la
-- persona de planilla al lado. Apagarle el descuento a un locador y de paso
-- romperle la retención a quien sí aporta sería mucho peor que el defecto que
-- se vino a arreglar, y ninguna pantalla lo mostraría.
--
-- Sueldo 1200, abril 2026 del 1 al 28 sin domingos = 24 días de 8 h. Números
-- redondos y sin feriados en el rango, para que la aritmética se siga de cabeza.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000af', 'ZZLOC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000af99', 'LocAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000af', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000af98');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000af98', true);

-- Cuatro locadoras que varían SOLO en las dos columnas por las que entraba el
-- defecto, y una de planilla como testigo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      tipo_vinculo, regimen_pension, con_hijos, sueldo_base_legal) values
  ('00000000-0000-0000-0000-00000000af01', 'Loc', 'DefaultConHijos',
   '00000000-0000-0000-0000-0000000000af', 'test-hash', '2025-01-01', 'rxh', 'integra', true,  1130.00),
  ('00000000-0000-0000-0000-00000000af02', 'Loc', 'DefaultSinHijos',
   '00000000-0000-0000-0000-0000000000af', 'test-hash', '2025-01-01', 'rxh', 'integra', false, 1130.00),
  ('00000000-0000-0000-0000-00000000af03', 'Loc', 'NullConHijos',
   '00000000-0000-0000-0000-0000000000af', 'test-hash', '2025-01-01', 'rxh', 'integra', true,  null),
  ('00000000-0000-0000-0000-00000000af04', 'Loc', 'NullSinHijos',
   '00000000-0000-0000-0000-0000000000af', 'test-hash', '2025-01-01', 'rxh', 'integra', false, null),
  ('00000000-0000-0000-0000-00000000af05', 'Testigo', 'DePlanilla',
   '00000000-0000-0000-0000-0000000000af', 'test-hash', '2025-01-01', 'planilla', 'integra', true, 1130.00);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 1200, '2025-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000af'
  and id <> '00000000-0000-0000-0000-00000000af99';

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 8, 'cerrada'
from generate_series('2026-04-01'::date, '2026-04-28'::date, interval '1 day') d
cross join (select id from personas
             where sede_base_id = '00000000-0000-0000-0000-0000000000af'
               and id <> '00000000-0000-0000-0000-00000000af99') p
where extract(dow from d) <> 0;

create temp table _c on commit drop as
select (e->>'persona_id')::uuid                  as pid,
       (e->>'asignacion_familiar')::numeric      as asig,
       (e->>'descuento_afp')::numeric            as afp,
       (e->>'pago_base')::numeric                as pago_base,
       (e->>'aporte_essalud')::numeric           as essalud,
       (e->>'total')::numeric                    as total
from jsonb_array_elements(fn_planilla_calcular('2026-04-01', '2026-04-28') -> 'filas') e;

-- ── 1 · Ni un céntimo de retención previsional, en las cuatro ───────────────
select is(
  (select count(*) from _c c join personas p on p.id = c.pid
    where p.tipo_vinculo = 'rxh' and c.afp <> 0),
  0::bigint,
  'A ninguna locadora se le retiene aporte previsional, tenga o no sueldo_base_legal');

-- ── 2 · Ni asignación familiar (Ley 25129: es para trabajadores) ────────────
select is(
  (select count(*) from _c c join personas p on p.id = c.pid
    where p.tipo_vinculo = 'rxh' and c.asig <> 0),
  0::bigint,
  'A ninguna locadora se le paga asignacion familiar, ni con con_hijos en true');

-- ── 3 · El DEFAULT 1130 ya no decide nada ──────────────────────────────────
-- Era el defecto principal: con la columna puesta se retenian S/154.02 y con
-- ella en NULL, S/0. Ahora las dos tienen que dar lo mismo.
select is(
  (select total from _c where pid = '00000000-0000-0000-0000-00000000af02'),
  (select total from _c where pid = '00000000-0000-0000-0000-00000000af04'),
  'sueldo_base_legal en 1130 o en NULL da el mismo pago: el DEFAULT ya no decide');

-- ── 4 · Y `con_hijos` tampoco ──────────────────────────────────────────────
select is(
  (select total from _c where pid = '00000000-0000-0000-0000-00000000af03'),
  (select total from _c where pid = '00000000-0000-0000-0000-00000000af04'),
  'con_hijos en true o false da el mismo pago para una locadora');

-- ── 5 · Las cuatro cobran exactamente su pago por horas, y nada mas ────────
-- 1200 x 192 h / (6.5 x 28) = 1265.93. Si el total fuera distinto del pago
-- base, algun concepto laboral se le habria colado.
select is(
  (select count(distinct total) from _c c join personas p on p.id = c.pid
    where p.tipo_vinculo = 'rxh'),
  1::bigint,
  'Las cuatro locadoras cobran lo mismo: su pago por horas y nada mas');

select is(
  (select distinct total from _c c join personas p on p.id = c.pid
    where p.tipo_vinculo = 'rxh'),
  (select distinct pago_base from _c c join personas p on p.id = c.pid
    where p.tipo_vinculo = 'rxh'),
  'Y ese total ES el pago base: ni se le suma ni se le resta nada');

-- ── 6 · EL PAGO POR HORAS NO SE CONDICIONA — la 0085 y la 0117 ─────────────
-- Medir horas para saber cuanto pagar es medir un RESULTADO. Si esta migracion
-- hubiera apagado tambien el pago base, le habria dejado de pagar a tres
-- personas su trabajo.
select cmp_ok(
  (select distinct pago_base from _c c join personas p on p.id = c.pid
    where p.tipo_vinculo = 'rxh'),
  '>', 0::numeric,
  'A una locadora se le sigue pagando por horas: eso nunca se condiciona');

-- ── 7 · EL TESTIGO NO SE MUEVE — la mitad del valor de esta prueba ─────────
select is(
  (select afp from _c where pid = '00000000-0000-0000-0000-00000000af05'),
  195.73::numeric,
  'A quien SI aporta se le sigue retiniendo igual: el cambio no se contagia');

select is(
  (select asig from _c where pid = '00000000-0000-0000-0000-00000000af05'),
  113.00::numeric,
  'Y sigue cobrando su asignacion familiar: la Ley 25129 si le aplica');

select * from finish();
rollback;
