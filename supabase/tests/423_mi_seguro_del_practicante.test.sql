-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 423_mi_seguro_del_practicante.test.sql — la 0530 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que una practicante pueda leer su póliza: es
-- que NO pueda leer nada más.
-- (a) cada practicante ve SOLO sus pólizas —ni la de otra practicante, ni la de
--     alguien que ya no lo es, ni una anulada—, y quien no es practicante no ve
--     nada (planilla, DO, una sesión sin ficha),
-- (b) lo que ve no lleva nada interno: la lista de columnas está fijada a
--     propósito, para que una columna nueva sea una decisión y no un descuido,
-- (c) de los archivos ve la póliza y el convenio de pago —no la factura, no «otro»,
--     no uno retirado—, y
-- (d) la función y Storage dicen LO MISMO: lo que `fn_mi_seguro` le muestra es
--     exactamente lo que Storage le deja abrir, archivo por archivo. Dos listas
--     que se escriben a mano en dos sitios terminan distintas; esta prueba es la
--     que lo nota.
-- ============================================================================
begin;
select plan(61);

-- ── Sede y personas ──────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000005300001', 'ZZB30', 'Sede mi seguro', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo, practicante_modalidad, estado, cuenta_de_servicio, fecha_cese) values
  ('00000000-0000-0000-0000-00000530a001', 'AdmMi',  'Lab', '00000000-0000-0000-0000-000005300001', 'admin',      'x', '00000000-0000-0000-0000-00000530b001', '2023-01-01', 'planilla',    'DO',          null,            'activo', false, null),
  ('00000000-0000-0000-0000-00000530a002', 'IntMi',  'Lab', '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b002', '2023-01-01', 'planilla',    'Vendedora',   null,            'activo', false, null),
  ('00000000-0000-0000-0000-00000530a011', 'Ana',    'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b011', '2026-10-01', 'practicante', 'Practicante', 'profesional',   'activo', false, null),
  ('00000000-0000-0000-0000-00000530a012', 'Beto',   'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b012', '2026-10-01', 'practicante', 'Practicante', 'preprofesional','activo', false, null),
  -- Practicante activa a la que NADIE le ha registrado una póliza todavía.
  ('00000000-0000-0000-0000-00000530a013', 'Fabi',   'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b013', '2026-10-01', 'practicante', 'Practicante', 'profesional',   'activo', false, null),
  -- Dani: se registra como practicante, tiene su póliza, y más abajo pasa a planilla.
  ('00000000-0000-0000-0000-00000530a014', 'Dani',   'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b014', '2026-10-01', 'practicante', 'Practicante', 'profesional',   'activo', false, null),
  -- Gaby: una póliza que termina HOY y la renovación que empieza HOY (el caso del último día).
  ('00000000-0000-0000-0000-00000530a015', 'Gaby',   'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b015', '2026-07-01', 'practicante', 'Practicante', 'profesional',   'activo', false, null);
set session_replication_role = origin;

-- Lo que Storage guardaría al recibir cada archivo.
insert into storage.objects (bucket_id, name, metadata) values
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a1.pdf', '{"size": 1779531, "mimetype": "application/pdf"}'),  -- Ana · póliza
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a2.pdf', '{"size": 65536,   "mimetype": "application/pdf"}'),  -- Ana · convenio de pago
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a3.pdf', '{"size": 40000,   "mimetype": "application/pdf"}'),  -- Ana · factura
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a4.jpg', '{"size": 900000,  "mimetype": "image/jpeg"}'),       -- Ana · «otro»
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a5.pdf', '{"size": 70000,   "mimetype": "application/pdf"}'),  -- Ana · convenio que DO retira
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000b1.pdf', '{"size": 1700000, "mimetype": "application/pdf"}'),  -- Beto · póliza
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000b2.pdf', '{"size": 1600000, "mimetype": "application/pdf"}'),  -- Beto · póliza de la anulada
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000d1.pdf', '{"size": 1500000, "mimetype": "application/pdf"}'),  -- Dani · póliza
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000f9.pdf', '{"size": 1000,    "mimetype": "application/pdf"}');  -- huérfano: ninguna fila lo usa

