-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 423_mi_seguro_de_cada_colaborador.test.sql — la 0530 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que alguien pueda leer su póliza: es que NO
-- pueda leer nada más.
-- (a) cada colaborador ve SOLO su seguro y SUS pólizas —ni las de otra persona, ni las
--     anuladas—, y quien no tiene ficha o no hace sesión no ve nada,
-- (b) la puerta es «es MI póliza», no «hoy estoy en ese seguro»: quien pasó de FOLA a
--     EsSalud conserva su póliza y su PDF,
-- (c) lo que ve no lleva nada interno: las listas de columnas están fijadas a propósito,
--     para que una columna nueva sea una decisión y no un descuido,
-- (d) un seguro sin póliza (EsSalud) no inventa una póliza ni un hueco,
-- (e) de los archivos ve la póliza y el convenio de pago —no la factura, no «otro», no
--     uno retirado—, y
-- (f) la función y Storage dicen LO MISMO: lo que `fn_mis_polizas` le muestra es
--     exactamente lo que Storage le deja abrir, archivo por archivo; y «en qué seguro
--     está» y «cubre hoy» dicen lo mismo que lee DO en `fn_seguros_equipo` y en
--     `fn_seguros_tablero`.
-- ============================================================================
begin;
select plan(91);

-- ── Sede y personas ──────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000005300001', 'ZZB30', 'Sede mi seguro', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo, practicante_modalidad, estado, cuenta_de_servicio, fecha_cese) values
  ('00000000-0000-0000-0000-00000530a001', 'AdmMi',    'Lab', '00000000-0000-0000-0000-000005300001', 'admin',      'x', '00000000-0000-0000-0000-00000530b001', '2023-01-01', 'planilla',    'DO',          null,             'activo', false, null),
  -- Planilla: EsSalud, que no lleva póliza.
  ('00000000-0000-0000-0000-00000530a002', 'PlaMi',    'Lab', '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b002', '2023-01-01', 'planilla',    'Vendedora',   null,             'activo', false, null),
  -- Los practicantes: FOLA.
  ('00000000-0000-0000-0000-00000530a011', 'Ana',      'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b011', '2026-10-01', 'practicante', 'Practicante', 'profesional',    'activo', false, null),
  ('00000000-0000-0000-0000-00000530a012', 'Beto',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b012', '2026-10-01', 'practicante', 'Practicante', 'preprofesional', 'activo', false, null),
  -- Fabi: practicante a la que nadie le ha registrado una póliza todavía.
  ('00000000-0000-0000-0000-00000530a013', 'Fabi',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b013', '2026-10-01', 'practicante', 'Practicante', 'profesional',    'activo', false, null),
  -- Dani: se registra como practicante, tiene su póliza FOLA, y más abajo pasa a planilla.
  ('00000000-0000-0000-0000-00000530a014', 'Dani',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b014', '2026-10-01', 'practicante', 'Practicante', 'profesional',    'activo', false, null),
  -- Gaby: una póliza que termina HOY y la renovación que empieza HOY (el caso del último día).
  ('00000000-0000-0000-0000-00000530a015', 'Gaby',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b015', '2026-07-01', 'practicante', 'Practicante', 'profesional',    'activo', false, null),
  -- Hugo: de planilla, pero DO lo pasó a FOLA con una asignación.
  ('00000000-0000-0000-0000-00000530a016', 'Hugo',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b016', '2025-01-01', 'planilla',    'Vendedor',    null,             'activo', false, null),
  -- Iris: de planilla (EsSalud) y, además, un seguro complementario con su propia póliza.
  ('00000000-0000-0000-0000-00000530a017', 'Iris',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b017', '2024-01-01', 'planilla',    'Vendedora',   null,             'activo', false, null),
  -- Honorarios: no le corresponde un seguro principal. Y una persona a prueba, que va a EsSalud.
  ('00000000-0000-0000-0000-00000530a018', 'Rolo',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b018', '2026-03-01', 'rxh',         'Honorarios',  null,             'activo', false, null),
  ('00000000-0000-0000-0000-00000530a019', 'Nora',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b019', '2026-10-01', 'prueba',      'Vendedora',   null,             'activo', false, null),
  -- Lalo: su ÚNICA póliza FOLA termina HOY y no hay renovación: hoy no tiene cobertura (el borde del último día).
  ('00000000-0000-0000-0000-00000530a021', 'Lalo',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b021', '2026-07-01', 'practicante', 'Practicante', 'profesional',    'activo', false, null),
  -- Mara: practicante cuyo seguro principal (FOLA) no tiene póliza, pero SÍ una vigente de otro seguro. Esa no la cubre en FOLA.
  ('00000000-0000-0000-0000-00000530a022', 'Mara',     'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b022', '2026-10-01', 'practicante', 'Practicante', 'profesional',    'activo', false, null),
  -- La cuenta de servicio de un terminal no es una persona.
  ('00000000-0000-0000-0000-00000530a020', 'Estacion', 'Mi',  '00000000-0000-0000-0000-000005300001', 'integrante', 'x', '00000000-0000-0000-0000-00000530b020', '2026-10-01', 'planilla',    'Estación',    null,             'activo', true,  null);
set session_replication_role = origin;

-- Lo que Storage guardaría al recibir cada archivo (peso y tipo salen de acá). Los nombres
-- son hexadecimales a propósito: la ruta tiene que ser `<uuid>.<ext>`.
insert into storage.objects (bucket_id, name, metadata) values
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a1.pdf', '{"size": 1779531, "mimetype": "application/pdf"}'),  -- Ana · póliza
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a2.pdf', '{"size": 65536,   "mimetype": "application/pdf"}'),  -- Ana · convenio de pago
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a3.pdf', '{"size": 40000,   "mimetype": "application/pdf"}'),  -- Ana · factura
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a4.jpg', '{"size": 900000,  "mimetype": "image/jpeg"}'),       -- Ana · «otro»
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000a5.pdf', '{"size": 70000,   "mimetype": "application/pdf"}'),  -- Ana · convenio que DO retira
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000b1.pdf', '{"size": 1700000, "mimetype": "application/pdf"}'),  -- Beto · póliza
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000b2.pdf', '{"size": 1600000, "mimetype": "application/pdf"}'),  -- Beto · póliza de la anulada
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000d1.pdf', '{"size": 1500000, "mimetype": "application/pdf"}'),  -- Dani · póliza FOLA
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000c1.pdf', '{"size": 1400000, "mimetype": "application/pdf"}'),  -- Hugo · póliza FOLA
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000e1.pdf', '{"size": 300000,  "mimetype": "application/pdf"}'),  -- Iris · póliza complementaria
  ('polizas-seguro', '5b000000-0000-0000-0000-0000000000f9.pdf', '{"size": 1000,    "mimetype": "application/pdf"}');  -- huérfano: ninguna fila lo usa

-- ── A · Lo que existe y quién puede llamarlo ─────────────────────────────
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_mis_polizas', 'fn_seguro_archivo_es_mio')),
  3, 'existen las tres funciones de la 0530');

select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_mis_polizas', 'fn_seguro_archivo_es_mio')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'ninguna le responde a quien no inició sesión');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_mis_polizas', 'fn_seguro_archivo_es_mio')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  3, 'y las tres las puede llamar quien sí inició sesión (un grant faltante fallaría en silencio)');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_mi_seguro', 'fn_mis_polizas', 'fn_seguro_archivo_es_mio')
      and p.prosecdef and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')),
  3, 'las tres son SECURITY DEFINER con el search_path fijo');

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

-- Las listas de columnas, fijas. Una columna nueva es una decisión sobre qué ve una persona
-- de sí misma, y estas aserciones obligan a tomarla a la vista.
select is(
  (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_mi_seguro'),
  'TABLE(tipo text, tipo_nombre text, con_poliza boolean, cubre_hoy boolean)',
  'fn_mi_seguro devuelve estas cuatro columnas y ninguna más: ni la descripción del seguro, ni quién se lo asignó');

select is(
  (select pg_get_function_result(p.oid) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_mis_polizas'),
  'TABLE(poliza_id uuid, producto text, producto_nombre text, aseguradora text, numero_poliza text, vigente_desde date, vigente_hasta date, cubre_hoy boolean, plan text, beneficio_enfermedad numeric, beneficio_accidente numeric, archivos jsonb)',
  'fn_mis_polizas devuelve estas doce columnas y ninguna más: ni prima, ni pagos, ni nota, ni quién la registró');

-- ── B · Las pólizas de la prueba (las registra DO, como en producción) ────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);

-- Un seguro complementario con póliza, que DO agrega desde la pantalla. Su descripción es
-- un texto para DO: la 423 comprueba más abajo que ninguna función la devuelve.
select set_config('t.vida',
  fn_seguro_tipo_crear('Vida Ley prueba 530', 'DESCRIPCION INTERNA DE DO', false, true,
                       'Dar de alta en el seguro de vida', 'Dar de baja en el seguro de vida'), true);

-- Ana: la vigente (92 días, como la de hoy) y su renovación, que empieza el día en que termina
-- la primera. Con prima, nota y un paso marcado: todo lo que NO debe salir.
select set_config('t.ana',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a011', 'salud_practicantes', 'Pacífico Seguros', '24043267',
    fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, fn_hoy_lima() + 20, null, null, null, true,
    'Nota interna de DO que Ana no debe leer')::text, true);
select set_config('t.ana_renov',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a011', 'salud_practicantes', 'Pacífico Seguros', '24043277',
    fn_hoy_lima() + 82, fn_hoy_lima() + 174, 179.97, null, null, null, null, null, null)::text, true);
select fn_seguro_marcar_paso(current_setting('t.ana')::uuid, 'pagada', fn_hoy_lima() - 3, null);

-- Beto: primero una que se registró por error y se anula, luego la buena.
select set_config('t.beto_mala',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a012', 'salud_practicantes', 'Pacífico Seguros', '24043299',
    fn_hoy_lima() - 100, fn_hoy_lima() - 8, 179.97, null, null, null, null, null, null)::text, true);
select fn_seguro_adjuntar(current_setting('t.beto_mala')::uuid, 'poliza', '5b000000-0000-0000-0000-0000000000b2.pdf', 'la-mala.pdf');
select fn_seguro_anular(current_setting('t.beto_mala')::uuid, 'Se registró con otra persona');
select set_config('t.beto',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a012', 'salud_practicantes', 'Pacífico Seguros', '24043266',
    fn_hoy_lima() - 5, fn_hoy_lima() + 87, 179.97, null, null, null, null, null, null)::text, true);

-- Dani: póliza FOLA vigente; más abajo pasa a planilla.
select set_config('t.dani',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a014', 'salud_practicantes', 'Pacífico Seguros', '24043265',
    fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null)::text, true);

-- Gaby: la que termina hoy (a las 12 M) y la renovación que empieza hoy.
select fn_seguro_registrar('00000000-0000-0000-0000-00000530a015', 'salud_practicantes', 'Pacífico Seguros', '24043278',
  fn_hoy_lima() - 92, fn_hoy_lima(), 179.97, null, null, null, null, null, null);
select fn_seguro_registrar('00000000-0000-0000-0000-00000530a015', 'salud_practicantes', 'Pacífico Seguros', '24043288',
  fn_hoy_lima(), fn_hoy_lima() + 92, 179.97, null, null, null, null, null, null);

-- Hugo: de planilla, y DO lo pasa a FOLA con una asignación; recién entonces se le registra la póliza.
select fn_seguro_asignar('00000000-0000-0000-0000-00000530a016', 'salud_practicantes', fn_hoy_lima(), 'Prueba: DO lo pasa a FOLA');
select set_config('t.hugo',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a016', 'salud_practicantes', 'Pacífico Seguros', '24043255',
    fn_hoy_lima() - 3, fn_hoy_lima() + 89, 179.97, null, null, null, null, null, null)::text, true);

