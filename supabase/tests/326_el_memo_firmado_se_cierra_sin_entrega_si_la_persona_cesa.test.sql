-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 326_el_memo_firmado_se_cierra_sin_entrega_si_la_persona_cesa.test.sql
-- ============================================================================
-- fn_expediente_cerrar_sin_entrega (mig. 0412) resuelve un memo FIRMADO cuando
-- la persona cesa antes de que se le pueda entregar. Reglas que se blindan:
--   · mientras la persona siga ACTIVA, la función se niega: el camino sigue
--     siendo entregarle el documento, no cerrarlo.
--   · ya cesada, el cierre funciona, deja constancia del motivo en
--     `observacion`, y el documento queda en `cerrado_sin_entrega`.
--   · solo se cierra un FIRMADO: ni un borrador ni un documento ya cerrado
--     (o cualquier otro estado) admiten esta acción.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000fe', 'ZZTEST', 'Sede de laboratorio', true);

-- Admin con sesión simulada (salta la FK a auth.users con replica).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id)
values ('00000000-0000-0000-0000-00000000ce0a', 'AdminDisc', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000fe', 'test-hash', 'admin',
        '00000000-0000-0000-0000-00000000ce0b');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ce0b', true);

-- La persona sancionada: arranca ACTIVA.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000ce0c', 'PruebaCese', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000fe', 'test-hash');

-- Un memo FIRMADO, pendiente de entrega.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, firmante_id, firmado_at, correlativo, creado_por)
values
  ('00000000-0000-0000-0000-00000000ce01', '00000000-0000-0000-0000-00000000ce0c',
   'tardanza', 'amonestacion', 'firmado',
   '00000000-0000-0000-0000-00000000ce0a', now(), 'T-01/9997-2026-CAYLA',
   '00000000-0000-0000-0000-00000000ce0a');

-- ── Mientras sigue activa, no se cierra ─────────────────────────────────────
select throws_like(
  $$ select fn_expediente_cerrar_sin_entrega('00000000-0000-0000-0000-00000000ce01', null) $$,
  '%sigue activa%',
  'No se cierra sin entrega mientras la persona sigue activa: el camino es entregarle el documento');

-- Cesa.
update personas set estado = 'inactivo', fecha_cese = current_date, motivo_cese = 'renuncia'
  where id = '00000000-0000-0000-0000-00000000ce0c';

-- ── Ya cesada, el cierre funciona ────────────────────────────────────────────
select lives_ok(
  $$ select fn_expediente_cerrar_sin_entrega('00000000-0000-0000-0000-00000000ce01', 'no se pudo ubicar') $$,
  'Ya cesada la persona, el memo firmado se puede cerrar sin entrega');

select is(
  (select estado from expediente_disciplinario where id = '00000000-0000-0000-0000-00000000ce01'),
  'cerrado_sin_entrega', 'Tras cerrar, el documento queda en cerrado_sin_entrega');

select alike(
  (select observacion from expediente_disciplinario where id = '00000000-0000-0000-0000-00000000ce01'),
  '%CERRADO SIN ENTREGA%', 'Queda constancia en el legajo de por qué se cerró sin entregar');

-- ── No se cierra dos veces: ya no está firmado ──────────────────────────────
select throws_like(
  $$ select fn_expediente_cerrar_sin_entrega('00000000-0000-0000-0000-00000000ce01', null) $$,
  '%firmado%',
  'Un documento ya cerrado no se vuelve a cerrar: solo se cierra un firmado');

-- ── Un borrador tampoco: solo un firmado pasa por acá ───────────────────────
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, creado_por)
values
  ('00000000-0000-0000-0000-00000000ce02', '00000000-0000-0000-0000-00000000ce0c',
   'tardanza', 'amonestacion', 'borrador', '00000000-0000-0000-0000-00000000ce0a');

select throws_like(
  $$ select fn_expediente_cerrar_sin_entrega('00000000-0000-0000-0000-00000000ce02', null) $$,
  '%firmado%',
  'Un borrador no se cierra sin entrega: primero tiene que firmarse');

select * from finish();
rollback;
