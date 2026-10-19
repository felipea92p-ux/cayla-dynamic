-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 431_el_dni_de_quien_esta_de_prueba.test.sql — 0538
-- ============================================================================
-- Qué fija esta prueba, en orden de importancia:
--   · La líder de equipo puede escribir y cargar el DNI SOLO de quien está de
--     prueba en SU sede. No de otra sede, no de alguien de planilla de su propia
--     sede, y un integrante no puede de nadie.
--   · El DNI entra por la puerta de siempre: queda una solicitud aprobada, las
--     columnas de `datos_personales` y la fila de auditoría.
--   · La lectura no se tocó: la líder ya leía los archivos de su sede (para poder
--     aprobar) y sigue sin leer los de otra.
--   · Quién cerró pruebas hace poco se ve (y solo lo ve quien puede actuar).
-- ============================================================================
begin;
select plan(30);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000431a01', 'ZZDN1', 'Sede de laboratorio 1', true),
  ('00000000-0000-0000-0000-000000431a02', 'ZZDN2', 'Sede de laboratorio 2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000431b01', 'Admin',      'Lab', '00000000-0000-0000-0000-000000431a01', 'admin',           'x', '00000000-0000-0000-0000-000000431c01', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000431b02', 'LiderUno',   'Lab', '00000000-0000-0000-0000-000000431a01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000431c02', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000431b03', 'LiderDos',   'Lab', '00000000-0000-0000-0000-000000431a02', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000431c03', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000431b04', 'Integrante', 'Lab', '00000000-0000-0000-0000-000000431a01', 'integrante',      'x', '00000000-0000-0000-0000-000000431c04', '2024-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000431d01', 'PruebaUno', 'Lab', '00000000-0000-0000-0000-000000431a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000431d02', 'PruebaDos', 'Lab', '00000000-0000-0000-0000-000000431a02', 'integrante', 'x', '2026-10-01', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000431d03', 'DePlanilla','Lab', '00000000-0000-0000-0000-000000431a01', 'integrante', 'x', '2024-02-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000431d04', 'PruebaCierra','Lab','00000000-0000-0000-0000-000000431a01', 'integrante', 'x', '2026-10-01', 'activo', 'prueba');

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

-- ── 1 · El permiso de escribir en la carpeta de cada quien ──────────────────
select pg_temp.como('00000000-0000-0000-0000-000000431c02');   -- líder de la sede 1
select ok(fn_solicitud_perfil_puede_escribir('solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-1.jpg') is true,
  'ESCRIBIR · la líder sube el DNI de alguien de prueba de su sede');
select ok(fn_solicitud_perfil_puede_escribir('solicitud/00000000-0000-0000-0000-000000431d02/dni-anverso-1.jpg') is not true,
  'ESCRIBIR · no el de alguien de prueba de otra sede');
select ok(fn_solicitud_perfil_puede_escribir('solicitud/00000000-0000-0000-0000-000000431d03/dni-anverso-1.jpg') is not true,
  'ESCRIBIR · ni el de alguien de planilla de su propia sede: ese lo sube cada quien');
select ok(fn_solicitud_perfil_puede_escribir('solicitud/00000000-0000-0000-0000-000000431b02/dni-anverso-1.jpg') is true,
  'ESCRIBIR · y por supuesto su propia carpeta');
select ok(fn_solicitud_perfil_puede_escribir('otra-carpeta/00000000-0000-0000-0000-000000431d01/dni.jpg') is not true,
  'ESCRIBIR · una carpeta que no es «solicitud» no pasa');

select pg_temp.como('00000000-0000-0000-0000-000000431c04');   -- un integrante
select ok(fn_solicitud_perfil_puede_escribir('solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-1.jpg') is not true,
  'ESCRIBIR · un integrante no sube el DNI de nadie');

select pg_temp.como('00000000-0000-0000-0000-000000431c01');   -- la admin
select ok(fn_solicitud_perfil_puede_escribir('solicitud/00000000-0000-0000-0000-000000431d03/dni-anverso-1.jpg') is true,
  'ESCRIBIR · administración sigue pudiendo con cualquiera, como antes');

-- ── 2 · La lectura no se tocó ───────────────────────────────────────────────
-- La líder ya leía los archivos de su sede (para poder aprobar una solicitud);
-- eso es de antes y sigue igual. Lo que no puede es leer los de OTRA sede.
select pg_temp.como('00000000-0000-0000-0000-000000431c02');
select ok(fn_solicitud_perfil_puede_leer('solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-1.jpg') is true,
  'LEER · como antes: la líder lee los archivos de la gente de su sede');
select ok(fn_solicitud_perfil_puede_leer('solicitud/00000000-0000-0000-0000-000000431d02/dni-anverso-1.jpg') is not true,
  'LEER · y no los de otra sede');
-- ── 3 · Cargar el DNI de quien está de prueba ───────────────────────────────
select throws_like(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d02', 'solicitud/00000000-0000-0000-0000-000000431d02/a.jpg', 'solicitud/00000000-0000-0000-0000-000000431d02/b.jpg') $$,
  '%No puedes cargar%', 'CARGAR · la líder no carga el DNI de otra sede');
select throws_like(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d03', 'solicitud/00000000-0000-0000-0000-000000431d03/a.jpg', 'solicitud/00000000-0000-0000-0000-000000431d03/b.jpg') $$,
  '%solo para quien está de prueba%', 'CARGAR · ni el de alguien de planilla de su sede');
select throws_like(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d01', 'solicitud/00000000-0000-0000-0000-000000431d01/a.jpg', null) $$,
  '%las dos caras%', 'CARGAR · hacen falta las dos caras');
select throws_like(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d01', 'solicitud/00000000-0000-0000-0000-000000431d01/a.jpg', 'solicitud/00000000-0000-0000-0000-000000431d01/a.jpg') $$,
  '%la misma imagen%', 'CARGAR · el anverso y el reverso no pueden ser la misma imagen');
select throws_like(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d01', 'solicitud/00000000-0000-0000-0000-000000431d02/a.jpg', 'solicitud/00000000-0000-0000-0000-000000431d02/b.jpg') $$,
  '%carpeta de esa persona%', 'CARGAR · los archivos tienen que estar en la carpeta de ESA persona, no en la de otra');

select lives_ok(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d01', 'solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-1.jpg', 'solicitud/00000000-0000-0000-0000-000000431d01/dni-reverso-1.jpg') $$,
  'CARGAR · la líder carga las dos caras de alguien de prueba de su sede');
select is(
  (select foto_dni_anverso_ruta || ' | ' || foto_dni_reverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-000000431d01'),
  'solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-1.jpg | solicitud/00000000-0000-0000-0000-000000431d01/dni-reverso-1.jpg',
  'CARGAR · quedan en su ficha, por la puerta de siempre');
select is(
  (select estado || '/' || resuelta_por::text from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-000000431d01' and campo = 'foto_dni'),
  'aprobado/00000000-0000-0000-0000-000000431b02', 'CARGAR · como solicitud ya aprobada, con quién la aprobó (el historial de siempre)');
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000431d01' and campo_modificado = 'datos_personales.foto_dni'
      and corregido_por = '00000000-0000-0000-0000-000000431b02'),
  1, 'CARGAR · y deja su fila de auditoría');
select ok(fn_solicitud_perfil_ruta_congelada('solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-1.jpg'),
  'CARGAR · lo aprobado queda congelado: nadie lo pisa');

-- Una segunda carga NO pisa la anterior: es otra solicitud, con otro nombre de archivo.
select lives_ok(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d01', 'solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-2.jpg', 'solicitud/00000000-0000-0000-0000-000000431d01/dni-reverso-2.jpg') $$,
  'CARGAR · se puede volver a cargar (foto borrosa): es otra solicitud');
select is(
  (select foto_dni_anverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-000000431d01'),
  'solicitud/00000000-0000-0000-0000-000000431d01/dni-anverso-2.jpg', 'CARGAR · y la ficha queda con la última');

select pg_temp.como('00000000-0000-0000-0000-000000431c04');   -- un integrante
select throws_like(
  $$ select fn_prueba_cargar_dni('00000000-0000-0000-0000-000000431d01', 'solicitud/00000000-0000-0000-0000-000000431d01/a.jpg', 'solicitud/00000000-0000-0000-0000-000000431d01/b.jpg') $$,
  '%No puedes cargar%', 'CARGAR · un integrante no puede');

-- ── 4 · Quién cerró pruebas hace poco ───────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-000000431c02');   -- la líder de la sede 1
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado, entrada_ts, salida_final_ts) values
  ('00000000-0000-0000-0000-000000431d04', '2026-10-02', '00000000-0000-0000-0000-000000431a01', 5.5, 'cerrada', '2026-10-02 09:00-05', '2026-10-02 15:30-05');
select lives_ok(
  $$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000431d04', 'retirado', 'Dijo que no volvía') $$,
  'CIERRES · la líder cierra una prueba');
select is((select count(*)::int from fn_pruebas_cierres_recientes()), 1,
  'CIERRES · y ella misma ve su cierre');
select is((select decidida_por || '/' || resultado || '/' || horas_marcadas::text from fn_pruebas_cierres_recientes()),
  'LiderUno Lab/retirado/5.50', 'CIERRES · con quién lo decidió y las horas que quedaron marcadas (las de «se retiró» no se pagan)');

select pg_temp.como('00000000-0000-0000-0000-000000431c03');   -- la líder de la OTRA sede
select is((select count(*)::int from fn_pruebas_cierres_recientes()), 0,
  'CIERRES · la líder de otra sede no los ve');

select pg_temp.como('00000000-0000-0000-0000-000000431c01');   -- la admin
select is((select count(*)::int from fn_pruebas_cierres_recientes()), 1,
  'CIERRES · administración ve los de todas las sedes');
update pruebas set cerrada_at = now() - interval '3 days' where persona_id = '00000000-0000-0000-0000-000000431d04';
select is((select count(*)::int from fn_pruebas_cierres_recientes(48)), 0,
  'CIERRES · pasadas las 48 horas ya no salen');
select is((select count(*)::int from fn_pruebas_cierres_recientes(120)), 1,
  'CIERRES · pero sí si se piden más horas');
select ok(not has_function_privilege('anon', 'fn_pruebas_cierres_recientes(integer)', 'execute')
          and not has_function_privilege('anon', 'fn_prueba_cargar_dni(uuid, text, text)', 'execute'),
  'SEGURIDAD · sin sesión no se ejecuta ninguna de las dos');

select * from finish();
rollback;
