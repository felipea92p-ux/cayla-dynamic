-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 86_cabos_sueltos_de_la_auditoria.test.sql
-- ============================================================================
-- Los cinco que dejó la revisión adversaria de la 0081 y cerró la 0086:
--   · el auto-cierre nocturno no duplica una salida final viva
--   · reactivar no puede dejar dos salidas finales el mismo día
--   · corregir una marca que rompe el día lo sella, en vez de callarse
--   · la autorización se comprueba antes que el estado de la marca
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000f8', 'ZZCAB', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000a8', 'PruebaAdminC', 'Laboratorio', '00000000-0000-0000-0000-0000000000f8', 'admin', 'test-hash', '00000000-0000-0000-0000-0000000000a9'),
  ('00000000-0000-0000-0000-0000000000b8', 'PruebaIntruso', 'Laboratorio', '00000000-0000-0000-0000-0000000000f8', 'integrante', 'test-hash', '00000000-0000-0000-0000-0000000000b9');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000c8', 'PruebaDia', 'Laboratorio', '00000000-0000-0000-0000-0000000000f8', 'test-hash');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-0000000000c8', '2026-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 48,
        '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
          "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
          "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
          "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a9', true);

-- ── Corregir una marca que rompe el día: se sella, no se calla ───────────────
-- Se convierte la "salida a almuerzo" en "salida final" dejando vivo su regreso.
-- Es el primer paso del flujo normal de arreglo, así que NO debe bloquearse —
-- pero el día queda imposible y tiene que notarse.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0005-000000000001', gen_random_uuid(), '00000000-0000-0000-0000-0000000000c8', '00000000-0000-0000-0000-0000000000f8', 'entrada',          '2026-07-22T09:00:00-05:00'),
  ('00000000-0000-0000-0005-000000000002', gen_random_uuid(), '00000000-0000-0000-0000-0000000000c8', '00000000-0000-0000-0000-0000000000f8', 'salida_almuerzo',  '2026-07-22T13:00:00-05:00'),
  ('00000000-0000-0000-0005-000000000003', gen_random_uuid(), '00000000-0000-0000-0000-0000000000c8', '00000000-0000-0000-0000-0000000000f8', 'retorno_almuerzo', '2026-07-22T14:00:00-05:00'),
  ('00000000-0000-0000-0005-000000000004', gen_random_uuid(), '00000000-0000-0000-0000-0000000000c8', '00000000-0000-0000-0000-0000000000f8', 'salida_final',     '2026-07-22T18:00:00-05:00');

select lives_ok($$ select fn_corregir_marca('00000000-0000-0000-0005-000000000002', 'salida_final'::tipo_marca, null, 'Se fue a su casa a la 1') $$,
                'SELLA · convertir una salida temporal en salida final NO se bloquea: es el primer paso del arreglo');

select is((select fn_dia_incoherente('00000000-0000-0000-0000-0000000000c8', '2026-07-22')),
          true, 'SELLA · el día queda con una secuencia imposible (dos salidas finales y un regreso huérfano)');

select is((select count(*)::int from marcajes
           where persona_id='00000000-0000-0000-0000-0000000000c8'
             and (timestamp_marca at time zone 'America/Lima')::date='2026-07-22'
             and estado_revision='pendiente_revision' and anulada_at is null) > 0,
          true, 'SELLA · y el día queda sellado para revisión, en vez de pasar por bueno en silencio');

-- Hay que anular TODO lo que queda después: el regreso huérfano y la segunda
-- salida final. Es exactamente lo que la pantalla propone marcado al guardar —
-- con el regreso solo no basta, porque quedarían dos salidas finales.
select fn_anular_marcaje('00000000-0000-0000-0005-000000000003', 'Regreso que ya no corresponde');
select fn_anular_marcaje('00000000-0000-0000-0005-000000000004', 'Queda después de la salida final real');

select is((select fn_dia_incoherente('00000000-0000-0000-0000-0000000000c8', '2026-07-22')),
          false, 'SELLA · anulado todo lo que sobraba, el día cuadra otra vez');

-- ── Reactivar no puede dejar dos salidas finales ────────────────────────────
-- La de las 18:00 está anulada y la de las 13:00 viva: revivirla dejaría dos.
select throws_ok($$ select fn_reactivar_marcaje('00000000-0000-0000-0005-000000000004', 'Me arrepiento') $$,
                 null, null, 'DOS SALIDAS · reactivar se rechaza si el día ya tiene otra salida final viva');

-- ── El auto-cierre no duplica una salida final viva ─────────────────────────
-- El día de arriba tiene una salida final viva (la de las 13:00, ya convertida).
select is((select count(*)::int from marcajes
           where persona_id='00000000-0000-0000-0000-0000000000c8'
             and (timestamp_marca at time zone 'America/Lima')::date='2026-07-22'
             and tipo='salida_final' and anulada_at is null),
          1, 'AUTO-CIERRE · de partida hay exactamente una salida final viva');

select fn_auto_cierre();

select is((select count(*)::int from marcajes
           where persona_id='00000000-0000-0000-0000-0000000000c8'
             and (timestamp_marca at time zone 'America/Lima')::date='2026-07-22'
             and tipo='salida_final' and anulada_at is null),
          1, 'AUTO-CIERRE · tras pasar el cron sigue habiendo una, no dos');

-- ── La autorización va antes que el estado de la marca ──────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b9', true);
select throws_ok($$ select fn_anular_marcaje('00000000-0000-0000-0005-000000000001', 'no deberia poder') $$,
                 null, null, 'PERMISO · un integrante no puede anular marcas de nadie');

select * from finish();
rollback;
