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
select plan(63);

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
  ('00000000-0000-0000-0000-00000610c006', 'Renovada',    'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', '00000000-0000-0000-0000-00000610b006', '2025-01-01', 'rxh', null),
  ('00000000-0000-0000-0000-00000610c007', 'SoloAnulado', 'Rxh', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', '00000000-0000-0000-0000-00000610b007', '2025-01-01', 'rxh', null),
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
select is((select count(*)::int from fn_locaciones_listar()), 0,
  'en el historial solo vería los suyos, y no tiene ninguno');
select throws_ok($$ select * from fn_locaciones_listar('00000000-0000-0000-0000-00000610c006') $$,
  'P0001', 'Solo Desarrollo Organizacional ve los contratos de locación de otra persona.',
  'pedir los de otra persona da error, no una lista vacía que parezca «no tiene»');
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
                         '00000000-0000-0000-0000-00000610a001')),
  0, 'ni la de planilla sin locación, ni la cuenta de servicio, ni DO salen en el tablero');
select is(
  (select row(estado, vinculo_actual)::text from fn_locaciones_tablero() where persona_id = '00000000-0000-0000-0000-00000610d003'),
  row('abierta_sin_rxh', 'cesada')::text,
  'la que cesó con su locación abierta sí sale: hay que terminarla');
select is(
  (select string_agg(estado, ',' order by id) from fn_locaciones_listar('00000000-0000-0000-0000-00000610c006')) is not null
    and (select count(*)::int from fn_locaciones_listar('00000000-0000-0000-0000-00000610c006')) = 2
    and (select string_agg(estado, ',') from fn_locaciones_listar('00000000-0000-0000-0000-00000610c007')) = 'anulado'
    and (select string_agg(estado, ',') from fn_locaciones_listar('00000000-0000-0000-0000-00000610c008')) = 'terminado',
  true, 'el historial trae los anulados y los terminados, con su estado');
reset role;

-- ── D · Registrar un contrato firmado ────────────────────────────────────
select is(
  (select count(*)::int from storage.buckets where id = 'contratos-locacion' and public is false and file_size_limit = 52428800),
  1, 'el bucket de los escaneos existe, es privado y limita a 50 MB');
select is(
  (select count(*)::int from pg_policies where schemaname = 'storage' and policyname like 'contratos\_locacion\_%'),
  5, 'el almacén tiene sus cinco políticas (las cuatro de DO y la de leer lo propio)');
select is(
  (select has_function_privilege('authenticated', 'fn_locacion_registrar(uuid,text,date,date,date,text,text)', 'EXECUTE')
      and not has_function_privilege('anon', 'fn_locacion_registrar(uuid,text,date,date,date,text,text)', 'EXECUTE')),
  true, 'registrar lo puede llamar quien inició sesión, y nadie sin sesión');

