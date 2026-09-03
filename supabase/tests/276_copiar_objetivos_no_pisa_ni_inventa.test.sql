-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 276_copiar_objetivos_no_pisa_ni_inventa.test.sql
-- ============================================================================
-- fn_objetivos_copiar_mes_anterior (0348) es la única RPC de objetivos que no
-- tiene un dato explícito que validar: en vez de "¿este texto mide entre 1 y
-- 300?" tiene que decidir SOLO a partir de lo que ya existe — si el mes
-- destino está vacío, si el mes anterior tiene algo, quién puede tocar a
-- quién. Esas tres preguntas son las que esta prueba fija: que no pise un mes
-- que ya tiene objetivos propios, que no invente una copia de la nada, que
-- los copiados salgan SIN marcar aunque el original estuviera cumplido (es un
-- objetivo nuevo, no un historial), y que respete los mismos candados que el
-- resto de la 0032 (permiso por sede, mes pagado).
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000e1', 'ZZCP1', 'Sede de laboratorio A', true),
  ('00000000-0000-0000-0000-0000000000e2', 'ZZCP2', 'Sede de laboratorio B', true);

-- Admin (necesita auth_user_id contra auth.users, que no existe en esta
-- prueba: replica salta esa FK igual que el trigger de escalafón).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000e3', 'CpAdmin', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'admin', 'x', '00000000-0000-0000-0000-00000000ee03'),
  ('00000000-0000-0000-0000-0000000000e4', 'CpEncargada', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000ee04');
set session_replication_role = origin;

-- Integrantes: A y C en la sede de la encargada, B en la otra sede.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000e5', 'CpIntegranteA', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'x'),
  ('00000000-0000-0000-0000-0000000000e6', 'CpIntegranteB', 'Lab', '00000000-0000-0000-0000-0000000000e2', 'x'),
  ('00000000-0000-0000-0000-0000000000e7', 'CpIntegranteC', 'Lab', '00000000-0000-0000-0000-0000000000e1', 'x');

-- A tiene dos objetivos en agosto 2026, uno ya cumplido.
insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden, cumplido) values
  ('00000000-0000-0000-0000-0000000000e5', 2026, 8, 'Capacitación de atención al cliente', 'Coordinar con DO', 1, true),
  ('00000000-0000-0000-0000-0000000000e5', 2026, 8, 'Cero tardanzas en el mes', null, 2, false);

-- C también tiene un objetivo en agosto (para el caso de la encargada).
insert into objetivos_items (persona_id, anio, mes, descripcion, orden) values
  ('00000000-0000-0000-0000-0000000000e7', 2026, 8, 'Ordenar el almacén', 1);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee03', true); -- admin

-- ── 1 · Admin copia agosto → septiembre para A ──────────────────────────────
select is(
  (fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-0000000000e5', 2026, 9)->>'copiados')::int,
  2,
  'ADMIN · copia los 2 objetivos de agosto hacia septiembre, que estaba vacío');

-- ── 2 · Los copiados llegan SIN marcar, aunque uno de agosto sí lo estaba ───
select is(
  (select count(*)::int from objetivos_items
   where persona_id = '00000000-0000-0000-0000-0000000000e5' and anio = 2026 and mes = 9 and not cumplido),
  2,
  'COPIA · los dos objetivos de septiembre llegan sin marcar, aunque uno de agosto estaba cumplido');

select is(
  (select descripcion from objetivos_items
   where persona_id = '00000000-0000-0000-0000-0000000000e5' and anio = 2026 and mes = 9 and orden = 1),
  'Capacitación de atención al cliente',
  'COPIA · la descripción (e indicaciones) viaja igual, no solo el conteo');

-- ── 3 · Repetirlo ya no es un mes vacío: se niega ───────────────────────────
select throws_ok(
  $$ select fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-0000000000e5', 2026, 9) $$,
  null, null,
  'NO VACÍO · septiembre ya tiene objetivos propios: copiar encima se niega, no los duplica');

-- ── 4 · Nada que copiar: B no tiene objetivos en septiembre ─────────────────
select throws_ok(
  $$ select fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-0000000000e6', 2026, 10) $$,
  null, null,
  'MES ANTERIOR VACÍO · sin objetivos en septiembre para B, no hay nada que copiar hacia octubre');

-- ── 5 · Mes pagado: el candado de fn_mes_planilla_pagado también aplica aquí ─
insert into periodos_planilla (fecha_ini, fecha_fin, estado)
values ('2026-09-29', '2026-10-28', 'pagado');

select throws_ok(
  $$ select fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-0000000000e5', 2026, 10) $$,
  null, null,
  'MES PAGADO · aunque septiembre (A) sí tiene qué copiar, octubre ya está pagado: se niega igual');

-- ── 6 · Permiso: la encargada de la sede A/C no gestiona a B (otra sede) ────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ee04', true); -- encargada

select throws_ok(
  $$ select fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-0000000000e6', 2026, 10) $$,
  null, null,
  'PERMISO · la encargada de otra sede no puede copiar objetivos de B, con o sin datos que copiar');

-- ── 7 · Permiso: la misma encargada SÍ gestiona a su integrante C ───────────
select is(
  (fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-0000000000e7', 2026, 9)->>'copiados')::int,
  1,
  'PERMISO · la encargada de la sede de C sí puede copiarle agosto → septiembre');

-- ── 8 · La función sigue siendo la que expone la pantalla ───────────────────
select has_function(
  'public', 'fn_objetivos_copiar_mes_anterior', array['uuid','int4','int4'],
  'fn_objetivos_copiar_mes_anterior sigue existiendo con la firma que llama /admin/objetivos');

select * from finish();
rollback;
