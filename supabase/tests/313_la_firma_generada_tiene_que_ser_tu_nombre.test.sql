-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 313_la_firma_generada_tiene_que_ser_tu_nombre.test.sql
-- ============================================================================
-- LO QUE CUIDA (0394): que una firma GENERADA (texto escrito, no escaneo) solo
-- se guarde si el texto se reconoce como el nombre de quien la guarda — para
-- que "jsdlaksj" no pase como firma de nadie.
--
-- Y que la firma ESCANEADA (sin texto) siga funcionando exactamente igual que
-- antes de esta migración: es la regresión que más importa, porque de eso
-- dependen política salarial, liquidaciones, documentación, contratos y la
-- ficha de personas.
-- ============================================================================
begin;
select plan(12);

-- ── 1 · fn_firma_texto_coincide, en aislamiento ─────────────────────────────
select ok(
  fn_firma_texto_coincide('Felipe M. Diaz', 'Felipe Manuel', 'Diaz Lopez'),
  'COINCIDE · el formato sugerido por la pantalla (nombre + inicial + apellido)');

select ok(
  fn_firma_texto_coincide('Felipe Diaz', 'Felipe Manuel', 'Diaz Lopez'),
  'COINCIDE · nombre y apellido completos, sin el segundo nombre');

select ok(
  fn_firma_texto_coincide('FELIPE MANUEL DIAZ LOPEZ', 'Felipe Manuel', 'Diaz Lopez'),
  'COINCIDE · el nombre completo en mayúsculas, palabra por palabra');

select ok(
  fn_firma_texto_coincide('Félipe Díaz', 'Felipe', 'Diaz'),
  'COINCIDE · las tildes no importan');

select ok(
  fn_firma_texto_coincide('Felipe Lopez', 'Felipe Manuel', 'Diaz Lopez'),
  'COINCIDE · vale firmar con el apellido materno en vez del paterno');

select ok(
  not fn_firma_texto_coincide('jsdlaksj', 'Felipe Manuel', 'Diaz Lopez'),
  'NO COINCIDE · una cadena que no reconoce ninguna palabra del nombre');

select ok(
  not fn_firma_texto_coincide('M. Diaz', 'Felipe Manuel', 'Diaz Lopez'),
  'NO COINCIDE · falta el primer nombre completo (una inicial no basta)');

select ok(
  not fn_firma_texto_coincide('Felipe Manuel', 'Felipe Manuel', 'Diaz Lopez'),
  'NO COINCIDE · falta un apellido completo');

select ok(
  not fn_firma_texto_coincide('Felipe Perez', 'Felipe Manuel', 'Diaz Lopez'),
  'NO COINCIDE · un apellido que no es el suyo, aunque el nombre sí lo sea');

-- ── 2 · fn_set_mi_firma con el texto de la firma ────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000fb00', 'ZZFIR3', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-00000000fb01', 'Felipe Manuel', 'Diaz Lopez',
   '00000000-0000-0000-0000-00000000fb00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-00000000fb09');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fb09', true);

select throws_ok(
  $$ select fn_set_mi_firma(
       'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
       'jsdlaksj') $$,
  null, null,
  'IMPOSIBLE · fn_set_mi_firma rechaza un texto que no es su nombre');

select lives_ok(
  $$ select fn_set_mi_firma(
       'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
       'Felipe M. Diaz') $$,
  'VÁLIDO · fn_set_mi_firma acepta el formato sugerido, que sí es su nombre');

-- ── 3 · Sin texto (el camino de siempre: subir un escaneo) sigue igual ──────
select lives_ok(
  $$ select fn_set_mi_firma(
       'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==') $$,
  'REGRESIÓN · sin p_texto_firma (como llaman política salarial, contratos, etc.) no se valida nada, igual que antes de la 0394');

select * from finish();
rollback;
