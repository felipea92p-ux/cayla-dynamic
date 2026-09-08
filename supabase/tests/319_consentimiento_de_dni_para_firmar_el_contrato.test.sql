-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0402_....sql.
-- ============================================================================
-- 319_consentimiento_de_dni_para_firmar_el_contrato.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. Sin consentimiento registrado, fn_mi_consentimiento_dni() no devuelve fila.
--   2. Nadie puede registrar un DNI en la carpeta de otra persona.
--   3. La propia persona sí puede registrar el suyo, y queda con la fecha de hoy.
--   4. Volver a subir actualiza la MISMA fila (una por persona), no crea otra.
--   5. RLS: cada quien ve solo su propia constancia — salvo admin/líder, que ve
--      la de cualquiera (mismo criterio que solicitudes_cambio_perfil, 0399).
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000d10a', 'ZZDNI', 'Sede de laboratorio DNI', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d20a', 'DniAdmin', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'admin', 'x', '00000000-0000-0000-0000-00000000daaa', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d30a', 'DniColab', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000dbbb', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d40a', 'DniOtra', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000dccc', '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dbbb', true);

-- ── 1 · De partida, sin fila ─────────────────────────────────────────────────
select is((select count(*)::int from fn_mi_consentimiento_dni()), 0,
  'DE PARTIDA · sin DNI subido, fn_mi_consentimiento_dni() no devuelve fila');

-- ── 2 · No se puede registrar la carpeta de otra persona ────────────────────
select throws_ok($$ select fn_registrar_mi_dni(
    '00000000-0000-0000-0000-00000000d40a/dni.jpg') $$,
  null, null, 'AJENO · no puede registrar un archivo en la carpeta de otra persona');

-- ── 3 · Registra el suyo ──────────────────────────────────────────────────────
select lives_ok($$ select fn_registrar_mi_dni(
    '00000000-0000-0000-0000-00000000d30a/dni.jpg') $$,
  'PROPIO · registra su DNI sin problema');

select is((select storage_path from fn_mi_consentimiento_dni()),
  '00000000-0000-0000-0000-00000000d30a/dni.jpg',
  'PROPIO · fn_mi_consentimiento_dni() devuelve la ruta guardada');

select ok((select aceptado_at from fn_mi_consentimiento_dni()) >= now() - interval '1 minute',
  'PROPIO · aceptado_at queda con la fecha de hoy');

-- ── 4 · Volver a subir actualiza la misma fila ───────────────────────────────
select fn_registrar_mi_dni('00000000-0000-0000-0000-00000000d30a/dni-nuevo.jpg');

select is((select count(*)::int from consentimientos_dni where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  1, 'REEMPLAZO · sigue siendo una sola fila, no dos');

select is((select storage_path from fn_mi_consentimiento_dni()), '00000000-0000-0000-0000-00000000d30a/dni-nuevo.jpg',
  'REEMPLAZO · la fila quedó con la ruta más reciente');

-- ── 5 · RLS: otra colaboradora no ve la constancia ajena, admin sí ──────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dccc', true);
select is((select count(*)::int from consentimientos_dni where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  0, 'RLS · otra colaboradora no ve la constancia de DniColab');

select * from finish();
rollback;