-- ── A · Lo que existe y quién puede llamarlo ─────────────────────────────
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_seguro_archivo_es_mio')),
  2, 'existen las dos funciones de la 0530');

select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_seguro_archivo_es_mio')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'ninguna le responde a quien no inició sesión');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_seguro_archivo_es_mio')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  2, 'y las dos las puede llamar quien sí inició sesión (un grant faltante fallaría en silencio)');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_seguro_archivo_es_mio')
      and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')),
  2, 'las dos son SECURITY DEFINER con el search_path fijo');

select is(
  (select count(*)::int from pg_policies where schemaname = 'storage' and policyname like 'polizas\_seguro\_%'),
  5, 'Storage tiene cinco políticas del bucket: las cuatro de DO y la de lectura propia');

select is(
  (select row(cmd, roles::text)::text from pg_policies
    where schemaname = 'storage' and policyname = 'polizas_seguro_select_propia'),
  row('SELECT', '{authenticated}')::text,
  'la nueva es solo de lectura, y solo para quien inició sesión');

select is(
  (select count(*)::int from pg_policies where schemaname = 'storage'
      and policyname like 'polizas\_seguro\_%' and cmd <> 'SELECT'),
  3, 'las que escriben siguen siendo las tres de DO: insert, update y delete');

-- La lista de columnas, fija. Una columna nueva es una decisión sobre qué ve una
-- persona de sí misma, y esta aserción obliga a tomarla a la vista.
select is(
  (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_mi_seguro'),
  'TABLE(poliza_id uuid, aseguradora text, numero_poliza text, vigente_desde date, vigente_hasta date, cubre_hoy boolean, plan text, beneficio_enfermedad numeric, beneficio_accidente numeric, archivos jsonb)',
  'fn_mi_seguro devuelve estas diez columnas y ninguna más: ni prima, ni pagos, ni nota, ni quién la registró');

-- ── B · Las pólizas de la prueba (las registra DO, como en producción) ────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);

-- Ana: la vigente (92 días, como la de hoy) y su renovación, que empieza el día en
-- que termina la primera. Con prima, nota y pasos marcados: todo lo que NO debe salir.
select set_config('t.ana',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a011', 'Pacífico Seguros', '24043267',
    fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, fn_hoy_lima() + 20, null, null, null, true,
    'Nota interna de DO que Ana no debe leer')::text, true);
select set_config('t.ana_renov',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a011', 'Pacífico Seguros', '24043277',
    fn_hoy_lima() + 82, fn_hoy_lima() + 174, 179.97, null, null, null, null, null, null)::text, true);
select fn_seguro_marcar_paso(current_setting('t.ana')::uuid, 'pagada', fn_hoy_lima() - 3, null);

-- Beto: primero una que se registró por error y se anula, luego la buena.
select set_config('t.beto_mala',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a012', 'Pacífico Seguros', '24043299',
    fn_hoy_lima() - 100, fn_hoy_lima() - 8, 179.97, null, null, null, null, null, null)::text, true);
select fn_seguro_adjuntar(current_setting('t.beto_mala')::uuid, 'poliza', '5b000000-0000-0000-0000-0000000000b2.pdf', 'la-mala.pdf');
select fn_seguro_anular(current_setting('t.beto_mala')::uuid, 'Se registró con otra persona');
select set_config('t.beto',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a012', 'Pacífico Seguros', '24043266',
    fn_hoy_lima() - 5, fn_hoy_lima() + 87, 179.97, null, null, null, null, null, null)::text, true);

-- Dani: póliza vigente; más abajo pasa a planilla.
select set_config('t.dani',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a014', 'Pacífico Seguros', '24043265',
    fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null)::text, true);

