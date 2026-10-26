-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 427_la_constancia_de_la_boleta_trae_sus_datos.test.sql — la 0533
-- ============================================================================
-- Lo que hay que proteger acá:
-- (a) quien ve la firma ve estos datos, y nadie más: DO cualquiera; la persona,
--     solo los de su boleta publicada; ni otra persona ni la líder de equipo,
-- (b) la fecha de pago es la de SU grupo, no la del periodo (que es la del
--     último grupo que se pagó): una persona de planilla no sale «pagada» el
--     día que se pagó a los RxH,
-- (c) lo que no está registrado vuelve en NULL, no inventado, y
-- (d) solo la llama quien inició sesión.
-- ============================================================================
begin;
select plan(14);

-- ── Sede, personas y periodo ─────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000533001', 'ZZC33', 'Sede constancia', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo, documento, tipo_documento) values
  ('00000000-0000-0000-0000-0000005330a1', 'DoCons',  'Lab', '00000000-0000-0000-0000-000000533001', 'admin',           'x', '00000000-0000-0000-0000-0000005330b1', '2023-01-01', 'planilla', 'DO',              '10000001', 'dni'),
  ('00000000-0000-0000-0000-0000005330a2', 'AnaCons', 'Lab', '00000000-0000-0000-0000-000000533001', 'integrante',      'x', '00000000-0000-0000-0000-0000005330b2', '2023-01-01', 'planilla', 'Vendedora',       '10000002', 'dni'),
  ('00000000-0000-0000-0000-0000005330a3', 'RosCons', 'Lab', '00000000-0000-0000-0000-000000533001', 'integrante',      'x', '00000000-0000-0000-0000-0000005330b3', '2023-01-01', 'rxh',      'Diseñadora',      'CE0000003', 'ce'),
  ('00000000-0000-0000-0000-0000005330a4', 'LidCons', 'Lab', '00000000-0000-0000-0000-000000533001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000005330b4', '2023-01-01', 'planilla', 'Líder de equipo', '10000004', 'dni'),
  ('00000000-0000-0000-0000-0000005330a5', 'BeaCons', 'Lab', '00000000-0000-0000-0000-000000533001', 'integrante',      'x', '00000000-0000-0000-0000-0000005330b5', '2023-01-01', 'planilla', 'Vendedora',       null,       null);
set session_replication_role = origin;

-- Ana tiene registrado el nombre de su DNI; Bea no tiene ni ficha ni documento.
insert into datos_personales (persona_id, nombre_dni) values
  ('00000000-0000-0000-0000-0000005330a2', 'ANA CONSTANCIA LAB');

-- Planilla se pagó el 30; RxH el 5 del mes siguiente. El periodo queda «pagado»
-- con la fecha del ÚLTIMO grupo, que es la que NO debe salir en la hoja de Ana.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at) values
  ('00000000-0000-0000-0000-0000005330f1', '2018-07-29', '2018-08-28', 'pagado', '2018-09-05 17:00:00+00');
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at) values
  ('00000000-0000-0000-0000-0000005330f1', 'planilla', 'pagado', '2018-08-30 17:00:00+00'),
  ('00000000-0000-0000-0000-0000005330f1', 'rxh',      'pagado', '2018-09-05 17:00:00+00');

select set_config('t.ana1', '00000000-0000-0000-0000-0000005330f1/00000000-0000-0000-0000-0000005330a2/f5330000-0000-0000-0000-000000000001.jpg', true);
select set_config('t.ros1', '00000000-0000-0000-0000-0000005330f1/00000000-0000-0000-0000-0000005330a3/f5330000-0000-0000-0000-000000000002.jpg', true);
select set_config('t.bea1', '00000000-0000-0000-0000-0000005330f1/00000000-0000-0000-0000-0000005330a5/f5330000-0000-0000-0000-000000000003.jpg', true);
insert into storage.objects (bucket_id, name, metadata) values
  ('boletas', current_setting('t.ana1'), '{"size": 1000, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.ros1'), '{"size": 1000, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.bea1'), '{"size": 1000, "mimetype": "image/jpeg"}');

