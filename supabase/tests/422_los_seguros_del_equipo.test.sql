-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 422_los_seguros_del_equipo.test.sql — la 0528 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) NADIE fuera de DO ve ni escribe un seguro —ni la fila ni el PDF—, y ni
--     siquiera DO escribe las tablas directo: todo pasa por las funciones,
-- (b) cada colaborador esté en el seguro que le toca: AUTOMÁTICO por su vínculo
--     (practicante → FOLA, planilla y prueba → EsSalud, honorarios y sin vínculo →
--     ninguno), y solo lo que DO cambia a mano mande sobre eso,
-- (c) el sistema nombre el HUECO —quien tiene un seguro con póliza y no tiene una
--     que cubra HOY— y no invente uno donde no lo hay (EsSalud no lleva póliza),
-- (d) «cubre hoy» cuente el día final como NO cubierto, y una renovación que empieza
--     ese mismo día no se cruce,
-- (e) cuando alguien cambia de seguro (por vínculo o por DO) quede escrito «antes →
--     ahora» y los dos pendientes (baja y alta) se cierren SOLOS cuando ya no hacen
--     falta, y nunca se pidan por algo que ya pasó,
-- (f) un fallo del registro de cambios JAMÁS frene un cambio de vínculo (eso mueve la
--     planilla de una persona real), y
-- (g) nada se borra: tipo, póliza, paso o archivo se archivan, anulan, desmarcan o
--     retiran con motivo, y todo deja su rastro.
-- ============================================================================
begin;
select plan(237);

-- ── Sede y personas ──────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000005280001', 'ZZB28', 'Sede seguros', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo, practicante_modalidad, estado, cuenta_de_servicio, fecha_cese) values
  ('00000000-0000-0000-0000-00000528a001', 'AdmSeg',  'Lab', '00000000-0000-0000-0000-000005280001', 'admin',           'x', '00000000-0000-0000-0000-00000528b001', '2023-01-01', 'planilla',      'DO',              null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a002', 'DoSeg',   'Lab', '00000000-0000-0000-0000-000005280001', 'lider_do',        'x', '00000000-0000-0000-0000-00000528b002', '2023-01-01', 'planilla',      'Líder DO',        null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a003', 'EncSeg',  'Lab', '00000000-0000-0000-0000-000005280001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000528b003', '2023-01-01', 'planilla',      'Líder de equipo', null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a004', 'IntSeg',  'Lab', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', '00000000-0000-0000-0000-00000528b004', '2023-01-01', 'planilla',      'Vendedora',       null,            'activo',   false, null),
  -- Los practicantes.
  ('00000000-0000-0000-0000-00000528a011', 'Ana',     'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante',   'Practicante',     'profesional',   'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a012', 'Beto',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante',   'Practicante',     'preprofesional','activo',   false, null),
  ('00000000-0000-0000-0000-00000528a013', 'Carla',   'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-01-01', 'practicante',   'Practicante',     'profesional',   'inactivo', false, '2026-10-10'),
  ('00000000-0000-0000-0000-00000528a015', 'Estacion','Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante',   'Estación',        'profesional',   'activo',   true,  null),
  ('00000000-0000-0000-0000-00000528a016', 'Fabi',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante',   'Practicante',     'profesional',   'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a021', 'Jose',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'practicante',   'Practicante',     'profesional',   'activo',   false, null),
  -- El resto del equipo, uno por vínculo.
  ('00000000-0000-0000-0000-00000528a014', 'Dani',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2025-01-01', 'planilla',      'Vendedora',       null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a017', 'Gabi',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-03-01', 'rxh',           'Honorarios',      null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a018', 'Hugo',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2026-10-01', 'prueba',        'Vendedor',        null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a019', 'Ines',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2020-01-01', 'no_trabajador', 'Accionista',      null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a020', 'Iris',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2024-01-01', 'planilla',      'Vendedora',       null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a022', 'Kari',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2024-06-01', 'planilla',      'Vendedora',       null,            'activo',   false, null),
  ('00000000-0000-0000-0000-00000528a023', 'Luis',    'Seg', '00000000-0000-0000-0000-000005280001', 'integrante',      'x', null,                                   '2024-06-01', 'planilla',      'Vendedor',        null,            'activo',   false, null);
set session_replication_role = origin;

-- Lo que Storage guardaría al recibir cada archivo (peso y tipo salen de acá).
insert into storage.objects (bucket_id, name, metadata) values
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000001.pdf', '{"size": 1779531, "mimetype": "application/pdf"}'),
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000002.pdf', '{"size": 65536, "mimetype": "application/pdf"}'),
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000003.jpg', '{"size": 900000, "mimetype": "image/jpeg"}'),
  ('polizas-seguro', '5a000000-0000-0000-0000-000000000009.pdf', '{"size": 1000, "mimetype": "application/pdf"}');

-- ── A · El bucket, las tablas, el catálogo y los permisos ────────────────
select is(
  (select count(*)::int from storage.buckets where id = 'polizas-seguro' and public is false and file_size_limit = 52428800),
  1, 'el bucket existe, es privado y limita a 50 MB por archivo');

select is(
  (select count(*)::int from pg_policies where schemaname = 'storage' and policyname like 'polizas\_seguro\_%'),
  4, 'Storage tiene sus cuatro políticas (insert, select, update, delete)');

select is(
  (select count(*)::int from pg_class
    where relname in ('seguros_tipos','seguros_asignaciones','seguros_cambios','polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos')
      and relrowsecurity),
  6, 'las seis tablas tienen RLS activa');

select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and (p.proname like 'fn\_seguro\_%' or p.proname like 'fn\_seguros\_%' or p.proname = 'fn_trg_seguros_cambio_de_vinculo')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'ninguna función de seguros le responde a quien no inició sesión');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proname in ('fn_seguro_tipo_crear','fn_seguro_tipo_editar','fn_seguro_tipo_activar','fn_seguro_registrar',
                        'fn_seguro_corregir','fn_seguro_marcar_paso','fn_seguro_anular','fn_seguro_adjuntar',
                        'fn_seguro_retirar_archivo','fn_seguro_archivo_libre','fn_seguro_asignar',
                        'fn_seguro_volver_al_automatico','fn_seguro_cambio_marcar','fn_seguros_tipos',
                        'fn_seguros_equipo','fn_seguros_tablero','fn_seguros_cambios','fn_seguro_historial',
                        'fn_seguro_archivos')),
  19, 'y las diecinueve las puede llamar quien sí inició sesión (un grant faltante fallaría en silencio)');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proname in ('fn_seguro_tipo_por_vinculo','fn_seguro_tipo_principal','fn_seguro_datos_validos',
                        'fn_trg_seguros_cambio_de_vinculo')),
  0, 'las de apoyo y el disparador no las llama nadie desde fuera');

-- Sin política Y sin privilegio: las dos puertas cerradas (molde de la 0509).
select is(
  (select count(*)::int from pg_policies where schemaname = 'public'
      and tablename in ('seguros_tipos','seguros_asignaciones','seguros_cambios','polizas_seguro','polizas_seguro_archivos','polizas_seguro_eventos')
      and cmd <> 'SELECT'),
  0, 'ninguna de las seis tablas tiene una política que no sea de lectura');