-- Gaby: la que termina hoy (a las 12 M) y la renovación que empieza hoy.
select fn_seguro_registrar('00000000-0000-0000-0000-00000530a015', 'Pacífico Seguros', '24043278',
  fn_hoy_lima() - 92, fn_hoy_lima(), 179.97, null, null, null, null, null, null);
select fn_seguro_registrar('00000000-0000-0000-0000-00000530a015', 'Pacífico Seguros', '24043288',
  fn_hoy_lima(), fn_hoy_lima() + 92, 179.97, null, null, null, null, null, null);

-- Los archivos. El convenio de Ana se sube ANTES que su póliza: el orden de la
-- respuesta tiene que ser por tipo, no por quién llegó primero.
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'convenio_pago', '5b000000-0000-0000-0000-0000000000a2.pdf', 'convenio.pdf');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'poliza',        '5b000000-0000-0000-0000-0000000000a1.pdf', 'Poliza APELLIDO NOMBRE.pdf');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'factura',       '5b000000-0000-0000-0000-0000000000a3.pdf', 'factura.pdf');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'otro',          '5b000000-0000-0000-0000-0000000000a4.jpg', 'foto.jpg');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'convenio_pago', '5b000000-0000-0000-0000-0000000000a5.pdf', 'convenio-viejo.pdf');
select fn_seguro_adjuntar(current_setting('t.beto')::uuid, 'poliza',       '5b000000-0000-0000-0000-0000000000b1.pdf', 'beto.pdf');
select fn_seguro_adjuntar(current_setting('t.dani')::uuid, 'poliza',       '5b000000-0000-0000-0000-0000000000d1.pdf', 'dani.pdf');
-- El convenio viejo de Ana se retira (DO se equivocó de archivo).
select fn_seguro_retirar_archivo(
  (select id from polizas_seguro_archivos where storage_path = '5b000000-0000-0000-0000-0000000000a5.pdf'),
  'Era el convenio de otra persona');

-- Dani deja de ser practicante: pasa a planilla con su póliza todavía vigente.
set session_replication_role = replica;
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null
 where id = '00000000-0000-0000-0000-00000530a014';
set session_replication_role = origin;

-- ── C · Ana ve SU seguro, y nada más ─────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
set local role authenticated;

select is((select count(*)::int from fn_mi_seguro()), 2, 'Ana ve sus dos pólizas: la vigente y la renovación');
select is(
  (select array_agg(numero_poliza order by o) from (select numero_poliza, row_number() over () as o from fn_mi_seguro()) t),
  array['24043277', '24043267'],
  'la más reciente primero: primero la renovación y luego la vigente');
select is(
  (select array_agg(cubre_hoy order by o) from (select cubre_hoy, row_number() over () as o from fn_mi_seguro()) t),
  array[false, true],
  'cubre hoy la vigente; la renovación, que empieza el día en que termina la otra, todavía no');
select is(
  (select row(aseguradora, vigente_desde, vigente_hasta)::text from fn_mi_seguro() where numero_poliza = '24043267'),
  row('Pacífico Seguros', fn_hoy_lima() - 10, fn_hoy_lima() + 82)::text,
  'con su aseguradora y su vigencia');
select is(
  (select row(plan, beneficio_enfermedad, beneficio_accidente)::text from fn_mi_seguro() where numero_poliza = '24043267'),
  row(null::text, null::numeric, null::numeric)::text,
  'el plan y los beneficios máximos salen vacíos mientras el corredor no los confirme');
select is(
  (select jsonb_agg(a->>'tipo' order by o) from (
     select a, o from fn_mi_seguro() f, jsonb_array_elements(f.archivos) with ordinality as x(a, o)
      where f.numero_poliza = '24043267') t),
  '["poliza", "convenio_pago"]'::jsonb,
  'de su póliza ve la póliza y el convenio de pago, la póliza primero aunque el convenio se subió antes');