-- Lo que Storage guardaría al recibir cada archivo (el peso y el tipo salen de acá).
insert into storage.objects (bucket_id, name, metadata) values
  ('contratos-locacion', '61000000-0000-0000-0000-0000000000a1.pdf', '{"size": 182000, "mimetype": "application/pdf"}'),
  ('contratos-locacion', '61000000-0000-0000-0000-0000000000a2.jpg', '{"size": 900000, "mimetype": "image/jpeg"}'),
  ('contratos-locacion', '61000000-0000-0000-0000-0000000000a3.pdf', '{"size": 1000, "mimetype": "application/pdf"}');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b002","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610c001', 'Diseño', fn_hoy_lima(), fn_hoy_lima() + 180,
       fn_hoy_lima(), '61000000-0000-0000-0000-0000000000a1.pdf', 'contrato.pdf') $$,
  'P0001', 'Solo Desarrollo Organizacional registra contratos de locación.', 'una integrante no registra contratos');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610c001', 'Diseño', fn_hoy_lima(), fn_hoy_lima() + 180,
       fn_hoy_lima(), '61000000-0000-0000-0000-0000000000ff.pdf', 'contrato.pdf') $$,
  'P0001', 'El archivo no llegó al almacén. Vuelve a subirlo.', 'una ruta que no está en el almacén no entra (el archivo va primero)');
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610c001', 'Diseño', fn_hoy_lima(), fn_hoy_lima() + 180,
       fn_hoy_lima(), 'Sin Contrato Rxh DNI.pdf', 'contrato.pdf') $$,
  'P0001', 'La ruta del archivo no tiene la forma esperada.', 'una ruta con nombres no entra');
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610c001', '  ', fn_hoy_lima(), fn_hoy_lima() + 180,
       fn_hoy_lima(), '61000000-0000-0000-0000-0000000000a1.pdf', 'contrato.pdf') $$,
  'P0001', 'Escribe qué servicio se contrata (al menos 3 letras), con las palabras del contrato.', 'ni uno sin servicio');
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610c001', 'Diseño', fn_hoy_lima(), fn_hoy_lima() - 1,
       fn_hoy_lima(), '61000000-0000-0000-0000-0000000000a1.pdf', 'contrato.pdf') $$,
  'P0001', 'El contrato no puede terminar antes de empezar.', 'ni uno que termina antes de empezar');
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610c001', 'Diseño', fn_hoy_lima(), fn_hoy_lima() + 180,
       fn_hoy_lima() + 1, '61000000-0000-0000-0000-0000000000a1.pdf', 'contrato.pdf') $$,
  'P0001', 'La fecha de firma no puede ser posterior a hoy.', 'ni uno firmado mañana');
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610d001', 'Diseño', fn_hoy_lima() - 30, fn_hoy_lima() + 180,
       fn_hoy_lima() - 30, '61000000-0000-0000-0000-0000000000a1.pdf', 'contrato.pdf') $$,
  'P0001', 'Esa persona no cobra por honorarios: solo se le puede archivar una locación que ya terminó.',
  'a alguien de planilla no se le registra una locación vigente: serían dos vínculos a la vez');
select is(
  fn_locacion_registrar('00000000-0000-0000-0000-00000610d001', 'Fotografía de producto', fn_hoy_lima() - 300, fn_hoy_lima() - 100,
    fn_hoy_lima() - 300, '61000000-0000-0000-0000-0000000000a3.pdf', 'locacion-anterior.pdf') is not null,
  true, 'pero sí se le archiva la que ya terminó, la de antes de pasar a planilla');

select set_config('t.nuevo',
  fn_locacion_registrar('00000000-0000-0000-0000-00000610c001', '  Diseño de la colección de invierno ', fn_hoy_lima() - 5,
    fn_hoy_lima() + 180, fn_hoy_lima() - 6, '61000000-0000-0000-0000-0000000000a2.jpg', 'Contrato SinContrato.jpg')::text, true);
select is(
  (select row(servicio, mime, bytes, registrado_por)::text from contratos_locacion where id = current_setting('t.nuevo')::uuid),
  row('Diseño de la colección de invierno', 'image/jpeg', 900000::bigint, '00000000-0000-0000-0000-00000610a001'::uuid)::text,
  'el servicio se recorta, el tipo y el peso salen del almacén y queda quién lo registró');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c001'), 'vigente', 'y quien no tenía contrato pasa a «vigente»');
select throws_ok(
  $$ select fn_locacion_registrar('00000000-0000-0000-0000-00000610c002', 'Otra cosa', fn_hoy_lima(), fn_hoy_lima() + 180,
       fn_hoy_lima(), '61000000-0000-0000-0000-0000000000a2.jpg', 'el-mismo.jpg') $$,
  'P0001', 'Ese archivo ya está registrado en otro contrato.', 'un mismo escaneo no sostiene dos contratos');
select is(
  (select row(fn_locacion_libre('61000000-0000-0000-0000-0000000000a2.jpg'), fn_locacion_libre('61000000-0000-0000-0000-0000000000a1.pdf'))::text),
  row(false, true)::text, 'un escaneo registrado no se puede pisar ni borrar; uno huérfano sí');
reset role;

