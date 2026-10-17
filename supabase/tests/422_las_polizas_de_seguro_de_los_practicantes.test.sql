-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 422_las_polizas_de_seguro_de_los_practicantes.test.sql — la 0528 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) NADIE fuera de DO ve ni escribe una póliza —ni la fila ni el PDF—, porque
--     el papel lleva DNI y fecha de nacimiento del asegurado, y ni siquiera DO
--     escribe las tablas directo: todo pasa por las funciones,
-- (b) el sistema nombra el HUECO: quien es practicante activo y no tiene una
--     póliza que cubra HOY sale sin póliza —ese es el error caro: una persona sin
--     ningún seguro, Ley 28518 art. 52.5—, y una póliza que vence o se anula lo
--     deja a la vista otra vez,
-- (c) «cubre hoy» cuenta el día final como NO cubierto (la póliza vence a las
--     12 M de ese día) y una renovación que empieza ese mismo día no se cruza,
-- (d) nada se borra: una póliza se anula con motivo, un paso se desmarca con
--     motivo, un archivo se retira con motivo, y todo deja su rastro, y
-- (e) el peso y el tipo del archivo salen de Storage, no del navegador.
-- ============================================================================
begin;
select plan(102);

-- ── Sede y personas ──────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000005280001', 'ZZB28', 'Sede seguros', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo, practicante_modalidad, estado, cuenta_de_servicio, fecha_cese) values
  ('00000000-0000-0000-0000-00000528a001', 'AdmSeg',  'Lab', '00000000-0000-0000-0000-000005280001', 'admin',           'x', '00000000-0000-0000-0000-00000528b001', '2023-01-01', 'planilla',    'DO',              null,           'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a002', 'DoSeg',   'Lab', '00000000-0000-0000-0000-000005280001', 'lider_do',        'x', '00000000-0000-0000-0000-00000528b002', '2023-01-01', 'planilla',    'Líder DO',        null,           'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a003', 'EncSeg',  'Lab', '00000000-0000-0000-0000-000005280001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000528b003', '2023-01-01', 'planilla',    'Líder de equipo', null,           'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a004', 'IntSeg',  'Lab', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', '00000000-0000-0000-0000-00000528b004', '2023-01-01', 'planilla',    'Vendedora',       null,           'activo',   false, null),
  -- Los practicantes de la prueba.
  ('00000000-0000-0000-0000-00000528a011', 'Ana',     'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante', 'Practicante',     'profesional',  'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a012', 'Beto',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante', 'Practicante',     'preprofesional','activo',  false, null),
  ('00000000-0000-0000-0000-00000528a013', 'Carla',   'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-01-01', 'practicante', 'Practicante',     'profesional',  'inactivo', false, '2026-10-10'),
  ('00000000-0000-0000-0000-00000528a014', 'Dani',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2025-01-01', 'planilla',    'Vendedora',       null,           'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a015', 'Estacion','Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante', 'Estación',        'profesional',  'activo',   true, null),
  ('00000000-0000-0000-0000-00000528a016', 'Fabi',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante', 'Practicante',     'profesional',  'activo',   false, null);
set session_replication_role = origin;

-- Lo que Storage guardaría al recibir cada archivo (peso y tipo salen de acá).
insert into storage.objects (bucket_id, name, metadata) values
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000001.pdf', '{"size": 1779531, "mimetype": "application/pdf"}'),
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000002.pdf', '{"size": 65536, "mimetype": "application/pdf"}'),
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000003.jpg', '{"size": 900000, "mimetype": "image/jpeg"}'),
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000009.pdf', '{"size": 1000, "mimetype": "application/pdf"}');

-- ── A · El bucket, las tablas y los permisos ─────────────────────────────
select is(
  (select count(*)::int from storage.buckets where id = 'polizas-seguro' and public is false and file_size_limit = 52428800),
  1, 'el bucket existe, es privado y limita a 50 MB por archivo');

select is(
  (select count(*)::int from pg_policies where schemaname = 'storage' and policyname like 'polizas\_seguro\_%'),
  4, 'Storage tiene sus cuatro políticas (insert, select, update, delete)');

select is(
  (select count(*)::int from pg_class where relname in ('polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos') and relrowsecurity),
  3, 'las tres tablas tienen RLS activa');

select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and (p.proname like 'fn\_seguro\_%' or p.proname = 'fn_seguros_tablero')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'ninguna función de seguros le responde a quien no inició sesión');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proname in ('fn_seguro_registrar','fn_seguro_corregir','fn_seguro_marcar_paso','fn_seguro_anular',
                        'fn_seguro_adjuntar','fn_seguro_retirar_archivo','fn_seguro_archivo_libre',
                        'fn_seguros_tablero','fn_seguro_historial','fn_seguro_archivos')),
  10, 'y las diez las puede llamar quien sí inició sesión (un grant faltante fallaría en silencio)');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_seguro_datos_validos'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  0, 'la función de reglas internas no la llama nadie desde fuera');

-- Sin política Y sin privilegio: las dos puertas cerradas (molde de la 0509).
select is(
  (select count(*)::int from pg_policies where schemaname = 'public'
      and tablename in ('polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos') and cmd <> 'SELECT'),
  0, 'ninguna de las tres tablas tiene una política que no sea de lectura');

select is(
  (select count(*)::int from (values ('polizas_seguro'), ('polizas_seguro_archivos'), ('polizas_seguro_eventos')) t(tabla)
    cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) v(priv)
   where has_table_privilege('authenticated', 'public.' || t.tabla, v.priv)),
  0, 'y authenticated no tiene privilegio de escribir en ninguna (ni truncate)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);
set local role authenticated;
select throws_ok(
  $$ insert into polizas_seguro (persona_id, aseguradora, numero_poliza, vigente_desde, vigente_hasta, prima_total, creada_por)
     values ('00000000-0000-0000-0000-00000528a011', 'Pacífico', '99999999', '2026-10-01', '2027-01-01', 1,
             '00000000-0000-0000-0000-00000528a001') $$,
  '42501', null, 'ni DO inserta una póliza a mano: solo por la función');
select throws_ok($$ update polizas_seguro set nota = 'otra' $$, '42501', null, 'ni la actualiza a mano');
select throws_ok($$ delete from polizas_seguro $$, '42501', null, 'ni la borra');
select throws_ok($$ insert into polizas_seguro_eventos (poliza_id, evento, detalle, hecho_por)
     values (gen_random_uuid(), 'registrada', 'inventado', '00000000-0000-0000-0000-00000528a001') $$,
  '42501', null, 'ni escribe un rastro inventado');
reset role;

-- ── B · Quién llama qué ──────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b004', true);
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede registrar pólizas de seguro.', 'una integrante no registra pólizas');
select throws_ok($$ select * from fn_seguros_tablero() $$,
  'P0001', 'Solo Desarrollo Organizacional ve los seguros del equipo.', 'ni ve el tablero');
select throws_ok($$ select * from fn_seguro_historial(gen_random_uuid()) $$,
  'P0001', 'Solo Desarrollo Organizacional ve el historial de una póliza.', 'ni el historial');
select throws_ok($$ select * from fn_seguro_archivos(gen_random_uuid()) $$,
  'P0001', 'Solo Desarrollo Organizacional ve los archivos de una póliza.', 'ni los archivos');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b003', true);
select throws_ok($$ select * from fn_seguros_tablero() $$,
  'P0001', 'Solo Desarrollo Organizacional ve los seguros del equipo.', 'la líder de equipo tampoco lo ve');
select throws_ok(
  $$ select fn_seguro_marcar_paso(gen_random_uuid(), 'pagada', fn_hoy_lima(), null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede marcar los pasos de una póliza.', 'ni marca un paso');

-- ── C · Qué se rechaza al registrar ──────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);
select throws_ok(
  $$ select fn_seguro_registrar(gen_random_uuid(), 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Esa persona no existe.', 'una persona que no existe no entra');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Esta póliza es el Seguro de Salud Practicantes: solo se registra a quien está en modalidad formativa.',
  'a quien está en planilla no se le registra esta póliza');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a013', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Esa persona está inactiva.', 'ni a una practicante que ya se fue');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', '  ', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Escribe la aseguradora.', 'sin aseguradora no entra');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Pacífico', '12',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Escribe el número de la póliza.', 'ni sin número');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Pacífico', '24043267',
       fn_hoy_lima() + 5, fn_hoy_lima() - 5, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'La vigencia tiene que terminar después de empezar.', 'ni una vigencia al revés');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, null, null, null, null, null, null, null) $$,
  'P0001', 'Escribe la prima total (con IGV); puede ser 0 si no hay que pagar.', 'ni sin prima');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, 0, null, null, null) $$,
  'P0001', 'El beneficio máximo por enfermedad tiene que ser mayor que 0, o quedar vacío si no está confirmado.',
  'un beneficio en 0 no vale: o es un monto o queda sin confirmar');