select is(
  (select count(*)::int
     from (values ('seguros_tipos'), ('seguros_asignaciones'), ('seguros_cambios'),
                  ('polizas_seguro'), ('polizas_seguro_archivos'), ('polizas_seguro_eventos')) t(tabla)
    cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) v(priv)
   where has_table_privilege('authenticated', 'public.' || t.tabla, v.priv)),
  0, 'y authenticated no tiene privilegio de escribir en ninguna (ni truncate)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);
set local role authenticated;
select throws_ok(
  $$ insert into polizas_seguro (persona_id, producto, aseguradora, numero_poliza, vigente_desde, vigente_hasta, prima_total, creada_por)
     values ('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico', '99999999', '2026-10-01', '2027-01-01', 1,
             '00000000-0000-0000-0000-00000528a001') $$,
  '42501', null, 'ni DO inserta una póliza a mano: solo por la función');
select throws_ok($$ update polizas_seguro set nota = 'otra' $$, '42501', null, 'ni la actualiza a mano');
select throws_ok($$ update seguros_tipos set nombre = 'otro' $$, '42501', null, 'ni cambia un tipo de seguro a mano');
select throws_ok(
  $$ insert into seguros_asignaciones (persona_id, tipo, desde, motivo, creada_por)
     values ('00000000-0000-0000-0000-00000528a014', 'essalud', '2026-10-01', 'inventada',
             '00000000-0000-0000-0000-00000528a001') $$,
  '42501', null, 'ni se inventa una asignación');
select throws_ok(
  $$ insert into seguros_cambios (persona_id, de_tipo, a_tipo, fecha, origen)
     values ('00000000-0000-0000-0000-00000528a014', 'essalud', null, '2026-10-01', 'vinculo') $$,
  '42501', null, 'ni un cambio de seguro');
select throws_ok($$ delete from polizas_seguro $$, '42501', null, 'ni borra pólizas');
reset role;

-- Los dos tipos de sistema, tal como salen de la migración.
select is(
  (select row(nombre, principal, con_poliza, aplica_a_vinculos, de_sistema, activo)::text
     from seguros_tipos where clave = 'salud_practicantes'),
  row('FOLA', true, true, array['practicante'], true, true)::text,
  'FOLA viene de sistema: principal, con póliza y automático para los practicantes');
select is(
  (select row(nombre, principal, con_poliza, aplica_a_vinculos, de_sistema, activo)::text
     from seguros_tipos where clave = 'essalud'),
  row('EsSalud', true, false, array['planilla', 'prueba'], true, true)::text,
  'EsSalud viene de sistema: principal, SIN póliza («por planilla») y automático para planilla y prueba');

select is(
  (select string_agg(v || '=' || coalesce(fn_seguro_tipo_por_vinculo(v), '-'), ',' order by v)
     from unnest(array['planilla', 'prueba', 'rxh', 'practicante', 'no_trabajador']) v),
  'no_trabajador=-,planilla=essalud,practicante=salud_practicantes,prueba=essalud,rxh=-',
  'cada vínculo cae en su seguro: honorarios y sin vínculo, en ninguno');

