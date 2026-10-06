-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 410_cargar_mi_documento_desde_lo_mio.test.sql — 0513 (sección 8)
-- ============================================================================
-- Quien NO tiene documento lo propone desde «Lo mío»; lo aprueba DO. Quien ya
-- lo tiene no puede proponerlo (corregirlo es de DO). Un número que ya es de
-- otra persona se rechaza SIN decir de quién.
--
-- Todos los números y nombres son inventados.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000041000', 'ZZ410', 'Sede de laboratorio 410', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso,
                      tipo_documento, documento) values
  ('00000000-0000-0000-0000-000000041001', 'Admin', 'Cuatrocientosdiez', '00000000-0000-0000-0000-000000041000',
   'admin', 'x', '00000000-0000-0000-0000-0000000410a1', '2024-01-01', 'dni', '41000001'),
  ('00000000-0000-0000-0000-000000041002', 'Ya', 'Tiene', '00000000-0000-0000-0000-000000041000',
   'integrante', 'x', '00000000-0000-0000-0000-0000000410a2', '2024-01-01', 'dni', '41000002'),
  ('00000000-0000-0000-0000-000000041006', 'Encargada', 'Sede', '00000000-0000-0000-0000-000000041000',
   'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000410a6', '2024-01-01', 'dni', '41000006');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000041003', 'Sin', 'Uno', '00000000-0000-0000-0000-000000041000',
   'integrante', 'x', '00000000-0000-0000-0000-0000000410a3', '2024-01-01'),
  ('00000000-0000-0000-0000-000000041004', 'Sin', 'Dos', '00000000-0000-0000-0000-000000041000',
   'integrante', 'x', '00000000-0000-0000-0000-0000000410a4', '2024-01-01'),
  ('00000000-0000-0000-0000-000000041005', 'Sin', 'Tres', '00000000-0000-0000-0000-000000041000',
   'integrante', 'x', '00000000-0000-0000-0000-0000000410a5', '2024-01-01');
set session_replication_role = origin;

-- ── EL CATÁLOGO ─────────────────────────────────────────────────────────────
select is(
  (select solo_do::text || ' · ' || requiere_documento::text || ' · ' || array_to_string(columnas, ',')
     from catalogo_campos_perfil where campo = 'documento'),
  'true · false · tipo_documento,documento',
  'CATÁLOGO · «documento» es de DO, sin adjunto, y trae tipo y número');

-- ── LO QUE SE PUEDE PROPONER ────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000410a3', true);
select lives_ok(
  $$ select fn_crear_solicitud_perfil('documento',
       jsonb_build_object('tipo_documento', 'dni', 'documento', '4100 0003'), '{}') $$,
  'PROPONER · quien no tiene documento lo propone, sin adjunto');

select is(
  (select valor_propuesto->>'documento' from solicitudes_cambio_perfil
    where persona_id = '00000000-0000-0000-0000-000000041003' and campo = 'documento'),
  '41000003',
  'PROPONER · lo que queda guardado es el número normalizado: DO ve y aplica lo mismo');

-- ── LO QUE SE RECHAZA ───────────────────────────────────────────────────────
select throws_ok(
  $$ select fn_crear_solicitud_perfil('documento',
       jsonb_build_object('tipo_documento', 'dni', 'documento', '4100004'), '{}') $$,
  'El DNI tiene exactamente 8 dígitos.',
  'RECHAZA · un DNI de 7 dígitos, con el largo exacto');

select throws_ok(
  $$ select fn_crear_solicitud_perfil('documento',
       jsonb_build_object('documento', '41000004'), '{}') $$,
  'Falta el dato «tipo_documento» para este campo.',
  'RECHAZA · sin tipo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000410a4', true);
select throws_ok(
  $$ select fn_crear_solicitud_perfil('documento',
       jsonb_build_object('tipo_documento', 'dni', 'documento', '41000002'), '{}') $$,
  'Ese número ya está registrado. Avisa a Desarrollo Organizacional para que lo revise.',
  'RECHAZA · un número que ya es de otra persona, y el mensaje NO dice de quién');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000410a2', true);
select throws_ok(
  $$ select fn_crear_solicitud_perfil('documento',
       jsonb_build_object('tipo_documento', 'dni', 'documento', '41000099'), '{}') $$,
  'Tu documento ya está cargado. Si hay un error, solo Desarrollo Organizacional lo puede corregir.',
  'RECHAZA · quien ya tiene documento no lo vuelve a proponer: corregirlo es de DO');

-- ── LA APROBACIÓN ───────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000410a6', true);
select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil
      where persona_id = '00000000-0000-0000-0000-000000041003' and campo = 'documento'),
    true, null) $$,
  null, null, 'APRUEBA · la líder de equipo de su sede NO puede: el documento es de DO');

-- `replica`: aprobar hace UPDATE sobre `personas` y esa FK contra auth.users es un
-- artefacto del banco de pruebas (misma razón que la 322).
set session_replication_role = replica;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000410a1', true);
select lives_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil
      where persona_id = '00000000-0000-0000-0000-000000041003' and campo = 'documento'),
    true, null) $$,
  'APRUEBA · DO sí');
set session_replication_role = origin;

select is(
  (select tipo_documento || ' ' || documento from personas where id = '00000000-0000-0000-0000-000000041003'),
  'dni 41000003',
  'APRUEBA · el documento queda en la ficha, con su tipo');

select is(
  (select valor_anterior || ' → ' || valor_nuevo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000041003' and campo_modificado = 'personas.documento'),
  '(vacío) → DNI 41000003',
  'APRUEBA · y deja rastro, por la misma puerta que Datos personales');

select is(
  (select estado from solicitudes_cambio_perfil
    where persona_id = '00000000-0000-0000-0000-000000041003' and campo = 'documento'),
  'aprobado',
  'APRUEBA · la solicitud queda aprobada');

-- ── LA PROPUESTA VIEJA ──────────────────────────────────────────────────────
-- Tres propone, y ANTES de que DO la mire alguien le carga el documento por
-- Datos personales. Aprobar la propuesta pisaría un número que ya se revisó.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000410a5', true);
select lives_ok(
  $$ select fn_crear_solicitud_perfil('documento',
       jsonb_build_object('tipo_documento', 'ce', 'documento', '000410005'), '{}') $$,
  'VIEJA · otra persona sin documento propone un carné');

set session_replication_role = replica;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000410a1', true);
select lives_ok(
  $$ select fn_set_documento('00000000-0000-0000-0000-000000041005', '41000055', null, 'dni') $$,
  'VIEJA · DO le carga otro documento por Datos personales mientras tanto');

select throws_like($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil
      where persona_id = '00000000-0000-0000-0000-000000041005' and campo = 'documento'),
    true, null) $$,
  '%la propuesta quedó vieja%',
  'VIEJA · aprobar la propuesta se niega: no pisa un documento que DO ya cargó');
set session_replication_role = origin;

select is(
  (select documento from personas where id = '00000000-0000-0000-0000-000000041005'),
  '41000055',
  'VIEJA · y el documento que cargó DO sigue ahí');

select * from finish();
rollback;