-- Iris: sigue en EsSalud y además tiene una póliza de un seguro complementario.
select set_config('t.iris',
  fn_seguro_registrar('00000000-0000-0000-0000-00000530a017', current_setting('t.vida'), 'Rímac Seguros', 'VL-0001',
    fn_hoy_lima() - 20, fn_hoy_lima() + 160, 50, null, null, null, null, null, null)::text, true);

-- Lalo: la póliza que termina hoy, y ninguna otra.
select fn_seguro_registrar('00000000-0000-0000-0000-00000530a021', 'salud_practicantes', 'Pacífico Seguros', '24043244',
  fn_hoy_lima() - 92, fn_hoy_lima(), 179.97, null, null, null, null, null, null);

-- Mara: sin póliza FOLA, con una póliza vigente del seguro complementario.
select fn_seguro_registrar('00000000-0000-0000-0000-00000530a022', current_setting('t.vida'), 'Rímac Seguros', 'VL-0002',
  fn_hoy_lima() - 20, fn_hoy_lima() + 160, 50, null, null, null, null, null, null);

-- Los archivos. El convenio de Ana se sube ANTES que su póliza: el orden de la respuesta
-- tiene que ser por tipo, no por quién llegó primero.
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'convenio_pago', '5b000000-0000-0000-0000-0000000000a2.pdf', 'convenio.pdf');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'poliza',        '5b000000-0000-0000-0000-0000000000a1.pdf', 'Poliza APELLIDO NOMBRE.pdf');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'factura',       '5b000000-0000-0000-0000-0000000000a3.pdf', 'factura.pdf');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'otro',          '5b000000-0000-0000-0000-0000000000a4.jpg', 'foto.jpg');
select fn_seguro_adjuntar(current_setting('t.ana')::uuid, 'convenio_pago', '5b000000-0000-0000-0000-0000000000a5.pdf', 'convenio-viejo.pdf');
select fn_seguro_adjuntar(current_setting('t.beto')::uuid, 'poliza',       '5b000000-0000-0000-0000-0000000000b1.pdf', 'beto.pdf');
select fn_seguro_adjuntar(current_setting('t.dani')::uuid, 'poliza',       '5b000000-0000-0000-0000-0000000000d1.pdf', 'dani.pdf');
select fn_seguro_adjuntar(current_setting('t.hugo')::uuid, 'poliza',       '5b000000-0000-0000-0000-0000000000c1.pdf', 'hugo.pdf');
select fn_seguro_adjuntar(current_setting('t.iris')::uuid, 'poliza',       '5b000000-0000-0000-0000-0000000000e1.pdf', 'iris.pdf');
-- El convenio viejo de Ana se retira (DO se equivocó de archivo).
select fn_seguro_retirar_archivo(
  (select id from polizas_seguro_archivos where storage_path = '5b000000-0000-0000-0000-0000000000a5.pdf'),
  'Era el convenio de otra persona');