select is(
  (select count(*)::int from fn_mi_seguro() f, jsonb_array_elements(f.archivos) a
    where a->>'storage_path' in ('5b000000-0000-0000-0000-0000000000a3.pdf', '5b000000-0000-0000-0000-0000000000a4.jpg',
                                 '5b000000-0000-0000-0000-0000000000a5.pdf')),
  0, 'no ve la factura, ni «otro», ni el convenio que DO retiró');
select is(
  (select array_agg(k order by k) from (
     select distinct jsonb_object_keys(a) as k from fn_mi_seguro() f, jsonb_array_elements(f.archivos) a) t),
  array['bytes', 'id', 'mime', 'storage_path', 'tipo'],
  'de cada archivo salen cinco datos, y ninguno es el nombre con que DO lo subió');
select is(
  (select (a->>'bytes')::int from fn_mi_seguro() f, jsonb_array_elements(f.archivos) a
    where a->>'storage_path' = '5b000000-0000-0000-0000-0000000000a1.pdf'),
  1779531, 'el peso sale de Storage');
select is(
  (select jsonb_typeof(archivos) || ':' || jsonb_array_length(archivos)::text
     from fn_mi_seguro() where numero_poliza = '24043277'),
  'array:0', 'una póliza sin archivos trae un arreglo vacío, no null');
select is(
  (select count(*)::int from fn_mi_seguro() where numero_poliza in ('24043266', '24043265', '24043299')),
  0, 'ni una póliza de otra persona ni una anulada');

-- Lo de Storage, visto por Ana.
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro'),
  array['5b000000-0000-0000-0000-0000000000a1.pdf', '5b000000-0000-0000-0000-0000000000a2.pdf'],
  'Storage le deja ver exactamente dos archivos: su póliza y su convenio de pago');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '%a3.pdf'),
  0, 'la factura es invisible para ella');

select throws_ok(
  $$ insert into storage.objects (bucket_id, name, metadata)
     values ('polizas-seguro', '5b000000-0000-0000-0000-0000000000aa.pdf', '{"size": 1, "mimetype": "application/pdf"}') $$,
  '42501', null, 'no puede subir un archivo');
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects where bucket_id = 'polizas-seguro';
update storage.objects set metadata = '{"size": 1, "mimetype": "application/pdf"}' where bucket_id = 'polizas-seguro';
select is((select count(*)::int from polizas_seguro), 0, 'ni lee las pólizas directo de la tabla');
reset role;

-- Solo cuenta los archivos de ESTA prueba (`5b…`): la base local es compartida y
-- puede traer archivos de otras sesiones en el mismo bucket.
select is(
  (select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  9, 'intentó borrar y pisar todo y no se perdió ni se cambió ningún archivo');
select is(
  (select (metadata->>'size')::int from storage.objects where name = '5b000000-0000-0000-0000-0000000000a1.pdf'),
  1779531, 'el peso de su póliza sigue intacto');

-- ── D · fn_seguro_archivo_es_mio, archivo por archivo ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
set local role authenticated;
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a1.pdf'), true,  'Ana: su póliza es suya');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a2.pdf'), true,  'Ana: su convenio de pago es suyo');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a3.pdf'), false, 'Ana: su factura NO la abre');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a4.jpg'), false, 'Ana: el papel «otro» NO lo abre');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a5.pdf'), false, 'Ana: lo retirado NO lo abre');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000b1.pdf'), false, 'Ana: la póliza de Beto no es suya');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000f9.pdf'), false, 'Ana: un archivo que ninguna fila usa no es suyo');
select is(fn_seguro_archivo_es_mio(null), false, 'y un null no es de nadie (false, no null)');
reset role;

