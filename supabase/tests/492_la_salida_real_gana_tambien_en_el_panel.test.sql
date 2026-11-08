-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 492 — La salida real gana a la del auto-cierre también desde Correcciones (0605)
-- ============================================================================
-- Hasta la 0605, agregar desde Correcciones la salida real de un día que cerró
-- el sistema dejaba DOS salidas finales activas, y la jornada se quedaba con la
-- más tardía. Si la persona salió antes de la hora programada, se pagaban horas
-- que no trabajó. El terminal ya lo resolvía desde la 0320; el panel no.
--
-- Lo que se exige aquí:
--   1. Salida real ANTES que la del sistema → queda una sola, se paga la real,
--      el día deja de estar «pendiente» y queda el rastro.
--   2. Salida real DESPUÉS → queda una sola (antes quedaban dos).
--   3. Si DO ya CONFIRMÓ la del sistema, agregar otra se rechaza (decisión de
--      Felipe, 2026-11-08: una decisión humana no se deshace sola).
--   4. Confirmar la del sistema cuando el día ya tiene una salida real también
--      se rechaza: es la otra puerta al mismo día con dos salidas.
--   5. Lo que no es salida final, y los días sin auto-cierre, siguen igual.
--   6. La función que retira la marca del sistema no se puede llamar desde la
--      app: solo la usan las funciones guardián.
-- ============================================================================
begin;
select plan(19);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000049200', 'ZZ492', 'Sede de laboratorio 492', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-000000049201', 'PruebaAdmin492', 'Laboratorio', '00000000-0000-0000-0000-000000049200', 'admin', 'test-hash', '00000000-0000-0000-0000-000000049209');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-000000049211', 'PruebaAntes', 'Laboratorio', '00000000-0000-0000-0000-000000049200', 'test-hash'),
  ('00000000-0000-0000-0000-000000049212', 'PruebaDespues', 'Laboratorio', '00000000-0000-0000-0000-000000049200', 'test-hash'),
  ('00000000-0000-0000-0000-000000049213', 'PruebaConfirmada', 'Laboratorio', '00000000-0000-0000-0000-000000049200', 'test-hash'),
  ('00000000-0000-0000-0000-000000049214', 'PruebaDosPuertas', 'Laboratorio', '00000000-0000-0000-0000-000000049200', 'test-hash'),
  ('00000000-0000-0000-0000-000000049215', 'PruebaOtras', 'Laboratorio', '00000000-0000-0000-0000-000000049200', 'test-hash');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 48,
       '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
         "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
         "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
         "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-000000049211'::uuid, '00000000-0000-0000-0000-000000049212'::uuid,
                  '00000000-0000-0000-0000-000000049213'::uuid, '00000000-0000-0000-0000-000000049214'::uuid,
                  '00000000-0000-0000-0000-000000049215'::uuid]) p;

-- Cada caso arranca igual: entró a las 09:00 y el sistema le puso la salida a
-- las 18:00 (su hora programada), sin revisar.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
select gen_random_uuid(), gen_random_uuid(), p, '00000000-0000-0000-0000-000000049200', t, ts, o, r
from (values
  ('00000000-0000-0000-0000-000000049211'::uuid, 'entrada'::tipo_marca,      '2026-07-14T09:00:00-05:00'::timestamptz, 'terminal'::origen_marca,    'normal'::estado_revision),
  ('00000000-0000-0000-0000-000000049211',       'salida_final',             '2026-07-14T18:00:00-05:00',               'auto_cierre',                'pendiente_revision'),
  ('00000000-0000-0000-0000-000000049212',       'entrada',                  '2026-07-14T09:00:00-05:00',               'terminal',                   'normal'),
  ('00000000-0000-0000-0000-000000049212',       'salida_final',             '2026-07-14T18:00:00-05:00',               'auto_cierre',                'pendiente_revision'),
  ('00000000-0000-0000-0000-000000049213',       'entrada',                  '2026-07-14T09:00:00-05:00',               'terminal',                   'normal'),
  ('00000000-0000-0000-0000-000000049213',       'salida_final',             '2026-07-14T18:00:00-05:00',               'auto_cierre',                'revisada'),
  ('00000000-0000-0000-0000-000000049214',       'entrada',                  '2026-07-14T09:00:00-05:00',               'terminal',                   'normal'),
  ('00000000-0000-0000-0000-000000049214',       'salida_final',             '2026-07-14T18:00:00-05:00',               'auto_cierre',                'pendiente_revision'),
  ('00000000-0000-0000-0000-000000049214',       'salida_final',             '2026-07-14T16:00:00-05:00',               'admin_correccion',           'revisada'),
  ('00000000-0000-0000-0000-000000049215',       'entrada',                  '2026-07-14T09:00:00-05:00',               'terminal',                   'normal'),
  ('00000000-0000-0000-0000-000000049215',       'salida_final',             '2026-07-14T18:00:00-05:00',               'auto_cierre',                'pendiente_revision'),
  ('00000000-0000-0000-0000-000000049215',       'entrada',                  '2026-07-15T09:00:00-05:00',               'terminal',                   'normal')
) v(p, t, ts, o, r);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049209', true);

-- Cuántas salidas finales activas tiene un día.
create or replace function pg_temp.salidas(p uuid, d date) returns bigint language sql as $$
  select count(*) from marcajes
   where persona_id = p and tipo = 'salida_final' and anulada_at is null
     and (timestamp_marca at time zone 'America/Lima')::date = d
$$;

