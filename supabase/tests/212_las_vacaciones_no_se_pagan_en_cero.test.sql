-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 212_las_vacaciones_no_se_pagan_en_cero.test.sql
-- ============================================================================
-- Quien pasaba de vacaciones un periodo entero cobraba S/0.00. Un día de
-- vacaciones vale `hh.pago / dias_marcados` —el promedio de lo que se le pagó
-- por día trabajado, que es literal el art. 15 del D. Leg. 713—; sin ningún día
-- marcado ese cociente es 0/0 y el mes salía en cero, sin que nada avisara.
--
-- No es el caso raro: las vacaciones peruanas son 30 días CALENDARIO y el
-- periodo tiene 31. Basta tomarlas completas, que es lo que la ley manda.
--
-- La 0254 ya había resuelto exactamente esto para el descanso médico y la 0262
-- para la maternidad. La 0275 le da a las vacaciones la MISMA tarifa de
-- respaldo, y esta prueba fija las dos mitades: que el caso roto se arregle, y
-- —más importante— que a quien SÍ marcó días no se le mueva un céntimo.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000007b1', 'ZZVC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000007b2', 'VcAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000007b1', 'admin', 'x',
        '00000000-0000-0000-0000-0000000007ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo) values
  ('00000000-0000-0000-0000-0000000007b3', 'VcTodoElMes', 'Lab', '00000000-0000-0000-0000-0000000007b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000007b4', 'VcParcial',   'Lab', '00000000-0000-0000-0000-0000000007b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000007b5', 'VcControl',   'Lab', '00000000-0000-0000-0000-0000000007b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
  ('00000000-0000-0000-0000-0000000007b6', 'VcFija',      'Lab', '00000000-0000-0000-0000-0000000007b1', 'x', '2024-01-01', 'taller_produccion', 'planilla', true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1185, '2024-01-01' from personas
 where apellidos = 'Lab' and nombres like 'Vc%' and nombres <> 'VcAdmin';

-- Lunes a viernes. El sábado y el domingo NO son laborables: los días de
-- vacaciones que caen ahí no se pagan, y eso lo fija la prueba 2.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5], 32.5
from personas where apellidos = 'Lab' and nombres like 'Vc%' and nombres <> 'VcAdmin';

-- El feriado que cae dentro de las vacaciones: es lo que hace medible la
-- prueba 5. `horas_vacaciones` no sale en el JSON —es interna— y lo único que
-- la delata desde fuera es el prorrateo del feriado que la consume.
insert into feriados (fecha, nombre) values ('2026-07-29', 'Fiestas Patrias')
on conflict do nothing;

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-0000000007b3', 'vacaciones', '2026-07-29', '2026-08-28', 'lab', '00000000-0000-0000-0000-0000000007b2'),
  ('00000000-0000-0000-0000-0000000007b4', 'vacaciones', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-0000000007b2'),
  ('00000000-0000-0000-0000-0000000007b6', 'vacaciones', '2026-08-10', '2026-08-14', 'lab', '00000000-0000-0000-0000-0000000007b2');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000007ff', true);

-- VcParcial y VcControl trabajan exactamente los mismos tres días. La única
-- diferencia entre ellas es que VcParcial además tiene una semana de vacaciones.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000007b1', m.tipo, m.ts
from personas p,
     (values ('entrada'::tipo_marca,      timestamptz '2026-08-03T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-03T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-04T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-04T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-05T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-05T15:30:00-05:00')) m(tipo, ts)
where p.id in ('00000000-0000-0000-0000-0000000007b4', '00000000-0000-0000-0000-0000000007b5',
               '00000000-0000-0000-0000-0000000007b6');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-0000000007e1', '2026-07-29', '2026-08-28', 'abierto');

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- 1 · EL DEFECTO. Sin la tarifa de respaldo esto era exactamente 0.00, y la
--     boleta lo imprimía como si le tocara cero.
select cmp_ok(
  (pg_temp.fila('VcTodoElMes Lab')->>'monto_vacaciones')::numeric, '>', 0::numeric,
  'quien pasa el periodo entero de vacaciones cobra su mes, no S/0.00');

-- 2 · Y cobra la tarifa de CONTRATO: salario entre sus días laborables, por los
--     días de vacaciones que le tocaba trabajar. Ni el sábado ni el domingo
--     entran. Con 22 días laborables de lunes a viernes en el periodo, los 22
--     días valen el salario entero.
select cmp_ok(
  abs((pg_temp.fila('VcTodoElMes Lab')->>'monto_vacaciones')::numeric - 1185::numeric),
  '<', 0.02::numeric,
  'y esa tarifa es la de su contrato: el mes completo, sin sábados ni domingos');

-- 3 · Va DENTRO de pago_base. Es lo que hace que chk_foto_cuadra siga cuadrando
--     sin tocar la tabla congelada, la restricción ni fn_planilla_congelar.
select is(
  (pg_temp.fila('VcTodoElMes Lab')->>'pago_base')::numeric,
  (pg_temp.fila('VcTodoElMes Lab')->>'monto_vacaciones')::numeric,
  'el monto entra dentro de pago_base, no por fuera');

-- 4 · LA MITAD QUE MÁS IMPORTA. A quien SÍ marcó días no se le mueve nada: su
--     día de vacaciones sigue valiendo el promedio de lo que se le pagó por día
--     trabajado, que es el art. 15, y NO la tarifa de contrato. El respaldo solo
--     entra cuando el promedio no existe. Si alguien invierte el orden del
--     coalesce, esta prueba lo dice.
select cmp_ok(
  abs((pg_temp.fila('VcParcial Lab')->>'monto_vacaciones')::numeric
      - (pg_temp.fila('VcControl Lab')->>'pago_base')::numeric / 3 * 5),
  '<', 0.02::numeric,
  'a quien marcó días le sigue valiendo el promedio, no la tarifa de respaldo');

-- 5 · Las HORAS también tienen respaldo, y no es cosmético: `horas_vacaciones`
--     alimenta el prorrateo del feriado. Si el día cuenta como trabajado para el
--     sueldo tiene que contar también para el feriado, o el mismo día sería
--     «trabajado» en una línea y «no trabajado» en la de al lado.
--
--     Esa columna NO sale en el JSON: es interna, y la consume el lateral `fer`.
--     Así que se mide por su consecuencia, que además es la que se paga. Sin el
--     respaldo, `horas_vacaciones` vale 0 para quien no marcó, el prorrateo
--     queda en 7.5 × 0 y su feriado sale S/0.00 estando de vacaciones.
select cmp_ok(
  (pg_temp.fila('VcTodoElMes Lab')->>'monto_feriados')::numeric, '>', 0::numeric,
  'el feriado de quien está de vacaciones se prorratea: las horas también tienen respaldo');

-- 6 · A quien no tiene vacaciones no se le mueve nada.
select is(
  (pg_temp.fila('VcControl Lab')->>'dias_vacaciones_pagados')::int, 0,
  'quien no tiene vacaciones no cobra ninguna');

-- 7 · Y a sueldo fijo tampoco: su rama es la otra del case, cobra su monto
--     mensual marque o no. Meterle la tarifa de respaldo lo pagaría dos veces.
select is(
  (pg_temp.fila('VcFija Lab')->>'monto_vacaciones')::numeric, 0::numeric,
  'a sueldo fijo no se le suma nada: ya cobra el periodo completo');

select * from finish();
rollback;
