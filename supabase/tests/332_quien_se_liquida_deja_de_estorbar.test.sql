-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 332_quien_se_liquida_deja_de_estorbar.test.sql — defiende la 0419
-- ============================================================================
-- QUÉ DEFIENDE
--
--   `fn_persona_liquidada` distingue las TRES situaciones que le importan al
--   resto del sistema: activo (false), cesado sin liquidar todavía (false —
--   sigue teniendo trabajo pendiente) y cesado con liquidación pagada y no
--   anulada (true — recién ahí deja de estorbar). Y que una liquidación
--   ANULADA no cuenta como pagada: si se marcó por error y se anuló, la
--   persona vuelve a verse en todos lados hasta que se le liquide de verdad.
--
--   Y que `fn_personas_funciones()` reparte esa misma respuesta bajo la
--   clave `liquidada`, para que Ausencias/Educación/Correcciones pregunten
--   una sola vez y no tres.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000033200', 'ZZ3320', 'Sede de laboratorio 332', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000033201', 'Admin332', 'Lab', '00000000-0000-0000-0000-000000033200',
        'admin', 'x', '00000000-0000-0000-0000-000000033299', '2024-01-01');
set session_replication_role = origin;

-- ── Fixtures: activa, cesada-sin-liquidar, cesada-liquidada, cesada-anulada ──
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, fecha_cese)
values
  ('00000000-0000-0000-0000-000000033210', 'Activa', 'Lab', '00000000-0000-0000-0000-000000033200',
   'x', '2026-01-05', 'activo', null),
  ('00000000-0000-0000-0000-000000033211', 'SinLiquidar', 'Lab', '00000000-0000-0000-0000-000000033200',
   'x', '2026-01-05', 'inactivo', '2026-06-01'),
  ('00000000-0000-0000-0000-000000033212', 'Liquidada', 'Lab', '00000000-0000-0000-0000-000000033200',
   'x', '2026-01-05', 'inactivo', '2026-06-01'),
  ('00000000-0000-0000-0000-000000033213', 'AnuladaNadaMas', 'Lab', '00000000-0000-0000-0000-000000033200',
   'x', '2026-01-05', 'inactivo', '2026-06-01');

insert into liquidacion_pagada (
  persona_id, version, congelada_por, persona, fecha_cese,
  monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle, anulada
) values (
  '00000000-0000-0000-0000-000000033212', 1, '00000000-0000-0000-0000-000000033201',
  'Liquidada Lab', '2026-06-01', 100, 200, 50, 25, 375, '{}'::jsonb, false
);

insert into liquidacion_pagada (
  persona_id, version, congelada_por, persona, fecha_cese,
  monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle,
  anulada, motivo_anulacion, anula_version
) values (
  '00000000-0000-0000-0000-000000033213', 1, '00000000-0000-0000-0000-000000033201',
  'AnuladaNadaMas Lab', '2026-06-01', 0, 0, 0, 0, 0, '{}'::jsonb,
  true, 'se registró por error, prueba 332', 1
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000033299', true);

select is(fn_persona_liquidada('00000000-0000-0000-0000-000000033210'), false,
  'ACTIVA · nunca liquidada, no cesó');
select is(fn_persona_liquidada('00000000-0000-0000-0000-000000033211'), false,
  'CESADA SIN LIQUIDAR · sigue false — puede tener trabajo pendiente antes de liquidarse');
select is(fn_persona_liquidada('00000000-0000-0000-0000-000000033212'), true,
  'CESADA Y LIQUIDADA · true — recién acá deja de estorbar en las pantallas');
select is(fn_persona_liquidada('00000000-0000-0000-0000-000000033213'), false,
  'LIQUIDACIÓN ANULADA · sigue false — anulada no cuenta como pagada');

select is(
  (select (elem->>'liquidada')::boolean
     from jsonb_array_elements(fn_personas_funciones()) elem
    where elem->>'persona_id' = '00000000-0000-0000-0000-000000033212'),
  true,
  'fn_personas_funciones · reparte la misma respuesta bajo la clave "liquidada"');

select is(
  (select (elem->>'liquidada')::boolean
     from jsonb_array_elements(fn_personas_funciones()) elem
    where elem->>'persona_id' = '00000000-0000-0000-0000-000000033211'),
  false,
  'fn_personas_funciones · la cesada sin liquidar sigue en false, no en null');

select * from finish();
rollback;
