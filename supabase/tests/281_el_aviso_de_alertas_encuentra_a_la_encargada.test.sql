-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 281_el_aviso_de_alertas_encuentra_a_la_encargada.test.sql — la 0354
-- ============================================================================
-- Lo que hay que proteger acá: que `fn_alertas_email_pendientes` resuelva a
-- la encargada de la SEDE de la persona del aviso (no a la persona misma —
-- ese es un cambio de audiencia a propósito, ver la 0354), que una sede sin
-- encargada activa con correo devuelva la lista vacía en vez de reventar, que
-- lo viejo (>2 días) no se despache, que `fn_marcar_alerta_resultado` cierre
-- bien los dos desenlaces, y que nadie salvo el rol de servicio pueda leer
-- esta cola — expone correos de encargadas, no es para cualquiera.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000f0001', 'ZZF01', 'Sede con encargada', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000f0002', 'ZZF02', 'Sede sin encargada', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, email, estado, fecha_ingreso, fecha_cese, motivo_cese) values
  ('00000000-0000-0000-0000-0000000f0011', 'FAviso', 'Encargada',
   '00000000-0000-0000-0000-0000000f0001', 'supervisor_sede', 'x', 'encargada.aviso@example.com', 'activo', '2024-01-15', null, null),
  ('00000000-0000-0000-0000-0000000f0012', 'FAviso', 'Afectada',
   '00000000-0000-0000-0000-0000000f0001', 'integrante', 'x', null, 'activo', '2024-01-15', null, null),
  -- Sede sin nadie con rol supervisor_sede ni es_encargada_piso.
  ('00000000-0000-0000-0000-0000000f0013', 'FAviso', 'Huerfana',
   '00000000-0000-0000-0000-0000000f0002', 'integrante', 'x', null, 'activo', '2024-01-15', null, null),
  -- Encargada inactiva: no debe contar como destinataria.
  ('00000000-0000-0000-0000-0000000f0014', 'FAviso', 'ExEncargada',
   '00000000-0000-0000-0000-0000000f0001', 'supervisor_sede', 'x', 'ex.encargada@example.com', 'inactivo', '2024-01-15', '2026-08-01', 'renuncia');
set session_replication_role = origin;

-- Un aviso reciente (debe salir) y uno viejo (no debe salir).
insert into alertas (id, persona_id, tipo, canal, payload, created_at) values
  ('00000000-0000-0000-0000-0000000f0021', '00000000-0000-0000-0000-0000000f0012', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-09-03'), now() - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000f0022', '00000000-0000-0000-0000-0000000f0013', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-09-03'), now() - interval '1 hour'),
  ('00000000-0000-0000-0000-0000000f0023', '00000000-0000-0000-0000-0000000f0012', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-08-01'), now() - interval '5 days');

create temp table _pendientes as select * from fn_alertas_email_pendientes();

select is((select count(*)::int from _pendientes), 2,
  'Solo las dos avisos de menos de 2 días salen — la de hace 5 días queda afuera');

select is((select count(*)::int from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f0023'),
  0, 'La alerta de hace 5 días no aparece entre las pendientes');

select is((select destinatarios from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f0021'),
  array['encargada.aviso@example.com'],
  'La sede con encargada activa resuelve su correo, y no el de la ex-encargada inactiva');

select is((select destinatarios_nombres from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f0021'),
  array['FAviso Encargada'],
  'El nombre que acompaña al correo es el de la encargada, no el de la persona del aviso');

select is((select persona_nombre from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f0021'),
  'FAviso Afectada',
  'El aviso sigue identificando a la persona a la que le pasó, aunque el destinatario sea otra');

select is((select destinatarios from _pendientes where alerta_id = '00000000-0000-0000-0000-0000000f0022'),
  '{}'::text[],
  'Una sede sin encargada activa con correo devuelve la lista vacía, no un error');

-- ── Cerrar el resultado ──────────────────────────────────────────────────────
select fn_marcar_alerta_resultado('00000000-0000-0000-0000-0000000f0021', true, null);
select is((select estado from alertas where id = '00000000-0000-0000-0000-0000000f0021'),
  'enviado', 'Marcar éxito deja la alerta en estado enviado');
select isnt((select enviado_at from alertas where id = '00000000-0000-0000-0000-0000000f0021'),
  null, 'Marcar éxito registra enviado_at');

select fn_marcar_alerta_resultado('00000000-0000-0000-0000-0000000f0022', false, 'sin encargada con correo activo en esa sede');
select is((select estado from alertas where id = '00000000-0000-0000-0000-0000000f0022'),
  'fallido', 'Marcar fallo deja la alerta en estado fallido');
select is((select nota_fallo from alertas where id = '00000000-0000-0000-0000-0000000f0022'),
  'sin encargada con correo activo en esa sede', 'El motivo del fallo queda anotado para poder auditarlo después');

select throws_ok(
  $$ select fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000000000', true, null) $$,
  'Esa alerta (00000000-0000-0000-0000-000000000000) ya no existe.',
  'Cerrar una alerta que no existe avisa en vez de fallar en silencio'
);

-- ── Nadie salvo el rol de servicio puede leer esta cola ─────────────────────
set role authenticated;
select throws_ok($$ select fn_alertas_email_pendientes() $$, null, null,
  'AUTHENTICATED · no puede leer la cola de avisos, aunque sea admin — expone correos de otras personas');
reset role;

select * from finish();
rollback;