-- ── D · Las pólizas reales de la prueba ──────────────────────────────────
-- Ana: la vigente, como la de hoy (92 días). Beto: una vencida hace 8 días.
select set_config('t.ana',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', '  Pacífico Seguros ', ' 24043267 ',
    fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, fn_hoy_lima() + 20, '  ', null, null, null, '   ')::text, true);
select set_config('t.beto_vieja',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a012', 'Pacífico Seguros', '24043266',
    fn_hoy_lima() - 100, fn_hoy_lima() - 8, 179.97, null, 'Plan 1', 16800, 36000, true, 'Vencida')::text, true);

select is(
  (select row(aseguradora, numero_poliza, plan, nota, producto, creada_por)::text from polizas_seguro where id = current_setting('t.ana')::uuid),
  row('Pacífico Seguros', '24043267', null::text, null::text, 'salud_practicantes', '00000000-0000-0000-0000-00000528a001'::uuid)::text,
  'los textos se recortan, un plan o una nota en blanco quedan vacíos, y queda quién la registró');

select throws_ok(
  format($$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Pacífico', '24043268',
     %L::date, %L::date, 179.97, null, null, null, null, null, null) $$,
     (fn_hoy_lima() + 30)::text, (fn_hoy_lima() + 120)::text),
  'P0001', 'Esa persona ya tiene una póliza que se cruza con esas fechas. Si la anterior estaba mal, anúlala primero.',
  'una póliza que se cruza con otra viva de la misma persona no entra');