-- Dani deja de ser practicante: pasa a planilla con su póliza FOLA todavía vigente.
set session_replication_role = replica;
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null
 where id = '00000000-0000-0000-0000-00000530a014';
set session_replication_role = origin;

-- ── C · En qué seguro está cada colaborador ──────────────────────────────
-- Una sola vez el rol de quien inició sesión; lo que cambia de una persona a otra es quién es.
set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('salud_practicantes', 'FOLA', true, true)::text, 'Ana, practicante: FOLA, lleva póliza y la cubre hoy');
select is((select count(*)::int from fn_mi_seguro()), 1, 'y es UNA sola fila');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b012', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('salud_practicantes', 'FOLA', true, true)::text, 'Beto, practicante: FOLA y cubierto (su póliza anulada no cuenta)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b013', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('salud_practicantes', 'FOLA', true, false)::text, 'Fabi, practicante sin póliza registrada: FOLA, lleva póliza y hoy no la cubre ninguna');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b002', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('essalud', 'EsSalud', false, null::boolean)::text, 'alguien de planilla: EsSalud, que no lleva póliza, y por eso «cubre hoy» no se pregunta');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b014', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('essalud', 'EsSalud', false, null::boolean)::text, 'Dani, que pasó de practicante a planilla: ya está en EsSalud');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b016', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('salud_practicantes', 'FOLA', true, true)::text, 'Hugo, de planilla pero asignado a FOLA por DO: FOLA, y cubierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b017', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('essalud', 'EsSalud', false, null::boolean)::text, 'Iris: su seguro principal sigue siendo EsSalud aunque tenga una póliza de otro seguro');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b019', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('essalud', 'EsSalud', false, null::boolean)::text, 'una persona a prueba: EsSalud');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b018', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row(null::text, null::text, false, null::boolean)::text, 'honorarios: no le corresponde ningún seguro principal, y la fila lo dice sin inventar nada');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b015', true);
select is((select cubre_hoy from fn_mi_seguro()), true, 'Gaby: la póliza que empieza hoy la cubre, aunque la anterior termine hoy');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b021', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('salud_practicantes', 'FOLA', true, false)::text, 'Lalo: su única póliza terminó hoy a las 12 M y no hay otra: hoy no tiene cobertura');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b022', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('salud_practicantes', 'FOLA', true, false)::text, 'Mara: una póliza vigente de OTRO seguro no cubre su FOLA, que es el principal');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select is((select row(tipo, tipo_nombre, con_poliza, cubre_hoy)::text from fn_mi_seguro()),
  row('essalud', 'EsSalud', false, null::boolean)::text, 'DO también es un colaborador: ve el suyo, no el de las demás');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b020', true);