-- ── 1 · Salió ANTES de la hora que puso el sistema ───────────────────────────
select lives_ok($$ select fn_agregar_marcaje('00000000-0000-0000-0000-000000049211', 'salida_final',
                     '2026-07-14T16:00:00-05:00', 'Salió a las 4, se olvidó de marcar') $$,
                'ANTES · agregar la salida real se acepta');

select is(pg_temp.salidas('00000000-0000-0000-0000-000000049211', '2026-07-14'), 1::bigint,
          'ANTES · queda UNA sola salida final activa');

select is((select horas_trabajadas from jornadas
            where persona_id = '00000000-0000-0000-0000-000000049211' and fecha = '2026-07-14'),
          7.00::numeric, 'ANTES · se pagan las 7 h que trabajó, no las 9 que suponía el sistema');

select isnt((select estado::text from jornadas
              where persona_id = '00000000-0000-0000-0000-000000049211' and fecha = '2026-07-14'),
            'auto_cerrada_pendiente', 'ANTES · el día deja de figurar como cerrado por el sistema');

select is((select anulada_at is not null from marcajes
            where persona_id = '00000000-0000-0000-0000-000000049211' and origen = 'auto_cierre'),
          true, 'ANTES · la marca del sistema queda ANULADA, no borrada');

select is((select count(*) from correcciones_auditoria ca
             join marcajes m on m.id = ca.marcaje_id
            where m.persona_id = '00000000-0000-0000-0000-000000049211'
              and ca.campo_modificado = 'auto_cierre_reemplazado'),
          1::bigint, 'ANTES · y queda su rastro en la auditoría, como en el terminal (0320)');

select is((select corregido_por from correcciones_auditoria ca
             join marcajes m on m.id = ca.marcaje_id
            where m.persona_id = '00000000-0000-0000-0000-000000049211'
              and ca.campo_modificado = 'auto_cierre_reemplazado'),
          '00000000-0000-0000-0000-000000049201'::uuid,
          'ANTES · el rastro dice QUIÉN lo corrigió (quien pulsó en el panel)');

-- ── 2 · Salió DESPUÉS de la hora que puso el sistema ─────────────────────────
select lives_ok($$ select fn_agregar_marcaje('00000000-0000-0000-0000-000000049212', 'salida_final',
                     '2026-07-14T20:00:00-05:00', 'Cerró tienda tarde') $$,
                'DESPUÉS · agregar la salida real se acepta');

select is(pg_temp.salidas('00000000-0000-0000-0000-000000049212', '2026-07-14'), 1::bigint,
          'DESPUÉS · queda UNA sola salida final activa (antes quedaban dos)');

select is((select horas_trabajadas from jornadas
            where persona_id = '00000000-0000-0000-0000-000000049212' and fecha = '2026-07-14'),
          11.00::numeric, 'DESPUÉS · se pagan las 11 h reales');

select is(fn_dia_incoherente('00000000-0000-0000-0000-000000049212', '2026-07-14'), false,
          'DESPUÉS · el día ya no queda con una secuencia imposible');

-- ── 3 · DO ya había CONFIRMADO la salida del sistema ─────────────────────────
select throws_like($$ select fn_agregar_marcaje('00000000-0000-0000-0000-000000049213', 'salida_final',
                       '2026-07-14T16:00:00-05:00', 'Otra salida') $$,
                   '%CONFIRM%', 'CONFIRMADA · agregar otra salida final se rechaza con un aviso claro');

select is(pg_temp.salidas('00000000-0000-0000-0000-000000049213', '2026-07-14'), 1::bigint,
          'CONFIRMADA · y no entró nada: sigue la única salida, la confirmada');

-- ── 4 · La otra puerta: confirmar la del sistema cuando ya hay una real ──────
select throws_like($$ select fn_confirmar_auto_cierre(
                       (select id from marcajes where persona_id = '00000000-0000-0000-0000-000000049214'
                          and origen = 'auto_cierre'), 'Confirmo la del sistema') $$,
                   '%salida final%', 'DOS PUERTAS · confirmar la del sistema con una salida real ya puesta se rechaza');

select is((select estado_revision::text from marcajes
            where persona_id = '00000000-0000-0000-0000-000000049214' and origen = 'auto_cierre'),
          'pendiente_revision', 'DOS PUERTAS · la marca del sistema sigue sin confirmar, a la espera de que DO elija');

-- ── 5 · Lo que no es salida final, y los días sin auto-cierre ────────────────
select lives_ok($$ select fn_agregar_marcaje('00000000-0000-0000-0000-000000049215', 'salida_almuerzo',
                     '2026-07-14T13:00:00-05:00', 'Olvidó marcar el almuerzo') $$,
                'OTRAS · agregar una salida que no es la final no toca la del sistema');

select is((select anulada_at is null from marcajes
            where persona_id = '00000000-0000-0000-0000-000000049215' and origen = 'auto_cierre'),
          true, 'OTRAS · la salida del sistema sigue activa');

select lives_ok($$ select fn_agregar_marcaje('00000000-0000-0000-0000-000000049215', 'salida_final',
                     '2026-07-15T18:00:00-05:00', 'Día sin auto-cierre') $$,
                'OTRAS · en un día sin auto-cierre, agregar la salida final funciona como siempre');

-- ── 6 · La función que retira la marca no es una puerta para la app ──────────
select is(has_function_privilege('authenticated',
            'fn_retirar_salida_del_robot(uuid, date, timestamptz, uuid, text)', 'execute'),
          false, 'PUERTA · la app no puede llamar directo a fn_retirar_salida_del_robot');

select * from finish();
rollback;
