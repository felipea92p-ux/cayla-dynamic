-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 265_el_generador_hace_convenios_de_practicas.test.sql — 0333
-- ============================================================================
-- Hasta la 0333, `contratos_generados.tipo` solo aceptaba tres valores, todos
-- de un contrato de trabajo. Una practicante (0322) no tiene contrato de
-- trabajo — necesitaba su propio tipo de documento, y esta prueba cuida las
-- tres promesas de la 0333: que el CHECK lo admita, que `fn_contrato_registrar`
-- lo guarde y mueva `fecha_fin_contrato` igual que un contrato, y que
-- `fn_contratos_tablero` deje de exigir `en_planilla` para mostrarla.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000265000', 'ZZ265', 'Sede de laboratorio 265', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000265aa0', 'Jefa', 'Lab265',
        '00000000-0000-0000-0000-000000265000', 'admin', 'h',
        '00000000-0000-0000-0000-000000265aff', '2025-01-02');
set session_replication_role = origin;

-- Una practicante — la 0322 ya la da de alta bajo modalidad formativa.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo, practicante_modalidad)
values ('00000000-0000-0000-0000-000000265001', 'Nora', 'Practicante265',
        '00000000-0000-0000-0000-000000265000', 'h', '2026-06-01', 'practicante', 'preprofesional');

do $sesion$ begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000265aff', true);
end $sesion$;

-- ── 1 · El CHECK admite el cuarto tipo, vía fn_contrato_registrar ──────────
select lives_ok(
  $$ select fn_contrato_registrar(
       p_persona_id := '00000000-0000-0000-0000-000000265001', p_tipo := 'convenio_practicas',
       p_cargo := 'Practicante de Sistemas', p_sede_id := '00000000-0000-0000-0000-000000265000',
       p_remuneracion_mensual := 1025, p_fecha_inicio := '2026-06-01', p_fecha_fin := '2026-12-01',
       p_documento_html := '<p>convenio</p>') $$,
  'fn_contrato_registrar acepta convenio_practicas sin reventar el CHECK que la 0333 reconstruyó');

select is(
  (select tipo from contratos_generados where documento_html = '<p>convenio</p>'),
  'convenio_practicas',
  'Se guarda tal cual — no traducido a nuevo/renovacion');

-- ── 2 · El CHECK sigue siendo un CHECK: rechaza un tipo inventado ──────────
select throws_ok(
  $$ insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin, documento_html, generado_por)
     values ('00000000-0000-0000-0000-000000265001', 'tipo_que_no_existe', 'X',
             '00000000-0000-0000-0000-000000265000', 100, '2026-01-01', '2026-02-01', '<p>x</p>',
             '00000000-0000-0000-0000-000000265aa0') $$,
  '23514',
  null,
  'un tipo que no está en la lista sigue rebotando contra el CHECK');

-- ── 3 · Firmar el convenio mueve fecha_fin_contrato, igual que un contrato ──
select fn_contrato_registrar(
  p_id := (select id from contratos_generados where documento_html = '<p>convenio</p>'),
  p_storage_path := 'contratos/' || (select id from contratos_generados where documento_html = '<p>convenio</p>')::text || '.pdf',
  p_fecha_firma := '2026-06-05');

select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-000000265001'),
  '2026-12-01'::date,
  'Firmar el convenio fija fecha_fin_contrato — se reusa como fecha de fin del convenio (0333)');

-- ── 4 · fn_contratos_tablero ya no exige en_planilla ────────────────────────
-- La practicante tiene en_planilla=false (columna generada) pero SÍ está
-- tipo_vinculo='practicante' — el filtro viejo la habría dejado afuera.
select ok(
  exists (select 1 from fn_contratos_tablero() where persona_id = '00000000-0000-0000-0000-000000265001'),
  'Una practicante con convenio aparece en el tablero de contratos');

select is(
  (select en_planilla from personas where id = '00000000-0000-0000-0000-000000265001'),
  false,
  'Confirmación de que sí es en_planilla=false — si esto cambiara, la prueba 4 dejaría de probar lo que dice probar');

select * from finish();
rollback;