select is((select count(*)::int from fn_mi_seguro()), 0, 'la cuenta de servicio de un terminal no es una persona: sin fila');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b099', true);
select is((select count(*)::int from fn_mi_seguro()), 0, 'una sesión sin ficha enlazada: vacío, no error');

select set_config('request.jwt.claim.sub', '', true);
select is((select count(*)::int from fn_mi_seguro()), 0, 'sin identidad en la sesión: vacío, no error');
reset role;

-- «En qué seguro está» y «cubre hoy» dicen lo mismo que lee DO. Se guarda lo que ve cada
-- quien y se compara persona por persona, con la regla de la 0528 como juez.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
create temp table t_equipo on commit drop as
  select persona_id, tipo, con_poliza, cubre_hoy from fn_seguros_equipo();
create temp table t_mia (persona_id uuid, tipo text, con_poliza boolean, cubre_hoy boolean) on commit drop;
do $$
declare r record;
begin
  for r in select id, auth_user_id from personas
            where id::text like '00000000-0000-0000-0000-00000530a0%' and auth_user_id is not null loop
    perform set_config('request.jwt.claim.sub', r.auth_user_id::text, true);
    insert into t_mia select r.id, m.tipo, m.con_poliza, m.cubre_hoy from fn_mi_seguro() m;
  end loop;
