-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 390_estadisticas_de_casos_para_el_dashboard.test.sql
-- ============================================================================
-- Cubre la migración 0493: `fn_casos_resumen(p_desde)`. No vuelve a probar la
-- regla de acceso completa —eso ya lo blindan 381 y 386—, solo que esta
-- función agrega SOBRE esa misma regla y no por encima de ella:
--   (a) quien gestiona un reporte lo ve reflejado en el resumen;
--   (b) quien no lo gestiona (otra sede, o solo lo escribió) no lo ve, ni
--       siquiera como un número suelto;
--   (c) los campos que devuelve (mes, sede, tipo, vía, estado, vencido)
--       coinciden con el reporte de origen;
--   (d) `p_desde` filtra por `creado_at`, no por hoy;
--   (e) nadie sin `authenticated` puede llamarla.
-- ============================================================================
begin;
select plan(18);

-- ── Semilla ──────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000d5301', 'ZZR01', 'Sede resumen 1', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000d5302', 'ZZR02', 'Sede resumen 2', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-0000000d0301', 'Rita',  'Res', '00000000-0000-0000-0000-0000000d5301', 'integrante',      'x', '00000000-0000-0000-0000-0000000d1301', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000d0302', 'Lola',  'Res', '00000000-0000-0000-0000-0000000d5301', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000d1302', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000d0303', 'Nora',  'Res', '00000000-0000-0000-0000-0000000d5302', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000d1303', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000d0304', 'Dina',  'Res', '00000000-0000-0000-0000-0000000d5301', 'lider_do',        'x', '00000000-0000-0000-0000-0000000d1304', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-0000000d0306', 'Sara',  'Res', '00000000-0000-0000-0000-0000000d5302', 'integrante',      'x', '00000000-0000-0000-0000-0000000d1306', '2023-01-01', 'planilla', 'Vendedora');
set session_replication_role = origin;

create function pg_temp.id_de(p_relato text) returns uuid language sql as $$
  select id from reportes where relato = p_relato;
$$;

-- ── Crear tres reportes: dos en la sede 1, uno en la sede 2 ─────────────────
-- 'empresa', 'idea' y 'consulta' no nombran involucradas, así que no hace
-- falta montar la maquinaria de convivencia ni de Título X: esta prueba es de
-- la agregación, no de la regla de acceso.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1301', true);
select lives_ok($$ select fn_reporte_crear('empresa', 'reclamo', '00000000-0000-0000-0000-0000000d5301',
                     fn_hoy_lima(), 'R1 la caja registradora se traba seguido', '{}', '{}', 'que_cambie') $$,
  'Rita crea un reporte sobre la empresa, en la sede 1');
select lives_ok($$ select fn_reporte_crear('idea', 'reclamo', '00000000-0000-0000-0000-0000000d5301',
                     fn_hoy_lima(), 'R2 poner un espejo más en el probador', '{}', '{}', 'que_cambie') $$,
  'Rita crea una idea de mejora, en la sede 1');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1306', true);
select lives_ok($$ select fn_reporte_crear('consulta', 'reclamo', '00000000-0000-0000-0000-0000000d5302',
                     fn_hoy_lima(), 'R3 puedo cambiar mi turno del sábado', '{}', '{}', null) $$,
  'Sara crea una consulta, en la sede 2');

-- La líder de la sede 1 pone «R2» en revisión: un reporte no queda «recibido»
-- para siempre en esta prueba.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1302', true);
select lives_ok($$ select fn_reporte_en_revision(pg_temp.id_de('R2 poner un espejo más en el probador')) $$,
  'Lola, líder de la sede 1, pone R2 en revisión');

-- Un plazo vencido a mano en R2, con una clave que ese reporte no usa todavía
-- (no toca el que abrió fn_reporte_crear para la vía reclamo).
select lives_ok($$ insert into reporte_plazos (reporte_id, clave, norma, descripcion, duena, desde, vence_at)
                    values (pg_temp.id_de('R2 poner un espejo más en el probador'), 'acuse', 'prueba 390',
                            'plazo vencido de prueba', 'do', now() - interval '10 days', now() - interval '3 days') $$,
  'se abre a mano un segundo plazo, ya vencido, sobre R2');

-- R1 se envejece 4 meses: sirve para probar el filtro `p_desde`.
select lives_ok($$ update reportes set creado_at = now() - interval '4 months'
                    where id = pg_temp.id_de('R1 la caja registradora se traba seguido') $$,
  'R1 se envejece a hace 4 meses, para el filtro p_desde');

-- ── (a)+(b) Cada quien ve lo que gestiona, y nada más ───────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1302', true);
select is( (select count(*) from fn_casos_resumen(null)), 2::bigint,
  'Lola (líder, sede 1) ve sus dos reportes' );
select is( (select count(*) from fn_casos_resumen(null) where sede_codigo <> 'ZZR01'), 0::bigint,
  'y ninguno de la sede 2: R3 no le toca' );

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1303', true);
select is( (select count(*) from fn_casos_resumen(null)), 1::bigint,
  'Nora (líder, sede 2) ve solo el suyo' );
select is( (select sede_codigo from fn_casos_resumen(null) limit 1), 'ZZR02',
  'y es el de su propia sede' );

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1301', true);
select is( (select count(*) from fn_casos_resumen(null)), 0::bigint,
  'Rita, que solo ESCRIBIÓ R1 y R2, no los gestiona: no le aparecen aquí' );

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d1304', true);
select is( (select count(*) from fn_casos_resumen(null)), 3::bigint,
  'Dina (DO) ve los tres reportes, de las dos sedes' );

-- ── (c) Los campos coinciden con el reporte de origen ───────────────────────
select is( (select estado from fn_casos_resumen(null) where sede_codigo = 'ZZR01' and tipo = 'idea'), 'en_revision',
  'R2 aparece con el estado que tiene de verdad' );
select is( (select vencido from fn_casos_resumen(null) where sede_codigo = 'ZZR01' and tipo = 'idea'), true,
  'R2 sale marcado como vencido: el plazo a mano lo cumple' );
select is( (select vencido from fn_casos_resumen(null) where sede_codigo = 'ZZR01' and tipo = 'empresa'), false,
  'R1 no tiene ningún plazo vencido' );
select is( (select mes from fn_casos_resumen(null) where sede_codigo = 'ZZR02'), date_trunc('month', now())::date,
  'el mes de R3 es el de hoy, truncado' );

-- ── (d) `p_desde` filtra por creado_at ───────────────────────────────────────
select is( (select count(*) from fn_casos_resumen(current_date - interval '2 months')), 2::bigint,
  'con p_desde de hace 2 meses, R1 (envejecido a 4) queda fuera: Dina ve solo 2' );
select is( (select count(*) from fn_casos_resumen(current_date - interval '6 months')), 3::bigint,
  'con p_desde de hace 6 meses entran los tres' );

-- ── (e) Nadie sin `authenticated` la llama ──────────────────────────────────
reset role;
set local role anon;
select throws_ok($$ select * from fn_casos_resumen(null) $$, '42501', null,
  'anon no tiene permiso de ejecutar fn_casos_resumen');
reset role;

select * from finish();
rollback;