-- DO sube las tres y publica; después sube una segunda versión de Bea que
-- queda en borrador (la persona no la ve).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000005330b1', true);
select fn_boleta_guardar_version('00000000-0000-0000-0000-0000005330f1','00000000-0000-0000-0000-0000005330a2','imagen', jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1'))));
select fn_boleta_guardar_version('00000000-0000-0000-0000-0000005330f1','00000000-0000-0000-0000-0000005330a3','imagen', jsonb_build_array(jsonb_build_object('path', current_setting('t.ros1'))));
select fn_boletas_publicar('00000000-0000-0000-0000-0000005330f1');
select fn_boleta_guardar_version('00000000-0000-0000-0000-0000005330f1','00000000-0000-0000-0000-0000005330a5','imagen', jsonb_build_array(jsonb_build_object('path', current_setting('t.bea1'))));

select set_config('t.ana', (select v.id::text from boletas_versiones v join boletas b on b.id = v.boleta_id where b.persona_id = '00000000-0000-0000-0000-0000005330a2'), true);
select set_config('t.ros', (select v.id::text from boletas_versiones v join boletas b on b.id = v.boleta_id where b.persona_id = '00000000-0000-0000-0000-0000005330a3'), true);
select set_config('t.bea', (select v.id::text from boletas_versiones v join boletas b on b.id = v.boleta_id where b.persona_id = '00000000-0000-0000-0000-0000005330a5'), true);

-- ── A · La función y sus permisos ────────────────────────────────────────
select ok(has_function_privilege('authenticated', 'fn_boleta_datos_de_constancia(uuid)', 'EXECUTE'),
  'la puede llamar quien inició sesión');
select ok(not has_function_privilege('anon', 'fn_boleta_datos_de_constancia(uuid)', 'EXECUTE'),
  'y no quien no inició sesión');

-- ── B · Lo que dice ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000005330b1', true);
select is(
  (select nombre || ' | ' || nombre_dni || ' | ' || tipo_documento || ' ' || documento || ' | ' || sede_codigo || ' | ' || cargo
     from fn_boleta_datos_de_constancia(current_setting('t.ana')::uuid)),
  'AnaCons Lab | ANA CONSTANCIA LAB | dni 10000002 | ZZC33 | Vendedora',
  'DO ve el nombre, el del DNI, el documento, la sede y el cargo de Ana');
select is(
  (select pagado_at from fn_boleta_datos_de_constancia(current_setting('t.ana')::uuid)),
  '2018-08-30 17:00:00+00'::timestamptz,
  'la fecha de pago de Ana es la de planilla, no la del periodo (que es la de RxH)');
select is(
  (select tipo_documento || ' · ' || pagado_at::date from fn_boleta_datos_de_constancia(current_setting('t.ros')::uuid)),
  'ce · 2018-09-05',
  'y la de Rosa, que es RxH, es la de su grupo, con su carné de extranjería');
select is(
  (select (nombre_dni is null and documento is null and tipo_documento is null and nombre = 'BeaCons Lab')
     from fn_boleta_datos_de_constancia(current_setting('t.bea')::uuid)),
  true,
  'sin ficha ni documento, vuelven en NULL: no se inventa nada');

update periodo_grupo_pago set estado = 'abierto', pagado_at = null
 where periodo_id = '00000000-0000-0000-0000-0000005330f1' and grupo = 'planilla';
select is((select pagado_at from fn_boleta_datos_de_constancia(current_setting('t.ana')::uuid)), null,
  'si su grupo se reabre, la fecha de pago deja de decirse');
update periodo_grupo_pago set estado = 'pagado', pagado_at = '2018-08-30 17:00:00+00'
 where periodo_id = '00000000-0000-0000-0000-0000005330f1' and grupo = 'planilla';

-- ── C · Quién la ve ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000005330b2', true);
select is((select documento from fn_boleta_datos_de_constancia(current_setting('t.ana')::uuid)), '10000002',
  'Ana ve los datos de su boleta publicada');
select is((select pagado_at from fn_boleta_datos_de_constancia(current_setting('t.ana')::uuid)),
  '2018-08-30 17:00:00+00'::timestamptz,
  'incluida la fecha de pago de su grupo, que no puede leer de la tabla');
select throws_ok($$ select * from fn_boleta_datos_de_constancia(current_setting('t.ros')::uuid) $$,
  'P0001', 'Esa boleta no está disponible.', 'Ana no ve los datos de la boleta de Rosa');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000005330b4', true);
select throws_ok($$ select * from fn_boleta_datos_de_constancia(current_setting('t.ana')::uuid) $$,
  'P0001', 'Esa boleta no está disponible.', 'la líder de equipo tampoco: es la misma regla que la firma');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000005330b5', true);
select throws_ok($$ select * from fn_boleta_datos_de_constancia(current_setting('t.bea')::uuid) $$,
  'P0001', 'Esa boleta no está disponible.', 'Bea no ve los datos de una boleta suya que sigue en borrador');

select throws_ok($$ select * from fn_boleta_datos_de_constancia(gen_random_uuid()) $$,
  'P0001', 'Esa boleta no existe.', 'una versión que no existe lo dice');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_boleta_datos_de_constancia'),
  1, 'hay una sola función con ese nombre (ninguna sobrecarga)');

select * from finish();
rollback;