-- Una renovación que empieza el día en que la otra termina NO se cruza: así se renueva.
select lives_ok(
  format($$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Pacífico Seguros', '24043267',
     %L::date, %L::date, 179.97, null, null, null, null, null, 'Renovación') $$,
     (fn_hoy_lima() + 82)::text, (fn_hoy_lima() + 174)::text),
  'una renovación que empieza el día en que termina la anterior sí entra (con el mismo número: cambia la vigencia)');

select throws_ok(
  format($$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a012', 'Pacífico Seguros', '24043266',
     %L::date, %L::date, 179.97, null, null, null, null, null, null) $$,
     (fn_hoy_lima() - 100)::text, (fn_hoy_lima() - 20)::text),
  'P0001', 'Esa persona ya tiene una póliza que se cruza con esas fechas. Si la anterior estaba mal, anúlala primero.',
  'y repetir la misma vigencia se rechaza por el cruce antes que por el índice');

select is(
  (select count(*)::int from polizas_seguro_eventos where poliza_id = current_setting('t.ana')::uuid and evento = 'registrada'),
  1, 'registrar deja su rastro');

-- ── E · El hueco: quién no tiene una póliza que cubra hoy ────────────────
select is(
  (select cubre_hoy from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  true, 'la póliza de Ana cubre hoy');
select is(
  (select cubre_hoy from fn_seguros_tablero() where poliza_id = current_setting('t.beto_vieja')::uuid),
  false, 'la de Beto venció hace ocho días: no cubre hoy');
select is(
  (select count(*)::int from fn_seguros_tablero()
    where persona_id = '00000000-0000-0000-0000-00000528a012' and poliza_id is null),
  1, 'Beto —practicante activo sin póliza que cubra hoy— sale con una fila SIN póliza: el hueco');
select is(
  (select count(*)::int from fn_seguros_tablero()
    where persona_id = '00000000-0000-0000-0000-00000528a012' and poliza_id is not null),
  1, 'y su póliza vencida sigue saliendo como historia');
select is(
  (select count(*)::int from fn_seguros_tablero()
    where persona_id = '00000000-0000-0000-0000-00000528a011' and poliza_id is null),
  0, 'Ana, que sí tiene una que cubre hoy, no es un hueco');
select is(
  (select count(*)::int from fn_seguros_tablero() where poliza_id is null
     and persona_id in ('00000000-0000-0000-0000-00000528a013', '00000000-0000-0000-0000-00000528a014',
                        '00000000-0000-0000-0000-00000528a015')),
  0, 'ni la practicante inactiva, ni quien está en planilla, ni una cuenta de servicio son un hueco');
select is(
  (select count(*)::int from fn_seguros_tablero() where poliza_id is null
     and persona_id = '00000000-0000-0000-0000-00000528a016'),
  1, 'Fabi, practicante activa que nunca tuvo póliza, sí');

-- El último día es EXCLUSIVO: la póliza que vence hoy ya no cubre hoy.
select set_config('t.fabi_hoy',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a016', 'Pacífico Seguros', '24043270',
    fn_hoy_lima() - 91, fn_hoy_lima(), 179.97, null, null, null, null, null, null)::text, true);
