-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 283_el_saldo_de_vacaciones_separa_calculo_de_permiso.test.sql — la 0357 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que la función interna exista: es que
-- (a) `fn_vacaciones_saldo` sigue devolviendo EXACTO lo mismo que antes —
-- misma guardia, mismo resultado — así que ninguna pantalla que ya la usa
-- se entera de este cambio, (b) `fn_vacaciones_saldo_interno` funciona SIN
-- ninguna sesión, la forma real en que la llama el cron, y (c) la cola de
-- alertas encola vacaciones por vencer con el criterio inclusivo correcto
-- (por vencer O ya vencido), no solo contratos.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000009601', 'ZZAL3', 'Sede alertas tres', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, email) values
  -- Ingreso reciente A PROPÓSITO: con 2023-01-01 (el que usan otras pruebas)
  -- ella misma acumularía récords vencidos y contaminaría el conteo — este
  -- archivo necesita que la única que dispare sea AlvVencida.
  ('00000000-0000-0000-0000-000000009701', 'AlvAdmin', 'Lab', '00000000-0000-0000-0000-000000009601', 'admin', 'x',
   '00000000-0000-0000-0000-000000009801', (fn_hoy_lima() - interval '2 months')::date, 'admin2@cayla.test'),
  -- Ajena, sin permiso de ver el saldo de nadie más. Mismo motivo: ingreso reciente.
  ('00000000-0000-0000-0000-000000009702', 'AlvAjena', 'Lab', '00000000-0000-0000-0000-000000009601', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009802', (fn_hoy_lima() - interval '2 months')::date, null),
  -- 4 años de antigüedad, CERO vacaciones tomadas: records_vencidos > 0 seguro.
  ('00000000-0000-0000-0000-000000009703', 'AlvVencida', 'Lab', '00000000-0000-0000-0000-000000009601', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009803', (fn_hoy_lima() - interval '4 years')::date, null),
  -- Recién ingresada: sin ningún récord completo, no debe alertar.
  ('00000000-0000-0000-0000-000000009704', 'AlvNueva', 'Lab', '00000000-0000-0000-0000-000000009601', 'integrante', 'x',
   '00000000-0000-0000-0000-000000009804', (fn_hoy_lima() - interval '2 months')::date, null);
set session_replication_role = origin;

-- ── fn_vacaciones_saldo_interno funciona sin ninguna sesión ─────────────────
select lives_ok(
  $$ select fn_vacaciones_saldo_interno('00000000-0000-0000-0000-000000009703', fn_hoy_lima()) $$,
  'fn_vacaciones_saldo_interno calcula sin ninguna sesión — como la llama el cron'
);

select is(
  (select (fn_vacaciones_saldo_interno('00000000-0000-0000-0000-000000009703', fn_hoy_lima()) ->> 'records_vencidos')::int > 0),
  true,
  'cuatro años sin tomar vacaciones: hay al menos un récord vencido'
);

-- ── fn_vacaciones_saldo sigue exigiendo permiso — el refactor no lo tocó ────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009802', true);
select throws_ok(
  $$ select fn_vacaciones_saldo('00000000-0000-0000-0000-000000009703', null) $$,
  'No puedes ver el saldo de vacaciones de otra persona.',
  'la guardia de fn_vacaciones_saldo sigue viva tras separar el cálculo'
);

-- ── Y para quien sí puede, da EXACTO lo mismo que la función interna ────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000009801', true);
select is(
  (select fn_vacaciones_saldo('00000000-0000-0000-0000-000000009703', fn_hoy_lima())),
  (select fn_vacaciones_saldo_interno('00000000-0000-0000-0000-000000009703', fn_hoy_lima())),
  'fn_vacaciones_saldo (pública) devuelve EXACTO lo mismo que la interna — el contrato externo no cambió'
);

-- ── La cola de alertas ya encola vacaciones, sin sesión ──────────────────
select set_config('request.jwt.claim.sub', null, true);
select lives_ok(
  $$ select fn_generar_alertas_vencimiento() $$,
  'genera alertas de vacaciones también, sin ninguna sesión abierta'
);

select is(
  (select count(*)::int from alertas where tipo = 'vacaciones_por_vencer'),
  1,
  'una sola alerta de vacaciones: la recién ingresada no generó nada'
);

select is(
  (select payload ->> 'persona' from alertas where tipo = 'vacaciones_por_vencer'),
  'AlvVencida Lab',
  'y es la persona con récords vencidos, no la nueva'
);

select is(
  (select persona_id from alertas where tipo = 'vacaciones_por_vencer'),
  '00000000-0000-0000-0000-000000009701'::uuid,
  'la alerta queda a nombre del admin con correo'
);

-- ── Idempotente ──────────────────────────────────────────────────────────
select lives_ok($$ select fn_generar_alertas_vencimiento() $$, 'se puede correr de nuevo sin fallar');
select is(
  (select count(*)::int from alertas where tipo = 'vacaciones_por_vencer'),
  1,
  'y sigue habiendo una sola fila de vacaciones: el mismo hecho no se duplica'
);

select * from finish();
rollback;
