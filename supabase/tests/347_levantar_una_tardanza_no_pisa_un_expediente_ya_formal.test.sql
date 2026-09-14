-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 347_levantar_una_tardanza_no_pisa_un_expediente_ya_formal.test.sql — 0438
-- ============================================================================
-- La hermana de la prueba 346, en la dirección contraria. Los escenarios de
-- las fechas 10 (firmado) y 05 (entregado) llevan un levantamiento insertado
-- a mano DIRECTO en tardanzas_justificadas —no vía fn_levantar_tardanza,
-- porque ese camino está bloqueado por esta misma migración—: simulan el
-- caso real, una tardanza que se perdonó ANTES de que existiera el
-- expediente formal sobre esa fecha.
-- ============================================================================
begin;
select plan(9);

-- ── El laboratorio ──────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre)
values ('aaaaaaaa-0438-0000-0000-000000000001','T38','Sede de la prueba 347');

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values ('bbbbbbbb-0438-0000-0000-000000000001','00000000-0000-0000-0000-000000000000',
        'authenticated','authenticated','prueba347@cayla.local','x', now(), now(), now());

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id) values
 ('cccccccc-0438-0000-0000-00000000000a','Ada','Admin',
  'aaaaaaaa-0438-0000-0000-000000000001','x','admin','bbbbbbbb-0438-0000-0000-000000000001'),
 ('cccccccc-0438-0000-0000-00000000000b','Rosa','Trujillo',
  'aaaaaaaa-0438-0000-0000-000000000001','x','integrante', null);

set local request.jwt.claims = '{"sub":"bbbbbbbb-0438-0000-0000-000000000001","role":"authenticated"}';

-- ── Los expedientes: uno por escenario, cada uno en su propia fecha ─────────
insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, hechos, correlativo, firmante_id, firmado_at, creado_por)
values
 ('cccccccc-0438-0000-0000-00000000000b','tardanza','amonestacion','firmado',
  '[{"fecha":"2019-02-10","minutos":15}]'::jsonb,
  'T-0438/0001-2019-CAYLA','cccccccc-0438-0000-0000-00000000000a', now(),
  'cccccccc-0438-0000-0000-00000000000a');

insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, hechos, correlativo, firmante_id, firmado_at,
   medio_entrega, entregado_at, creado_por)
values
 ('cccccccc-0438-0000-0000-00000000000b','tardanza','amonestacion','entregado',
  '[{"fecha":"2019-02-05","minutos":20}]'::jsonb,
  'T-0438/0002-2019-CAYLA','cccccccc-0438-0000-0000-00000000000a', now(),
  'fisico', now(), 'cccccccc-0438-0000-0000-00000000000a');

insert into expediente_disciplinario
  (persona_id, tipo_causal, nivel, estado, hechos, creado_por)
values
 ('cccccccc-0438-0000-0000-00000000000b','tardanza','verbal','borrador',
  '[{"fecha":"2019-02-01","minutos":5}]'::jsonb,
  'cccccccc-0438-0000-0000-00000000000a');

-- Levantamientos preexistentes en las fechas con expediente formal — simula
-- que se perdonaron ANTES de que el expediente se firmara/entregara. No se
-- crean con fn_levantar_tardanza porque ese camino está bloqueado a partir de
-- esta migración: es dato de partida, no el resultado de la función.
insert into tardanzas_justificadas (persona_id, fecha, motivo, creado_por) values
 ('cccccccc-0438-0000-0000-00000000000b','2019-02-10','fuerza_mayor','cccccccc-0438-0000-0000-00000000000a'),
 ('cccccccc-0438-0000-0000-00000000000b','2019-02-05','salud','cccccccc-0438-0000-0000-00000000000a');

-- ── § 1 · Levantar se frena con un expediente formal ────────────────────────
select throws_ok(
  format('select fn_levantar_tardanza(%L, %L, ''fuerza_mayor'')',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-10'),
  null,
  'levantar una tardanza del día 10 (firmado) se frena');

select throws_ok(
  format('select fn_levantar_tardanza(%L, %L, ''salud'')',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-05'),
  null,
  'levantar una tardanza del día 05 (entregado) se frena');

-- ── § 2 · Lo que NO puede empezar a frenar ──────────────────────────────────
select lives_ok(
  format('select fn_levantar_tardanza(%L, %L, ''transporte'')',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-01'),
  'levantar un día con solo un BORRADOR se sigue pudiendo');

select lives_ok(
  format('select fn_levantar_tardanza(%L, %L, ''otro'', ''paro de transporte'')',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-15'),
  'levantar un día sin ningún expediente se sigue pudiendo');

select lives_ok(
  format('select fn_levantar_tardanza(%L, %L, ''salud'')',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-11'),
  'LA TRAMPA: el firmado es del 10, no del 11 — un día vecino no se contagia');

-- ── § 3 · Quitar el levantamiento se frena igual ────────────────────────────
select throws_ok(
  format('select fn_quitar_levantamiento(%L, %L)',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-10'),
  null,
  'quitar el levantamiento del día 10 (firmado) se frena');

select throws_ok(
  format('select fn_quitar_levantamiento(%L, %L)',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-05'),
  null,
  'quitar el levantamiento del día 05 (entregado) se frena');

-- ── § 4 · Y sigue pudiéndose quitar donde no hay expediente formal ─────────
select lives_ok(
  format('select fn_quitar_levantamiento(%L, %L)',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-01'),
  'quitar el levantamiento de un día con solo un BORRADOR se sigue pudiendo');

select lives_ok(
  format('select fn_quitar_levantamiento(%L, %L)',
         'cccccccc-0438-0000-0000-00000000000b', '2019-02-15'),
  'quitar el levantamiento de un día sin expediente se sigue pudiendo');

select * from finish();
rollback;