select is(
  (select cubre_hoy from fn_seguros_tablero() where poliza_id = current_setting('t.fabi_hoy')::uuid),
  false, 'una póliza cuyo último día es hoy ya no cubre hoy (vence a las 12 M de ese día)');
select is(
  (select count(*)::int from fn_seguros_tablero()
    where persona_id = '00000000-0000-0000-0000-00000528a016' and poliza_id is null),
  1, 'así que Fabi sigue siendo un hueco el día en que su póliza vence, no al día siguiente');

-- Una póliza de quien dejó de ser practicante: hay que pedir la baja.
select set_config('t.ana_futura',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'Otra aseguradora', '77777777',
    fn_hoy_lima() + 200, fn_hoy_lima() + 290, 10, null, null, null, null, null, null)::text, true);
set session_replication_role = replica;
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null where id = '00000000-0000-0000-0000-00000528a011';
set session_replication_role = origin;
select is(
  (select es_practicante_activo from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  false, 'cuando Ana pasa a planilla su póliza sale marcada: ya no es practicante activo');
select is(
  (select count(*)::int from fn_seguros_tablero() where persona_id = '00000000-0000-0000-0000-00000528a011' and poliza_id is null),
  0, 'y no es un hueco: quien está en planilla no necesita este seguro');
set session_replication_role = replica;
update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'profesional' where id = '00000000-0000-0000-0000-00000528a011';
set session_replication_role = origin;
select is(
  (select sede from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  'ZZB28', 'la lista dice la sede por su código');
select is(
  (select persona from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  'Ana Seg', 'y el nombre completo');

-- La líder DO también es DO.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b002', true);
select ok((select count(*)::int from fn_seguros_tablero()) > 0, 'la líder DO ve el tablero');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);

-- ── F · Los pasos del papeleo ────────────────────────────────────────────
select throws_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'cobrada', fn_hoy_lima(), null) $$, current_setting('t.ana')),
  'P0001', 'Ese paso no existe: usa pagada, firmada o factura.', 'un paso que no existe se rechaza');
