-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 300_fn_set_horario_semanal_gana_el_mismo_candado_que_objetivos.test.sql
-- ============================================================================
-- La 0380 agrega un pg_advisory_xact_lock a fn_set_horario_semanal, igual
-- que la 0361 ya hizo para fn_objetivos_copiar_mes_anterior. Un test de
-- concurrencia real (dos sesiones a la vez) no es practicable en pgTAP —
-- se fija aquí lo que sí se puede comprobar: que el candado existe en el
-- cuerpo vigente, y que la función sigue funcionando de punta a punta para
-- el caso normal (una sola llamada).
-- ============================================================================
begin;
select plan(3);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000009701', 'ZZHS1', 'Sede horario semanal', true, 'tienda');

set session_replication_role = replica;
insert into personas
  (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado) values
  ('00000000-0000-0000-0000-000000009702', 'HsAdmin', 'Lab',
   '00000000-0000-0000-0000-000000009701', 'admin', 'x',
   '00000000-0000-0000-0000-000000009712', '2022-01-01', 'activo'),
  ('00000000-0000-0000-0000-000000009703', 'HsIntegrante', 'Lab',
   '00000000-0000-0000-0000-000000009701', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009713', '2024-01-01', 'activo');
set session_replication_role = origin;

-- ── El candado está en el cuerpo vigente ─────────────────────────────────
select ok(
  position('advisory_xact_lock' in pg_get_functiondef('fn_set_horario_semanal'::regproc)) > 0,
  'CANDADO · fn_set_horario_semanal toma un pg_advisory_xact_lock antes de tocar horarios_asignados'
);

-- ── El caso normal sigue funcionando: una llamada guarda el horario ─────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009712', true);
select lives_ok(
  $$ select fn_set_horario_semanal(
       '00000000-0000-0000-0000-000000009703',
       '2026-09-07',
       '{"1": {"e": "09:00", "s": "18:00"}, "3": {"e": "09:00", "s": "18:00"}}'::jsonb,
       'Prueba pgTAP.') $$,
  'NORMAL · el caso de una sola llamada sigue guardando el horario sin error'
);

select is(
  (select count(*)::int from horarios_asignados
    where persona_id = '00000000-0000-0000-0000-000000009703'
      and vigente_desde = '2026-09-07'),
  1,
  'NORMAL · el tramo quedó guardado exactamente una vez'
);

select * from finish();
rollback;
