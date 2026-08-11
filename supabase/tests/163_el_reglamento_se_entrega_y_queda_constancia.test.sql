-- ============================================================================
-- 163_el_reglamento_se_entrega_y_queda_constancia.test.sql
-- ============================================================================
-- Defiende la 0208, y en particular las tres cosas que la hacen valer como
-- PRUEBA y no como una tabla de documentos:
--
--   · Que la constancia diga QUÉ VERSIÓN se recibió. Un cargo firmado a mano
--     dice que recibiste «un» reglamento; no dice cuál. El día que el v4.0
--     sustituya al v3.0, esa es la única diferencia que importa.
--   · Que la fecha de la primera constancia NO se pueda pisar. Es lo que
--     prueba, y volver a escribirla la borraría.
--   · Que la vía en papel exija el papel. Aquí la constancia ES la prueba: una
--     fila sin escaneo detrás es sólo la afirmación de quien la escribió.
--
-- POR QUÉ SE PRUEBA LA VÍA EN PAPEL Y NO SÓLO LA DE PANTALLA
--   Medido en producción el 2026-08-10: de 24 personas activas, 17 tienen
--   cuenta y 7 no. Casi un tercio del equipo no puede entrar al panel. Si esta
--   mitad se rompiera, la prueba quedaría incompleta justo donde más se mira,
--   y ninguna prueba de la vía de pantalla lo notaría.
--
-- POR QUÉ SE PRUEBA EL PERMISO Y NO SÓLO QUE LA FUNCIÓN EXISTA
--   Desde la 0076 este proyecto revoca el EXECUTE que Postgres da a PUBLIC, así
--   que una función nueva nace sin permiso para `authenticated`. Olvidarlo no
--   da error al aplicar la migración: da una pantalla vacía. Es lo que la 0204
--   tuvo que reponer, y lo que ninguna prueba cazó porque todas corrían como
--   dueño de la base. Ésta cambia de rol a propósito.
-- ============================================================================
begin;
select plan(12);

-- ── Escenario ───────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000d200', 'ZZDOC', 'Sede de laboratorio', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('dd000000-0000-0000-0000-0000000000d1',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.doc@laboratorio.local', '', now(), now()),
       ('dd000000-0000-0000-0000-0000000000d2',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'integrante.doc@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol,
                      auth_user_id, tipo_vinculo, estado)
values ('00000000-0000-0000-0000-00000000d201', 'DocAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000d200', 'test-hash', 'admin',
        'dd000000-0000-0000-0000-0000000000d1', 'planilla', 'activo'),
       ('00000000-0000-0000-0000-00000000d202', 'DocIntegrante', 'Laboratorio',
        '00000000-0000-0000-0000-00000000d200', 'test-hash', 'integrante',
        'dd000000-0000-0000-0000-0000000000d2', 'planilla', 'activo'),
       -- Sin cuenta: el caso de las 7 personas medidas en producción.
       ('00000000-0000-0000-0000-00000000d203', 'DocSinCuenta', 'Laboratorio',
        '00000000-0000-0000-0000-00000000d200', 'test-hash', 'integrante',
        null, 'planilla', 'activo');
set session_replication_role = origin;

-- ── 1 · El navegador puede ejecutar las cinco funciones ─────────────────────
-- La comprobación que la 0204 enseñó a hacer: existir no basta.
select ok(
  bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  'Las cinco funciones son ejecutables por authenticated'
)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('fn_publicar_documento', 'fn_acusar_documento',
                    'fn_registrar_acuse_papel', 'fn_documentos_vigentes',
                    'fn_acuses_documento');

-- ── 2 · Publicar es de la Gerencia ──────────────────────────────────────────
set local role authenticated;
set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d2","role":"authenticated"}';

select throws_ok(
  $$ select fn_publicar_documento('rit', 'RIT', 'texto cualquiera') $$,
  null,
  'Una integrante no puede publicar un documento institucional');

-- ── 3 · La administradora sí, y arranca en la versión 1 ─────────────────────
set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d1","role":"authenticated"}';

select is(
  fn_publicar_documento('rit', 'Reglamento Interno de Trabajo', 'TEXTO v4.0'),
  1,
  'La primera publicación es la versión 1');

-- ── 4 · El mismo texto NO crea versión nueva ────────────────────────────────
-- Republicar sin cambios obligaría a las 24 personas a dejar constancia otra
-- vez de algo que no cambió, y una constancia pedida sin motivo enseña que la
-- constancia es trámite.
select is(
  fn_publicar_documento('rit', 'Reglamento Interno de Trabajo', 'TEXTO v4.0'),
  1,
  'Publicar el mismo texto devuelve la versión que ya existía');

-- ── 5 · Un texto distinto sí ────────────────────────────────────────────────
select is(
  fn_publicar_documento('rit', 'Reglamento Interno de Trabajo', 'TEXTO v4.1'),
  2,
  'Un texto distinto crea la versión siguiente');

-- ── 6 · El texto queda CONGELADO, no se regenera ────────────────────────────
select is(
  (select documento from documentos_institucionales where tipo = 'rit' and version = 1),
  'TEXTO v4.0',
  'La versión 1 conserva su texto aunque exista la 2');

-- ── 7 · La constancia propia ────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d2","role":"authenticated"}';

select lives_ok(
  $$ select fn_acusar_documento(
       (select id from documentos_institucionales where tipo='rit' and version=2),
       'Doc Integrante') $$,
  'Una integrante puede dejar constancia de la versión vigente');

-- ── 8 · Y no se puede pisar ─────────────────────────────────────────────────
select fn_acusar_documento(
  (select id from documentos_institucionales where tipo='rit' and version=2),
  'Nombre Distinto');

select is(
  (select nombre_declarado from documentos_acuses
    where persona_id = '00000000-0000-0000-0000-00000000d202'),
  'Doc Integrante',
  'Volver a acusar no pisa la constancia original');

-- ── 9 · La constancia es POR VERSIÓN ────────────────────────────────────────
-- Es lo que un cargo de papel no puede probar.
select is(
  (select count(*)::int from documentos_acuses a
    join documentos_institucionales d on d.id = a.documento_id
   where a.persona_id = '00000000-0000-0000-0000-00000000d202' and d.version = 1),
  0,
  'Haber acusado la versión 2 no cuenta como haber acusado la 1');

-- ── 10 · El seguimiento es sólo para quien manda ────────────────────────────
select is(
  (select count(*)::int from fn_acuses_documento(
     (select id from documentos_institucionales where tipo='rit' and version=2))),
  0,
  'Una integrante no ve quién falta por dejar constancia');

reset role;
reset request.jwt.claims;
set local role authenticated;
set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d1","role":"authenticated"}';

-- ── 11 · Sin papel no hay constancia en papel ───────────────────────────────
select throws_ok(
  $$ select fn_registrar_acuse_papel(
       (select id from documentos_institucionales where tipo='rit' and version=2),
       '00000000-0000-0000-0000-00000000d203', '   ') $$,
  null,
  'La vía en papel exige el escaneo del cargo firmado');

-- ── 12 · Con el papel, quien no tiene cuenta queda cubierta ─────────────────
select fn_registrar_acuse_papel(
  (select id from documentos_institucionales where tipo='rit' and version=2),
  '00000000-0000-0000-0000-00000000d203',
  'rit/v2/sincuenta-cargo.jpg',
  now() - interval '1 day',
  'entregado en la tienda');

select is(
  (select via from documentos_acuses
    where persona_id = '00000000-0000-0000-0000-00000000d203'),
  'papel',
  'Quien no tiene cuenta deja constancia por la vía en papel');

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
