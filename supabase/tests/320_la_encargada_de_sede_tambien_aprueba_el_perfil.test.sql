-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0403_....sql.
-- ============================================================================
-- 320_la_encargada_de_sede_tambien_aprueba_el_perfil.test.sql
-- ============================================================================
-- Lo que esta prueba vigila, por orden de importancia:
--
--   1. La encargada de la MISMA sede que la colaboradora puede resolver su
--      solicitud de perfil — antes de la 0403 esto era exclusivo de DO.
--   2. La encargada de OTRA sede no puede: ni resolverla, ni verla en su
--      bandeja de pendientes.
--   3. fn_solicitudes_perfil_pendientes le muestra a cada encargada solo lo
--      de su propio equipo; a DO, todo.
--   4. fn_solicitud_perfil_puede_leer (el documento adjunto) sigue la misma
--      regla de alcance: la encargada de la sede correcta puede abrirlo, la
--      de otra sede no — y eso no le da permiso para escribir/borrar nada,
--      que sigue siendo fn_solicitud_perfil_puede_escribir sin tocar.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa, tipo)
values
  ('00000000-0000-0000-0000-00000000d10a', 'ZZED1', 'Sede de laboratorio encargada A', true, 'tienda'),
  ('00000000-0000-0000-0000-00000000d10b', 'ZZED2', 'Sede de laboratorio encargada B', true, 'tienda');

set session_replication_role = replica;
-- Colaboradora, de la sede A.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d30a', 'EdColab', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000dbbb', '2024-01-01');
-- Encargada de la MISMA sede (A) — la que sí debería poder resolver.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d40a', 'EdEncargadaA', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000dccc', '2024-01-01');
-- Encargada de OTRA sede (B) — no debería poder ver ni resolver nada de A.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d50a', 'EdEncargadaB', 'Lab', '00000000-0000-0000-0000-00000000d10b', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000dddd', '2024-01-01');
-- DO, para el control de "sigue pudiendo todo".
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d60a', 'EdAdmin', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'admin', 'x', '00000000-0000-0000-0000-00000000deee', '2024-01-01');
set session_replication_role = origin;

-- La colaboradora propone un cambio de celular (no exige documento).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dbbb', true);
select fn_crear_solicitud_perfil('celular', jsonb_build_object('celular', '900111222'));

-- ── 1 · fn_solicitudes_perfil_pendientes respeta el alcance por sede ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dccc', true);
select is((select count(*)::int from fn_solicitudes_perfil_pendientes()
           where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  1, 'BANDEJA · la encargada de la MISMA sede ve la solicitud pendiente');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dddd', true);
select is((select count(*)::int from fn_solicitudes_perfil_pendientes()
           where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  0, 'BANDEJA · la encargada de OTRA sede no la ve');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000deee', true);
select is((select count(*)::int from fn_solicitudes_perfil_pendientes()
           where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  1, 'BANDEJA · DO ve cualquier sede');

-- ── 2 · Resolver: solo la encargada correcta (o DO) ────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dddd', true);
select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000d30a' and campo = 'celular'),
    true, null) $$,
  null, null, 'RESOLVER · la encargada de OTRA sede no puede aprobar');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dccc', true);
select lives_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000d30a' and campo = 'celular'),
    true, null) $$,
  'RESOLVER · la encargada de SU MISMA sede sí puede aprobar');

select is((select celular from datos_personales where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  '900111222', 'RESOLVER · y el valor real cambió al aprobar');

-- Una solicitud ya resuelta no se puede resolver dos veces, ni siquiera por
-- la encargada correcta — mismo candado que ya cubre la 316 para DO.
select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000d30a' and campo = 'celular'),
    true, null) $$,
  null, null, 'RESOLVER · una solicitud ya resuelta no se vuelve a resolver');

-- ── 3 · Leer el documento adjunto sigue el mismo alcance por sede ──────────
select is(fn_solicitud_perfil_puede_leer('solicitud/00000000-0000-0000-0000-00000000d30a/dni.jpg'),
  true, 'DOCUMENTO · la propia persona puede leer el suyo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dccc', true);
select is(fn_solicitud_perfil_puede_leer('solicitud/00000000-0000-0000-0000-00000000d30a/dni.jpg'),
  true, 'DOCUMENTO · la encargada de su misma sede puede leerlo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dddd', true);
select is(fn_solicitud_perfil_puede_leer('solicitud/00000000-0000-0000-0000-00000000d30a/dni.jpg'),
  false, 'DOCUMENTO · la encargada de otra sede no puede leerlo');

-- Y leer no es escribir: fn_solicitud_perfil_puede_escribir (sin tocar en
-- esta migración) sigue siendo solo admin/lider o el dueño de la carpeta —
-- la encargada de la sede correcta NO puede subir ni reemplazar ese archivo.
select is(fn_solicitud_perfil_puede_escribir('solicitud/00000000-0000-0000-0000-00000000d30a/dni.jpg'),
  false, 'DOCUMENTO · leer no es escribir — la encargada no puede subir/reemplazar el ajeno');

select * from finish();
rollback;