end $$;
select is((select count(*)::int from t_mia), 13,
  'de las catorce personas de la prueba, trece tienen fila (la cuenta de servicio no)');
select is(
  (select count(*)::int from t_mia m join t_equipo e on e.persona_id = m.persona_id
    where (m.tipo, m.con_poliza, m.cubre_hoy) is distinct from (e.tipo, e.con_poliza, e.cubre_hoy)),
  0, 'en qué seguro está cada una y si la cubre hoy dice lo mismo que lee DO en fn_seguros_equipo');

-- ── D · Sus pólizas ──────────────────────────────────────────────────────
set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
select is((select count(*)::int from fn_mis_polizas()), 2, 'Ana ve sus dos pólizas: la vigente y la renovación');
select is(
  (select array_agg(numero_poliza order by o) from (select numero_poliza, row_number() over () as o from fn_mis_polizas()) t),
  array['24043277', '24043267'],
  'la más reciente primero: primero la renovación y luego la vigente');
select is(
  (select array_agg(cubre_hoy order by o) from (select cubre_hoy, row_number() over () as o from fn_mis_polizas()) t),
  array[false, true],
  'cubre hoy la vigente; la renovación, que empieza el día en que termina la otra, todavía no');
select is(
  (select row(producto, producto_nombre, aseguradora, vigente_desde, vigente_hasta)::text
     from fn_mis_polizas() where numero_poliza = '24043267'),
  row('salud_practicantes', 'FOLA', 'Pacífico Seguros', fn_hoy_lima() - 10, fn_hoy_lima() + 82)::text,
  'cada póliza dice de qué seguro es, con su aseguradora y su vigencia');
select is(
  (select row(plan, beneficio_enfermedad, beneficio_accidente)::text from fn_mis_polizas() where numero_poliza = '24043267'),
  row(null::text, null::numeric, null::numeric)::text,
  'el plan y los beneficios máximos salen vacíos mientras el corredor no los confirme');
select is(
  (select jsonb_agg(a->>'tipo' order by o) from (
     select a, o from fn_mis_polizas() f, jsonb_array_elements(f.archivos) with ordinality as x(a, o)
      where f.numero_poliza = '24043267') t),
  '["poliza", "convenio_pago"]'::jsonb,
  'de su póliza ve la póliza y el convenio de pago, la póliza primero aunque el convenio se subió antes');
select is(
  (select count(*)::int from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a
    where a->>'storage_path' in ('5b000000-0000-0000-0000-0000000000a3.pdf', '5b000000-0000-0000-0000-0000000000a4.jpg',
                                 '5b000000-0000-0000-0000-0000000000a5.pdf')),
  0, 'no ve la factura, ni «otro», ni el convenio que DO retiró');
