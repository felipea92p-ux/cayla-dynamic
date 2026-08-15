-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 195_el_descanso_medico_se_paga.test.sql
-- ============================================================================
-- `fn_planilla_calcular` no leía la tabla `ausencias` ni una vez: de los cuatro
-- tipos que el catálogo declara pagables, solo pagaba `vacaciones`, y porque
-- esas viven en una tabla aparte. Un descanso médico salía S/0.00 mientras las
-- pantallas decían que se pagaba y las provisiones sí lo devengaban.
--
-- Esto fija lo que arregló la 0254, incluidas las tres decisiones que más fácil
-- se rompen sin que nadie lo note: que el feriado de dentro no se pague dos
-- veces, que el domingo no se pague, y que el tope de 20 días del RIT muerda.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000005a1', 'ZZDM', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000005a2', 'DmAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000005a1', 'admin', 'x',
        '00000000-0000-0000-0000-0000000005ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000005a3', 'DmEnferma',   'Lab', '00000000-0000-0000-0000-0000000005a1', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-0000000005a4', 'DmControl',   'Lab', '00000000-0000-0000-0000-0000000005a1', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-0000000005a5', 'DmTodoElMes', 'Lab', '00000000-0000-0000-0000-0000000005a1', 'x', '2024-01-01', 'taller_produccion', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1185, '2024-01-01' from personas
 where apellidos = 'Lab' and nombres in ('DmEnferma','DmControl','DmTodoElMes');

-- Lunes a sábado. El domingo NO es laborable, y eso importa para la prueba 3.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39,
       '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
         "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
         "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb
from personas where apellidos = 'Lab' and nombres in ('DmEnferma','DmControl','DmTodoElMes');

-- El feriado que cae DENTRO del descanso médico: el nudo del caso real.
insert into feriados (fecha, nombre) values
  ('2026-07-29', 'Fiestas Patrias'), ('2026-08-06', 'Batalla de Junín')
on conflict do nothing;

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-0000000005a3', 'descanso_medico', '2026-07-29', '2026-08-03', 'lab', '00000000-0000-0000-0000-0000000005a2'),
  ('00000000-0000-0000-0000-0000000005a5', 'descanso_medico', '2026-07-29', '2026-08-28', 'lab', '00000000-0000-0000-0000-0000000005a2');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000005ff', true);

-- La enferma y la de control trabajan exactamente los mismos tres días.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000005a1', m.tipo, m.ts
from personas p,
     (values ('entrada'::tipo_marca,      timestamptz '2026-08-05T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-05T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-06T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-06T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-07T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-07T15:30:00-05:00')) m(tipo, ts)
where p.id in ('00000000-0000-0000-0000-0000000005a3', '00000000-0000-0000-0000-0000000005a4');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-0000000005e1', '2026-07-29', '2026-08-28', 'abierto');

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- 1 · Se pagan días. Antes de la 0254 esto era 0 y la persona cobraba de menos.
select cmp_ok(
  (pg_temp.fila('DmEnferma Lab')->>'dias_descanso_medico_pagados')::int, '>', 0,
  'un descanso médico paga días, en vez de salir en cero');

-- 2 y 3 · CUATRO días de seis, y el porqué de cada descuento:
--   29/07 es feriado — la planilla ya lo paga en su propia línea
--   02/08 es domingo — no le tocaba trabajar
-- Si alguien quita uno de los dos filtros, esta prueba lo dice.
select is(
  (pg_temp.fila('DmEnferma Lab')->>'dias_descanso_medico_pagados')::int, 4,
  'de 6 días calendario se pagan 4: el feriado y el domingo no');

-- La tolerancia de un céntimo NO es pereza: la función redondea el monto una
-- sola vez, al final, y esta prueba lo reconstruye desde un `pago_base` que el
-- JSON ya trae redondeado. Exigir igualdad exacta compararía dos redondeos
-- distintos del mismo número y fallaría por dónde se redondea, no por cuánto se
-- paga. Lo que se está fijando es la REGLA de valoración, no el redondeo.
select cmp_ok(
  abs((pg_temp.fila('DmEnferma Lab')->>'monto_descanso_medico')::numeric
      - (pg_temp.fila('DmControl Lab')->>'pago_base')::numeric / 3 * 4),
  '<', 0.02::numeric,
  'y cada día vale el promedio de lo que se le pagó por día trabajado');

-- 4 · Va DENTRO de pago_base, que es lo que hace que chk_foto_cuadra siga
--     cuadrando sin tocar la tabla congelada ni la restricción.
select is(
  (pg_temp.fila('DmEnferma Lab')->>'pago_base')::numeric,
  (pg_temp.fila('DmControl Lab')->>'pago_base')::numeric
    + (pg_temp.fila('DmEnferma Lab')->>'monto_descanso_medico')::numeric,
  'el monto entra dentro de pago_base, no por fuera');

-- 5 · A quien no tiene ninguna ausencia no se le mueve nada.
select is(
  (pg_temp.fila('DmControl Lab')->>'dias_descanso_medico_pagados')::int, 0,
  'quien no tiene descanso médico no cobra ninguno');

-- 6 · EL TOPE DEL RIT. Un descanso de todo el periodo tiene 26 días laborables
--     no feriados, pero CAYLA solo asume los primeros 20 CALENDARIO del año: de
--     esos 20, quince son laborables y no feriados. Sin tope daría más.
select is(
  (pg_temp.fila('DmTodoElMes Lab')->>'dias_descanso_medico_pagados')::int, 15,
  'el tope de 20 días calendario del RIT art. 31 f) muerde');

-- 7 · EL RESPALDO DE LA TARIFA. Quien pasó el periodo entero enfermo no marcó
--     ni un día: el promedio sería 0/0. Sin respaldo cobraría cero, que es el
--     mismo defecto con otra cara y en el caso más grave.
select cmp_ok(
  (pg_temp.fila('DmTodoElMes Lab')->>'monto_descanso_medico')::numeric, '>', 0::numeric,
  'quien no marcó ningún día cobra su tarifa de contrato, no cero');

-- 8 · Y el periodo se puede cerrar: si el monto se hubiera puesto por fuera de
--     pago_base, chk_foto_cuadra rechazaría y no se congelaría NINGUNA fila.
select lives_ok(
  $$select fn_planilla_congelar('eeeeeeee-0000-0000-0000-0000000005e1', 'pago',
                                '00000000-0000-0000-0000-0000000005a2')$$,
  'el periodo se congela con descansos médicos pagados dentro');

select * from finish();
rollback;