-- ── B · Quién llama qué ──────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b004', true);
select throws_ok(
  $$ select fn_seguro_tipo_crear('EPS', null, false, true, null, null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede agregar tipos de seguro.', 'una integrante no agrega tipos de seguro');
select throws_ok(
  $$ select fn_seguro_tipo_editar('essalud', 'EsSalud', null, null, null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede editar tipos de seguro.', 'ni los edita');
select throws_ok(
  $$ select fn_seguro_tipo_activar('essalud', false, 'no') $$,
  'P0001', 'Solo Desarrollo Organizacional puede archivar tipos de seguro.', 'ni los archiva');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede registrar pólizas de seguro.', 'ni registra pólizas');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'essalud', fn_hoy_lima(), 'un motivo') $$,
  'P0001', 'Solo Desarrollo Organizacional puede cambiar el seguro de una persona.', 'ni le cambia el seguro a nadie');
select throws_ok(
  $$ select fn_seguro_volver_al_automatico(gen_random_uuid(), null, 'un motivo') $$,
  'P0001', 'Solo Desarrollo Organizacional puede cambiar el seguro de una persona.', 'ni lo devuelve al automático');
select throws_ok(
  $$ select fn_seguro_cambio_marcar(gen_random_uuid(), 'baja', fn_hoy_lima(), null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede marcar los pasos de un cambio de seguro.', 'ni marca un paso de un cambio');
select throws_ok($$ select * from fn_seguros_equipo() $$,
  'P0001', 'Solo Desarrollo Organizacional ve los seguros del equipo.', 'ni ve en qué está cada colaborador');
select throws_ok($$ select * from fn_seguros_tablero() $$,
  'P0001', 'Solo Desarrollo Organizacional ve los seguros del equipo.', 'ni las pólizas');
select throws_ok($$ select * from fn_seguros_tipos() $$,
  'P0001', 'Solo Desarrollo Organizacional ve los tipos de seguro.', 'ni el catálogo');
select throws_ok($$ select * from fn_seguros_cambios(null, false) $$,
  'P0001', 'Solo Desarrollo Organizacional ve los cambios de seguro.', 'ni los cambios');
select throws_ok($$ select * from fn_seguro_historial(gen_random_uuid()) $$,
  'P0001', 'Solo Desarrollo Organizacional ve el historial de una póliza.', 'ni el historial de una póliza');
select throws_ok($$ select * from fn_seguro_archivos(gen_random_uuid()) $$,
  'P0001', 'Solo Desarrollo Organizacional ve los archivos de una póliza.', 'ni sus archivos');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b003', true);
select throws_ok($$ select * from fn_seguros_equipo() $$,
  'P0001', 'Solo Desarrollo Organizacional ve los seguros del equipo.', 'la líder de equipo tampoco lo ve');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'essalud', fn_hoy_lima(), 'un motivo') $$,
  'P0001', 'Solo Desarrollo Organizacional puede cambiar el seguro de una persona.', 'ni cambia el seguro de nadie');

-- ── C · El catálogo: DO agrega, edita y archiva tipos ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);

select throws_ok(
  $$ select fn_seguro_tipo_crear('x', null, false, true, null, null) $$,
  'P0001', 'Escribe cómo se llama el seguro (al menos 2 letras).', 'un seguro sin nombre no entra');
select throws_ok(
  $$ select fn_seguro_tipo_crear('!!!', null, false, true, null, null) $$,
  'P0001', 'El nombre del seguro tiene que llevar letras o números.', 'ni uno cuyo nombre no tiene ni una letra');
select throws_ok(
  $$ select fn_seguro_tipo_crear('Sin póliza ni principal', null, false, false, null, null) $$,
  'P0001', 'Un seguro que va además del principal necesita póliza: sin ella no hay nada que registrar.',
  'un complementario sin póliza no tiene nada que registrar');
select throws_ok(
  $$ select fn_seguro_tipo_crear('Algo', null, null, true, null, null) $$,
  'P0001', 'Falta decir si es el seguro principal y si lleva póliza.', 'ni uno sin decir si es principal');

select set_config('t.eps', fn_seguro_tipo_crear('EPS', null, false, true, 'Registrar la póliza de la EPS', null), true);
select set_config('t.vl',  fn_seguro_tipo_crear('Vida Ley', '  Seguro de vida  ', false, true, null, null), true);
select set_config('t.vl2', fn_seguro_tipo_crear('Vida-Ley', null, false, true, null, null), true);
select set_config('t.nandu', fn_seguro_tipo_crear('Seguro Médico Ñandú', null, false, true, null, null), true);
select set_config('t.sis', fn_seguro_tipo_crear('SIS', null, true, false, null, null), true);
select set_config('t.pp', fn_seguro_tipo_crear('Plan Premium', null, true, true, null, null), true);

select is(
  (select string_agg(x, ',' order by x) from unnest(array[current_setting('t.eps'), current_setting('t.vl'),
     current_setting('t.vl2'), current_setting('t.nandu'), current_setting('t.sis'), current_setting('t.pp')]) x),
  'eps,plan_premium,seguro_medico_nandu,sis,vida_ley,vida_ley_2',
  'la clave sale del nombre (sin tildes, con guiones bajos) y si ya existe se le suma un número');

select is(
  (select row(nombre, descripcion, principal, con_poliza, aplica_a_vinculos, de_sistema, activo, creado_por)::text
     from seguros_tipos where clave = 'vida_ley'),
  row('Vida Ley', 'Seguro de vida', false, true, array[]::text[], false, true, '00000000-0000-0000-0000-00000528a001'::uuid)::text,
  'un tipo que agrega DO nace sin vínculos automáticos, recortado y con quién lo creó');

select throws_ok(
  $$ select fn_seguro_tipo_crear('eps', null, false, true, null, null) $$,
  'P0001', 'Ya hay un seguro con ese nombre.', 'el nombre no se repite, ni cambiando mayúsculas');

select throws_ok(
  $$ select fn_seguro_tipo_editar('essalud', 'Otro nombre', null, null, null) $$,
  'P0001', 'Un seguro de sistema conserva su nombre.', 'un seguro de sistema no cambia de nombre');
select lives_ok(
  $$ select fn_seguro_tipo_editar('essalud', 'EsSalud', 'Seguro social de salud, por planilla.', 'Confirmar el alta con el contador', null) $$,
  'pero sí se edita lo que dicen sus pendientes y su descripción');
select is(
  (select row(descripcion, texto_alta, texto_baja)::text from seguros_tipos where clave = 'essalud'),
  row('Seguro social de salud, por planilla.', 'Confirmar el alta con el contador', null::text)::text,
  'y queda escrito (la baja, vacía, volverá al texto de siempre al leerse)');
select lives_ok(
  $$ select fn_seguro_tipo_editar('essalud', 'EsSalud', 'Seguro social de salud. Se paga con la planilla y lo declara el contador: Dynamic solo lo muestra.',
       'Confirmar con el contador el alta en EsSalud', 'Confirmar con el contador la baja en EsSalud') $$,
  'se deja como estaba para el resto de la prueba');
select lives_ok($$ select fn_seguro_tipo_editar('eps', 'EPS Pacífico', null, null, null) $$, 'un tipo de DO sí cambia de nombre');
select throws_ok(
  $$ select fn_seguro_tipo_editar('vida_ley_2', 'vida ley', null, null, null) $$,
  'P0001', 'Ya hay un seguro con ese nombre.', 'pero no a uno que ya existe');
select throws_ok($$ select fn_seguro_tipo_editar('no_existe', 'Algo', null, null, null) $$,
  'P0001', 'Ese tipo de seguro no existe.', 'ni se edita uno que no existe');

select throws_ok($$ select fn_seguro_tipo_activar('essalud', false, 'ya no lo usamos') $$,
  'P0001', 'Los seguros de sistema no se archivan.', 'un seguro de sistema no se archiva');
select throws_ok($$ select fn_seguro_tipo_activar('seguro_medico_nandu', true, null) $$,
  'P0001', 'Ese tipo de seguro ya está activo.', 'activar uno activo se rechaza');
select throws_ok($$ select fn_seguro_tipo_activar('seguro_medico_nandu', false, 'no') $$,
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado junto al tipo.', 'archivar pide motivo');
select lives_ok($$ select fn_seguro_tipo_activar('seguro_medico_nandu', false, '  no lo usa nadie  ') $$,
  'DO archiva un tipo que no se usa');
select is(
  (select row(activo, archivado_motivo, archivado_por)::text from seguros_tipos where clave = 'seguro_medico_nandu'),
  row(false, 'no lo usa nadie', '00000000-0000-0000-0000-00000528a001'::uuid)::text,
  'queda archivado, con motivo y con quién lo hizo');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'seguro_medico_nandu', 'Otra aseguradora', 'SM-001',
       fn_hoy_lima() - 5, fn_hoy_lima() + 85, 50, null, null, null, null, null, null) $$,
  'P0001', 'Ese tipo de seguro está archivado.', 'a un tipo archivado no se le registran pólizas');
select lives_ok($$ select fn_seguro_tipo_activar('seguro_medico_nandu', true, null) $$, 'y se puede volver a activar');

-- ── D · En qué seguro está cada colaborador, antes de registrar nada ─────
select is(fn_seguro_tipo_principal('00000000-0000-0000-0000-00000528a011', fn_hoy_lima()), 'salud_practicantes',
  'un practicante está en FOLA por su vínculo');
select is(fn_seguro_tipo_principal('00000000-0000-0000-0000-00000528a014', fn_hoy_lima()), 'essalud',
  'alguien de planilla, en EsSalud');
select is(fn_seguro_tipo_principal('00000000-0000-0000-0000-00000528a018', fn_hoy_lima()), 'essalud',
  'y alguien en prueba también');
select is(fn_seguro_tipo_principal('00000000-0000-0000-0000-00000528a017', fn_hoy_lima()), null,
  'honorarios no tienen seguro de la empresa');

select is(
  (select row(tipo, origen, con_poliza, cubre_hoy, hueco)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a014'),
  row('essalud', 'vinculo', false, null::boolean, false)::text,
  'la fila de alguien de planilla dice EsSalud «por vínculo», sin póliza y sin hueco: EsSalud no lleva póliza');
select is(
  (select row(tipo, origen, con_poliza, hueco)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a011'),
  row('salud_practicantes', 'vinculo', true, true)::text,
  'la de un practicante dice FOLA, que pide póliza: y todavía no tiene ninguna, así que es un hueco');
select is(
  (select row(tipo, origen, hueco)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a017'),
  row(null::text, null::text, false)::text,
  'la de honorarios no tiene tipo ni hueco: no aplica');
select is(
  (select row(tipo_automatico, tipo_automatico_nombre)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a014'),
  row('essalud', 'EsSalud')::text,
  'el seguro automático de alguien de planilla es EsSalud, con su nombre listo para la pantalla');
select is(
  (select row(tipo_automatico, tipo_automatico_nombre)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a011'),
  row('salud_practicantes', 'FOLA')::text, 'el de un practicante, FOLA');
select is(
  (select row(tipo_automatico, tipo_automatico_nombre)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a017'),
  row(null::text, null::text)::text, 'y a honorarios no le toca ninguno por su vínculo');
select is(
  (select count(*)::int from fn_seguros_equipo()
    where persona_id in ('00000000-0000-0000-0000-00000528a013', '00000000-0000-0000-0000-00000528a015')),
  0, 'ni una practicante que ya se fue sin póliza ni una cuenta de servicio son una fila');

-- ── E · Registrar pólizas ────────────────────────────────────────────────
select throws_ok(
  $$ select fn_seguro_registrar(gen_random_uuid(), 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Esa persona no existe.', 'una persona que no existe no entra');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a013', 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Esa persona está inactiva.', 'ni una que ya se fue');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'nada', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Ese tipo de seguro no existe.', 'ni de un tipo que no existe');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'essalud', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Ese seguro es «por planilla»: no tiene póliza que registrar.', 'EsSalud no lleva póliza');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'El seguro principal de esa persona hoy es EsSalud: no se le registra una póliza de FOLA. Si debe cambiar, cámbiale el seguro primero.',
  'a alguien de planilla no se le registra FOLA: su seguro es otro');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a019', 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'El seguro principal de esa persona hoy es ninguno: no se le registra una póliza de FOLA. Si debe cambiar, cámbiale el seguro primero.',
  'ni a quien no tiene seguro principal');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', '  ', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Escribe la aseguradora.', 'sin aseguradora no entra');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico', '12',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'Escribe el número de la póliza.', 'ni sin número');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() + 5, fn_hoy_lima() - 5, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'La vigencia tiene que terminar después de empezar.', 'ni una vigencia al revés');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, null, null, null, null, null, null, null) $$,
  'P0001', 'Escribe la prima total (con IGV); puede ser 0 si no hay que pagar.', 'ni sin prima');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico', '24043267',
       fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, null, null, 0, null, null, null) $$,
  'P0001', 'El beneficio máximo por enfermedad tiene que ser mayor que 0, o quedar vacío si no está confirmado.',
  'un beneficio en 0 no vale: o es un monto o queda sin confirmar');

-- Ana: la vigente, como la de hoy (92 días). Beto: una vencida hace 8 días.
select set_config('t.ana',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', '  Pacífico Seguros ', ' 24043267 ',
    fn_hoy_lima() - 10, fn_hoy_lima() + 82, 179.97, fn_hoy_lima() + 20, '  ', null, null, null, '   ')::text, true);
select set_config('t.beto_vieja',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a012', 'salud_practicantes', 'Pacífico Seguros', '24043266',
    fn_hoy_lima() - 100, fn_hoy_lima() - 8, 179.97, null, 'Plan 1', 16800, 36000, true, 'Vencida')::text, true);

