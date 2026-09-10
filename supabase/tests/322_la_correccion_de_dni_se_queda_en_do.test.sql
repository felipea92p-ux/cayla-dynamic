-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0405_....sql.
-- ============================================================================
-- 322_la_correccion_de_dni_se_queda_en_do.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. La encargada de sede NO puede aprobar una corrección de identidad de su
--      equipo, y el mensaje lo dice — antes llegaba hasta fn_set_documento y
--      moría hablando de otro permiso.
--   2. DO sí puede: cerrar la puerta a la encargada no puede cerrársela a quien
--      siempre la tuvo. Es la mitad que se olvida, y la que deja pasar una
--      regresión sin que nadie se entere.
--   3. La encargada SIGUE pudiendo con los demás campos de su equipo (celular),
--      que es lo que la 0403 vino a habilitar. Sin esto, «arreglar» el defecto
--      podría haber sido revertir la 0403 sin querer.
--   4. La solicitud le sigue APARECIENDO en la bandeja, marcada como de DO: si
--      desapareciera, su equipo esperaría algo que ella no ve.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000f10a', 'ZZDO1', 'Sede laboratorio solo_do', true, 'tienda'),
       ('00000000-0000-0000-0000-00000000f10b', 'ZZDO2', 'Otra sede laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-00000000f20a', 'DoAdmin', 'Lab', '00000000-0000-0000-0000-00000000f10a', 'admin', 'x', '00000000-0000-0000-0000-00000000faaa', '2024-01-01'),
  ('00000000-0000-0000-0000-00000000f30a', 'DoEncargada', 'Lab', '00000000-0000-0000-0000-00000000f10a', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000fbbb', '2024-01-01'),
  ('00000000-0000-0000-0000-00000000f40a', 'DoColab', 'Lab', '00000000-0000-0000-0000-00000000f10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000fccc', '2024-01-01');
set session_replication_role = origin;

-- ── DE PARTIDA · el catálogo marca identidad como de DO, y solo eso ─────────
select is((select solo_do from catalogo_campos_perfil where campo = 'correccion_identidad'),
  true, 'CATÁLOGO · correccion_identidad queda marcada como de DO');

select is((select count(*)::int from catalogo_campos_perfil where solo_do),
  1, 'CATÁLOGO · y es el único campo marcado — no se cerró de más');

-- La colaboradora pide corregir su número de documento.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fccc', true);
select fn_crear_solicitud_perfil('correccion_identidad',
  jsonb_build_object('documento', '87654321'),
  array['solicitud/00000000-0000-0000-0000-00000000f40a/dni.jpg']);

-- ── 1 · La encargada de su sede no puede aprobarla ──────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fbbb', true);

select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil
      where persona_id = '00000000-0000-0000-0000-00000000f40a' and campo = 'correccion_identidad'),
    true, null) $$,
  null, null, 'ENCARGADA · no puede aprobar una corrección de identidad');

-- ── 4 · Pero la sigue viendo en su bandeja, marcada ─────────────────────────
select is((select count(*)::int from fn_solicitudes_perfil_pendientes()
           where campo = 'correccion_identidad'),
  1, 'BANDEJA · la encargada sigue viendo la solicitud, no se le esconde');

select is((select solo_do from fn_solicitudes_perfil_pendientes()
           where campo = 'correccion_identidad'),
  true, 'BANDEJA · y viene marcada como de DO, para que la pantalla lo diga');

-- ── 3 · Con los demás campos de su equipo sí puede (no se revirtió la 0403) ─
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fccc', true);
select fn_crear_solicitud_perfil('celular', jsonb_build_object('celular', '987654321'));

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fbbb', true);
select lives_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil
      where persona_id = '00000000-0000-0000-0000-00000000f40a' and campo = 'celular'),
    true, null) $$,
  'ENCARGADA · sigue aprobando lo que sí le toca — la 0403 no se revirtió');

-- ── 2 · Y DO sí puede con la identidad ──────────────────────────────────────
-- `replica` otra vez acá, y no solo en los inserts de arriba: aprobar esto pasa
-- por fn_set_documento, que hace UPDATE sobre `personas` — y ese update vuelve
-- a comprobar la FK contra auth.users que el insert había esquivado. Estas
-- personas de laboratorio no tienen usuario real detrás (misma razón que la
-- 104), así que la FK es un artefacto del banco de pruebas y no lo que se está
-- midiendo. Lo que se mide es que el guard nuevo de la 0405 deje pasar a DO.
set session_replication_role = replica;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000faaa', true);
select lives_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil
      where persona_id = '00000000-0000-0000-0000-00000000f40a' and campo = 'correccion_identidad'),
    true, null) $$,
  'DO · sí aprueba la corrección de identidad, que es de quien siempre fue');
set session_replication_role = origin;

select * from finish();
rollback;
