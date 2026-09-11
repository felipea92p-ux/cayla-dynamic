-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 333_las_colas_de_correcciones_dejan_de_ver_a_quien_se_liquido.test.sql
-- Defiende la 0422
-- ============================================================================
-- QUÉ DEFIENDE
--
--   `fn_dias_por_revisar` y `fn_marcas_apartadas` dejan de listar para
--   siempre el marcaje sin resolver de alguien ya liquidado, pero SIGUEN
--   listando el de alguien cesado que todavía no se liquida — es la misma
--   distinción que defiende la 332 para `fn_persona_liquidada`, aplicada
--   ahora a las dos colas que alimentan Correcciones.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000033300', 'ZZ3330', 'Sede de laboratorio 333', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000033301', 'Admin333', 'Lab', '00000000-0000-0000-0000-000000033300',
        'admin', 'x', '00000000-0000-0000-0000-000000033399', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, fecha_cese)
values
  ('00000000-0000-0000-0000-000000033310', 'SinLiquidar333', 'Lab', '00000000-0000-0000-0000-000000033300',
   'x', '2026-01-05', 'inactivo', '2026-06-01'),
  ('00000000-0000-0000-0000-000000033311', 'Liquidada333', 'Lab', '00000000-0000-0000-0000-000000033300',
   'x', '2026-01-05', 'inactivo', '2026-06-01');

insert into liquidacion_pagada (
  persona_id, version, congelada_por, persona, fecha_cese,
  monto_periodo, monto_vacaciones, monto_grati, monto_cts, total, detalle, anulada
) values (
  '00000000-0000-0000-0000-000000033311', 1, '00000000-0000-0000-0000-000000033301',
  'Liquidada333 Lab', '2026-06-01', 100, 0, 0, 0, 100, '{}'::jsonb, false
);

-- Un marcaje pendiente_revision para cada una, el mismo día.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
values
  ('00000000-0000-0000-0000-000000033320', gen_random_uuid(), '00000000-0000-0000-0000-000000033310',
   '00000000-0000-0000-0000-000000033300', 'entrada', '2026-05-20 09:00:00-05', 'terminal', 'pendiente_revision'),
  ('00000000-0000-0000-0000-000000033321', gen_random_uuid(), '00000000-0000-0000-0000-000000033311',
   '00000000-0000-0000-0000-000000033300', 'entrada', '2026-05-20 09:00:00-05', 'terminal', 'pendiente_revision');

-- Una marca apartada sin resolver para cada una.
insert into marcas_apartadas (id, client_uuid, persona_id, tipo, timestamp_cliente)
values
  ('00000000-0000-0000-0000-000000033330', gen_random_uuid(), '00000000-0000-0000-0000-000000033310',
   'entrada', '2026-05-21 09:00:00-05'),
  ('00000000-0000-0000-0000-000000033331', gen_random_uuid(), '00000000-0000-0000-0000-000000033311',
   'entrada', '2026-05-21 09:00:00-05');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000033399', true);

select is(
  (select count(*)::int from fn_dias_por_revisar(50) where persona_id = '00000000-0000-0000-0000-000000033310'),
  1, 'DÍAS POR REVISAR · la cesada SIN liquidar sigue en la cola');
select is(
  (select count(*)::int from fn_dias_por_revisar(50) where persona_id = '00000000-0000-0000-0000-000000033311'),
  0, 'DÍAS POR REVISAR · la ya liquidada desaparece para siempre, aunque su marcaje siga pendiente_revision');

select is(
  (select count(*)::int from fn_marcas_apartadas() where persona_id = '00000000-0000-0000-0000-000000033310'),
  1, 'MARCAS APARTADAS · la cesada SIN liquidar sigue en la cola');
select is(
  (select count(*)::int from fn_marcas_apartadas() where persona_id = '00000000-0000-0000-0000-000000033311'),
  0, 'MARCAS APARTADAS · la ya liquidada desaparece para siempre');

select * from finish();
rollback;