select is(
  (select array_agg(k order by k) from (
     select distinct jsonb_object_keys(a) as k from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a) t),
  array['bytes', 'id', 'mime', 'storage_path', 'tipo'],
  'de cada archivo salen cinco datos, y ninguno es el nombre con que DO lo subió');
select is(
  (select (a->>'bytes')::int from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a
    where a->>'storage_path' = '5b000000-0000-0000-0000-0000000000a1.pdf'),
  1779531, 'el peso sale de Storage');
select is(
  (select jsonb_typeof(archivos) || ':' || jsonb_array_length(archivos)::text
     from fn_mis_polizas() where numero_poliza = '24043277'),
  'array:0', 'una póliza sin archivos trae un arreglo vacío, no null');
select is(
  (select count(*)::int from fn_mis_polizas() where numero_poliza in ('24043266', '24043265', '24043299', '24043255', 'VL-0001')),
  0, 'ni una póliza de otra persona ni una anulada');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b012', true);
select is((select array_agg(numero_poliza) from fn_mis_polizas()), array['24043266'],
  'Beto ve su póliza y no la que se anuló');

-- LA PUERTA ES «ES MI PÓLIZA»: Dani ya está en EsSalud y conserva su póliza FOLA.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b014', true);
select is(
  (select array_agg(numero_poliza || ':' || producto_nombre || ':' || cubre_hoy) from fn_mis_polizas()),
  array['24043265:FOLA:true'],
  'Dani, que ya está en EsSalud, sigue viendo su póliza FOLA: es suya, y todavía cubre');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b016', true);
select is((select array_agg(numero_poliza) from fn_mis_polizas()), array['24043255'],
  'Hugo, asignado a FOLA por DO, ve su póliza');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b017', true);
select is(
  (select array_agg(numero_poliza || ':' || producto_nombre) from fn_mis_polizas()),
  array['VL-0001:Vida Ley prueba 530'],
  'Iris ve la póliza de su seguro complementario, con el nombre de ese seguro');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b022', true);
select is(
  (select array_agg(numero_poliza || ':' || producto_nombre || ':' || cubre_hoy) from fn_mis_polizas()),
  array['VL-0002:Vida Ley prueba 530:true'],
  'Mara ve su póliza del seguro complementario, que cubre hoy, aunque su FOLA no tenga ninguna');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b013', true);
select is((select count(*)::int from fn_mis_polizas()), 0, 'Fabi, practicante sin póliza registrada: nada, y sin error');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b002', true);
select is((select count(*)::int from fn_mis_polizas()), 0, 'alguien de planilla en EsSalud: no tiene póliza que ver');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b018', true);
select is((select count(*)::int from fn_mis_polizas()), 0, 'honorarios: nada');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select is((select count(*)::int from fn_mis_polizas()), 0, 'DO tampoco ve en «Mi seguro» las de las demás: es lo MÍO, no el tablero');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b099', true);
select is((select count(*)::int from fn_mis_polizas()), 0, 'una sesión sin ficha enlazada: vacío, no error');
select set_config('request.jwt.claim.sub', '', true);
select is((select count(*)::int from fn_mis_polizas()), 0, 'sin identidad en la sesión: vacío, no error');
reset role;

-- ── E · Los archivos en Storage ──────────────────────────────────────────
set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  array['5b000000-0000-0000-0000-0000000000a1.pdf', '5b000000-0000-0000-0000-0000000000a2.pdf'],
  'Storage le deja ver a Ana exactamente dos archivos: su póliza y su convenio de pago');
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
select is((select count(*)::int from seguros_cambios), 0, 'ni los cambios de seguro');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b012', true);
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  array['5b000000-0000-0000-0000-0000000000b1.pdf'],
  'Beto abre solo su archivo: ni los de Ana ni el de su póliza anulada');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b014', true);
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  array['5b000000-0000-0000-0000-0000000000d1.pdf'],
  'Dani, ya en EsSalud, sigue abriendo el PDF de su póliza FOLA');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b016', true);
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  array['5b000000-0000-0000-0000-0000000000c1.pdf'], 'Hugo abre el suyo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b017', true);
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  array['5b000000-0000-0000-0000-0000000000e1.pdf'], 'Iris abre el de su póliza complementaria');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b013', true);
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'), 0, 'Fabi no abre ninguno');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b002', true);
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'), 0, 'alguien de planilla en EsSalud, tampoco');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b099', true);
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'), 0, 'una sesión sin ficha, tampoco');
select set_config('request.jwt.claim.sub', '', true);
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'), 0, 'ni sin identidad');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select is((select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'), 11,
  'DO sigue viendo los once archivos de la prueba por su propia política, también los retirados');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, metadata)
     values ('polizas-seguro', 'Nombre Apellido DNI.pdf', '{"size": 1, "mimetype": "application/pdf"}') $$,
  '42501', null, 'DO no sube un archivo con nombres en la ruta');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a1.pdf'), false,
  'y para la función de «lo mío», la póliza de Ana no es de DO');

