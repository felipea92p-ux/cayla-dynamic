-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 312_cualquiera_guarda_su_propia_firma.test.sql
-- ============================================================================
-- LO QUE CUIDA (0393): que `fn_set_mi_firma` deje entrar a CUALQUIER persona
-- con sesión (no solo admin/líder), porque ahora también sirve para que una
-- colaboradora genere la firma que va a llevar SU PROPIO contrato — no solo
-- para quien firma documentos en nombre de la empresa.
--
-- Y que lo que NO tenía que cambiar, no haya cambiado:
--   · la terminal de sede (sin fila en `personas`) sigue sin poder guardar nada;
--   · admin/líder —el caso de antes— sigue funcionando igual;
--   · cada quien sigue viendo (`fn_mi_firma`) SOLO la suya, nunca la ajena;
--   · el formato inválido y `null` (borrar) siguen comportándose igual.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000fa00', 'ZZFIR2', 'Sede de laboratorio', true);

-- Una integrante cualquiera: el caso que la 0065 dejaba afuera a propósito.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-00000000fa01', 'FirmaIntegrante', 'Laboratorio',
   '00000000-0000-0000-0000-00000000fa00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-00000000fa09'),
  ('00000000-0000-0000-0000-00000000fa02', 'FirmaOtraIntegrante', 'Laboratorio',
   '00000000-0000-0000-0000-00000000fa00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-00000000fa08'),
  ('00000000-0000-0000-0000-00000000fa03', 'FirmaAdmin', 'Laboratorio',
   '00000000-0000-0000-0000-00000000fa00', 'admin', 'test-hash',
   '00000000-0000-0000-0000-00000000fa07');
set session_replication_role = origin;

-- ── 1 · Una integrante (no admin/líder) guarda su propia firma ──────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa09', true);

select lives_ok(
  $$ select fn_set_mi_firma(
       'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==') $$,
  'VÁLIDO · una integrante sí puede guardar su propia firma (antes de la 0393, esto solo lo dejaba admin/líder)');

select ok(
  (select fn_mi_firma()) like 'data:image/%',
  'VÁLIDO · y fn_mi_firma() se la devuelve de vuelta');

-- ── 2 · Admin sigue pudiendo, igual que antes ───────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa07', true);

select lives_ok(
  $$ select fn_set_mi_firma(
       'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==') $$,
  'REGRESIÓN · admin sigue pudiendo guardar la suya, como antes de la 0393');

-- ── 3 · La terminal (sin fila en personas) sigue sin poder ──────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000fe', true);

select throws_ok(
  $$ select fn_set_mi_firma('data:image/png;base64,AAAA') $$,
  null, null,
  'IMPOSIBLE · una identidad sin fila en personas (la terminal) no guarda nada');

-- ── 4 · El formato inválido sigue rechazándose ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa08', true);

select throws_ok(
  $$ select fn_set_mi_firma('esto no es una imagen') $$,
  null, null,
  'IMPOSIBLE · un valor que no es una data-url de imagen se rechaza igual que antes');

-- ── 5 · Cada quien ve SOLO la suya ───────────────────────────────────────────
-- FirmaOtraIntegrante nunca guardó nada: no puede heredar la de FirmaIntegrante.
select is(
  (select fn_mi_firma()),
  null::text,
  'AISLADA · una integrante sin firma propia no ve la de otra persona');

-- ── 6 · null sigue borrando ──────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fa09', true);
select fn_set_mi_firma(null);

select is(
  (select fn_mi_firma()),
  null::text,
  'BORRA · pasar null sigue quitando la firma guardada, igual que antes de la 0393');

select * from finish();
rollback;
