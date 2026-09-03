-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 274_el_generador_hace_indefinidos.test.sql — 0347
-- ============================================================================
-- Hasta la 0347, `contratos_generados.tipo` no tenía ningún valor para un
-- contrato a plazo indeterminado — todo lo que no era convenio o adendum
-- salía como plazo fijo por inicio o incremento de actividad (art. 57). Esta
-- prueba cuida cuatro promesas de la 0347:
--   1. El CHECK admite 'indefinido', y la constraint nueva ata `fecha_fin` a
--      NULL únicamente para ese tipo — en ambas direcciones.
--   2. `fn_contrato_registrar` rechaza un indefinido CON fecha de fin.
--   3. Firmar un indefinido deja `personas.fecha_fin_contrato` en NULL,
--      incluso si esa persona ya tenía una fecha puesta por un contrato
--      anterior a plazo fijo.
--   4. `fn_contratos_tablero` nunca exige `comunicado_mtpe_at` a un
--      indefinido, y no lo deja atrapado en "sin_vencimiento": llega a 'ok'
--      en cuanto se entrega la copia.
-- ============================================================================
begin;
select plan(10);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000274000', 'ZZ274', 'Sede de laboratorio 274', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000274aa0', 'Jefa', 'Lab274',
        '00000000-0000-0000-0000-000000274000', 'admin', 'h',
        '00000000-0000-0000-0000-000000274aff', '2025-01-02');
set session_replication_role = origin;

-- El sujeto: alguien que YA tiene un contrato a plazo fijo firmado (y por lo
-- tanto ya tiene fecha_fin_contrato puesta) y pasa a indefinido.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000274001', 'Gina', 'Indefinida274',
        '00000000-0000-0000-0000-000000274000', 'h', '2026-01-05');

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000274aff', true);
end $sesion$;

-- ── 0 · Punto de partida: un contrato a plazo fijo YA firmado, con fecha_fin
-- puesta en personas.fecha_fin_contrato — para probar que pasar a indefinido
-- de verdad la BORRA, no que nunca estuvo puesta.
do $previo$
declare v_id uuid;
begin
  v_id := fn_contrato_registrar(
    p_persona_id := '00000000-0000-0000-0000-000000274001', p_tipo := 'nuevo',
    p_cargo := 'Asesora', p_sede_id := '00000000-0000-0000-0000-000000274000',
    p_remuneracion_mensual := 1130,
    p_fecha_inicio := '2026-01-05', p_fecha_fin := '2026-07-05',
    p_documento_html := '<p>plazo fijo previo</p>');
  perform fn_contrato_registrar(p_id := v_id,
    p_storage_path := 'contratos/' || v_id::text || '.pdf', p_fecha_firma := '2026-01-06');
end $previo$;

select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-000000274001'),
  '2026-07-05'::date,
  'punto de partida: el plazo fijo previo dejó fecha_fin_contrato puesta');

-- ── 1 · El CHECK admite 'indefinido' con fecha_fin NULL, vía fn_contrato_registrar ──
select lives_ok(
  $$ select fn_contrato_registrar(
       p_persona_id := '00000000-0000-0000-0000-000000274001', p_tipo := 'indefinido',
       p_cargo := 'Asesora Senior', p_sede_id := '00000000-0000-0000-0000-000000274000',
       p_remuneracion_mensual := 1500, p_fecha_inicio := '2026-07-06', p_fecha_fin := null,
       p_documento_html := '<p>indefinido</p>') $$,
  'fn_contrato_registrar acepta indefinido con fecha_fin null');

select is(
  (select tipo from contratos_generados where documento_html = '<p>indefinido</p>'),
  'indefinido',
  'se guarda tal cual');

select ok(
  (select fecha_fin from contratos_generados where documento_html = '<p>indefinido</p>') is null,
  'y su fecha_fin queda en NULL, no una fecha de relleno');

-- ── 2 · fn_contrato_registrar RECHAZA un indefinido CON fecha de fin ───────
select throws_ok(
  $$ select fn_contrato_registrar(
       p_persona_id := '00000000-0000-0000-0000-000000274001', p_tipo := 'indefinido',
       p_cargo := 'X', p_sede_id := '00000000-0000-0000-0000-000000274000',
       p_remuneracion_mensual := 1500, p_fecha_inicio := '2026-07-06', p_fecha_fin := '2027-07-06',
       p_documento_html := '<p>indefinido con fin, no debe pasar</p>') $$,
  'P0001', 'Un contrato indefinido no lleva fecha de fin.',
  'un indefinido con fecha de fin explícita se rechaza en la función, antes de llegar al CHECK');

-- ── 3 · La constraint de la tabla ata tipo y fecha_fin en las dos direcciones ──
select throws_ok(
  $$ insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin, documento_html, generado_por)
     values ('00000000-0000-0000-0000-000000274001', 'indefinido', 'X',
             '00000000-0000-0000-0000-000000274000', 100, '2026-01-01', '2026-02-01', '<p>x</p>',
             '00000000-0000-0000-0000-000000274aa0') $$,
  '23514', null,
  'un indefinido con fecha_fin puesta rebota contra contrato_fecha_fin_segun_tipo');

select throws_ok(
  $$ insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin, documento_html, generado_por)
     values ('00000000-0000-0000-0000-000000274001', 'nuevo', 'X',
             '00000000-0000-0000-0000-000000274000', 100, '2026-01-01', null, '<p>x</p>',
             '00000000-0000-0000-0000-000000274aa0') $$,
  '23514', null,
  'y un plazo fijo SIN fecha_fin también rebota — la constraint ata los dos tipos por igual');

-- ── 4 · Firmar el indefinido BORRA la fecha de vencimiento que ya tenía ────
do $firma$
declare v_id uuid;
begin
  v_id := (select id from contratos_generados where documento_html = '<p>indefinido</p>');
  perform fn_contrato_registrar(p_id := v_id,
    p_storage_path := 'contratos/' || v_id::text || '.pdf', p_fecha_firma := '2026-07-06');
end $firma$;

select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-000000274001'),
  null,
  'firmar el indefinido deja personas.fecha_fin_contrato en NULL, aunque antes tuviera una fecha puesta');

-- ── 5 · fn_contratos_tablero: pendiente por copia, nunca por MTPE ──────────
select is(
  (select estado from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000274001'),
  'tramite_pendiente',
  'firmado y sin copia entregada: trámite pendiente — nunca "sin_vencimiento", aunque su fecha efectiva sea NULL');

select fn_contrato_marcar_tramite(
  (select id from contratos_generados where documento_html = '<p>indefinido</p>'), 'copia');

select is(
  (select estado from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000274001'),
  'ok',
  'con la copia entregada llega a "ok" sin que nadie haya marcado comunicado al MTPE — ese trámite no le corresponde');

select * from finish();
rollback;
