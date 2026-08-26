-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 237_la_negativa_a_firmar_entrega_el_documento.test.sql
-- ============================================================================
-- Numeral 55.4 del Reglamento: «Si la colaboradora se niega a firmar, se
-- levanta acta de negativa suscrita por quien entrega y por un testigo. El acta
-- produce los mismos efectos que el cargo firmado».
--
-- Hasta la 0303 no los producía. El acta se subía como adjunto y el documento
-- se quedaba en `firmado`; y desde que la 0213 y la 0246 pasaron la escalera a
-- medir por `entregado_at`, un memo con acta de negativa DESAPARECÍA del
-- escalón: no agravaba, no contaba como peldaño, y la siguiente sanción de esa
-- persona volvía a salir desde abajo.
--
-- Lo que fija esta prueba:
--   · Con acta y testigo, el documento queda ENTREGADO y AGRAVA igual que uno
--     firmado — que es el punto entero.
--   · Sin testigo no se entrega: un acta sin quien la atestigüe no es un acta.
--   · UN testigo basta (numeral 55.4), y no dos: los dos son del artículo 38 l)
--     y del 60, que regulan otra cosa.
--   · El testigo puede no tener usuario en el sistema.
--   · Y los medios de siempre siguen funcionando.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000ac001', 'ZZNEG', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000ac002', 'AdminNeg', 'Lab',
        '00000000-0000-0000-0000-0000000ac001', 'admin', 'x',
        '00000000-0000-0000-0000-0000000ac0a2', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000ac003', 'SeNego',  'Lab', '00000000-0000-0000-0000-0000000ac001', 'x', '2024-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-0000000ac004', 'Testigo', 'Lab', '00000000-0000-0000-0000-0000000ac001', 'x', '2024-01-01', 'activo', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ac0a2', true);

-- Una amonestación firmada, lista para entregar.
create function pg_temp.firmada(p_corr text) returns uuid language sql as $$
  insert into expediente_disciplinario
    (persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos,
     firmante_id, firmado_at, correlativo, creado_por)
  values ('00000000-0000-0000-0000-0000000ac003', 'tardanza', 'amonestacion', 'firmado',
          fn_hoy_lima() - 5, fn_hoy_lima() - 5, '[]'::jsonb,
          '00000000-0000-0000-0000-0000000ac002', now(), p_corr,
          '00000000-0000-0000-0000-0000000ac002')
  returning id;
$$;

-- ── Antes: firmado y sin entregar, no agrava ───────────────────────────────
create temp table _d as select pg_temp.firmada('NEG/001') as id;

select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-0000000ac003')),
          'amonestacion',
          'ART. 56.2 · firmado y sin entregar todavía no agrava');

-- ── Sin testigo, no se entrega ─────────────────────────────────────────────
select throws_like(
  format($$ select fn_expediente_entregar(%L, 'acta_negativa', now(), null, null) $$, (select id from _d)),
  '%numeral 55.4%',
  '55.4 · un acta sin testigo no entrega nada, y el error dice por qué');

select throws_like(
  format($$ select fn_expediente_entregar(%L, 'acta_negativa', now(), '   ', null) $$, (select id from _d)),
  '%numeral 55.4%',
  '55.4 · ni con un nombre en blanco');

select is((select estado from expediente_disciplinario where id = (select id from _d)),
          'firmado', 'Y el documento sigue firmado, sin quedar a medias');

-- ── Con acta y UN testigo, se entrega ──────────────────────────────────────
select lives_ok(
  format($$ select fn_expediente_entregar(%L, 'acta_negativa', now(), 'Testigo Lab',
              '00000000-0000-0000-0000-0000000ac004') $$, (select id from _d)),
  '55.4 · con quien entrega y UN testigo, el acta entrega el documento');

select is(
  (select estado || '/' || medio_entrega || '/' || entrega_testigo_nombre
     from expediente_disciplinario where id = (select id from _d)),
  'entregado/acta_negativa/Testigo Lab',
  'Queda ENTREGADO, con su medio y su testigo en la fila');

select is((select entregado_por from expediente_disciplinario where id = (select id from _d)),
          '00000000-0000-0000-0000-0000000ac002',
          '55.4 · y consta quién entregó, que también suscribe el acta');

-- ── Y AGRAVA. Es todo el punto ─────────────────────────────────────────────
select is((select nivel_siguiente from fn_tardanza_escalon('00000000-0000-0000-0000-0000000ac003')),
          'suspension',
          'ART. 56.1 · el acta produce los mismos efectos que el cargo: ahora SÍ agrava');

-- ── El testigo puede no estar en el sistema ────────────────────────────────
-- En una tienda puede atestiguar quien esté delante. Un acta que no se pueda
-- levantar porque el testigo no tiene usuario no serviría de nada.
create temp table _d2 as select pg_temp.firmada('NEG/002') as id;
select lives_ok(
  format($$ select fn_expediente_entregar(%L, 'acta_negativa', now(), 'Una persona sin usuario', null) $$,
    (select id from _d2)),
  'El testigo puede no tener cuenta: basta su nombre');

select * from finish();
rollback;