select is(
  (select row(producto, aseguradora, numero_poliza, plan, nota, creada_por)::text from polizas_seguro where id = current_setting('t.ana')::uuid),
  row('salud_practicantes', 'Pacífico Seguros', '24043267', null::text, null::text, '00000000-0000-0000-0000-00000528a001'::uuid)::text,
  'los textos se recortan, un plan o una nota en blanco quedan vacíos, y queda quién la registró');

select throws_ok(
  format($$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico', '24043268',
     %L::date, %L::date, 179.97, null, null, null, null, null, null) $$,
     (fn_hoy_lima() + 30)::text, (fn_hoy_lima() + 120)::text),
  'P0001', 'Esa persona ya tiene una póliza de FOLA que se cruza con esas fechas. Si la anterior estaba mal, anúlala primero.',
  'una póliza que se cruza con otra viva del MISMO seguro no entra');

-- Una renovación que empieza el día en que termina la anterior NO se cruza: así se renueva.
select set_config('t.ana_renov',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'salud_practicantes', 'Pacífico Seguros', '24043267',
    fn_hoy_lima() + 82, fn_hoy_lima() + 174, 179.97, null, null, null, null, null, 'Renovación')::text, true);
select ok(current_setting('t.ana_renov') <> '', 'una renovación que empieza el día en que termina la anterior sí entra (con el mismo número: cambia la vigencia)');

select throws_ok(
  format($$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a012', 'salud_practicantes', 'Pacífico Seguros', '24043266',
     %L::date, %L::date, 179.97, null, null, null, null, null, null) $$,
     (fn_hoy_lima() - 100)::text, (fn_hoy_lima() - 20)::text),
  'P0001', 'Esa persona ya tiene una póliza de FOLA que se cruza con esas fechas. Si la anterior estaba mal, anúlala primero.',
  'y repetir la misma vigencia se rechaza por el cruce antes que por el índice');

-- Un complementario: va ADEMÁS del principal. Se le registra a quien lo tenga, sea del vínculo que sea.
select set_config('t.dani_vl',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'vida_ley', 'Rímac Seguros', 'VL-001',
    fn_hoy_lima() - 5, fn_hoy_lima() + 360, 120, null, null, null, null, null, null)::text, true);
select set_config('t.ana_vl',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a011', 'vida_ley', 'Rímac Seguros', 'VL-002',
    fn_hoy_lima() - 10, fn_hoy_lima() + 82, 120, null, null, null, null, null, null)::text, true);
select ok(current_setting('t.dani_vl') <> '' and current_setting('t.ana_vl') <> '',
  'un seguro complementario se le registra a quien lo tenga, y puede coincidir en fechas con su principal');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'vida_ley', 'Rímac Seguros', 'VL-003',
       fn_hoy_lima(), fn_hoy_lima() + 90, 120, null, null, null, null, null, null) $$,
  'P0001', 'Esa persona ya tiene una póliza de Vida Ley que se cruza con esas fechas. Si la anterior estaba mal, anúlala primero.',
  'pero dos del mismo complementario que se pisan no entran');
select is(
  (select count(*)::int from seguros_cambios where persona_id in
     ('00000000-0000-0000-0000-00000528a011', '00000000-0000-0000-0000-00000528a014')),
  0, 'registrar una póliza no es cambiar de seguro: no deja ningún cambio');

select is(
  (select count(*)::int from polizas_seguro_eventos where poliza_id = current_setting('t.ana')::uuid and evento = 'registrada'
      and detalle like 'FOLA · póliza 24043267, del %'),
  1, 'registrar deja su rastro, con el nombre del seguro');

-- Fabi: una póliza cuyo último día es hoy. Jose: una vigente, y después se va.
select set_config('t.fabi_hoy',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a016', 'salud_practicantes', 'Pacífico Seguros', '24043270',
    fn_hoy_lima() - 91, fn_hoy_lima(), 179.97, null, null, null, null, null, null)::text, true);
select set_config('t.jose',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a021', 'salud_practicantes', 'Pacífico Seguros', '24043271',
    fn_hoy_lima() - 5, fn_hoy_lima() + 87, 179.97, null, null, null, null, null, null)::text, true);
set session_replication_role = replica;
update personas set estado = 'inactivo', fecha_cese = fn_hoy_lima() where id = '00000000-0000-0000-0000-00000528a021';
set session_replication_role = origin;