-- La función de apoyo, archivo por archivo, vista por Ana.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a1.pdf'), true,  'Ana: su póliza es suya');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a2.pdf'), true,  'Ana: su convenio de pago es suyo');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a3.pdf'), false, 'Ana: su factura NO la abre');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a4.jpg'), false, 'Ana: el papel «otro» NO lo abre');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000a5.pdf'), false, 'Ana: lo retirado NO lo abre');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000b1.pdf'), false, 'Ana: la póliza de Beto no es suya');
select is(fn_seguro_archivo_es_mio('5b000000-0000-0000-0000-0000000000f9.pdf'), false, 'Ana: un archivo que ninguna fila usa no es suyo');
select is(fn_seguro_archivo_es_mio(null), false, 'y un null no es de nadie (false, no null)');
reset role;

select is(
  (select count(*)::int from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  11, 'Ana intentó borrar y pisar todo y no se perdió ni se cambió ningún archivo');
select is(
  (select (metadata->>'size')::int from storage.objects where name = '5b000000-0000-0000-0000-0000000000a1.pdf'),
  1779531, 'el peso de su póliza sigue intacto');

-- ── F · La función y Storage dicen lo mismo ──────────────────────────────
-- Para cada archivo que EXISTE en las tablas (de cualquier tipo, retirado o no): lo que
-- `fn_mis_polizas` le muestra a alguien, lo que `fn_seguro_archivo_es_mio` dice y lo que
-- Storage le deja ver son el mismo conjunto. Se mide con la identidad de cada una pero como el
-- dueño de las tablas, para poder recorrer TODOS los archivos. Tres personas con tres historias:
-- una practicante con convenio y retiros, quien ya cambió de seguro, y quien tiene un
-- seguro complementario.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
select is(
  (select array_agg(storage_path order by storage_path) from polizas_seguro_archivos where fn_seguro_archivo_es_mio(storage_path)),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a),
  'Ana: lo que dice la función de Storage y lo que lista fn_mis_polizas es el mismo conjunto de archivos');
set local role authenticated;
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a),
  'Ana: y lo que Storage le deja ver es ese mismo conjunto');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b014', true);
select is(
  (select array_agg(storage_path order by storage_path) from polizas_seguro_archivos where fn_seguro_archivo_es_mio(storage_path)),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a),
  'Dani: lo que dice la función de Storage y lo que lista fn_mis_polizas es el mismo conjunto');
set local role authenticated;
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a),
  'Dani: y lo que Storage le deja ver es ese mismo conjunto');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b017', true);
select is(
  (select array_agg(storage_path order by storage_path) from polizas_seguro_archivos where fn_seguro_archivo_es_mio(storage_path)),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a),
  'Iris: lo que dice la función de Storage y lo que lista fn_mis_polizas es el mismo conjunto');
set local role authenticated;
select is(
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  (select array_agg(a->>'storage_path' order by a->>'storage_path') from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a),
  'Iris: y lo que Storage le deja ver es ese mismo conjunto');
reset role;

-- ── G · El último día no cubre, y DO y la persona leen lo mismo ───────────
-- Gaby: la póliza que termina hoy ya no cubre (vence a las 12 M de ese día) y la renovación
-- que empieza hoy sí. Es el borde donde un `<=` por un `<` deja a alguien «cubierto» un día de más.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b015', true);
select is(
  (select array_agg(numero_poliza || ':' || cubre_hoy order by o)
     from (select numero_poliza, cubre_hoy, row_number() over () as o from fn_mis_polizas()) t),
  array['24043288:true', '24043278:false'],
  'Gaby: la póliza que empieza hoy cubre; la que termina hoy, a las 12 M, ya no');
