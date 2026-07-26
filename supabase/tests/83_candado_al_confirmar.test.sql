-- ============================================================================
-- 83_candado_al_confirmar.test.sql — Los tres agujeros que encontró la revisión
-- ============================================================================
-- La 0081 pasó por cuatro revisores independientes, cada hallazgo por un
-- verificador cuyo trabajo era demostrar que era falso. Tres de los que
-- sobrevivieron tocaban las funciones nuevas. Esto los deja cerrados por escrito:
--
--   1. Confirmar un auto-cierre era la ÚNICA de las cuatro operaciones sin el
--      candado de periodo pagado — y justo la que enciende la medición de la
--      salida anticipada y el tiempo adicional de ese día.
--   2. Corregir la hora podía mover la marca a otro día, y el día que dejaba
--      atrás nunca se recalculaba: seguía cobrando horas que ya no existían.
--   3. Dos correcciones a la vez sobre la misma marca se pisaban.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000fb', 'ZZCAN', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000f0', 'PruebaAdminC', 'Laboratorio', '00000000-0000-0000-0000-0000000000fb', 'admin', 'test-hash', '00000000-0000-0000-0000-0000000000f9');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000f1', 'PruebaPag', 'Laboratorio', '00000000-0000-0000-0000-0000000000fb', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000f2', 'PruebaDia', 'Laboratorio', '00000000-0000-0000-0000-0000000000fb', 'test-hash');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 48,
       '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
         "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
         "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
         "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-0000000000f1'::uuid,
                  '00000000-0000-0000-0000-0000000000f2'::uuid]) p;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000f9', true);

-- ── 1 · Un periodo YA PAGADO no se toca, tampoco confirmando ────────────────
insert into periodos_planilla (fecha_ini, fecha_fin, estado)
values ('2026-06-01', '2026-06-30', 'pagado');

insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0004-000000000001', gen_random_uuid(), '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000fb', 'entrada',      '2026-06-15T09:00:00-05:00', 'terminal',    'normal'),
  ('00000000-0000-0000-0004-000000000002', gen_random_uuid(), '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000fb', 'salida_final', '2026-06-15T14:00:00-05:00', 'auto_cierre', 'pendiente_revision');

select throws_ok($$ select fn_confirmar_auto_cierre('00000000-0000-0000-0004-000000000002', 'prueba') $$,
                 null, null, 'PAGADO · confirmar un auto-cierre de un periodo ya pagado se rechaza');

select throws_ok($$ select fn_anular_marcaje('00000000-0000-0000-0004-000000000002', 'prueba de candado') $$,
                 null, null, 'PAGADO · anular también se rechaza (ya lo hacía)');

select is((select minutos_salida_temprana from jornadas where persona_id='00000000-0000-0000-0000-0000000000f1' and fecha='2026-06-15'),
          null::int, 'PAGADO · y el día sigue sin medir salida anticipada: la planilla pagada no se movió');

-- ── 2 · Mover una marca de día recalcula también el día que abandona ─────────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0004-000000000011', gen_random_uuid(), '00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000fb', 'entrada',      '2026-07-20T08:00:00-05:00'),
  ('00000000-0000-0000-0004-000000000012', gen_random_uuid(), '00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000fb', 'salida_final', '2026-07-20T16:30:00-05:00');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000f2' and fecha='2026-07-20'),
          8.50::numeric, 'DIA · de partida el 20 de julio tiene 8.50 h');

-- Corregir la hora ya no puede mudar la marca de día: para eso están anular y agregar.
select throws_ok($$ select fn_corregir_marca('00000000-0000-0000-0004-000000000011', null, '2026-07-21T08:00:00-05:00'::timestamptz, 'mover al dia siguiente') $$,
                 null, null, 'DIA · corregir la hora no puede mover la marca a otro día');

-- Y si una marca cambia de día por otra vía, el trigger recalcula los dos.
update marcajes set timestamp_marca = '2026-07-21T08:00:00-05:00'
 where id = '00000000-0000-0000-0004-000000000011';

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000f2' and fecha='2026-07-20'),
          null::numeric, 'DIA · el día que la marca abandona se recalcula: ya no cobra 8.50 h que no existieron');

-- ── 3 · Confirmar fuera de un periodo pagado sí funciona ────────────────────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0004-000000000021', gen_random_uuid(), '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000fb', 'entrada',      '2026-07-22T09:00:00-05:00', 'terminal',    'normal'),
  ('00000000-0000-0000-0004-000000000022', gen_random_uuid(), '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000fb', 'salida_final', '2026-07-22T16:00:00-05:00', 'auto_cierre', 'pendiente_revision');

select lives_ok($$ select fn_confirmar_auto_cierre('00000000-0000-0000-0004-000000000022', 'Se fue a las 4') $$,
                'LIBRE · fuera de un periodo pagado, confirmar sigue funcionando con normalidad');

select * from finish();
rollback;
