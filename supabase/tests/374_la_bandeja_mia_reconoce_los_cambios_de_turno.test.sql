-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 374_la_bandeja_mia_reconoce_los_cambios_de_turno.test.sql — defiende la 0473
-- ============================================================================
-- Qué defiende: que la versión vigente de `fn_bandeja_marcar_visto` acepta
-- 'cambio_turno' además de los ocho tipos anteriores, sigue siendo una sola
-- función, y sigue rechazando un tipo inventado. Mismo molde que la 358, que
-- defendió lo mismo para los tipos de educación de la 0453/0461.
--
-- Lo que caza: al siguiente que reescriba esta función partiendo de una
-- versión anterior a la 0473 — el mismo accidente de "copiar de la penúltima"
-- que `donde-vive.sh` existe para evitar.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre)
values ('aaaaaaaa-0473-0000-0000-000000000001', 'T74', 'Sede de la prueba 374');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0473-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'prueba374@cayla.local', 'x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('cccccccc-0473-0000-0000-000000000001', 'Tomás', 'Turno',
        'aaaaaaaa-0473-0000-0000-000000000001', 'x', 'integrante', 'bbbbbbbb-0473-0000-0000-000000000001');

set local request.jwt.claims = '{"sub":"bbbbbbbb-0473-0000-0000-000000000001","role":"authenticated"}';

-- ── 1-2 · La vigente es la de la 0473, y es una sola ────────────────────────
select ok(
  (select prosrc like '%CAMBIO 0473%' from pg_proc where proname = 'fn_bandeja_marcar_visto'),
  '0473: la versión vigente de fn_bandeja_marcar_visto es la de la 0473, no una anterior');

select is(
  (select count(*)::int from pg_proc where proname = 'fn_bandeja_marcar_visto'),
  1,
  '0473: una sola versión — ninguna sobrecarga olvidada');

-- ── 3-5 · 'cambio_turno' se acepta, se guarda, y no rompe un tipo viejo ─────
select lives_ok(
  $$ select fn_bandeja_marcar_visto('cambio_turno', 'dddddddd-0473-0000-0000-000000000001') $$,
  '0473: un cambio de turno se puede marcar como visto');

select lives_ok(
  $$ select fn_bandeja_marcar_visto('revision_movilidad', 'dddddddd-0473-0000-0000-000000000002') $$,
  '0473: un tipo de una migración anterior (revision_movilidad) se sigue aceptando');

select is(
  (select count(*)::int from bandeja_vistos
    where persona_id = 'cccccccc-0473-0000-0000-000000000001'
      and tipo_item in ('cambio_turno', 'revision_movilidad')),
  2,
  '0473: y los dos quedaron guardados — no se tragó la excepción por el camino');

-- ── 6 · Un tipo inventado se sigue rechazando, con su mensaje ──────────────
select throws_ok(
  $$ select fn_bandeja_marcar_visto('tipo_inventado', 'dddddddd-0473-0000-0000-000000000003') $$,
  'P0001',
  'Tipo de ítem de Bandeja no reconocido: tipo_inventado',
  '0473: un tipo que no existe se sigue rechazando — la guarda no se aflojó al ampliarla');

select * from finish();
rollback;
