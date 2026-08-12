-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 170_no_se_sanciona_con_un_reglamento_que_no_se_entrego.test.sql
-- ============================================================================
-- Numeral 60.5 del Reglamento. Dice dos cosas y solo una se programa:
--
--   «El desconocimiento de este Reglamento no exime de su cumplimiento. Sin
--    embargo, CAYLA no puede fundar una sanción en una disposición cuya
--    entrega, en la versión vigente a la fecha de los hechos, no conste
--    acreditada…»
--
-- Lo que fija esta prueba es justamente dónde está el borde:
--   · SIN constancia, no se emite una amonestación ni se citan sus cargos.
--   · CON constancia, todo sigue igual.
--   · Los hechos ANTERIORES a la versión no se frenan: el 60.5 manda
--     calificarlos conforme a la versión que sí le fue entregada, que es de
--     papel y no consta en la base. El sistema calla sobre lo que no ve.
--   · El DESPIDO no se frena. Se funda en una causal del art. 25 de la LPCL,
--     que rige por ley y no por entrega — frenarlo habría impedido despedir por
--     falta grave a quien no firmó su cargo, o sea, habría premiado no firmarlo.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ac01', 'ZZ605', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-00000000ac02', 'GerenciaSesenta', 'Lab',
        '00000000-0000-0000-0000-00000000ac01', 'admin', 'x',
        '00000000-0000-0000-0000-0000000ac002', '2020-01-01', 'activo');
set session_replication_role = origin;

-- Dos trabajadoras iguales en todo menos en la constancia.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado) values
  ('00000000-0000-0000-0000-00000000ac03', 'SinConstancia', 'Lab', '00000000-0000-0000-0000-00000000ac01', 'x', '2020-01-01', 'activo'),
  ('00000000-0000-0000-0000-00000000ac04', 'ConConstancia', 'Lab', '00000000-0000-0000-0000-00000000ac01', 'x', '2020-01-01', 'activo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ac002', true);

-- ── Antes de publicar nada, el candado calla ────────────────────────────────
select is(fn_reglamento_no_acusado('00000000-0000-0000-0000-00000000ac03', '2026-07-15'), null,
          'SIN VERSIÓN PUBLICADA · el candado no tiene nada que decir y no frena');

-- ── Se publica el Reglamento, vigente desde el 1 de julio ───────────────────
select lives_ok(
  $$ select fn_publicar_documento('rit', 'Reglamento de laboratorio',
       'Texto del Reglamento de laboratorio, version unica.', '2026-07-01'::date, null) $$,
  'DE PARTIDA · se publica una versión vigente desde el 01/07/2026');

-- ConConstancia la acusa; SinConstancia no.
insert into documentos_acuses (documento_id, persona_id, via, nombre_declarado)
select id, '00000000-0000-0000-0000-00000000ac04', 'sistema', 'ConConstancia Lab'
from documentos_institucionales where tipo = 'rit' order by version desc limit 1;

-- ── La pregunta, en seco ────────────────────────────────────────────────────
select isnt(fn_reglamento_no_acusado('00000000-0000-0000-0000-00000000ac03', '2026-07-15'), null,
            '60.5 · a quien no acusó, el candado le pone motivo');
select is(fn_reglamento_no_acusado('00000000-0000-0000-0000-00000000ac04', '2026-07-15'), null,
          '60.5 · a quien sí acusó, no');
select is(fn_reglamento_no_acusado('00000000-0000-0000-0000-00000000ac03', '2026-06-15'), null,
          '60.5 · los hechos ANTERIORES a la versión no se frenan: rige la que sí le fue entregada');

-- ── Sobre el expediente de verdad ───────────────────────────────────────────
select fn_expediente_crear_borrador('00000000-0000-0000-0000-00000000ac03',
  'tardanza', 'amonestacion', '[{"fecha":"2026-07-15","tipo":"tardanza"}]'::jsonb,
  '2026-07-01', '2026-07-15');

create temp table _sin as
  select id from expediente_disciplinario
  where persona_id = '00000000-0000-0000-0000-00000000ac03' and nivel = 'amonestacion';

select throws_ok(
  format($$ select fn_expediente_comunicar_cargos(%L, 2, null) $$, (select id from _sin)),
  null, null,
  'CARGOS · no se cita a descargo por hechos que después no se van a poder sancionar');

select throws_ok(
  format($$ select fn_expediente_firmar(%L) $$, (select id from _sin)),
  null, null,
  'FIRMA · y tampoco se firma la amonestación');

-- ── Con constancia, el camino queda como estaba ─────────────────────────────
select fn_expediente_crear_borrador('00000000-0000-0000-0000-00000000ac04',
  'tardanza', 'amonestacion', '[{"fecha":"2026-07-15","tipo":"tardanza"}]'::jsonb,
  '2026-07-01', '2026-07-15');

select lives_ok(
  format($$ select fn_expediente_comunicar_cargos(%L, 2, null) $$,
    (select id from expediente_disciplinario
     where persona_id = '00000000-0000-0000-0000-00000000ac04' and nivel = 'amonestacion')),
  'CARGOS · a quien sí acusó, el procedimiento sigue igual que antes');

-- ── El despido NO se frena ──────────────────────────────────────────────────
select fn_expediente_crear_borrador('00000000-0000-0000-0000-00000000ac03',
  'conducta', 'despido', '[{"fecha":"2026-07-20","tipo":"falta grave"}]'::jsonb,
  '2026-07-20', '2026-07-20');

select lives_ok(
  format($$ select fn_expediente_firmar(%L, '00000000-0000-0000-0000-00000000ac02') $$,
    (select id from expediente_disciplinario
     where persona_id = '00000000-0000-0000-0000-00000000ac03' and nivel = 'despido')),
  'DESPIDO · se funda en el art. 25 de la LPCL, no en el Reglamento: no firmar el cargo no protege de él');

select is(
  (select estado from expediente_disciplinario
   where persona_id = '00000000-0000-0000-0000-00000000ac03' and nivel = 'despido'),
  'firmado', 'DESPIDO · y quedó firmado de verdad');

select * from finish();
rollback;
