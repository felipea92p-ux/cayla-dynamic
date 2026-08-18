-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 206_el_descanso_medico_prorratea_el_feriado.test.sql
-- ============================================================================
-- La 0177 hizo que un día de VACACIONES sumara sus horas al prorrateo del
-- feriado. La 0254 hizo que un día de DESCANSO MÉDICO se pagara. Nadie unió
-- las dos cosas: `horas_vacaciones` entraba al prorrateo del feriado,
-- `horas_descanso_medico` no existía. Un feriado dentro (o cerca) de un
-- descanso médico salía pagado de menos — y quien pasaba el periodo ENTERO
-- de descanso médico, en S/0.00. La 0269 lo cierra.
--
-- NOTA para quien aplique la 0268 después de esta: ese cambio exige
-- `aprobada_at` para que un descanso médico pague. Esta prueba no lo pone
-- porque en esta rama la 0268 todavía no existe — cuando se una, esta prueba
-- (y la 195 y la 200) necesitan la aprobación seteada o dejan de pagar.
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000006a1', 'ZZFD', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000006a2', 'FdAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000006a1', 'admin', 'x',
        '00000000-0000-0000-0000-0000000006ff', '2024-01-01');
set session_replication_role = origin;

-- Los TRES ganan lo mismo, tienen el mismo horario, y el periodo trae un
-- feriado real (06/08, Batalla de Junín) para que el prorrateo no sea cero.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000006a3', 'FdControl',    'Lab', '00000000-0000-0000-0000-0000000006a1', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-0000000006a4', 'FdEnferma',    'Lab', '00000000-0000-0000-0000-0000000006a1', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-0000000006a5', 'FdVacaciones', 'Lab', '00000000-0000-0000-0000-0000000006a1', 'x', '2024-01-01', 'taller_produccion', 'planilla'),
  ('00000000-0000-0000-0000-0000000006a6', 'FdTodoElMes',  'Lab', '00000000-0000-0000-0000-0000000006a1', 'x', '2024-01-01', 'taller_produccion', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1300, '2024-01-01' from personas
 where apellidos = 'Lab' and nombres in ('FdControl','FdEnferma','FdVacaciones','FdTodoElMes');

-- Lunes a sábado, 6.5 h exactas por día (09:00-15:30, sin almuerzo).
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39
from personas where apellidos = 'Lab'
 and nombres in ('FdControl','FdEnferma','FdVacaciones','FdTodoElMes');

-- FdControl marca los TRES días (03, 04 y 05 de agosto — lunes a miércoles,
-- ninguno feriado). FdEnferma y FdVacaciones marcan solo DOS y su tercer día
-- (05/08) es su ausencia — descanso médico una, vacaciones la otra. Si el
-- prorrateo del feriado trata igual un día trabajado, un día de vacaciones y
-- un día de descanso médico, los tres deberían terminar con el MISMO feriado.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000006a1', m.tipo, m.ts
from personas p,
     (values ('entrada'::tipo_marca,      timestamptz '2026-08-03T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-03T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-08-04T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-04T15:30:00-05:00')) m(tipo, ts)
where p.id in ('00000000-0000-0000-0000-0000000006a3', '00000000-0000-0000-0000-0000000006a4',
               '00000000-0000-0000-0000-0000000006a5');

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), '00000000-0000-0000-0000-0000000006a3',
       '00000000-0000-0000-0000-0000000006a1', m.tipo, m.ts
from (values ('entrada'::tipo_marca,      timestamptz '2026-08-05T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-08-05T15:30:00-05:00')) m(tipo, ts);

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-0000000006a4', 'descanso_medico', '2026-08-05', '2026-08-05', 'lab', '00000000-0000-0000-0000-0000000006a2'),
  ('00000000-0000-0000-0000-0000000006a5', 'vacaciones',       '2026-08-05', '2026-08-05', 'lab', '00000000-0000-0000-0000-0000000006a2'),
  ('00000000-0000-0000-0000-0000000006a6', 'descanso_medico', '2026-07-29', '2026-08-28', 'lab', '00000000-0000-0000-0000-0000000006a2');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000006ff', true);

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- 1 · EL CORAZÓN DEL ARREGLO: un día de descanso médico prorratea el feriado
--     exactamente como un día de vacaciones. Antes de la 0269 esto fallaba
--     (descanso médico se quedaba en lo que costaba SIN esa ausencia).
select is(
  (pg_temp.fila('FdEnferma Lab')->>'monto_feriados')::numeric,
  (pg_temp.fila('FdVacaciones Lab')->>'monto_feriados')::numeric,
  'un día de descanso médico paga el feriado igual que un día de vacaciones');

-- 2 · Y los tres — trabajado, vacaciones, descanso médico — valen lo mismo
--     para el feriado: los tres suman exactamente 3 días-equivalente.
select is(
  (pg_temp.fila('FdEnferma Lab')->>'monto_feriados')::numeric,
  (pg_temp.fila('FdControl Lab')->>'monto_feriados')::numeric,
  'y vale lo mismo que si ese día se hubiera trabajado');

-- 3 · EL CASO 0/0. Quien pasa el periodo entero de descanso médico no marcó
--     ni un día: antes de la 0269 su feriado salía en S/0.00 —el mismo
--     defecto 0/0 que la 0254 ya había resuelto para el MONTO, sin resolver
--     para las HORAS—.
select cmp_ok(
  (pg_temp.fila('FdTodoElMes Lab')->>'monto_feriados')::numeric, '>', 0::numeric,
  'quien no marcó ningún día también cobra su feriado, no cero');

-- 4 · No es un permiso para pagar feriado de más: sigue dependiendo de que
--     `dmd.dias` cuente el día (tope de 20, feriados/vacaciones excluidos).
--     Este número no lo toca la 0269 — lo hereda tal cual estaba.
select is(
  (pg_temp.fila('FdEnferma Lab')->>'dias_descanso_medico_pagados')::int, 1,
  'sigue siendo un solo día pagado — la 0269 no cambia CUÁNTOS días cuentan');

-- 5 · La foto sigue cuadrando: el monto de feriados es informativo, y su
--     suma con el resto de columnas es lo que congela `fn_planilla_congelar`
--     (ya cubierto por la prueba 107). Aquí solo se confirma que el cálculo
--     no truena al pedirlo con ambas ausencias en el mismo periodo.
select isnt(
  pg_temp.fila('FdEnferma Lab'), null,
  'la fila se calcula sin errores con descanso médico y vacaciones a la vez');

select * from finish();
rollback;
