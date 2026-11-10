-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 496_el_contrato_de_locacion_de_quien_cobra_por_honorarios.test.sql — la 0610
-- ============================================================================
-- Lo que hay que proteger acá:
-- (a) que el tablero diga la verdad sobre cada persona por honorarios: quién
--     trabaja sin contrato, a quién se le venció, a quién se le vence pronto,
--     y que una renovación ya registrada apague el «vence pronto»,
-- (b) que en el tablero no aparezca nadie que no sea RxH activo,
-- (c) que nadie fuera de DO lo vea, y que nadie lo escriba a mano, y
-- (d) que un contrato no se edite ni se borre.
-- Las fechas se arman desde `fn_hoy_lima()`: una prueba con fechas fijas se
-- vence sola el día que el calendario la alcanza.
-- ============================================================================
begin;
select plan(23);

-- ── Sede y personas ──────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000006100001', 'ZZL61', 'Sede locación', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-00000610a001', 'DoLoc',    'Lab', '00000000-0000-0000-0000-000006100001', 'admin',      'x', '00000000-0000-0000-0000-00000610b001', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-00000610a002', 'AnaLoc',   'Lab', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', '00000000-0000-0000-0000-00000610b002', '2023-01-01', 'planilla', 'Vendedora'),
  -- Las personas por honorarios, una por cada estado del tablero.
  ('00000000-0000-0000-0000-00000610c001', 'SinContrato', 'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c002', 'Vencido',     'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c003', 'PorVencer',   'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c004', 'Vigente',     'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c005', 'PorEmpezar',  'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c006', 'Renovada',    'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c007', 'SoloAnulado', 'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c008', 'Terminada',   'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', null, '2025-01-01', 'rxh', null);
-- Quien NO tiene que aparecer: una de planilla y una cuenta de servicio con vínculo rxh.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, tipo_vinculo, cargo, cuenta_de_servicio) values
  ('00000000-0000-0000-0000-00000610d001', 'DePlanilla', 'Lab', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', '2023-01-01', 'planilla', 'Vendedora', false),
  ('00000000-0000-0000-0000-00000610d002', 'Estacion',   'Lab', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', '2023-01-01', 'rxh',      null,        true);
-- Y una que cobró por honorarios y ya cesó.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, tipo_vinculo, cargo, estado, fecha_cese) values
  ('00000000-0000-0000-0000-00000610d003', 'Cesada', 'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', '2024-01-01', 'rxh', null, 'inactivo', fn_hoy_lima() - 30);
set session_replication_role = origin;

-- Los contratos se escriben directo como superusuario: esta prueba mira el
-- tablero, no cómo se registran.
create function pg_temp.loc(p_persona text, p_ini date, p_fin date, p_ruta text) returns uuid language sql as $$
  insert into contratos_locacion (persona_id, servicio, fecha_inicio, fecha_fin, fecha_firma, storage_path,
                                  nombre_archivo, mime, bytes, registrado_por)
  values (p_persona::uuid, 'Diseño de la colección', p_ini, p_fin, least(p_ini, fn_hoy_lima()), p_ruta,
          'contrato.pdf', 'application/pdf', 1000, '00000000-0000-0000-0000-00000610a001')
  returning id $$;

select pg_temp.loc('00000000-0000-0000-0000-00000610c002', fn_hoy_lima() - 200, fn_hoy_lima() - 1,  '61000000-0000-0000-0000-000000000002.pdf');
select pg_temp.loc('00000000-0000-0000-0000-00000610c003', fn_hoy_lima() - 100, fn_hoy_lima() + 60, '61000000-0000-0000-0000-000000000003.pdf');
select pg_temp.loc('00000000-0000-0000-0000-00000610c004', fn_hoy_lima() - 100, fn_hoy_lima() + 61, '61000000-0000-0000-0000-000000000004.pdf');
select pg_temp.loc('00000000-0000-0000-0000-00000610c005', fn_hoy_lima() + 5,   fn_hoy_lima() + 200, '61000000-0000-0000-0000-000000000005.pdf');
-- Renovada: la actual vence en 10 días, y la siguiente ya está firmada.
select pg_temp.loc('00000000-0000-0000-0000-00000610c006', fn_hoy_lima() - 300, fn_hoy_lima() + 10, '61000000-0000-0000-0000-000000000061.pdf');
select pg_temp.loc('00000000-0000-0000-0000-00000610c006', fn_hoy_lima() + 11,  fn_hoy_lima() + 400, '61000000-0000-0000-0000-000000000062.pdf');
-- SoloAnulado: su único contrato se registró por error.
select set_config('t.anulado',
  pg_temp.loc('00000000-0000-0000-0000-00000610c007', fn_hoy_lima() - 10, fn_hoy_lima() + 300, '61000000-0000-0000-0000-000000000007.pdf')::text, true);
update contratos_locacion
   set anulado_at = now(), anulado_por = '00000000-0000-0000-0000-00000610a001', anulado_motivo = 'Era de otra persona'
 where id = current_setting('t.anulado')::uuid;
-- Terminada: el contrato llegaba lejos, pero se dio por terminado ayer.
select set_config('t.terminado',
  pg_temp.loc('00000000-0000-0000-0000-00000610c008', fn_hoy_lima() - 50, fn_hoy_lima() + 300, '61000000-0000-0000-0000-000000000008.pdf')::text, true);
update contratos_locacion
   set terminado_el = fn_hoy_lima() - 1, terminado_motivo = 'Se resolvió de común acuerdo',
       terminado_por = '00000000-0000-0000-0000-00000610a001', terminado_at = now()
 where id = current_setting('t.terminado')::uuid;
-- La que ya cesó tenía uno vigente: igual no sale en el tablero.
select pg_temp.loc('00000000-0000-0000-0000-00000610d003', fn_hoy_lima() - 10, fn_hoy_lima() + 300, '61000000-0000-0000-0000-0000000000d3.pdf');

create function pg_temp.estado(p_persona text) returns text language sql as $$
  select estado from fn_locaciones_tablero() where persona_id = p_persona::uuid $$;
-- Desde la 0076 ninguna función nace con EXECUTE: sin esto, la pantalla (authenticated) no puede usarla.
grant execute on function pg_temp.estado(text) to authenticated;

-- ── A · Permisos ─────────────────────────────────────────────────────────
select is(
  (select relrowsecurity from pg_class where relname = 'contratos_locacion'),
  true, 'la tabla tiene RLS');
select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname in ('fn_locaciones_tablero','fn_locaciones_listar')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'ninguna función de locación le responde a quien no inició sesión');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_locaciones_tablero','fn_locaciones_listar')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  2, 'y las dos las puede llamar quien sí inició sesión (un grant faltante fallaría en silencio)');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ insert into contratos_locacion (persona_id, servicio, fecha_inicio, fecha_fin, fecha_firma, storage_path,
                                     nombre_archivo, mime, bytes, registrado_por)
     values ('00000000-0000-0000-0000-00000610c001', 'Algo', fn_hoy_lima(), fn_hoy_lima(), fn_hoy_lima(),
             '61000000-0000-0000-0000-0000000000ff.pdf', 'x.pdf', 'application/pdf', 1,
             '00000000-0000-0000-0000-00000610a001') $$,
  '42501', null, 'ni DO inserta un contrato a mano');