-- ── E · Beto: lo suyo, y lo anulado no ───────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b012', true);
set local role authenticated;
select is(
  (select array_agg(numero_poliza) from fn_mi_seguro()),
  array['24043266'], 'Beto ve su póliza y no la que se anuló');
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro'),
  array['5b000000-0000-0000-0000-0000000000b1.pdf'],
  'y Storage le deja abrir solo su archivo: ni los de Ana ni el de su póliza anulada');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000b2.pdf'), false, 'el archivo de la póliza anulada no se abre');
reset role;

-- ── F · Quien no es practicante, o no tiene póliza, no ve nada ───────────
-- Un bloque por persona: (sub, descripción).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b013', true);
set local role authenticated;
select is((select count(*)::int from fn_mi_seguro()), 0, 'Fabi, practicante sin póliza registrada: nada, y sin error');
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro'), 0, 'y tampoco ve archivos de nadie');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b002', true);
set local role authenticated;
select is((select count(*)::int from fn_mi_seguro()), 0, 'alguien de planilla: nada');
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro'), 0, 'ni un archivo');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b014', true);
set local role authenticated;
select is((select count(*)::int from fn_mi_seguro()), 0, 'Dani, que dejó de ser practicante, ya no ve su póliza aunque siga vigente');
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro'), 0, 'ni su PDF');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000d1.pdf'), false, 'la función de Storage dice lo mismo');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
set local role authenticated;
select is((select count(*)::int from fn_mi_seguro()), 0, 'DO tampoco ve en «Mi seguro» las de las demás: es lo MÍO, no el tablero');
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'), 9, 'pero DO sigue viendo los nueve archivos de la prueba por su propia política');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a1.pdf'), false, 'y para la función de «lo mío», la póliza de Ana no es de DO');
reset role;

-- Una sesión con usuario pero sin ficha, y una sin sesión: vacío y sin error.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b099', true);
set local role authenticated;
select is((select count(*)::int from fn_mi_seguro()), 0, 'una sesión sin ficha enlazada: vacío, no error');
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro'), 0, 'y sin archivos');
reset role;

select set_config('request.jwt.claim.sub', '', true);
set local role authenticated;
select is((select count(*)::int from fn_mi_seguro()), 0, 'sin identidad en la sesión: vacío, no error');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a1.pdf'), false, 'y ningún archivo es suyo');
reset role;

-- ── G · La función y Storage dicen lo mismo ──────────────────────────────
-- Para cada archivo que EXISTE en las tablas (de cualquier tipo, retirado o no): lo
-- que `fn_mi_seguro` le muestra a Ana, lo que `fn_seguro_archivo_es_mio` dice y lo
-- que Storage le deja ver son el mismo conjunto. Se mide con la identidad de Ana pero
-- como el dueño de las tablas, para poder recorrer TODOS los archivos.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
select is(
  (select array_agg(storage_path order by storage_path) from polizas_seguro_archivos where fn_seguro_archivo_es_mio(storage_path)),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mi_seguro() f, jsonb_array_elements(f.archivos) a),
  'lo que dice la función de Storage y lo que lista fn_mi_seguro es el mismo conjunto de archivos');

set local role authenticated;
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro'),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mi_seguro() f, jsonb_array_elements(f.archivos) a),
  'y lo que Storage le deja ver es ese mismo conjunto');
reset role;

-- ── G2 · El último día no cubre, y DO y la practicante leen lo mismo ──────
-- Gaby: la póliza que termina hoy ya no cubre (vence a las 12 M de ese día) y la
-- renovación que empieza hoy sí. Es el borde donde un `<=` por un `<` deja a alguien
-- «cubierto» un día de más.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b015', true);
set local role authenticated;
select is(
  (select array_agg(numero_poliza || ':' || cubre_hoy order by o)
     from (select numero_poliza, cubre_hoy, row_number() over () as o from fn_mi_seguro()) t),
  array['24043288:true', '24043278:false'],
  'Gaby: la póliza que empieza hoy cubre; la que termina hoy, a las 12 M, ya no');
reset role;