-- ── F · El hueco: quién no tiene una póliza que cubra hoy ────────────────
select is(
  (select row(tipo, hueco, cubre_hoy)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a011'),
  row('salud_practicantes', false, true)::text,
  'Ana, con una póliza FOLA que cubre hoy, no es un hueco');
select is(
  (select row(hueco, cubre_hoy)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a012'),
  row(true, false)::text,
  'Beto, cuya póliza venció hace ocho días, es un hueco');
select is(
  (select row(hueco, cubre_hoy)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a016'),
  row(true, false)::text,
  'y Fabi, cuya póliza termina HOY, también: el último día es EXCLUSIVO (vence a las 12 M de ese día)');
select is(
  (select row(hueco, cubre_hoy)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a014'),
  row(false, null::boolean)::text,
  'una póliza complementaria no tapa ni crea un hueco: Dani sigue en EsSalud, sin póliza que pedir');
select is(
  (select row(activa, hueco)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a021'),
  row(false, false)::text,
  'Jose, que ya no está pero conserva una póliza vigente, sale en la lista (hay que pedir la baja) y no es un hueco');

select is(
  (select row(producto, producto_nombre, producto_principal, cubre_hoy)::text from fn_seguros_tablero()
    where poliza_id = current_setting('t.ana')::uuid),
  row('salud_practicantes', 'FOLA', true, true)::text,
  'el tablero dice de qué seguro es cada póliza, y si ese es el principal');
select is(
  (select row(producto, producto_nombre, producto_principal, cubre_hoy)::text from fn_seguros_tablero()
    where poliza_id = current_setting('t.dani_vl')::uuid),
  row('vida_ley', 'Vida Ley', false, true)::text,
  'y un complementario sale con su nombre');
select is(
  (select sede from fn_seguros_tablero() where poliza_id = current_setting('t.ana')::uuid),
  'ZZB28', 'la lista dice la sede por su código');

-- La líder DO también es DO.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b002', true);
select ok((select count(*)::int from fn_seguros_equipo()) > 0, 'la líder DO ve el equipo');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);

-- ── G · Los pasos del papeleo de una póliza ──────────────────────────────
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

-- ── H · Corregir ─────────────────────────────────────────────────────────
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
  'P0001', 'Esas fechas se cruzan con otra póliza del mismo seguro de esa persona.', 'ni corregir una vigencia hasta pisar la renovación del MISMO seguro');
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

-- ── I · Anular ───────────────────────────────────────────────────────────
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
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a016', 'salud_practicantes', 'Pacífico Seguros', '24043270',
       fn_hoy_lima() - 91, fn_hoy_lima() + 1, 179.97, null, null, null, null, null, null) $$,
  'y con la anulada fuera, se puede registrar la correcta con el mismo número y la misma fecha de inicio');
select is(
  (select hueco from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a016'),
  false, 'y Fabi deja de ser un hueco');

-- ── J · Los archivos ─────────────────────────────────────────────────────
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

-- ── K · El historial de una póliza ───────────────────────────────────────
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

-- ── L · Cambiar el seguro de una persona (asignaciones) ──────────────────
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'sis', fn_hoy_lima() - 10, 'no') $$,
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado en el historial de su seguro.', 'cambiar el seguro pide motivo');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'sis', null, 'Está en el SIS por convenio') $$,
  'P0001', 'Falta la fecha desde la que rige.', 'y una fecha');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'sis', fn_hoy_lima() + 1, 'Está en el SIS por convenio') $$,
  'P0001', 'La fecha no puede ser posterior a hoy.', 'que no sea de mañana');
select throws_ok(
  $$ select fn_seguro_asignar(gen_random_uuid(), 'sis', fn_hoy_lima(), 'Está en el SIS por convenio') $$,
  'P0001', 'Esa persona no existe.', 'a una persona que no existe no se le cambia nada');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a013', 'sis', fn_hoy_lima(), 'Está en el SIS por convenio') $$,
  'P0001', 'Esa persona está inactiva.', 'ni a una que ya se fue');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'nada', fn_hoy_lima(), 'Está en el SIS por convenio') $$,
  'P0001', 'Ese tipo de seguro no existe.', 'ni a un tipo que no existe');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'vida_ley', fn_hoy_lima(), 'Tiene seguro de vida') $$,
  'P0001', 'Ese seguro va además del principal: no se asigna, se le registra su póliza.',
  'un complementario no se asigna (la sacaría de EsSalud): se le registra su póliza');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a012', 'salud_practicantes', fn_hoy_lima(), 'Que siga en FOLA') $$,
  'P0001', 'Eso es lo que le corresponde por su vínculo: usa «volver al automático».',
  'lo que le toca por su vínculo no se asigna: dejaría a la persona fija y sin seguir su vínculo');

select set_config('t.asig1',
  fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'sis', fn_hoy_lima() - 10, '  Está en el SIS por un convenio  ')::text, true);
select is(
  (select row(tipo, origen, asignacion_motivo, con_poliza, hueco)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a014'),
  row('sis', 'asignacion', 'Está en el SIS por un convenio', false, false)::text,
  'después de asignarle el SIS, su fila dice SIS «por asignación», con el motivo recortado');
select is(
  (select asignacion_id from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a014'),
  current_setting('t.asig1')::uuid, 'y apunta a la asignación');
select is(
  (select row(tipo, tipo_automatico, tipo_automatico_nombre)::text from fn_seguros_equipo()
    where persona_id = '00000000-0000-0000-0000-00000528a014'),
  row('sis', 'essalud', 'EsSalud')::text,
  'con una asignación vigente la fila sigue diciendo cuál le toca por su vínculo (EsSalud), aunque hoy esté en el SIS');
select is(
  (select count(*)::int from seguros_cambios
    where persona_id = '00000000-0000-0000-0000-00000528a014' and de_tipo = 'essalud' and a_tipo = 'sis'
      and origen = 'asignacion' and detalle = 'Está en el SIS por un convenio'),
  1, 'el cambio EsSalud → SIS queda escrito, con el motivo');
select is(
  (select row(baja_pendiente, alta_pendiente, baja_texto, alta_texto)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a014', false)),
  row(true, true, 'Confirmar con el contador la baja en EsSalud', 'Dar de alta en SIS')::text,
  'deja dos pendientes: la baja de EsSalud y el alta en el SIS (el tipo que agregó DO no trae texto: lo arma con su nombre)');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'sis', fn_hoy_lima() - 9, 'Otra vez el SIS') $$,
  'P0001', 'Esa persona ya está en ese seguro.', 'asignar el seguro en el que ya está se rechaza');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'plan_premium', fn_hoy_lima() - 10, 'Pasa al plan premium') $$,
  'P0001', 'Ya tiene una asignación desde el ' || to_char(fn_hoy_lima() - 10, 'DD/MM/YYYY') || ': usa una fecha posterior, o vuélvela al automático primero.',
  'una fecha que no es posterior a la de la asignación abierta se rechaza');

-- Una segunda asignación cierra la anterior donde empieza.
select set_config('t.asig2',
  fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'plan_premium', fn_hoy_lima() - 3, 'Pasa al plan premium')::text, true);
select is(
  (select row(hasta, cerrada_motivo)::text from seguros_asignaciones where id = current_setting('t.asig1')::uuid),
  row(fn_hoy_lima() - 3, 'Reemplazada por otra asignación')::text,
  'la primera asignación termina donde empieza la segunda, y dice por qué');