select throws_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'pagada', fn_hoy_lima() + 1, null) $$, current_setting('t.ana')),
  'P0001', 'La fecha no puede ser posterior a hoy.', 'un paso no se marca con fecha de mañana');
select throws_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'pagada', null, null) $$, current_setting('t.ana')),
  'P0001', 'Ese paso ya está sin marcar.', 'desmarcar lo que no estaba marcado se rechaza');

select lives_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'pagada', fn_hoy_lima() - 2, null) $$, current_setting('t.ana')),
  'DO marca la prima como pagada');
select lives_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'firmada', fn_hoy_lima() - 1, null) $$, current_setting('t.ana')),
  'y la póliza como firmada');
select is(
  (select row(pagada_el, firmada_el, factura_recibida_el)::text from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  row(fn_hoy_lima() - 2, fn_hoy_lima() - 1, null::date)::text,
  'el tablero dice cada paso con su fecha, y la factura sigue pendiente');
select throws_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'pagada', fn_hoy_lima() - 2, null) $$, current_setting('t.ana')),
  'P0001', 'Ese paso ya estaba marcado con esa fecha.', 'repetir la misma marca se rechaza');
select lives_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'pagada', fn_hoy_lima() - 3, null) $$, current_setting('t.ana')),
  'se puede volver a marcar con otra fecha (la corrección de una fecha mal puesta)');
select is(
  (select detalle from polizas_seguro_eventos
    where poliza_id = current_setting('t.ana')::uuid and evento = 'paso_marcado' and detalle like 'Prima pagada: %'),
  'Prima pagada: ' || to_char(fn_hoy_lima() - 2, 'DD/MM/YYYY') || ' → ' || to_char(fn_hoy_lima() - 3, 'DD/MM/YYYY'),
  'y el rastro dice la fecha de antes y la de después');

select throws_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'firmada', null, 'no') $$, current_setting('t.ana')),
  'P0001', 'Escribe el motivo (al menos 5 letras): desmarcar un paso queda anotado.', 'desmarcar pide motivo');
select lives_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'firmada', null, 'la firmada era otra póliza') $$, current_setting('t.ana')),
  'con motivo, DO desmarca');