-- La misma cuenta que lee DO: el tablero de la 0528 y «Mi seguro» tienen que decir
-- lo mismo de cada póliza. Se guarda lo que ve cada quien y se compara.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
create temp table t_tablero on commit drop as select poliza_id, cubre_hoy from fn_seguros_tablero() where poliza_id is not null;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
create temp table t_ana on commit drop as select poliza_id, cubre_hoy from fn_mi_seguro();
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b015', true);
create temp table t_gaby on commit drop as select poliza_id, cubre_hoy from fn_mi_seguro();
select is(
  (select count(*)::int from (select * from t_ana union all select * from t_gaby) m
    left join t_tablero t on t.poliza_id = m.poliza_id
    where t.poliza_id is null or t.cubre_hoy is distinct from m.cubre_hoy),
  0, 'de las cuatro pólizas de Ana y de Gaby, «cubre hoy» dice lo mismo en «Mi seguro» que en el tablero de DO');

-- ── H · Los cambios de DO se notan al instante ───────────────────────────
-- DO confirma el plan y el beneficio: Ana los ve.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select fn_seguro_corregir(current_setting('t.ana')::uuid, 'Pacífico Seguros', '24043267',
  fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, fn_hoy_lima() + 20, 'Plan 1', 16800, 36000, true,
  'Nota interna de DO que Ana no debe leer', 'El corredor confirmó el plan');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
set local role authenticated;
select is(
  (select row(plan, beneficio_enfermedad, beneficio_accidente)::text from fn_mi_seguro() where numero_poliza = '24043267'),
  row('Plan 1', 16800.00::numeric, 36000.00::numeric)::text,
  'una vez confirmados por el corredor, el plan y los beneficios aparecen');
reset role;

-- DO retira el convenio de pago de Ana: lo pierde en las dos lecturas.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select fn_seguro_retirar_archivo(
  (select id from polizas_seguro_archivos where storage_path = '5b000000-0000-0000-0000-0000000000a2.pdf'),
  'Era una versión sin firmar');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
set local role authenticated;
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro'),
  array['5b000000-0000-0000-0000-0000000000a1.pdf'],
  'DO retiró su convenio: Storage ya no se lo deja abrir');
select is(
  (select count(*)::int from fn_mi_seguro() f, jsonb_array_elements(f.archivos) a where a->>'tipo' = 'convenio_pago'),
  0, 'y fn_mi_seguro ya no lo lista');
reset role;

-- DO anula la renovación de Ana: desaparece.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select fn_seguro_anular(current_setting('t.ana_renov')::uuid, 'Se registró con las fechas equivocadas');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
set local role authenticated;
select is(
  (select array_agg(numero_poliza) from fn_mi_seguro()),
  array['24043267'], 'la póliza anulada deja de aparecer');
reset role;

-- Si Ana dejara de ser practicante, lo pierde todo; si vuelve, lo recupera.
set session_replication_role = replica;
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null where id = '00000000-0000-0000-0000-00000530a011';
set session_replication_role = origin;
set local role authenticated;
select is(
  (select (select count(*) from fn_mi_seguro()) || ':' || (select count(*) from storage.objects where bucket_id = 'polizas-seguro')),
  '0:0', 'si Ana pasa a planilla, deja de ver su póliza y su PDF (las dos puertas a la vez)');
reset role;
set session_replication_role = replica;
update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'profesional' where id = '00000000-0000-0000-0000-00000530a011';
set session_replication_role = origin;
set local role authenticated;
select is(
  (select (select count(*) from fn_mi_seguro()) || ':' || (select count(*) from storage.objects where bucket_id = 'polizas-seguro')),
  '1:1', 'y si vuelve a ser practicante, los recupera');
reset role;

-- Nada de esto tocó lo de DO: la política de DO sigue mostrándole todo el bucket.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'), 9,
  'DO sigue viendo los nueve archivos de la prueba, también los retirados');
reset role;

select * from finish();
rollback;