select is(
  (select row(tipo, con_poliza, hueco)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a014'),
  row('plan_premium', true, true)::text,
  'con un seguro principal que pide póliza y todavía sin ella, Dani es un hueco');
select throws_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'salud_practicantes', 'Pacífico', '24043299',
       fn_hoy_lima() - 3, fn_hoy_lima() + 89, 179.97, null, null, null, null, null, null) $$,
  'P0001', 'El seguro principal de esa persona hoy es Plan Premium: no se le registra una póliza de FOLA. Si debe cambiar, cámbiale el seguro primero.',
  'y la póliza que se le puede registrar es la de SU seguro principal, no la de otro');
select set_config('t.dani_pp',
  fn_seguro_registrar('00000000-0000-0000-0000-00000528a014', 'plan_premium', 'Pacífico Seguros', 'PP-001',
    fn_hoy_lima() - 3, fn_hoy_lima() + 89, 300, null, null, null, null, null, null)::text, true);
select is(
  (select hueco from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a014'),
  false, 'con su póliza registrada deja de ser un hueco');
select is(
  (select row(de_tipo, a_tipo, baja_pendiente, alta_pendiente)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a014', false)
    where de_tipo = 'sis'),
  row('sis', 'plan_premium', true, false)::text,
  'y el alta en un seguro con póliza se cerró SOLA al registrarla; la baja del SIS (sin póliza) sigue pendiente');

-- Volver al automático.
select throws_ok(
  $$ select fn_seguro_volver_al_automatico(gen_random_uuid(), null, 'Vuelve a su vínculo') $$,
  'P0001', 'Esa asignación no existe.', 'volver al automático una asignación que no existe se rechaza');
select throws_ok(
  format($$ select fn_seguro_volver_al_automatico(%L, null, 'Vuelve a su vínculo') $$, current_setting('t.asig1')),
  'P0001', 'Esa asignación ya terminó.', 'ni una que ya terminó');
select throws_ok(
  format($$ select fn_seguro_volver_al_automatico(%L, fn_hoy_lima() + 1, 'Vuelve a su vínculo') $$, current_setting('t.asig2')),
  'P0001', 'La fecha no puede ser posterior a hoy.', 'ni con fecha de mañana');
select throws_ok(
  format($$ select fn_seguro_volver_al_automatico(%L, fn_hoy_lima() - 5, 'Vuelve a su vínculo') $$, current_setting('t.asig2')),
  'P0001', 'No puede terminar antes de empezar (empezó el ' || to_char(fn_hoy_lima() - 3, 'DD/MM/YYYY') || ').',
  'ni terminando antes de haber empezado');
select throws_ok(
  format($$ select fn_seguro_volver_al_automatico(%L, null, 'no') $$, current_setting('t.asig2')),
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado en el historial de su seguro.', 'y pide motivo');

select lives_ok(
  format($$ select fn_seguro_volver_al_automatico(%L, null, 'Vuelve a su seguro por vínculo') $$, current_setting('t.asig2')),
  'DO devuelve a Dani a su seguro automático');
select is(
  (select row(tipo, origen, asignacion_id)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a014'),
  row('essalud', 'vinculo', null::uuid)::text,
  'su fila vuelve a EsSalud «por vínculo»');
select is(
  (select tipo = tipo_automatico from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a014'),
  true, 'y al volver al automático, lo que tiene y lo que le toca son lo mismo');
select is(
  (select row(hasta, cerrada_motivo)::text from seguros_asignaciones where id = current_setting('t.asig2')::uuid),
  row(fn_hoy_lima(), 'Vuelve a su seguro por vínculo')::text,
  'la asignación termina hoy, con su motivo');
select is(
  (select row(baja_pendiente, alta_pendiente)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a014', false)
    where de_tipo = 'plan_premium' and a_tipo = 'essalud'),
  row(true, true)::text,
  'y el cambio Plan Premium → EsSalud deja la baja (todavía hay una póliza vigente del Plan Premium) y el alta en EsSalud');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'sis', fn_hoy_lima() - 8, 'Retroactivo al SIS') $$,
  'P0001', 'Esa fecha se cruza con una asignación anterior de la misma persona.',
  'una asignación que empieza antes de que termine una anterior se rechaza');

-- Un tipo con gente asignada no se archiva.
select set_config('t.asig_kari',
  fn_seguro_asignar('00000000-0000-0000-0000-00000528a022', 'sis', fn_hoy_lima() - 2, 'Está en el SIS por convenio')::text, true);
select throws_ok(
  $$ select fn_seguro_tipo_activar('sis', false, 'ya no se usa') $$,
  'P0001', 'Todavía hay colaboradores asignados a ese seguro: vuélvelos al automático antes de archivarlo.',
  'un tipo con alguien asignado no se archiva');
select throws_ok(
  $$ select fn_seguro_tipo_activar('plan_premium', false, 'ya no se usa') $$,
  'P0001', 'Todavía hay pólizas vigentes de ese seguro: no se archiva.',
  'ni uno con pólizas vigentes');

-- ── M · Cuando alguien cambia de vínculo: el disparador ──────────────────
-- Kari tiene una asignación vigente: cambiar de vínculo NO cambia su seguro.
update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'profesional'
 where id = '00000000-0000-0000-0000-00000528a022';
select is(
  (select count(*)::int from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a022' and origen = 'vinculo'),
  0, 'quien tiene una asignación de DO vigente no registra un cambio por cambiar de vínculo: su seguro no se movió');
select lives_ok(
  format($$ select fn_seguro_volver_al_automatico(%L, null, 'Ahora es practicante: vuelve a FOLA') $$, current_setting('t.asig_kari')),
  'al devolverla al automático, su seguro pasa a ser el de su vínculo nuevo');
select is(
  (select row(tipo, hueco)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a022'),
  row('salud_practicantes', true)::text, 'Kari, practicante, está en FOLA y todavía sin póliza: un hueco');
select is(
  (select count(*)::int from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a022' and de_tipo = 'sis' and a_tipo = 'salud_practicantes'),
  1, 'y el cambio SIS → FOLA quedó escrito');
select lives_ok($$ select fn_seguro_tipo_activar('sis', false, 'ya no se usa') $$, 'ahora sí se archiva el SIS');
select throws_ok(
  $$ select fn_seguro_asignar('00000000-0000-0000-0000-00000528a014', 'sis', fn_hoy_lima(), 'Otra vez al SIS') $$,
  'P0001', 'Ese tipo de seguro está archivado.', 'y no se le asigna a nadie más');

-- Ana pasa de practicante a planilla: FOLA → EsSalud.
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null
 where id = '00000000-0000-0000-0000-00000528a011';
select is(
  (select row(de_tipo, a_tipo, origen, vinculo_antes, vinculo_despues, fecha)::text from seguros_cambios
    where persona_id = '00000000-0000-0000-0000-00000528a011'),
  row('salud_practicantes', 'essalud', 'vinculo', 'practicante', 'planilla', fn_hoy_lima())::text,
  'cuando Ana pasa a planilla queda escrito «FOLA → EsSalud», con su vínculo de antes y de ahora');
select is(
  (select row(baja_pendiente, alta_pendiente, baja_texto, alta_texto)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a011', false)),
  row(true, true, 'Pedirle a la aseguradora la baja de su póliza FOLA', 'Confirmar con el contador el alta en EsSalud')::text,
  'y deja los dos pendientes: pedir la baja de la póliza FOLA (sigue vigente) y confirmar el alta en EsSalud');
select is(
  (select row(tipo, hueco, cubre_hoy)::text from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a011'),
  row('essalud', false, null::boolean)::text, 'su fila ya dice EsSalud, sin hueco');

-- Los cambios de vínculo que no mueven el seguro no escriben nada.
update personas set tipo_vinculo = 'planilla' where id = '00000000-0000-0000-0000-00000528a018';
update personas set tipo_vinculo = 'rxh' where id = '00000000-0000-0000-0000-00000528a019';
select is(
  (select count(*)::int from seguros_cambios where persona_id in
     ('00000000-0000-0000-0000-00000528a018', '00000000-0000-0000-0000-00000528a019')),
  0, 'prueba → planilla (los dos EsSalud) y sin vínculo → honorarios (ninguno) no mueven el seguro: no escriben nada');

-- Honorarios pasa a planilla: no tenía seguro y ahora EsSalud (solo hay alta).
update personas set tipo_vinculo = 'planilla' where id = '00000000-0000-0000-0000-00000528a017';
select is(
  (select row(de_tipo, a_tipo)::text from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a017'),
  row(null::text, 'essalud')::text, 'honorarios → planilla: no tenía seguro y ahora EsSalud');
select is(
  (select row(baja_pendiente, alta_pendiente)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a017', false)),
  row(false, true)::text, 'solo pide el alta: no hay baja de un seguro que no tenía');
select set_config('t.cambio_gabi', (select id::text from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a017'), true);
select throws_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'baja', fn_hoy_lima(), null) $$, current_setting('t.cambio_gabi')),
  'P0001', 'Ese cambio no tiene baja: la persona no tenía seguro antes.', 'y marcarle una baja se rechaza');

-- Planilla pasa a rxh: se queda sin seguro (solo hay baja).
update personas set tipo_vinculo = 'rxh' where id = '00000000-0000-0000-0000-00000528a023';
select set_config('t.cambio_luis', (select id::text from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a023'), true);
select is(
  (select row(de_tipo, a_tipo)::text from seguros_cambios where id = current_setting('t.cambio_luis')::uuid),
  row('essalud', null::text)::text, 'planilla → honorarios: sale de EsSalud y no entra a ninguno');
select throws_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'alta', fn_hoy_lima(), null) $$, current_setting('t.cambio_luis')),
  'P0001', 'Ese cambio no tiene alta: la persona se quedó sin seguro.', 'y marcarle un alta se rechaza');

-- Planilla pasa a practicante: EsSalud → FOLA. El alta se cierra sola al registrar la póliza.
update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'preprofesional'
 where id = '00000000-0000-0000-0000-00000528a020';
select set_config('t.cambio_iris', (select id::text from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a020'), true);
select is(
  (select row(baja_pendiente, alta_pendiente)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a020', false)),
  row(true, true)::text, 'planilla → practicante deja la baja de EsSalud y el alta en FOLA');
select is(
  (select hueco from fn_seguros_equipo() where persona_id = '00000000-0000-0000-0000-00000528a020'),
  true, 'y la practicante nueva, sin póliza, es un hueco');
select lives_ok(
  $$ select fn_seguro_registrar('00000000-0000-0000-0000-00000528a020', 'salud_practicantes', 'Pacífico Seguros', '24043280',
       fn_hoy_lima() - 1, fn_hoy_lima() + 91, 179.97, null, null, null, null, null, null) $$,
  'se le registra su póliza FOLA');
select is(
  (select row(baja_pendiente, alta_pendiente)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a020', false)),
  row(true, false)::text,
  'y el alta en FOLA se cerró SOLA (ya hay póliza); la baja de EsSalud, que no tiene póliza, sigue pendiente hasta que DO la marque');

-- Marcar los pasos.
select throws_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'otro', fn_hoy_lima(), null) $$, current_setting('t.cambio_iris')),
  'P0001', 'Ese paso no existe: usa baja o alta.', 'un paso que no existe se rechaza');
select throws_ok(
  $$ select fn_seguro_cambio_marcar(gen_random_uuid(), 'baja', fn_hoy_lima(), null) $$,
  'P0001', 'Ese cambio no existe.', 'un cambio que no existe también');
select throws_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'baja', fn_hoy_lima() + 1, null) $$, current_setting('t.cambio_iris')),
  'P0001', 'La fecha no puede ser posterior a hoy.', 'ni con fecha de mañana');
select lives_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'baja', fn_hoy_lima() - 1, 'Ya se lo confirmé al contador') $$, current_setting('t.cambio_iris')),
  'DO marca la baja de EsSalud como hecha');
select is(
  (select row(baja_pendiente, baja_hecha_el, baja_nota)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a020', false)),
  row(false, fn_hoy_lima() - 1, 'Ya se lo confirmé al contador')::text, 'y deja de pedirse, con su fecha y su nota');
select throws_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'baja', fn_hoy_lima() - 1, null) $$, current_setting('t.cambio_iris')),
  'P0001', 'Ese paso ya estaba marcado con esa fecha.', 'repetir la misma marca se rechaza');