select is(
  (select firmada_el from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  null::date, 'y el paso vuelve a pendiente');
select is(
  (select motivo from polizas_seguro_eventos
    where poliza_id = current_setting('t.ana')::uuid and evento = 'paso_desmarcado'),
  'la firmada era otra póliza', 'con su motivo en el historial');

-- ── G · Corregir ─────────────────────────────────────────────────────────
select throws_ok(
  format($$ select fn_seguro_corregir(%L, 'Pacífico Seguros', '24043267', %L::date, %L::date, 179.97, %L::date, null, null, null, null, null, 'sin cambios') $$,
    current_setting('t.ana'), (fn_hoy_lima() - 10)::text, (fn_hoy_lima() + 82)::text, (fn_hoy_lima() + 20)::text),
  'P0001', 'No cambiaste ningún dato.', 'corregir sin cambiar nada se rechaza');
select throws_ok(
  format($$ select fn_seguro_corregir(%L, 'Pacífico Seguros', '24043267', %L::date, %L::date, 179.97, %L::date, 'Plan 1', null, null, null, null, 'no') $$,
    current_setting('t.ana'), (fn_hoy_lima() - 10)::text, (fn_hoy_lima() + 82)::text, (fn_hoy_lima() + 20)::text),
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado en el historial de la póliza.', 'corregir pide motivo');
select throws_ok(
  format($$ select fn_seguro_corregir(%L, 'Pacífico Seguros', '24043267', %L::date, %L::date, 179.97, %L::date, 'Plan 1', null, null, null, null, 'se pisa con la renovación') $$,
    current_setting('t.ana'), (fn_hoy_lima() - 10)::text, (fn_hoy_lima() + 100)::text, (fn_hoy_lima() + 20)::text),
  'P0001', 'Esas fechas se cruzan con otra póliza de la misma persona.', 'ni corregir una vigencia hasta pisar la renovación');

select lives_ok(
  format($$ select fn_seguro_corregir(%L, 'Pacífico Seguros', '24043267', %L::date, %L::date, 179.97, %L::date, ' Plan 1 ', 16800, 36000, false, null, 'lo confirmó el corredor') $$,
    current_setting('t.ana'), (fn_hoy_lima() - 10)::text, (fn_hoy_lima() + 82)::text, (fn_hoy_lima() + 20)::text),
  'DO completa el plan y los beneficios cuando el corredor los confirma');
select is(
  (select row(plan, beneficio_enfermedad, beneficio_accidente, renueva_sola)::text from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  row('Plan 1', 16800.00::numeric, 36000.00::numeric, false)::text,
  'el tablero los muestra, con el plan recortado');
select is(
  (select detalle from polizas_seguro_eventos where poliza_id = current_setting('t.ana')::uuid and evento = 'datos_corregidos'),
  'plan: sin confirmar → Plan 1; beneficio por enfermedad: sin confirmar → 16800.00; beneficio por accidente: sin confirmar → 36000.00; renueva sola: sin confirmar → no',
  'y el rastro dice qué era antes de cada campo («sin confirmar» cuando estaba vacío)');

-- ── H · Anular ───────────────────────────────────────────────────────────
select throws_ok(
  format($$ select fn_seguro_anular(%L, 'no') $$, current_setting('t.fabi_hoy')),
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado junto a la póliza.', 'anular pide motivo');
select lives_ok(
  format($$ select fn_seguro_anular(%L, '  la registré a la persona equivocada  ') $$, current_setting('t.fabi_hoy')),
  'DO anula una póliza registrada por error');
select is(
  (select count(*)::int from fn_seguros_tablero() where poliza_id = current_setting('t.fabi_hoy')::uuid),
  0, 'la anulada deja de salir en el tablero');
select is(
  (select row(anulada_por, anulada_motivo)::text from polizas_seguro where id = current_setting('t.fabi_hoy')::uuid),
  row('00000000-0000-0000-0000-00000528a001'::uuid, 'la registré a la persona equivocada')::text,
  'pero la fila se conserva, con quién la anuló y por qué');
select throws_ok(
  format($$ select fn_seguro_anular(%L, 'otra vez más') $$, current_setting('t.fabi_hoy')),
  'P0001', 'Esa póliza ya está anulada.', 'no se anula dos veces');
select throws_ok(
  format($$ select fn_seguro_marcar_paso(%L, 'pagada', fn_hoy_lima(), null) $$, current_setting('t.fabi_hoy')),
  'P0001', 'Esa póliza está anulada: no se marca.', 'una anulada no se marca');
select throws_ok(
  format($$ select fn_seguro_corregir(%L, 'Pacífico', '24043270', %L::date, %L::date, 1, null, null, null, null, null, null, 'otra cosa') $$,
    current_setting('t.fabi_hoy'), (fn_hoy_lima() - 91)::text, fn_hoy_lima()::text),
  'P0001', 'Esa póliza está anulada: no se corrige.', 'ni se corrige');
select lives_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a016', 'Pacífico Seguros', '24043270',
       fn_hoy_lima() - 91, fn_hoy_lima() + 1, 179.97, null, null, null, null, null, null) $$,
  'y con la anulada fuera, se puede registrar la correcta con el mismo número y la misma fecha de inicio');
select is(
  (select count(*)::int from fn_seguros_tablero() where persona_id = '00000000-0000-0000-0000-00000528a016' and poliza_id is null),
  0, 'y Fabi deja de ser un hueco');

-- ── I · Los archivos ─────────────────────────────────────────────────────
select throws_ok(
  format($$ select fn_seguro_adjuntar(%L, 'poliza', '5a000000-0000-0000-0000-0000000000ff.pdf', 'x.pdf') $$, current_setting('t.ana')),
  'P0001', 'El archivo no llegó al almacén. Vuelve a subirlo.', 'una ruta que no existe en Storage no entra (el archivo va primero)');
select throws_ok(
  format($$ select fn_seguro_adjuntar(%L, 'poliza', 'Nombre Apellido DNI.pdf', 'x.pdf') $$, current_setting('t.ana')),
  'P0001', 'La ruta del archivo no tiene la forma esperada.', 'una ruta con nombres no entra');
select throws_ok(
  format($$ select fn_seguro_adjuntar(%L, 'recibo', '5a000000-0000-0000-0000-000000000001.pdf', 'x.pdf') $$, current_setting('t.ana')),
  'P0001', 'Ese tipo de archivo no existe: usa poliza, convenio_pago, factura u otro.', 'un tipo inventado no entra');
select throws_ok(
  format($$ select fn_seguro_adjuntar(%L, 'poliza', '5a000000-0000-0000-0000-000000000001.pdf', '  ') $$, current_setting('t.ana')),
  'P0001', 'Falta el nombre del archivo.', 'ni sin nombre');
select throws_ok(
  format($$ select fn_seguro_adjuntar(%L, 'poliza', '5a000000-0000-0000-0000-000000000001.pdf', 'x.pdf') $$, current_setting('t.fabi_hoy')),
  'P0001', 'Esa póliza está anulada: no se le adjuntan archivos.', 'a una anulada no se le adjunta nada');

select set_config('t.arch_poliza',
  fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'poliza', '5a000000-0000-0000-0000-000000000001.pdf',
    '  Cayla, Ana Seg, FOLA 24043267.pdf ')::text, true);
select set_config('t.arch_conv',
  fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'convenio_pago', '5a000000-0000-0000-0000-000000000003.jpg',
    'convenio.jpg')::text, true);