-- ── E · Anular, terminar, y la locación que quedó abierta ────────────────
-- Alguien que era RxH con su locación vigente y pasó a planilla (eso se hace en
-- Equipo): se escribe directo, porque la función de registrar ya no lo dejaría.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-00000610d004', 'PasoAPlanilla', 'Lab', '00000000-0000-0000-0000-000006100001', 'integrante', 'x', '2025-01-01', 'planilla', 'Vendedora');
set session_replication_role = origin;
select pg_temp.loc('00000000-0000-0000-0000-00000610d004', fn_hoy_lima() - 60, fn_hoy_lima() + 120, '61000000-0000-0000-0000-0000000000d4.pdf');

create function pg_temp.contrato_de(p_persona text) returns uuid language sql as $$
  select id from contratos_locacion where persona_id = p_persona::uuid and anulado_at is null
   order by registrado_at desc, id desc limit 1 $$;
grant execute on function pg_temp.contrato_de(text) to authenticated;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b002","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_anular(pg_temp.contrato_de('00000000-0000-0000-0000-00000610c004'), 'Era de otra persona') $$,
  'P0001', 'Solo Desarrollo Organizacional anula contratos de locación.', 'una integrante no anula');
select throws_ok(
  $$ select fn_locacion_terminar(pg_temp.contrato_de('00000000-0000-0000-0000-00000610c004'), fn_hoy_lima(), 'Pasó a planilla') $$,
  'P0001', 'Solo Desarrollo Organizacional termina contratos de locación.', 'ni termina');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b001","role":"authenticated"}', true);
set local role authenticated;
select is(
  (select row(estado, vinculo_actual)::text from fn_locaciones_tablero() where persona_id = '00000000-0000-0000-0000-00000610d004'),
  row('abierta_sin_rxh', 'planilla')::text,
  'quien pasó a planilla con su locación vigente sale avisada: son dos vínculos a la vez');

-- Anular
select throws_ok(
  $$ select fn_locacion_anular(pg_temp.contrato_de('00000000-0000-0000-0000-00000610c004'), 'mal') $$,
  'P0001', 'Escribe por qué se anula (al menos 5 letras): queda anotado junto al contrato.', 'anular pide motivo');
select set_config('t.vigente', pg_temp.contrato_de('00000000-0000-0000-0000-00000610c004')::text, true);
select fn_locacion_anular(current_setting('t.vigente')::uuid, 'Se registró con la fecha de fin equivocada');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c004'), 'sin_contrato', 'anulado su único contrato, vuelve a «sin contrato»');
select throws_ok(
  $$ select fn_locacion_anular(current_setting('t.vigente')::uuid, 'Otra vez el mismo') $$,
  'P0001', 'Ese contrato ya está anulado.', 'no se anula dos veces');

-- Terminar
select set_config('t.porvencer', pg_temp.contrato_de('00000000-0000-0000-0000-00000610c003')::text, true);
select throws_ok(
  $$ select fn_locacion_terminar(current_setting('t.porvencer')::uuid, fn_hoy_lima() + 60, 'Se resolvió antes') $$,
  'P0001', 'Esa fecha no es antes del fin del contrato: no hace falta terminarlo.', 'terminar en su propia fecha de fin no tiene sentido');
select throws_ok(
  $$ select fn_locacion_terminar(current_setting('t.porvencer')::uuid, fn_hoy_lima() - 102, 'Se resolvió antes') $$,
  'P0001', 'El último día no puede ser anterior a la víspera de su inicio.', 'ni antes de la víspera de empezar');
select fn_locacion_terminar(current_setting('t.porvencer')::uuid, fn_hoy_lima() - 1, 'Se resolvió de común acuerdo');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c003'), 'vencido', 'terminado ayer, ya no la cubre: «vencido»');
select throws_ok(
  $$ select fn_locacion_terminar(current_setting('t.porvencer')::uuid, fn_hoy_lima() - 2, 'Otra fecha') $$,
  'P0001', 'Ese contrato ya se dio por terminado.', 'no se termina dos veces');
