-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 354_objetivos_recuerdan_quien_los_toco.test.sql
-- ============================================================================
-- La 0449 agrega autoría (creado_por/actualizado_por) y borrado blando
-- (eliminado_at/eliminado_por) a objetivos_items, sin pedir motivo en ningún
-- caso (decisión de Felipe por AskUserQuestion, auditoría UX/UI del módulo,
-- 2026-09-14). Esta prueba fija:
--
--   · crear sella creado_por Y actualizado_por con quien lo crea;
--   · editar y marcar cumplido sellan actualizado_por con quien lo toca —
--     sin tocar creado_por, aunque lo haga otra persona con permiso;
--   · eliminar NO borra la fila: queda con eliminado_at/eliminado_por, fuera
--     de fn_objetivos_checklist, y dispara el mismo sync de siempre
--     (objetivos_mensuales vuelve a "sin registro" si era el único ítem);
--   · marcar/editar un ítem ya eliminado se comporta como "no existe";
--   · el tope de 20 ignora lo eliminado — ni cuenta de más ni dispara el
--     error antes de tiempo;
--   · "copiar del mes anterior" trata un mes con SOLO ítems eliminados como
--     vacío, y las copias quedan con la autoría de quien copia, no la
--     original.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000354e01', 'ZZ354', 'Sede de laboratorio 354', true);

-- Admin y encargada (necesitan auth_user_id contra auth.users, que no existe
-- en esta prueba: replica salta esa FK igual que el trigger de escalafón).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-000000354e03', 'DcAdmin', 'Lab', '00000000-0000-0000-0000-000000354e01', 'admin', 'x', '00000000-0000-0000-0000-000000354ee3'),
  ('00000000-0000-0000-0000-000000354e04', 'DcEncargada', 'Lab', '00000000-0000-0000-0000-000000354e01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-000000354ee4');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-000000354e05', 'DcIntegranteA', 'Lab', '00000000-0000-0000-0000-000000354e01', 'x');

-- ── 1 · Crear: sella creado_por Y actualizado_por con quien lo crea ─────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000354ee3', true); -- admin

select fn_objetivo_agregar('00000000-0000-0000-0000-000000354e05', 2026, 9, 'Ordenar el almacén', null);

select is(
  (select creado_por from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  '00000000-0000-0000-0000-000000354e03'::uuid,
  'CREAR · creado_por queda con el admin que lo agregó');

select is(
  (select actualizado_por from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  '00000000-0000-0000-0000-000000354e03'::uuid,
  'CREAR · actualizado_por también queda con quien lo creó');

-- ── 2 · Editar con OTRA persona: actualizado_por cambia, creado_por no ──────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000354ee4', true); -- encargada

select fn_objetivo_editar(
  (select id from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  'Ordenar el almacén general', null
);

select is(
  (select actualizado_por from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  '00000000-0000-0000-0000-000000354e04'::uuid,
  'EDITAR · actualizado_por pasa a ser la encargada que editó');

select is(
  (select creado_por from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  '00000000-0000-0000-0000-000000354e03'::uuid,
  'EDITAR · creado_por sigue siendo el admin original — editar no lo cambia');

-- ── 3 · Marcar cumplido: también sella actualizado_por ──────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000354ee3', true); -- admin otra vez

select fn_objetivo_marcar(
  (select id from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  true
);

select is(
  (select actualizado_por from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  '00000000-0000-0000-0000-000000354e03'::uuid,
  'MARCAR · actualizado_por vuelve a ser el admin que lo marcó cumplido');

-- ── 4 · Eliminar: deja de ser un delete físico ───────────────────────────────
select fn_objetivo_eliminar(
  (select id from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9)
);

select is(
  (select count(*)::int from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  1,
  'ELIMINAR · la fila SIGUE en la tabla — no es un delete físico');

select ok(
  (select eliminado_at is not null and eliminado_por = '00000000-0000-0000-0000-000000354e03'::uuid
     from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  'ELIMINAR · queda con eliminado_at y eliminado_por = quien lo borró');

select is(
  jsonb_array_length(fn_objetivos_checklist(2026, 9, '00000000-0000-0000-0000-000000354e05')),
  0,
  'ELIMINAR · pero fn_objetivos_checklist ya no lo devuelve');

select is(
  (select count(*)::int from objetivos_mensuales where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9),
  0,
  'ELIMINAR · y el sync borró la fila de objetivos_mensuales (vuelve a "sin registro")');

-- ── 5 · Marcar/editar un ítem ya eliminado: "no existe" ──────────────────────
select throws_ok(
  $$ select fn_objetivo_marcar((select id from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9 and eliminado_at is not null), true) $$,
  'P0001', 'Objetivo inexistente.',
  'ELIMINADO · marcarlo se comporta como si no existiera');

select throws_ok(
  $$ select fn_objetivo_editar((select id from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9 and eliminado_at is not null), 'x', null) $$,
  'P0001', 'Objetivo inexistente.',
  'ELIMINADO · editarlo se comporta como si no existiera');

-- ── 6 · El tope de 20 ignora lo eliminado ────────────────────────────────────
-- Septiembre de A ya tiene 1 ítem ELIMINADO (el del paso 4). Si el tope lo
-- contara, el vigésimo activo fallaría.
select lives_ok(
  $$ select fn_objetivo_agregar('00000000-0000-0000-0000-000000354e05', 2026, 9, 'Objetivo ' || n::text, null) from generate_series(1, 20) as n $$,
  'TOPE · 20 objetivos nuevos entran aunque haya 1 eliminado antes (no cuenta)');

select is(
  (select count(*)::int from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 9 and eliminado_at is null),
  20,
  'TOPE · quedan exactamente 20 activos');

select throws_ok(
  $$ select fn_objetivo_agregar('00000000-0000-0000-0000-000000354e05', 2026, 9, 'Objetivo 21', null) $$,
  'P0001', 'Máximo 20 objetivos por persona y mes.',
  'TOPE · el 21° activo sí choca con el tope');

-- ── 7 · "Copiar del mes anterior" trata un mes con solo eliminados como vacío ──
select fn_objetivo_agregar('00000000-0000-0000-0000-000000354e05', 2026, 10, 'Borrador de octubre', null);
select fn_objetivo_eliminar(
  (select id from objetivos_items where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 10)
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000354ee4', true); -- encargada copia esta vez

select is(
  (fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-000000354e05', 2026, 10)->>'copiados')::int,
  20,
  'COPIAR · octubre con solo un ítem eliminado se trata como vacío: copia los 20 de septiembre');

select is(
  (select count(*)::int from objetivos_items
    where persona_id = '00000000-0000-0000-0000-000000354e05' and anio = 2026 and mes = 10
      and eliminado_at is null and creado_por = '00000000-0000-0000-0000-000000354e04'::uuid),
  20,
  'COPIAR · las 20 copias quedan con creado_por = la encargada que copió, no el autor original');

select * from finish();
rollback;