select is(
  (select row(mime, bytes, nombre_archivo, subido_por)::text from polizas_seguro_archivos where id = current_setting('t.arch_poliza')::uuid),
  row('application/pdf', 1779531::bigint, 'Cayla, Ana Seg, FOLA 24043267.pdf', '00000000-0000-0000-0000-00000528a001'::uuid)::text,
  'el tipo y el peso salen de Storage, el nombre se recorta y queda quién lo subió');
select throws_ok(
  format($$ select fn_seguro_adjuntar(%L, 'factura', '5a000000-0000-0000-0000-000000000001.pdf', 'otra.pdf') $$, current_setting('t.beto_vieja')),
  'P0001', 'Ese archivo ya está adjunto a una póliza.', 'un mismo archivo no se adjunta dos veces');
select is(
  (select archivos from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  2, 'el tablero cuenta los archivos');

select throws_ok(
  format($$ select fn_seguro_retirar_archivo(%L, 'no') $$, current_setting('t.arch_conv')),
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado junto al archivo.', 'retirar un archivo pide motivo');
select lives_ok(
  format($$ select fn_seguro_retirar_archivo(%L, 'era el convenio de otra persona') $$, current_setting('t.arch_conv')),
  'DO retira un archivo');
select throws_ok(
  format($$ select fn_seguro_retirar_archivo(%L, 'otra vez más') $$, current_setting('t.arch_conv')),
  'P0001', 'Ese archivo ya está retirado.', 'no se retira dos veces');
select is(
  (select archivos from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  1, 'el tablero ya no cuenta el retirado');
select is(
  (select count(*)::int from fn_seguro_archivos(current_setting('t.ana')::uuid)),
  2, 'pero la lista de archivos de la póliza sí lo muestra, para que se vea qué se retiró');
select is(
  (select retirado_motivo from fn_seguro_archivos(current_setting('t.ana')::uuid) where id = current_setting('t.arch_conv')::uuid),
  'era el convenio de otra persona', 'con su motivo');
select is(
  (select subido_por_nombre from fn_seguro_archivos(current_setting('t.ana')::uuid) where id = current_setting('t.arch_poliza')::uuid),
  'AdmSeg Lab', 'y la lista dice quién subió cada uno');

-- ── J · El historial ─────────────────────────────────────────────────────
select is(
  (select string_agg(evento, ',' order by orden) from (
     select evento, row_number() over (order by hecho_at, id) as orden
       from polizas_seguro_eventos where poliza_id = current_setting('t.ana')::uuid) t),
  'registrada,paso_marcado,paso_marcado,paso_marcado,paso_desmarcado,datos_corregidos,archivo_adjuntado,archivo_adjuntado,archivo_retirado',
  'el historial de Ana cuenta, en orden, todo lo que se hizo con su póliza');
select is(
  (select count(*)::int from fn_seguro_historial(current_setting('t.ana')::uuid)),
  9, 'y la función lo devuelve entero');
select is(
  (select hecho_por from fn_seguro_historial(current_setting('t.ana')::uuid) limit 1),
  'AdmSeg Lab', 'con quién lo hizo');

-- Una fila de rastro no se cambia ni siquiera desde el SQL Editor? Las tablas se
-- cierran por privilegio, no por trigger: quien escribe es `postgres` y eso es
-- adrede (el SQL Editor y las funciones). Lo que se prueba es la puerta de usuario.

-- ── K · Los archivos en Storage ──────────────────────────────────────────
select is(fn_seguro_archivo_libre('5a000000-0000-0000-0000-000000000001.pdf'), false, 'un archivo que usa una fila no está libre');
select is(fn_seguro_archivo_libre('5a000000-0000-0000-0000-000000000003.jpg'), false, 'ni uno retirado: el retiro conserva el archivo');
select is(fn_seguro_archivo_libre('5a000000-0000-0000-0000-000000000009.pdf'), true,  'uno que nadie usa sí');

-- Storage nuevo prohíbe el DELETE directo salvo con esta marca; la política
-- de RLS es lo que se prueba, no ese freno.
select set_config('storage.allow_delete_query', 'true', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b004', true);
set local role authenticated;
select is(
  (select count(*)::int from storage.objects where bucket_id = 'polizas-seguro'),
  0, 'una integrante no ve ningún archivo del bucket');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, metadata)
     values ('polizas-seguro', '5a000000-0000-0000-0000-0000000000aa.pdf', '{"size": 1, "mimetype": "application/pdf"}') $$,
  '42501', null, 'ni sube uno');
select is((select count(*)::int from polizas_seguro), 0, 'ni lee las pólizas directo de la tabla');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b003', true);
set local role authenticated;
select is(
  (select count(*)::int from storage.objects where bucket_id = 'polizas-seguro'),
  0, 'la líder de equipo tampoco');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);
set local role authenticated;
select is(
  (select count(*)::int from storage.objects where bucket_id = 'polizas-seguro'),
  4, 'DO ve los cuatro');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, metadata)
     values ('polizas-seguro', 'Nombre Apellido DNI.pdf', '{"size": 1, "mimetype": "application/pdf"}') $$,
  '42501', null, 'DO no sube un archivo con nombres en la ruta');
delete from storage.objects where bucket_id = 'polizas-seguro' and name = '5a000000-0000-0000-0000-000000000001.pdf';
update storage.objects set metadata = '{"size": 1, "mimetype": "application/pdf"}'
 where bucket_id = 'polizas-seguro' and name = '5a000000-0000-0000-0000-000000000001.pdf';
delete from storage.objects where bucket_id = 'polizas-seguro' and name = '5a000000-0000-0000-0000-000000000009.pdf';
reset role;

select is(
  (select (metadata->>'size')::int from storage.objects where bucket_id = 'polizas-seguro' and name = '5a000000-0000-0000-0000-000000000001.pdf'),
  1779531, 'el archivo que usa una fila no se borró ni se pisó');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name = '5a000000-0000-0000-0000-000000000009.pdf'),
  0, 'el huérfano sí se pudo limpiar');

select * from finish();
rollback;
