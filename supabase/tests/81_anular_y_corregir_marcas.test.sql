-- ============================================================================
-- 81_anular_y_corregir_marcas.test.sql — Anular, reactivar, cambiar el tipo
-- ============================================================================
-- Prueba lo que trajo la migración 0081. Los tres casos vienen de días reales
-- del 25/07/2026 y de decisiones tomadas con Cayla el 26/07/2026:
--
--   · Una marca se ANULA, no se borra: queda en el historial con quién y por qué,
--     y el cálculo la ignora. Si la anulación fue un error, se reactiva.
--   · Se puede corregir el TIPO, no solo la hora — a Ytamar le marcaron "salida a
--     almuerzo" cuando en realidad se iba a su casa. Solo entre tipos de la misma
--     familia: una entrada nunca puede volverse salida.
--   · Un auto-cierre se puede CONFIRMAR cuando su hora es la buena, y desde ese
--     momento el día se mide entero (antes quedaba sin medir para siempre).
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000fd', 'ZZANU', 'Sede de laboratorio', true);

-- La admin que corrige (fn_verificar_corrector la reconoce por auth.uid()).
-- `replica` salta la FK a auth.users; se vuelve a `origin` enseguida porque en
-- replica los triggers están apagados y la jornada no se recalcularía.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000b0', 'PruebaAdmin', 'Laboratorio', '00000000-0000-0000-0000-0000000000fd', 'admin', 'test-hash', '00000000-0000-0000-0000-0000000000c0');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000b1', 'PruebaAN', 'Laboratorio', '00000000-0000-0000-0000-0000000000fd', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000b2', 'PruebaTI', 'Laboratorio', '00000000-0000-0000-0000-0000000000fd', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000b3', 'PruebaAC', 'Laboratorio', '00000000-0000-0000-0000-0000000000fd', 'test-hash');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 48,
       '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
         "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
         "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
         "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-0000000000b1'::uuid,
                  '00000000-0000-0000-0000-0000000000b2'::uuid,
                  '00000000-0000-0000-0000-0000000000b3'::uuid]) p;

-- Actúa la admin
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c0', true);

-- ── AN · anular deja la jornada como si esa marca no existiera ───────────────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0002-000000000001', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000fd', 'entrada',          '2026-07-22T09:00:00-05:00'),
  ('00000000-0000-0000-0002-000000000002', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000fd', 'salida_almuerzo',  '2026-07-22T13:00:00-05:00'),
  ('00000000-0000-0000-0002-000000000003', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000fd', 'retorno_almuerzo', '2026-07-22T14:00:00-05:00'),
  ('00000000-0000-0000-0002-000000000004', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000fd', 'salida_final',     '2026-07-22T18:00:00-05:00');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000b1' and fecha='2026-07-22'),
          8.00::numeric, 'AN · de partida: 8 h con su hora de refrigerio descontada');

select lives_ok($$ select fn_anular_marcaje('00000000-0000-0000-0002-000000000003', 'El regreso se marcó por error') $$,
                'AN · anular el regreso de almuerzo no da error');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000b1' and fecha='2026-07-22'),
          9.00::numeric, 'AN · sin el regreso, la pausa queda abierta y ya no se descuenta: 9 h');

select is((select tiene_salida_no_retornada from jornadas where persona_id='00000000-0000-0000-0000-0000000000b1' and fecha='2026-07-22'),
          true, 'AN · y el día queda marcado como "sin marca de retorno"');

select is((select count(*)::int from marcajes where id='00000000-0000-0000-0002-000000000003'),
          1, 'AN · la marca anulada NO se borró: sigue en la base');

select isnt((select anulada_por from marcajes where id='00000000-0000-0000-0002-000000000003'),
            null, 'AN · queda registrado quién la anuló');

-- Reactivar la devuelve al cálculo
select lives_ok($$ select fn_reactivar_marcaje('00000000-0000-0000-0002-000000000003', 'Me equivoqué al anular') $$,
                'AN · reactivar no da error');
select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000b1' and fecha='2026-07-22'),
          8.00::numeric, 'AN · al reactivarla vuelven a ser 8 h: anular es reversible');

-- El motivo no es opcional
select throws_ok($$ select fn_anular_marcaje('00000000-0000-0000-0002-000000000003', '') $$,
                 null, null, 'AN · anular sin motivo se rechaza');

-- ── TI · el caso Ytamar: la marca era su salida final, no su almuerzo ────────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0002-000000000011', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000fd', 'entrada',          '2026-07-25T09:00:00-05:00', 'terminal',    'normal'),
  ('00000000-0000-0000-0002-000000000012', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000fd', 'salida_almuerzo',  '2026-07-25T15:36:00-05:00', 'terminal',    'normal'),
  ('00000000-0000-0000-0002-000000000013', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000fd', 'retorno_almuerzo', '2026-07-25T15:53:00-05:00', 'terminal',    'normal'),
  ('00000000-0000-0000-0002-000000000014', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000fd', 'salida_final',     '2026-07-25T15:53:00-05:00', 'auto_cierre', 'pendiente_revision');

-- Se arregla como acordamos: se corrige el tipo y se anulan las dos sobrantes.
select lives_ok($$ select fn_corregir_marca('00000000-0000-0000-0002-000000000012', 'salida_final'::tipo_marca, null, 'Se fue a su casa; el terminal registró refrigerio por error') $$,
                'TI · se puede cambiar "salida a almuerzo" por "salida final"');
select lives_ok($$ select fn_anular_marcaje('00000000-0000-0000-0002-000000000013', 'Marca de un intento de corrección') $$,
                'TI · se anula el regreso que nunca ocurrió');
select lives_ok($$ select fn_anular_marcaje('00000000-0000-0000-0002-000000000014', 'Ya hay una salida final real') $$,
                'TI · se anula el auto-cierre que sobra');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000b2' and fecha='2026-07-25'),
          6.60::numeric, 'TI · el día queda como fue de verdad: 09:00 a 15:36 = 6.60 h');
select is((select estado::text from jornadas where persona_id='00000000-0000-0000-0000-0000000000b2' and fecha='2026-07-25'),
          'cerrada', 'TI · y sale de "auto-cerrada pendiente": el día está resuelto');

-- Una entrada nunca puede convertirse en salida
select throws_ok($$ select fn_corregir_marca('00000000-0000-0000-0002-000000000011', 'salida_final'::tipo_marca, null, 'prueba de familia') $$,
                 null, null, 'TI · cambiar una entrada por una salida se rechaza');

-- ── AC · confirmar un auto-cierre hace que el día se mida entero ─────────────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0002-000000000021', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000fd', 'entrada',      '2026-07-22T09:00:00-05:00', 'terminal',    'normal'),
  ('00000000-0000-0000-0002-000000000022', gen_random_uuid(), '00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000fd', 'salida_final', '2026-07-22T16:00:00-05:00', 'auto_cierre', 'pendiente_revision');

select is((select minutos_salida_temprana from jornadas where persona_id='00000000-0000-0000-0000-0000000000b3' and fecha='2026-07-22'),
          null::int, 'AC · sin revisar, un auto-cierre no mide salida anticipada: la hora la puso el sistema');

select fn_confirmar_auto_cierre('00000000-0000-0000-0002-000000000022', 'Confirmado: se fue a las 4');

select is((select minutos_salida_temprana from jornadas where persona_id='00000000-0000-0000-0000-0000000000b3' and fecha='2026-07-22'),
          120, 'AC · confirmado, la hora es real y sí se miden los 120 min de salida anticipada');

select * from finish();
rollback;
