-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 358_la_bandeja_reconoce_los_items_de_educacion.test.sql — defiende la 0453
-- (y desde la 0461, también el tercer tipo que agregó esa migración)
-- ============================================================================
-- Qué defiende: que la versión vigente de `fn_bandeja_marcar_visto` acepta los
-- tres tipos de ítem de educación (dos de la 0450, uno de la 0461), sigue
-- siendo una sola, y sigue rechazando un tipo que no existe.
--
-- LO QUE ESTA PRUEBA NO PUEDE HACER, Y CONVIENE DECIRLO. El accidente que
-- motivó la 0453 fue de ORDEN DE PEGADO: la 0436 se re-pegó en producción
-- después de la 0450. CI construye la base aplicando las migraciones en orden
-- numérico, así que ese estado nunca se forma aquí — en CI esta prueba
-- pasaría incluso sin la 0453, porque la 0450 ya deja la función bien.
--
-- Lo que sí caza, y por eso existe: al siguiente que reescriba esta función
-- partiendo de una versión que no sea la última. Quien copie el cuerpo de la
-- 0436 o de la 0450 —anteriores a la que agrega el tercer tipo— pierde uno de
-- los tipos, y las aserciones 3-5 se ponen en rojo. Es el accidente que
-- `donde-vive.sh` existe para evitar, y el mismo defecto que se coló en
-- producción por la otra puerta.
--
-- El marcador de la aserción 1 se actualiza con cada migración que vuelve a
-- tocar esta función (0453 lo dejó en «CAMBIO 0450»; la 0461 lo deja en
-- «CAMBIO 0461»): es un canario de «partiste de la última versión», no una
-- promesa de que ese texto exacto sobreviva para siempre.
--
-- Por qué la 6 exige el mensaje exacto: la función tiene DOS excepciones que
-- levantan P0001 —«tu cuenta no está enlazada» y «tipo no reconocido»—. Con
-- solo el código, un fallo de sesión haría pasar la prueba por el motivo
-- equivocado. Las 3 y 4 demuestran además que la sesión sí resuelve.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre)
values ('aaaaaaaa-0453-0000-0000-000000000001', 'T58', 'Sede de la prueba 358');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0453-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'prueba358@cayla.local', 'x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('cccccccc-0453-0000-0000-000000000001', 'Bea', 'Bandeja',
        'aaaaaaaa-0453-0000-0000-000000000001', 'x', 'admin', 'bbbbbbbb-0453-0000-0000-000000000001');

set local request.jwt.claims = '{"sub":"bbbbbbbb-0453-0000-0000-000000000001","role":"authenticated"}';

-- ── 1-2 · La vigente es la de la 0461, y es una sola ────────────────────────
select ok(
  (select prosrc like '%CAMBIO 0461%' from pg_proc where proname = 'fn_bandeja_marcar_visto'),
  '0461: la versión vigente de fn_bandeja_marcar_visto es la de la 0461, no una anterior');

select is(
  (select count(*)::int from pg_proc where proname = 'fn_bandeja_marcar_visto'),
  1,
  '0453/0461: una sola versión — ninguna sobrecarga olvidada');

-- ── 3-6 · Los tres tipos de educación se aceptan y se guardan ───────────────
select lives_ok(
  $$ select fn_bandeja_marcar_visto('entrega_educacion', 'dddddddd-0453-0000-0000-000000000001') $$,
  '0453: una entrega de constancia de estudios se puede marcar como vista');

select lives_ok(
  $$ select fn_bandeja_marcar_visto('aviso_fin_educacion', 'dddddddd-0453-0000-0000-000000000002') $$,
  '0453: un aviso de fin de estudios se puede marcar como visto');

select lives_ok(
  $$ select fn_bandeja_marcar_visto('solicitud_educacion', 'dddddddd-0453-0000-0000-000000000004') $$,
  '0461: una solicitud de apoyo educativo se puede marcar como vista');

select is(
  (select count(*)::int from bandeja_vistos
    where persona_id = 'cccccccc-0453-0000-0000-000000000001'
      and tipo_item in ('entrega_educacion', 'aviso_fin_educacion', 'solicitud_educacion')),
  3,
  '0453/0461: y los tres quedaron guardados — no se tragó la excepción por el camino');

-- ── 7 · Un tipo inventado se sigue rechazando, con su mensaje ──────────────
select throws_ok(
  $$ select fn_bandeja_marcar_visto('tipo_inventado', 'dddddddd-0453-0000-0000-000000000003') $$,
  'P0001',
  'Tipo de ítem de Bandeja no reconocido: tipo_inventado',
  '0453: un tipo que no existe se sigue rechazando — la guarda no se aflojó al ampliarla');

select * from finish();
rollback;
