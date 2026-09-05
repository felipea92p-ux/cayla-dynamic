-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 284_el_aviso_de_alertas_aprende_dos_audiencias.test.sql — la 0358 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá: que un aviso de contrato/vacaciones por
-- vencer resuelva su destinatario como `alertas.persona_id` DIRECTO —el DO
-- que fn_generar_alertas_vencimiento ya decidió al escribir—, sin buscar
-- ninguna encargada de sede; que auto_cierre y esta rama nueva convivan en
-- el mismo resultado sin mezclarse; y que si el destinatario ya no tiene
-- correo (se lo quitaron después de encolado), la fila salga con
-- destinatarios vacíos en vez de reventar. La prueba de que la rama de
-- auto_cierre NO CAMBIÓ vive en 281, que sigue en verde tal cual.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000f1001', 'ZZF11', 'Sede aviso dos audiencias', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, email, estado, fecha_ingreso) values
  -- El DO que fn_generar_alertas_vencimiento eligió como destinatario.
  ('00000000-0000-0000-0000-0000000f1011', 'FDos', 'Admin',
   '00000000-0000-0000-0000-0000000f1001', 'admin', 'x', 'admin.dos@example.com', 'activo', '2023-01-01'),
  -- Otro DO, sin correo — para probar que la falta de correo no revienta la lectura.
  ('00000000-0000-0000-0000-0000000f1012', 'FDos', 'SinCorreo',
   '00000000-0000-0000-0000-0000000f1001', 'lider_do', 'x', null, 'activo', '2023-01-01'),
  -- La "afectada" de un aviso normal (auto_cierre), para probar que las dos ramas conviven.
  ('00000000-0000-0000-0000-0000000f1013', 'FDos', 'Afectada',
   '00000000-0000-0000-0000-0000000f1001', 'integrante', 'x', null, 'activo', '2023-01-01'),
  -- Encargada de esa sede: NO debe recibir nada de la rama de vencimientos.
  ('00000000-0000-0000-0000-0000000f1014', 'FDos', 'Encargada',
   '00000000-0000-0000-0000-0000000f1001', 'supervisor_sede', 'x', 'encargada.dos@example.com', 'activo', '2023-01-01');
set session_replication_role = origin;

insert into alertas (id, persona_id, tipo, canal, payload, created_at) values
  -- Aviso de vencimiento: persona_id YA es el destinatario (el admin).
  ('00000000-0000-0000-0000-0000000f1021', '00000000-0000-0000-0000-0000000f1011', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona', 'Alguien Vence', 'sede', 'ZZF11', 'dias_restantes', 10), now() - interval '1 hour'),
  -- Mismo tipo, pero apuntando al DO sin correo.
  ('00000000-0000-0000-0000-0000000f1022', '00000000-0000-0000-0000-0000000f1012', 'vacaciones_por_vencer', 'email',
   jsonb_build_object('persona', 'Otro Vence', 'sede', 'ZZF11', 'dias_para_vencer', 5), now() - interval '1 hour'),
  -- Un aviso normal en la misma tanda, para probar que las dos ramas conviven.
  ('00000000-0000-0000-0000-0000000f1023', '00000000-0000-0000-0000-0000000f1013', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-09-03'), now() - interval '1 hour');

create temp table _pendientes2 as select * from fn_alertas_email_pendientes();

select is((select count(*)::int from _pendientes2), 3, 'las tres avisos salen: dos de vencimiento y uno de auto_cierre');

select is(
  (select destinatarios from _pendientes2 where alerta_id = '00000000-0000-0000-0000-0000000f1021'),
  array['admin.dos@example.com'],
  'contrato_por_vencer: el destinatario es el admin de persona_id, no la encargada de su sede'
);

select is(
  (select destinatarios_nombres from _pendientes2 where alerta_id = '00000000-0000-0000-0000-0000000f1021'),
  array['FDos Admin'],
  'y el nombre que acompaña es el del propio admin'
);

select is(
  (select persona_nombre from _pendientes2 where alerta_id = '00000000-0000-0000-0000-0000000f1021'),
  'Alguien Vence',
  'persona_nombre sigue siendo el del payload — de quién es el vencimiento, no quién lo recibe'
);

select is(
  (select destinatarios from _pendientes2 where alerta_id = '00000000-0000-0000-0000-0000000f1022'),
  '{}'::text[],
  'vacaciones_por_vencer hacia un DO sin correo: lista vacía, no un error — y sobre todo, NUNCA la encargada'
);

select is(
  (select destinatarios from _pendientes2 where alerta_id = '00000000-0000-0000-0000-0000000f1023'),
  array['encargada.dos@example.com'],
  'auto_cierre en la misma tanda: sigue resolviendo la encargada, sin mezclarse con la rama nueva'
);

-- La encargada nunca aparece como destinataria de ninguna fila de vencimiento,
-- aunque técnicamente ES la encargada de la sede de ambos avisos.
select is(
  (select bool_or('encargada.dos@example.com' = any(destinatarios))
     from _pendientes2 where alerta_id in ('00000000-0000-0000-0000-0000000f1021', '00000000-0000-0000-0000-0000000f1022')),
  false,
  'la encargada de la sede jamás recibe un aviso de contrato o vacaciones por vencer'
);

select * from finish();
rollback;