select throws_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'baja', null, 'no') $$, current_setting('t.cambio_iris')),
  'P0001', 'Escribe el motivo (al menos 5 letras): quitar una marca queda anotado.', 'quitar una marca pide motivo');
select lives_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'baja', null, 'La marqué en la persona equivocada') $$, current_setting('t.cambio_iris')),
  'con motivo, se quita');
select is(
  (select row(baja_pendiente, baja_hecha_el)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a020', false)),
  row(true, null::date)::text, 'y la baja vuelve a pedirse');
select throws_ok(
  format($$ select fn_seguro_cambio_marcar(%L, 'alta', null, 'Ya estaba sin marcar') $$, current_setting('t.cambio_iris')),
  'P0001', 'Ese paso ya está sin marcar.', 'quitar una marca que no existe se rechaza');

-- Un seguro con póliza deja de pedir su baja solo cuando la póliza ya no está vigente.
select lives_ok(format($$ select fn_seguro_anular(%L, 'ya no es practicante, se anuló') $$, current_setting('t.ana')), 'se anula la póliza vigente de Ana');
select is(
  (select baja_pendiente from fn_seguros_cambios('00000000-0000-0000-0000-00000528a011', false)),
  true, 'pero queda la renovación futura de FOLA: la baja se sigue pidiendo');
select lives_ok(format($$ select fn_seguro_anular(%L, 'ya no es practicante, se anuló') $$, current_setting('t.ana_renov')), 'se anula también la renovación');
select is(
  (select baja_pendiente from fn_seguros_cambios('00000000-0000-0000-0000-00000528a011', false)),
  false, 'y sin ninguna póliza FOLA vigente la baja deja de pedirse SOLA: no hay nada que dar de baja');

-- Ana vuelve a practicante: el cambio viejo ya no pide nada y el nuevo pide el alta.
update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'profesional'
 where id = '00000000-0000-0000-0000-00000528a011';
select is(
  (select count(*)::int from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a011'),
  2, 'volver a practicante es otro cambio: EsSalud → FOLA');
select is(
  (select string_agg(row(de_tipo, a_tipo, baja_pendiente, alta_pendiente)::text, ' / ' order by creado_at desc)
     from fn_seguros_cambios('00000000-0000-0000-0000-00000528a011', false)),
  '(essalud,salud_practicantes,t,t) / (salud_practicantes,essalud,f,f)',
  'el nuevo pide la baja de EsSalud y el alta en FOLA (no tiene póliza vigente); el viejo ya no pide NADA: volvió al seguro del que salió');
select is(
  (select count(*)::int from fn_seguros_cambios('00000000-0000-0000-0000-00000528a011', true)),
  1, 'y «solo pendientes» deja únicamente el nuevo');
select is(
  (select count(*)::int from fn_seguros_cambios(null, true) where persona_id = '00000000-0000-0000-0000-00000528a011'),
  1, 'lo mismo para todas las personas a la vez');

-- Una persona que ya no está activa no registra cambios ni pide pasos.
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null
 where id = '00000000-0000-0000-0000-00000528a021';
select is(
  (select count(*)::int from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a021'),
  0, 'quien ya no está activo no registra cambios (de su baja se ocupa el cese)');
set session_replication_role = replica;
update personas set estado = 'inactivo', fecha_cese = fn_hoy_lima() where id = '00000000-0000-0000-0000-00000528a017';
set session_replication_role = origin;
select is(
  (select row(baja_pendiente, alta_pendiente)::text from fn_seguros_cambios('00000000-0000-0000-0000-00000528a017', false)),
  row(false, false)::text, 'y si la persona se va con pasos sin hacer, esos pasos dejan de pedirse');

-- Iris, que SÍ conserva su póliza FOLA vigente, va a planilla y vuelve: lo que ya no hace
-- falta no se pide aunque quede una póliza vigente (se distingue de «ya no hay póliza»).
update personas set tipo_vinculo = 'planilla', practicante_modalidad = null
 where id = '00000000-0000-0000-0000-00000528a020';
select is(
  (select baja_pendiente from fn_seguros_cambios('00000000-0000-0000-0000-00000528a020', false)
    where de_tipo = 'salud_practicantes' and a_tipo = 'essalud'),
  true, 'Iris pasa a planilla con su póliza FOLA vigente: se pide la baja de esa póliza');
update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'preprofesional'
 where id = '00000000-0000-0000-0000-00000528a020';
select is(
  (select baja_pendiente from fn_seguros_cambios('00000000-0000-0000-0000-00000528a020', false)
    where de_tipo = 'salud_practicantes' and a_tipo = 'essalud'),
  false, 'pero si vuelve a practicante, esa baja deja de pedirse aunque la póliza siga vigente: volvió al seguro del que salió');
select is(
  (select alta_pendiente from fn_seguros_cambios('00000000-0000-0000-0000-00000528a020', false)
    where de_tipo = 'salud_practicantes' and a_tipo = 'essalud'),
  false, 'y el alta en EsSalud tampoco: ya no está en EsSalud');

-- ── N · El catálogo con cuánta gente hay en cada tipo ────────────────────
select is(
  (select clave from fn_seguros_tipos() limit 1) in ('essalud', 'salud_practicantes'), true,
  'el catálogo empieza por los de sistema');
select is(
  (select personas from fn_seguros_tipos() where clave = 'essalud'),
  (select count(*)::int from fn_seguros_equipo() where tipo = 'essalud' and activa),
  'EsSalud cuenta a las personas activas que están en él, las mismas que la lista de equipo');
select is(
  (select row(personas, polizas_vigentes)::text from fn_seguros_tipos() where clave = 'vida_ley'),
  row(2, 2)::text, 'un complementario cuenta las personas con póliza vigente y las pólizas (Dani y Ana: la de Vida Ley de Ana sigue vigente aunque su vínculo cambió)');
select is(
  (select row(activo, archivado_motivo)::text from fn_seguros_tipos() where clave = 'sis'),
  row(false, 'ya no se usa')::text, 'y un tipo archivado dice su motivo');

-- ── O · Los archivos en Storage ──────────────────────────────────────────
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
select is((select count(*)::int from seguros_cambios), 0, 'ni los cambios de seguro');
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

-- ── O2 · Con las funciones de verdad ────────────────────────────────────
-- El disparador escucha la columna, no a quien la escribe. Las dos funciones que de verdad
-- cambian el vínculo en producción —`fn_set_tipo_vinculo` y `fn_cesar_persona`— tienen que
-- llevarse bien con él: un cambio que no mueve el seguro no deja nada, uno que sí lo mueve
-- deja su cambio, y un cese con vínculo nuevo en el mismo acto tampoco (ya no está activa).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo, practicante_modalidad, estado, cuenta_de_servicio, fecha_cese) values
  ('00000000-0000-0000-0000-00000528a024', 'Mara', 'Seg', '00000000-0000-0000-0000-000005280001', 'integrante', 'x', null, '2024-06-01', 'planilla', 'Vendedora',  null, 'activo', false, null),
  ('00000000-0000-0000-0000-00000528a025', 'Nico', 'Seg', '00000000-0000-0000-0000-000005280001', 'integrante', 'x', null, '2026-03-01', 'rxh',      'Honorarios', null, 'activo', false, null);
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000528b001', true);

select lives_ok(
  $$ select fn_set_tipo_vinculo('00000000-0000-0000-0000-00000528a024', 'prueba') $$,
  'DO pasa a Mara de planilla a prueba con la función de verdad');
select is(
  (select count(*)::int from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a024'),
  0, 'planilla → prueba no mueve su seguro (los dos son EsSalud): no deja cambio');
select lives_ok(
  $$ select fn_set_tipo_vinculo('00000000-0000-0000-0000-00000528a025', 'planilla') $$,
  'y pasa a Nico de honorarios a planilla');
select is(
  (select row(de_tipo, a_tipo, origen)::text from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a025'),
  row(null::text, 'essalud', 'vinculo')::text,
  'honorarios → planilla sí lo mueve: de «sin seguro» a EsSalud, por vínculo');
select lives_ok(
  $$ select fn_cesar_persona('00000000-0000-0000-0000-00000528a024', fn_hoy_lima(), 'fin_contrato', 'rxh') $$,
  'DO cesa a Mara y en el mismo acto la deja como honorarios');
select is(
  (select count(*)::int from seguros_cambios where persona_id = '00000000-0000-0000-0000-00000528a024'),
  0, 'quien ya no está activa no deja cambio, aunque su vínculo cambie en el cese');

-- ── P · Un fallo del registro de cambios NO frena el cambio de vínculo ───
-- Lo último de la prueba, porque rompe la tabla de cambios a propósito. Un cambio de
-- vínculo mueve la planilla de una persona real: el registro de su seguro no puede
-- dejarla sin cambiar.
drop table seguros_cambios cascade;
select lives_ok(
  $$ update personas set tipo_vinculo = 'practicante', practicante_modalidad = 'profesional'
      where id = '00000000-0000-0000-0000-00000528a014' $$,
  'aunque la tabla de cambios no exista, el cambio de vínculo se hace igual (el disparador solo avisa)');
select is(
  (select tipo_vinculo from personas where id = '00000000-0000-0000-0000-00000528a014'),
  'practicante', 'y el vínculo cambió de verdad');

select * from finish();
rollback;