reset role;

-- «Cubre hoy» de cada póliza dice lo mismo que el tablero de DO: dos respuestas a «¿esta
-- póliza cubre hoy?» no pueden diferir.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
create temp table t_tablero on commit drop as
  select poliza_id, cubre_hoy from fn_seguros_tablero();
create temp table t_polizas_mias (persona_id uuid, poliza_id uuid, cubre_hoy boolean) on commit drop;
do $$
declare r record;
begin
  for r in select id, auth_user_id from personas
            where id::text like '00000000-0000-0000-0000-00000530a0%' and auth_user_id is not null loop
    perform set_config('request.jwt.claim.sub', r.auth_user_id::text, true);
    insert into t_polizas_mias select r.id, m.poliza_id, m.cubre_hoy from fn_mis_polizas() m;
  end loop;
end $$;
select is((select count(*)::int from t_polizas_mias), 10,
  'las diez pólizas vivas de la prueba (Ana 2, Beto 1, Dani 1, Gaby 2, Hugo 1, Iris 1, Lalo 1, Mara 1) las ve cada dueña');
select is(
  (select count(*)::int from t_polizas_mias m left join t_tablero t on t.poliza_id = m.poliza_id
    where t.poliza_id is null or t.cubre_hoy is distinct from m.cubre_hoy),
  0, 'y «cubre hoy» de cada una dice lo mismo en «Mi seguro» que en el tablero de DO');

-- ── H · Los cambios de DO se notan al instante ───────────────────────────
-- DO confirma el plan y el beneficio: Ana los ve.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select fn_seguro_corregir(current_setting('t.ana')::uuid, 'Pacífico Seguros', '24043267',
  fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, fn_hoy_lima() + 20, 'Plan 1', 16800, 36000, true,
  'Nota interna de DO que Ana no debe leer', 'El corredor confirmó el plan');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
set local role authenticated;
select is(
  (select row(plan, beneficio_enfermedad, beneficio_accidente)::text from fn_mis_polizas() where numero_poliza = '24043267'),
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
  (select array_agg(name order by name) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%'),
  array['5b000000-0000-0000-0000-0000000000a1.pdf'],
  'DO retiró su convenio: Storage ya no se lo deja abrir');
select is(
  (select count(*)::int from fn_mis_polizas() f, jsonb_array_elements(f.archivos) a where a->>'tipo' = 'convenio_pago'),
  0, 'y fn_mis_polizas ya no lo lista');
reset role;

-- DO anula la renovación de Ana: desaparece.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b001', true);
select fn_seguro_anular(current_setting('t.ana_renov')::uuid, 'Se registró con las fechas equivocadas');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000530b011', true);
set local role authenticated;
select is((select array_agg(numero_poliza) from fn_mis_polizas()), array['24043267'], 'la póliza anulada deja de aparecer');
reset role;

-- Si Ana pasara a planilla, su seguro cambia pero NO pierde su póliza ni su PDF; si vuelve,
-- todo sigue igual. (Lo contrario de lo que hacía la primera versión de esta migración.)
set session_replication_role = replica;
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null where id = '00000000-0000-0000-0000-00000530a011';
set session_replication_role = origin;
set local role authenticated;
select is(
  (select (select tipo from fn_mi_seguro()) || ':' || (select count(*) from fn_mis_polizas()) || ':'
          || (select count(*) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%')),
  'essalud:1:1', 'si Ana pasa a planilla, su seguro es EsSalud y sigue viendo su póliza FOLA y su PDF');
reset role;
set session_replication_role = replica;
update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'profesional' where id = '00000000-0000-0000-0000-00000530a011';
set session_replication_role = origin;
set local role authenticated;
select is(
  (select (select tipo from fn_mi_seguro()) || ':' || (select count(*) from fn_mis_polizas()) || ':'
          || (select count(*) from storage.objects where bucket_id = 'polizas-seguro' and name like '5b000000-%')),
  'salud_practicantes:1:1', 'y si vuelve a ser practicante, vuelve a FOLA con lo mismo');
reset role;

select * from finish();
rollback;