select throws_ok(
  $$ select fn_locacion_anular(current_setting('t.porvencer')::uuid, 'Mejor anularlo') $$,
  'P0001', 'Ese contrato ya se dio por terminado: no se anula.', 'ni se anula uno ya terminado: existió');

-- Uno que se termina la víspera de empezar nunca estuvo en vigor.
select fn_locacion_terminar(pg_temp.contrato_de('00000000-0000-0000-0000-00000610c005'), fn_hoy_lima() + 4, 'No llegó a empezar');
select is(pg_temp.estado('00000000-0000-0000-0000-00000610c005'), 'sin_contrato', 'terminado la víspera de empezar: no cubre nada');

-- Terminar la de quien pasó a planilla la saca del tablero.
select fn_locacion_terminar(pg_temp.contrato_de('00000000-0000-0000-0000-00000610d004'), fn_hoy_lima() - 1, 'Pasó a planilla');
select is(
  (select count(*)::int from fn_locaciones_tablero() where persona_id = '00000000-0000-0000-0000-00000610d004'),
  0, 'terminada su locación, quien pasó a planilla deja de salir');
select is(
  (select row(terminado_motivo, terminado_por)::text from contratos_locacion
    where id = current_setting('t.porvencer')::uuid),
  row('Se resolvió de común acuerdo', '00000000-0000-0000-0000-00000610a001'::uuid)::text,
  'el término queda con su motivo y con quién lo hizo');
reset role;

-- ── F · Cada persona ve SU contrato en «Lo mío» ─────────────────────────
-- Renovada (c006) tiene dos contratos vivos; SoloAnulado (c007), uno anulado.
-- Para el escaneo: el almacén guardaría así los dos archivos de Renovada.
insert into storage.objects (bucket_id, name, metadata) values
  ('contratos-locacion', '61000000-0000-0000-0000-000000000061.pdf', '{"size": 1000, "mimetype": "application/pdf"}'),
  ('contratos-locacion', '61000000-0000-0000-0000-000000000007.pdf', '{"size": 1000, "mimetype": "application/pdf"}'),
  ('contratos-locacion', '61000000-0000-0000-0000-000000000004.pdf', '{"size": 1000, "mimetype": "application/pdf"}');

select is(
  (select has_function_privilege('authenticated', 'fn_locacion_es_mia(text)', 'EXECUTE')
      and not has_function_privilege('anon', 'fn_locacion_es_mia(text)', 'EXECUTE')),
  true, 'la comprobación de «es mío» la usa quien inició sesión, y nadie sin sesión');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b006","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from fn_locaciones_listar()), 2, 'quien cobra por honorarios ve sus dos contratos');
select is(
  (select count(*)::int from fn_locaciones_listar() where persona_id <> '00000000-0000-0000-0000-00000610c006'),
  0, 'y ninguno de otra persona');
select is((select count(*)::int from fn_locaciones_tablero()), 0, 'el tablero sigue siendo solo de DO');
select is(
  (select row(fn_locacion_es_mia('61000000-0000-0000-0000-000000000061.pdf'),
              fn_locacion_es_mia('61000000-0000-0000-0000-000000000004.pdf'))::text),
  row(true, false)::text, 'abre su propio escaneo, y no el de otra persona');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'contratos-locacion'
      and name in ('61000000-0000-0000-0000-000000000061.pdf', '61000000-0000-0000-0000-000000000004.pdf')),
  1, 'el almacén le deja leer su archivo y no el ajeno');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b007","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from fn_locaciones_listar()), 0,
  'un contrato anulado no se le muestra: puede ser el de otra persona registrado por error');
select is(fn_locacion_es_mia('61000000-0000-0000-0000-000000000007.pdf'), false, 'ni puede abrir su escaneo');
reset role;

-- Los motivos que DO escribe para DO no viajan a la persona.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000610b006","role":"authenticated"}', true);
set local role authenticated;
select is(
  (select bool_and(terminado_motivo is null and terminado_por_nombre is null) from fn_locaciones_listar()),
  true, 'la persona no ve los motivos internos de DO');
reset role;

select * from finish();
rollback;
