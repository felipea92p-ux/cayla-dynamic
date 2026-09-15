-- ============================================================================
-- 364_restaurar_una_version_anterior.test.sql
-- ============================================================================
-- Defiende la 0460. En particular:
--
--   · Que restaurar SÍ cree una versión nueva (a diferencia de republicar el
--     mismo texto con fn_publicar_documento, que no crea nada).
--   · Que el correlativo se recalcule al momento de restaurar, no antes.
--   · Que solo DO pueda restaurar.
--   · Que no se pueda "restaurar" la versión que ya es la vigente.
--   · Que la versión restaurada nazca SIN constancias — no hereda las de la
--     versión de la que viene.
-- ============================================================================
begin;
select plan(8);

-- ── Escenario ───────────────────────────────────────────────────────────────
insert into documentos_tipos (codigo, nombre, orden, requiere_acuse)
values ('zz_restaurar', 'Documento de laboratorio (restaurar)', 999, true);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000d300', 'ZZRST', 'Sede de laboratorio', true);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        created_at, updated_at)
values ('dd000000-0000-0000-0000-0000000000d4',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'admin.rst@laboratorio.local', '', now(), now()),
       ('dd000000-0000-0000-0000-0000000000d5',
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
        'integrante.rst@laboratorio.local', '', now(), now());

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol,
                      auth_user_id, tipo_vinculo, estado)
values ('00000000-0000-0000-0000-00000000d301', 'RstAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000d300', 'test-hash', 'admin',
        'dd000000-0000-0000-0000-0000000000d4', 'planilla', 'activo'),
       ('00000000-0000-0000-0000-00000000d302', 'RstIntegrante', 'Laboratorio',
        '00000000-0000-0000-0000-00000000d300', 'test-hash', 'integrante',
        'dd000000-0000-0000-0000-0000000000d5', 'planilla', 'activo');
set session_replication_role = origin;

set local role authenticated;
set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d4","role":"authenticated"}';

-- v1 y v2, con v2 vigente.
select fn_publicar_documento('zz_restaurar', 'Documento de laboratorio', 'TEXTO v1 — correcto');
select fn_publicar_documento('zz_restaurar', 'Documento de laboratorio', 'TEXTO v2 — con un error');

-- Alguien deja constancia de la v2, la que tiene el error.
set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d5","role":"authenticated"}';
select fn_acusar_documento(
  (select id from documentos_institucionales where tipo='zz_restaurar' and version=2),
  'Rst Integrante');

set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d4","role":"authenticated"}';

-- ── 1 · Restaurar exige DO ──────────────────────────────────────────────────
set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d5","role":"authenticated"}';

select throws_ok(
  $$ select fn_restaurar_documento(
       (select id from documentos_institucionales where tipo='zz_restaurar' and version=1)) $$,
  null,
  'Una integrante no puede restaurar una version');

set local request.jwt.claims = '{"sub":"dd000000-0000-0000-0000-0000000000d4","role":"authenticated"}';

-- ── 2 · No se puede "restaurar" la vigente ──────────────────────────────────
select throws_ok(
  $$ select fn_restaurar_documento(
       (select id from documentos_institucionales where tipo='zz_restaurar' and version=2)) $$,
  null,
  'No se puede restaurar la version que ya es la vigente');

-- ── 3 · Restaurar la v1 crea la v3 (no pisa nada) ───────────────────────────
select is(
  fn_restaurar_documento(
    (select id from documentos_institucionales where tipo='zz_restaurar' and version=1)),
  3,
  'Restaurar la v1 crea la version 3, no reescribe ninguna fila existente');

-- ── 4 · El texto restaurado es el de la v1, no el de la v2 ──────────────────
select is(
  (select documento from documentos_institucionales where tipo='zz_restaurar' and version=3),
  'TEXTO v1 — correcto',
  'La version restaurada lleva el texto de la version de origen');

-- ── 5 · Las versiones 1 y 2 siguen intactas ─────────────────────────────────
select is(
  (select documento from documentos_institucionales where tipo='zz_restaurar' and version=2),
  'TEXTO v2 — con un error',
  'Restaurar no toca el texto de la version vigente anterior');

-- ── 6 · La nota deja dicho de dónde viene ───────────────────────────────────
select matches(
  (select notas from documentos_institucionales where tipo='zz_restaurar' and version=3),
  '^Restaurada de la version 1',
  'La version restaurada explica de qué version viene');

-- ── 7 · La v3 nace SIN constancias, aunque la v2 sí tenía ───────────────────
select is(
  (select count(*)::int from documentos_acuses a
    join documentos_institucionales d on d.id = a.documento_id
   where d.tipo = 'zz_restaurar' and d.version = 3),
  0,
  'La version restaurada no hereda las constancias de la version anterior');

-- ── 8 · fn_documentos_vigentes ahora ve la v3 como la vigente ──────────────
select is(
  (select version from fn_documentos_vigentes() where tipo = 'zz_restaurar'),
  3,
  'La version restaurada pasa a ser la vigente, por ser la de mayor numero');

reset role;
reset request.jwt.claims;

select * from finish();
rollback;
