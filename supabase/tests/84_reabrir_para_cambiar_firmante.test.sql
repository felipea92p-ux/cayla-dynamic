-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 84_reabrir_para_cambiar_firmante.test.sql — Volver un memo firmado a borrador
-- ============================================================================
-- fn_expediente_reabrir (mig. 0131) existe para corregir el firmante de un memo
-- que se firmó a nombre de la persona equivocada. Reglas que se blindan:
--   · un memo FIRMADO (aún no entregado) puede volver a borrador; al hacerlo
--     pierde firmante, fecha de firma y número oficial (vuelve a ser un borrador
--     de verdad), y queda constancia de que se reabrió.
--   · un memo ENTREGADO ya es un artefacto del mundo real: NO se reabre (se anula
--     y se regenera). El límite tiene que sostenerse.
--
-- Exige permiso (admin/líder), por eso se simula la sesión de un admin.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000ff', 'ZZTEST', 'Sede de laboratorio', true);

-- Admin con sesión simulada (salta la FK a auth.users con replica).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('00000000-0000-0000-0000-00000000da0a', 'AdminDisc', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ff', 'test-hash', 'admin',
        '00000000-0000-0000-0000-00000000da0b');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000da0b', true);

-- La persona sancionada.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000da0c', 'PruebaSanc', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000ff', 'test-hash');

-- Un memo FIRMADO (por el admin) y otro ya ENTREGADO.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, firmante_id, firmado_at, correlativo, creado_por)
values
  ('00000000-0000-0000-0000-00000000da01', '00000000-0000-0000-0000-00000000da0c',
   'tardanza', 'amonestacion', 'firmado',
   '00000000-0000-0000-0000-00000000da0a', now(), 'T-01/9999-2026-CAYLA',
   '00000000-0000-0000-0000-00000000da0a');

insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, firmante_id, firmado_at, correlativo,
   medio_entrega, entregado_at, creado_por)
values
  ('00000000-0000-0000-0000-00000000da02', '00000000-0000-0000-0000-00000000da0c',
   'tardanza', 'amonestacion', 'entregado',
   '00000000-0000-0000-0000-00000000da0a', now(), 'T-01/9998-2026-CAYLA',
   'fisico', now(), '00000000-0000-0000-0000-00000000da0a');

-- ── Reabrir el firmado ──────────────────────────────────────────────────────
select lives_ok(
  $$ select fn_expediente_reabrir('00000000-0000-0000-0000-00000000da01') $$,
  'Un memo firmado (sin entregar) se puede volver a borrador');

select is(
  (select estado from expediente_disciplinario where id = '00000000-0000-0000-0000-00000000da01'),
  'borrador', 'Tras reabrir, el memo vuelve a estado borrador');

select is(
  (select firmante_id from expediente_disciplinario where id = '00000000-0000-0000-0000-00000000da01'),
  null::uuid, 'Tras reabrir, se suelta el firmante (para poder elegir otro)');

select is(
  (select correlativo from expediente_disciplinario where id = '00000000-0000-0000-0000-00000000da01'),
  null::text, 'Tras reabrir, pierde el número oficial (un borrador no tiene número)');

-- `alike` y no `like`: pgTAP no define una función `like` — ese nombre es el
-- operador SQL, así que `select like(...)` reventaba la sesión y las DOS pruebas
-- siguientes no llegaban a correr. La comparación con patrón se llama `alike`.
select alike(
  (select observacion from expediente_disciplinario where id = '00000000-0000-0000-0000-00000000da01'),
  '%REABIERTO%', 'Queda constancia de que el documento se reabrió');

-- ── Un entregado NO se reabre ───────────────────────────────────────────────
select throws_like(
  $$ select fn_expediente_reabrir('00000000-0000-0000-0000-00000000da02') $$,
  '%entregado%',
  'Un memo ya entregado no se reabre (se anula y se regenera)');

select * from finish();
rollback;