select throws_ok($$ update contratos_locacion set servicio = 'Otro' $$, '42501', null, 'ni lo actualiza a mano');
select throws_ok($$ delete from contratos_locacion $$, '42501', null, 'ni lo borra');
select is((select count(*)::int from contratos_locacion), 9, 'DO lee todos los contratos');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b002","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from contratos_locacion), 0, 'una integrante no lee ningún contrato de locación');
select is((select count(*)::int from fn_locaciones_tablero()), 0, 'ni ve el tablero');
select throws_ok($$ select * from fn_locaciones_listar() $$,
  'P0001', 'Solo Desarrollo Organizacional ve los contratos de locación.', 'ni el historial');
reset role;

-- ── B · Lo que no se edita ni se borra (aun como superusuario) ───────────
select throws_ok(
  $$ update contratos_locacion set fecha_fin = fecha_fin + 30
      where persona_id = '00000000-0000-0000-0000-00000610c003' $$,
  'P0001', 'Un contrato de locación no se edita: si tiene un dato mal, se anula y se registra de nuevo.',
  'mover la fecha de fin de un contrato no se puede: se anula y se registra de nuevo');
select throws_ok(
  $$ delete from contratos_locacion where persona_id = '00000000-0000-0000-0000-00000610c003' $$,
  'P0001', 'Un contrato de locación no se borra: si se registró por error, se anula con motivo.',
  'ni se borra');
select throws_ok(
  $$ update contratos_locacion set anulado_motivo = 'Otro motivo' where id = current_setting('t.anulado')::uuid $$,
  'P0001', 'Ese contrato ya está anulado.', 'una anulación no se reescribe');

-- ── C · Lo que dice el tablero ───────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b001","role":"authenticated"}', true);
set local role authenticated;
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c001'), 'sin_contrato', 'sin ningún contrato: «sin contrato»');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c002'), 'vencido', 'el que terminó ayer y sigue activa: «vencido»');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c003'), 'por_vencer', 'el que termina en 60 días: «vence pronto»');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c004'), 'vigente', 'el que termina en 61 días: «vigente»');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c005'), 'por_empezar', 'hoy sin cubrir pero con uno que empieza en 5 días: «por empezar»');
select is(
  (select row(estado, n_contratos, cubierto_hasta - fn_hoy_lima())::text from fn_locaciones_tablero()
    where persona_id = '00000000-0000-0000-0000-00000610c006'),
  row('vigente', 2, 400)::text,
  'una renovación ya firmada apaga el «vence pronto»: cuenta hasta el fin de la siguiente');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c007'), 'sin_contrato', 'un contrato anulado no cuenta');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c008'), 'vencido', 'uno terminado ayer cuenta hasta su término, no hasta su fecha de fin');
select is(
  (select count(*)::int from fn_locaciones_tablero()
    where persona_id in ('00000000-0000-0000-0000-00000610d001', '00000000-0000-0000-0000-00000610d002',
                         '00000000-0000-0000-0000-00000610d003', '00000000-0000-0000-0000-00000610a001')),
  0, 'ni la de planilla, ni la cuenta de servicio, ni la que ya cesó salen en el tablero');
select is(
  (select string_agg(estado, ',' order by id) from fn_locaciones_listar('00000000-0000-0000-0000-00000610c006')) is not null
    and (select count(*)::int from fn_locaciones_listar('00000000-0000-0000-0000-00000610c006')) = 2
    and (select string_agg(estado, ',') from fn_locaciones_listar('00000000-0000-0000-0000-00000610c007')) = 'anulado'
    and (select string_agg(estado, ',') from fn_locaciones_listar('00000000-0000-0000-0000-00000610c008')) = 'terminado',
  true, 'el historial trae los anulados y los terminados, con su estado');
reset role;

select * from finish();
rollback;
