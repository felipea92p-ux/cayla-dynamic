-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- ============================================================================
-- 472_lo_comunicado_no_cambia_y_el_descargo_se_lee_antes.test.sql — migración 0582
-- ============================================================================
-- Dos frenos, cada uno con el caso que DEBE frenar y el que debe pasar:
--   1. Comunicados los cargos, el borrador ya no cambia sus hechos ni su nivel
--      —ni por la función de editar ni por la de elevar—; sí sus días de
--      suspensión, que se fijan después del descargo.
--   2. El descargo no se valora con el plazo vivo, ni como «no presentó» si lo
--      escribió en su Info; y un borrador así no se firma.
--   Y sin sesión (el SQL Editor) no frena: es la salida para corregir a mano.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000047201', 'ZZLCN', 'Sede de laboratorio 472', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000047210', 'Emisora',    'Lab', '00000000-0000-0000-0000-000000047201', 'admin',      'x', '00000000-0000-0000-0000-0000000472a0', '2020-01-01', 'activo', 'planilla'),
  ('00000000-0000-0000-0000-000000047211', 'Sancionada', 'Lab', '00000000-0000-0000-0000-000000047201', 'integrante', 'x', '00000000-0000-0000-0000-0000000472a1', '2024-01-01', 'activo', 'planilla');

-- Tres borradores de tardanza, hechos de 2025 (el freno del 60.5 no se mete).
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta, hechos, creado_por)
select v.id, '00000000-0000-0000-0000-000000047211', 'tardanza', 'amonestacion', 'borrador',
       date '2025-02-03', date '2025-02-08', '[{"fecha":"2025-02-05","minutos":17}]'::jsonb,
       '00000000-0000-0000-0000-000000047210'
from (values ('00000000-0000-0000-0000-0000000472b1'::uuid),   -- se edita después de comunicar
             ('00000000-0000-0000-0000-0000000472b2'::uuid),   -- ella escribe su descargo
             ('00000000-0000-0000-0000-0000000472b3'::uuid))   -- quedó «sin descargo» con descargo escrito
  as v(id);
set session_replication_role = origin;

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', p_auth::text, true);
$$;

select pg_temp.como('00000000-0000-0000-0000-0000000472a0');
select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-0000000472b1', 2, null);
select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-0000000472b2', 2, null);
select fn_expediente_comunicar_cargos('00000000-0000-0000-0000-0000000472b3', 2, null);


-- ── 1 · Lo comunicado no cambia ─────────────────────────────────────────────
select throws_like(
  $$ select fn_expediente_editar_borrador('00000000-0000-0000-0000-0000000472b1',
       p_hechos => '[{"fecha":"2025-02-05","minutos":17},{"fecha":"2025-02-07","minutos":45}]'::jsonb) $$,
  '%Ya se le comunicaron estos cargos%',
  'comunicados los cargos, no se le agregan hechos');

select throws_like(
  $$ update expediente_disciplinario set nivel = 'suspension' where id = '00000000-0000-0000-0000-0000000472b1' $$,
  '%Ya se le comunicaron estos cargos%',
  'ni se le cambia el nivel (lo que hace «elevar a suspensión»)');

select lives_ok(
  $$ select fn_expediente_editar_borrador('00000000-0000-0000-0000-0000000472b1', p_observacion => 'Nota de quien tramita.') $$,
  'una nota de quien tramita sí se puede agregar');

select lives_ok(
  $$ update expediente_disciplinario set suspension_dias = 1 where id = '00000000-0000-0000-0000-0000000472b1' $$,
  'los días de suspensión se fijan después: no los frena');


-- ── 2 · El descargo se lee antes de decidir ─────────────────────────────────
select throws_like(
  $$ select fn_expediente_valorar_descargo('00000000-0000-0000-0000-0000000472b2', 'sin_descargo', null) $$,
  '%Su plazo de descargo vence%',
  'con el plazo vivo no se valora');

-- Ella escribe su descargo dentro del plazo.
select pg_temp.como('00000000-0000-0000-0000-0000000472a1');
select fn_cargos_detalle('00000000-0000-0000-0000-0000000472b2');
select fn_recibir_cargos('00000000-0000-0000-0000-0000000472b2');
select fn_presentar_descargo('00000000-0000-0000-0000-0000000472b2', 'Ese día avisé a mi líder que el bus no pasaba.');

-- Se vence el plazo (las dos fechas juntas, por chk_descargo_coherente).
set session_replication_role = replica;
update expediente_disciplinario
   set cargos_comunicados_at = now() - interval '5 days', descargo_vence_at = now() - interval '1 hour'
 where id in ('00000000-0000-0000-0000-0000000472b2', '00000000-0000-0000-0000-0000000472b3');
-- b3: quedó valorado «sin descargo» por un camino sin freno, y después aparece su descargo escrito.
update expediente_disciplinario set descargo_acogido = 'sin_descargo'
 where id = '00000000-0000-0000-0000-0000000472b3';
insert into descargos_presentados (expediente_id, texto)
values ('00000000-0000-0000-0000-0000000472b3', 'Mi descargo escrito, que nadie leyó.');
set session_replication_role = origin;

select pg_temp.como('00000000-0000-0000-0000-0000000472a0');

select throws_like(
  $$ select fn_expediente_valorar_descargo('00000000-0000-0000-0000-0000000472b2', 'sin_descargo', null) $$,
  '%Presentó su descargo por escrito%',
  'con su descargo escrito, no se valora como «no presentó descargo»');

select lives_ok(
  $$ select fn_expediente_valorar_descargo('00000000-0000-0000-0000-0000000472b2', 'no', 'Su líder confirma que no recibió ningún aviso ese día.') $$,
  'vencido el plazo, su descargo se valora');

select lives_ok(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000472b2') $$,
  'y valorado de verdad, se firma');

select throws_like(
  $$ select fn_expediente_firmar('00000000-0000-0000-0000-0000000472b3') $$,
  '%Vuelve a valorarlo antes de firmar%',
  'un borrador que dice «sin descargo» con un descargo escrito no se firma');


-- ── 3 · Sin sesión (el SQL Editor) no frena ─────────────────────────────────
select set_config('request.jwt.claim.sub', '', true);

select lives_ok(
  $$ update expediente_disciplinario set hechos = '[{"fecha":"2025-02-06","minutos":20}]'::jsonb
      where id = '00000000-0000-0000-0000-0000000472b1' $$,
  'sin sesión, una corrección a mano pasa');

select is(
  (select hechos -> 0 ->> 'fecha' from expediente_disciplinario where id = '00000000-0000-0000-0000-0000000472b1'),
  '2025-02-06',
  'y queda escrita');

select * from finish();
rollback;
