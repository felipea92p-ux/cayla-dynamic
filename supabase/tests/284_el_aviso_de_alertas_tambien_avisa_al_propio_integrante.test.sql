-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 284_el_aviso_de_alertas_tambien_avisa_al_propio_integrante.test.sql — la 0359
-- ============================================================================
-- La 0354 (prueba 281) ya protege que la encargada reciba el aviso. Esto
-- protege lo que agregó la 0359 encima: que la propia persona involucrada
-- TAMBIÉN esté en `destinatarios` cuando tiene correo cargado — y que si esa
-- persona es, a la vez, la encargada de su propia sede, no reciba el mismo
-- correo dos veces (el arreglo llega deduplicado).
-- ============================================================================
begin;
select plan(5);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000f8001', 'ZZF81', 'Sede con encargada', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000f8002', 'ZZF82', 'Sede sin correo del integrante', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000f8003', 'ZZF83', 'Sede donde la afectada es su propia encargada', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, email, estado, fecha_ingreso, fecha_cese, motivo_cese) values
  ('00000000-0000-0000-0000-0000000f8011', 'FInt', 'Encargada',
   '00000000-0000-0000-0000-0000000f8001', 'supervisor_sede', 'x', 'encargada.integrante@example.com', 'activo', '2024-01-15', null, null),
  ('00000000-0000-0000-0000-0000000f8012', 'FInt', 'ConCorreo',
   '00000000-0000-0000-0000-0000000f8001', 'integrante', 'x', 'afectada.integrante@example.com', 'activo', '2024-01-15', null, null),
  -- Sin correo cargado: no debe aparecer en destinatarios ni reventar la función.
  ('00000000-0000-0000-0000-0000000f8021', 'FInt', 'SinCorreo',
   '00000000-0000-0000-0000-0000000f8002', 'integrante', 'x', null, 'activo', '2024-01-15', null, null),
  -- Es su propia encargada de sede: el mismo correo no debe duplicarse.
  ('00000000-0000-0000-0000-0000000f8031', 'FInt', 'PropiaEncargada',
   '00000000-0000-0000-0000-0000000f8003', 'supervisor_sede', 'x', 'propia.encargada@example.com', 'activo', '2024-01-15', null, null);
set session_replication_role = origin;

insert into alertas (id, persona_id, tipo, canal, payload, created_at) values
  ('00000000-0000-0000-0000-0000000f8041', '00000000-0000-0000-0000-0000000f8012', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-09-03'), now() - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000f8042', '00000000-0000-0000-0000-0000000f8021', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-09-03'), now() - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000f8043', '00000000-0000-0000-0000-0000000f8031', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-09-03'), now() - interval '1 hour');

create temp table _pendientes as select * from fn_alertas_email_pendientes();

-- ── 1 · La persona CON correo entra junto a su encargada ────────────────────
select is(
  (select array(select unnest(destinatarios) order by 1) from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f8041'),
  array['afectada.integrante@example.com', 'encargada.integrante@example.com'],
  'destinatarios trae el correo de la propia persona Y el de su encargada'
);

select is(
  (select array(select unnest(destinatarios_nombres) order by 1) from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f8041'),
  array['FInt ConCorreo', 'FInt Encargada'],
  'destinatarios_nombres trae los dos nombres correspondientes'
);

-- ── 2 · Sin correo cargado, no aparece nada de la persona (ni error) ────────
select is(
  (select destinatarios from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f8042'),
  '{}'::text[],
  'Sin correo propio y sin encargada en esa sede, la lista sigue vacía — no revienta'
);

-- ── 3 · Es su propia encargada: el correo no se duplica ─────────────────────
select is(
  (select destinatarios from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f8043'),
  array['propia.encargada@example.com'],
  'Cuando la afectada es también la encargada de su sede, su correo aparece UNA sola vez'
);

select is(
  (select cardinality(destinatarios_nombres) from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f8043'),
  1,
  'Y su nombre también aparece una sola vez, no dos'
);

select * from finish();
rollback;
