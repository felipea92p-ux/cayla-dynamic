-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 345_la_bandeja_recuerda_lo_que_ya_viste.test.sql — 0436
-- ============================================================================
-- bandeja_vistos es una tabla mínima, no un flujo de negocio: no hay "pedir",
-- "atender" ni "resolver". Lo que hay que defender es más chico y más fácil
-- de romper sin darse cuenta: que marcar visto sea de verdad un upsert (no
-- duplica fila), que cada persona vea SOLO lo suyo (RLS), y que un tipo de
-- ítem inventado no entre calladito.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000345000', 'ZZ345', 'Sede de laboratorio', true)
on conflict (id) do nothing;

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  ('00000000-0000-0000-0000-000000345001', 'Prueba', 'Encargada345',
   '00000000-0000-0000-0000-000000345000', 'supervisor_sede', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000345011'),
  ('00000000-0000-0000-0000-000000345002', 'Prueba', 'OtraEncargada345',
   '00000000-0000-0000-0000-000000345000', 'supervisor_sede', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000345012');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000345011', true);

-- ── 1 · Marcar visto un ítem, sin haberlo visto antes ──────────────────────
select lives_ok(
  $$ select fn_bandeja_marcar_visto('revision', '00000000-0000-0000-0000-000000345101') $$,
  'OK · marcar visto un ítem nuevo no revienta');

select is(
  (select count(*)::int from bandeja_vistos
    where persona_id = '00000000-0000-0000-0000-000000345001'),
  1,
  'UNA FILA · quedó registrada la marca');

-- ── 2 · Volver a marcarlo es upsert, no una fila nueva ─────────────────────
select fn_bandeja_marcar_visto('revision', '00000000-0000-0000-0000-000000345101');
select is(
  (select count(*)::int from bandeja_vistos
    where persona_id = '00000000-0000-0000-0000-000000345001'),
  1,
  'UPSERT · marcar dos veces el mismo ítem sigue siendo una sola fila');

-- ── 3 · Otro tipo, u otro ítem, sí es una fila distinta ────────────────────
select fn_bandeja_marcar_visto('solicitud_vacacion', '00000000-0000-0000-0000-000000345102');
select is(
  (select count(*)::int from bandeja_vistos
    where persona_id = '00000000-0000-0000-0000-000000345001'),
  2,
  'DISTINTO ÍTEM · un tipo_item o item_id distinto sí agrega fila');

-- ── 4 · Un tipo de ítem que no existe no entra calladito ───────────────────
select throws_ok(
  $$ select fn_bandeja_marcar_visto('cosa_inventada', '00000000-0000-0000-0000-000000345103') $$,
  null, null,
  'RECHAZADO · un tipo_item fuera del catálogo de la zona "Por aprobar" no se guarda');

-- ── 5 · Aislada por RLS: otra persona no ve lo que yo marqué visto ─────────
-- `postgres` tiene BYPASSRLS (así conectan las migraciones), así que esta
-- comprobación solo es real si se hace como `authenticated` de verdad —
-- mismo patrón que ya usa 175_el_calendario_de_pago_lo_ve_cualquiera....
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000345012', true);
set role authenticated;
create temp table _ve_lo_de_otra as
  select count(*)::int as n from bandeja_vistos
   where persona_id = '00000000-0000-0000-0000-000000345001';
reset role;
select is(
  (select n from _ve_lo_de_otra),
  0,
  'AISLADA · la policy de select no deja ver las marcas de otra persona, aunque conozca su id');

-- ── 6 · Y tampoco puede marcar visto algo "a nombre de" otra persona ───────
-- (fn_bandeja_marcar_visto siempre usa fn_persona_actual_id(), nunca un
--  p_persona_id que alguien pudiera pasarle desde el navegador).
select fn_bandeja_marcar_visto('revision', '00000000-0000-0000-0000-000000345201');
select is(
  (select count(*)::int from bandeja_vistos
    where persona_id = '00000000-0000-0000-0000-000000345002'),
  1,
  'PROPIA · lo que marca queda a SU nombre, no al de la persona 345001');

-- ── 7 · Sin ficha enlazada, no marca nada ──────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000345999', true);
select throws_ok(
  $$ select fn_bandeja_marcar_visto('revision', '00000000-0000-0000-0000-000000345301') $$,
  null, null,
  'RECHAZADO · una cuenta sin persona enlazada no puede marcar nada visto');

select * from finish();
rollback;
