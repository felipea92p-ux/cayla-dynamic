-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 329_el_cese_tambien_deja_rastro.test.sql
-- ============================================================================
-- La 0415 le agrega auditoría a fn_cesar_persona, que hasta entonces era el
-- único de los cuatro campos "sensibles" (régimen de pensión, rol, sede, cese)
-- sin rastro en `correcciones_auditoria` — pese a ser el de mayor consecuencia:
-- decide la liquidación y si hubo causa justa. Esta prueba comprueba que la
-- fila queda escrita, con quién y con qué motivo — no que el cese en sí
-- funcione (eso ya lo cubren 103/177/219/296).
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000032900', 'ZZ329', 'Sede de laboratorio', true, 'tienda');

-- Mismo patrón que la 296: session_replication_role = replica porque el
-- UPDATE de fn_cesar_persona revalida el FK de auth_user_id, no solo el INSERT.
set local session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values
  ('00000000-0000-0000-0000-000000032901', 'CeseAuditado', 'Lab', '00000000-0000-0000-0000-000000032900', 'integrante', 'x', '00000000-0000-0000-0000-0000000329a1', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000032902', 'CeseConVinculo', 'Lab', '00000000-0000-0000-0000-000000032900', 'integrante', 'x', '00000000-0000-0000-0000-0000000329a2', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000032909', 'AdminLab',       'Lab', '00000000-0000-0000-0000-000000032900', 'admin',      'x', '00000000-0000-0000-0000-0000000329ad', '2024-01-01', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000329ad', true);

-- ── 1 · El cese en sí sigue funcionando igual que antes ─────────────────────
-- `motivo_cese` no es texto libre: el CHECK `personas_motivo_cese_valido`
-- (0086/0143/0325) exige uno de sus códigos fijos. 'despido' es el que más
-- pesa, porque exige expediente (D.S. 003-97-TR) y decide la liquidación.
select lives_ok($$
  select fn_cesar_persona('00000000-0000-0000-0000-000000032901'::uuid, '2026-07-10'::date, 'despido');
$$, 'el admin puede cesar, como siempre');

-- ── 2 · Deja exactamente una fila, no cuatro ────────────────────────────────
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000032901'
      and campo_modificado = 'personas.estado'),
  1,
  'el cese deja UNA fila de auditoría en personas.estado');

-- ── 3 · Antes/después son los valores reales, no el motivo de negocio ──────
select is(
  (select valor_anterior || ' → ' || valor_nuevo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000032901'
      and campo_modificado = 'personas.estado'),
  'activo → inactivo',
  'valor_anterior/valor_nuevo son el estado, no el motivo');

-- ── 4 · Quedó quién lo hizo, no quién se fue ────────────────────────────────
select is(
  (select corregido_por from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000032901'
      and campo_modificado = 'personas.estado'),
  '00000000-0000-0000-0000-000000032909'::uuid,
  'corregido_por es el admin que ejecutó el cese, no la persona cesada');

-- ── 5 · El motivo de negocio y la fecha quedan legibles en el rastro ───────
select ok(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000032901'
      and campo_modificado = 'personas.estado')
    like '%10/07/2026%Motivo: despido%',
  'el motivo del cese y la fecha quedan en el texto de la auditoría');

-- ── 6 · Sin tipo_vinculo, el texto no inventa un cambio de vínculo ─────────
select ok(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000032901'
      and campo_modificado = 'personas.estado')
    not like '%Vínculo pasa a%',
  'sin p_tipo_vinculo, el motivo no menciona un cambio de vínculo que no pidieron');

-- ── 7 · Con tipo_vinculo, sí queda dicho a qué cambió ───────────────────────
-- 'no_trabajador' y los demás códigos son los que acepta
-- `personas_tipo_vinculo_valido` (0085/0322) — tampoco es texto libre.
select fn_cesar_persona('00000000-0000-0000-0000-000000032902'::uuid, '2026-07-10'::date, 'mutuo_acuerdo', 'no_trabajador');
select ok(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000032902'
      and campo_modificado = 'personas.estado')
    like '%Vínculo pasa a no_trabajador.%',
  'con p_tipo_vinculo, el motivo dice a qué vínculo pasó');

select * from finish();
rollback;
