-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 397_el_archivo_de_la_empresa.test.sql — la 0503 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) NADIE fuera de DO ve un papel del archivo —ni la ficha ni el archivo—,
--     porque la constancia de un banco de datos lleva el DNI del representante,
-- (b) ningún papel se edita ni se borra: corregir deja la versión anterior en
--     el historial, y retirar exige motivo,
-- (c) un papel no se bifurca: dos reemplazos de la misma ficha no conviven,
-- (d) el peso y el tipo salen de Storage, no de lo que diga el navegador, y
-- (e) un archivo que una ficha usa no se pisa ni se borra; uno huérfano sí.
-- ============================================================================
begin;
select plan(49);

-- ── Sede y personas ──────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000005030001', 'ZZA03', 'Sede archivo', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-00000503a001', 'AdmArch', 'Lab', '00000000-0000-0000-0000-000005030001', 'admin',           'x', '00000000-0000-0000-0000-00000503b001', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-00000503a002', 'DoArch',  'Lab', '00000000-0000-0000-0000-000005030001', 'lider_do',        'x', '00000000-0000-0000-0000-00000503b002', '2023-01-01', 'planilla', 'Líder DO'),
  ('00000000-0000-0000-0000-00000503a003', 'EncArch', 'Lab', '00000000-0000-0000-0000-000005030001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000503b003', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-00000503a004', 'AnaArch', 'Lab', '00000000-0000-0000-0000-000005030001', 'integrante',      'x', '00000000-0000-0000-0000-00000503b004', '2023-01-01', 'planilla', 'Vendedora');
set session_replication_role = origin;

-- Lo que Storage guardaría al recibir cada archivo (peso y tipo salen de acá).
insert into storage.objects (bucket_id, name, metadata) values
  ('archivo-empresa', '1a000000-0000-0000-0000-000000000001.pdf', '{"size": 32768, "mimetype": "application/pdf"}'),
  ('archivo-empresa', '1a000000-0000-0000-0000-000000000002.pdf', '{"size": 65536, "mimetype": "application/pdf"}'),
  ('archivo-empresa', '1a000000-0000-0000-0000-000000000003.jpg', '{"size": 900000, "mimetype": "image/jpeg"}'),
  ('archivo-empresa', '1a000000-0000-0000-0000-000000000009.pdf', '{"size": 1000, "mimetype": "application/pdf"}');

-- ── A · El bucket y los permisos ─────────────────────────────────────────
select is(
  (select count(*)::int from storage.buckets where id = 'archivo-empresa' and public is false and file_size_limit = 52428800),
  1, 'el bucket existe, es privado y limita a 50 MB por archivo');

select is(
  (select count(*)::int from pg_policies where schemaname = 'storage' and policyname like 'archivo\_empresa\_%'),
  4, 'Storage tiene sus cuatro políticas (insert, select, update, delete)');

select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('fn_archivo_subir','fn_archivo_retirar','fn_archivo_empresa','fn_archivo_libre')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'ninguna función del archivo le responde a quien no inició sesión');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proname in ('fn_archivo_subir','fn_archivo_retirar','fn_archivo_empresa','fn_archivo_libre')),
  4, 'y las cuatro las puede llamar quien sí inició sesión (un grant faltante fallaría en silencio)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b001', true);
set local role authenticated;
select throws_ok(
  $$ insert into archivo_empresa (titulo, entidad, fecha_documento, storage_path, nombre_archivo, mime, bytes, subido_por)
     values ('Papel', 'SUNAT', '2026-01-01', '1a000000-0000-0000-0000-000000000001.pdf', 'x.pdf', 'application/pdf', 1,
             '00000000-0000-0000-0000-00000503a001') $$,
  '42501', null, 'ni DO inserta una ficha a mano: solo por la función');
select throws_ok($$ update archivo_empresa set titulo = 'otro' $$, '42501', null, 'ni actualiza una ficha a mano');
select throws_ok($$ delete from archivo_empresa $$, '42501', null, 'ni la borra');
select throws_ok($$ truncate archivo_empresa $$, '42501', null, 'ni vacía la tabla (truncate no pasa por RLS: lo detiene el permiso)');
reset role;

-- ── B · Quién sube, y qué se rechaza ─────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b004', true);
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constancia.pdf', 'Constancia', 'ANPD', null,
       '2026-09-08', null, null, null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede subir papeles al archivo de la empresa.', 'una integrante no sube papeles');
select throws_ok($$ select * from fn_archivo_empresa() $$,
  'P0001', 'Solo Desarrollo Organizacional ve el archivo de la empresa.', 'ni ve el archivo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b003', true);
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constancia.pdf', 'Constancia', 'ANPD', null,
       '2026-09-08', null, null, null) $$,
  'P0001', 'Solo Desarrollo Organizacional puede subir papeles al archivo de la empresa.', 'ni la líder de equipo');
select throws_ok($$ select * from fn_archivo_empresa() $$,
  'P0001', 'Solo Desarrollo Organizacional ve el archivo de la empresa.', 'ni lo ve la líder de equipo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b001', true);
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-0000000000ff.pdf', 'constancia.pdf', 'Constancia', 'ANPD', null,
       '2026-09-08', null, null, null) $$,
  'P0001', 'El archivo no llegó al almacén. Vuelve a subirlo.', 'una ruta que no existe en Storage no entra (el archivo va primero)');
select throws_ok(
  $$ select fn_archivo_subir('Felipe DNI.pdf', 'constancia.pdf', 'Constancia', 'ANPD', null,
       '2026-09-08', null, null, null) $$,
  'P0001', 'La ruta del archivo no tiene la forma esperada.', 'una ruta con nombres no entra');
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constancia.pdf', 'Constancia', 'ANPD', null,
       fn_hoy_lima() + 1, null, null, null) $$,
  'P0001', 'La fecha del papel no puede ser posterior a hoy.', 'un papel fechado mañana no entra');
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constancia.pdf', 'Constancia', 'ANPD', null,
       '2026-09-08', '2026-09-01', null, null) $$,
  'P0001', 'El papel no puede vencer antes de la fecha en que se emitió.', 'ni uno que vence antes de emitirse');
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constancia.pdf', '  ', 'ANPD', null,
       '2026-09-08', null, null, null) $$,
  'P0001', 'Escribe qué papel es (al menos 3 letras).', 'ni uno sin título');
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constancia.pdf', 'Constancia', null, null,
       '2026-09-08', null, null, null) $$,
  'P0001', 'Escribe quién emite el papel.', 'ni uno sin entidad');

-- Las fichas reales de la prueba. Se guarda cada id para usarlo después.
select set_config('t.const',
  fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constanciaInscripción videovigilancia.pdf',
    'Constancia de inscripción del banco de datos Videovigilancia',
    'Autoridad Nacional de Protección de Datos Personales', '  INS-2026-5135 ',
    '2026-09-08', null, null, '   ')::text, true);
select set_config('t.lic',
  fn_archivo_subir('1a000000-0000-0000-0000-000000000003.jpg', 'licencia.jpg',
    'Licencia de funcionamiento', 'Municipalidad de Trujillo', null,
    '2025-03-10', null, '00000000-0000-0000-0000-000005030001', 'Colgada junto a la caja')::text, true);

select is(
  (select row(mime, bytes, numero, nota, subido_por)::text from archivo_empresa where id = current_setting('t.const')::uuid),
  row('application/pdf', 32768::bigint, 'INS-2026-5135', null::text, '00000000-0000-0000-0000-00000503a001'::uuid)::text,
  'el tipo y el peso salen de Storage; el número se recorta, una nota en blanco queda vacía y queda quién la subió');

-- ── C · Lo que ve la pantalla ────────────────────────────────────────────
select is(
  (select count(*)::int from fn_archivo_empresa() where estado = 'vigente'),
  2, 'las dos fichas nuevas están vigentes');
select is(
  (select sede_nombre from fn_archivo_empresa() where id = current_setting('t.lic')::uuid),
  'Sede archivo', 'la licencia dice de qué sede es');
select is(
  (select subido_por_nombre from fn_archivo_empresa() where id = current_setting('t.const')::uuid),
  'AdmArch Lab', 'y la lista dice quién subió cada papel');

-- La líder DO también es DO.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b002', true);
select is((select count(*)::int from fn_archivo_empresa()), 2, 'la líder DO ve el archivo');

-- ── D · Reemplazar ───────────────────────────────────────────────────────
-- Corregir solo un dato: misma ruta, ficha nueva.
select set_config('t.const2',
  fn_archivo_subir('1a000000-0000-0000-0000-000000000001.pdf', 'constanciaInscripción videovigilancia.pdf',
    'Constancia de inscripción del banco de datos Videovigilancia',
    'Autoridad Nacional de Protección de Datos Personales', 'INS-2026-5135 · PJ-2026-4553',
    '2026-09-08', null, null, null, current_setting('t.const')::uuid)::text, true);

select is(
  (select estado || ' → ' || reemplazada_por from fn_archivo_empresa() where id = current_setting('t.const')::uuid),
  'reemplazada → ' || current_setting('t.const2'),
  'la ficha anterior queda en el historial, apuntando a la que la reemplaza');
select is(
  (select estado from fn_archivo_empresa() where id = current_setting('t.const2')::uuid),
  'vigente', 'y la nueva es la vigente');
select is(
  (select count(*)::int from archivo_empresa where storage_path = '1a000000-0000-0000-0000-000000000001.pdf'),
  2, 'las dos usan el mismo archivo: corregir un dato no obliga a subirlo otra vez');

select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000002.pdf', 'otra.pdf', 'Constancia', 'ANPD', null,
       '2026-09-08', null, null, null, current_setting('t.const')::uuid) $$,
  'P0001', 'Esa ficha ya fue reemplazada por otra. Recarga la pantalla.',
  'una ficha ya reemplazada no se reemplaza otra vez (dos pantallas abiertas no bifurcan el papel)');

-- Aunque alguien se saltara la función, la base no admite la bifurcación.
set session_replication_role = replica;
select throws_ok(
  $$ insert into archivo_empresa (titulo, entidad, fecha_documento, storage_path, nombre_archivo, mime, bytes, reemplaza_a, subido_por)
     values ('Bifurcación', 'ANPD', '2026-09-08', '1a000000-0000-0000-0000-000000000002.pdf', 'x.pdf', 'application/pdf', 1,
             current_setting('t.const')::uuid, '00000000-0000-0000-0000-00000503a001') $$,
  '23505', null, 'el índice único de reemplaza_a rechaza una segunda ficha que reemplace a la misma');
set session_replication_role = origin;

select throws_ok(
  format($$ select fn_archivo_retirar(%L, 'subida por error') $$, current_setting('t.const')),
  'P0001', 'Esa ficha ya fue reemplazada: se retira la versión vigente.', 'una ficha vieja no se retira');

-- ── E · Retirar ──────────────────────────────────────────────────────────
select throws_ok(
  format($$ select fn_archivo_retirar(%L, 'no') $$, current_setting('t.lic')),
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado junto al papel.', 'retirar exige motivo');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b004', true);
select throws_ok(
  format($$ select fn_archivo_retirar(%L, 'la sede cerró') $$, current_setting('t.lic')),
  'P0001', 'Solo Desarrollo Organizacional puede retirar papeles del archivo de la empresa.', 'una integrante no retira papeles');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b001', true);
select lives_ok(
  format($$ select fn_archivo_retirar(%L, '  la sede cerró  ') $$, current_setting('t.lic')),
  'DO retira la licencia de una sede que cerró');
select is(
  (select estado || ' · ' || retirado_por_nombre || ' · ' || retirado_motivo from fn_archivo_empresa() where id = current_setting('t.lic')::uuid),
  'retirada · AdmArch Lab · la sede cerró', 'queda retirada, con quién y por qué');
select throws_ok(
  format($$ select fn_archivo_retirar(%L, 'otra vez más') $$, current_setting('t.lic')),
  'P0001', 'Esa ficha ya está retirada.', 'no se retira dos veces');
select throws_ok(
  $$ select fn_archivo_subir('1a000000-0000-0000-0000-000000000003.jpg', 'licencia.jpg', 'Licencia', 'Municipalidad', null,
       '2025-03-10', null, null, null, current_setting('t.lic')::uuid) $$,
  'P0001', 'Esa ficha está retirada: no se reemplaza. Sube el papel como nuevo.', 'ni se reemplaza una retirada');

-- ── F · Nada se edita ni se borra, ni siquiera desde el SQL Editor ───────
select throws_ok(
  format($$ update archivo_empresa set vence_el = '2030-01-01' where id = %L $$, current_setting('t.const2')),
  'P0001', 'Una ficha del archivo no se edita: se reemplaza por otra.', 'cambiar un dato a mano se rechaza');
select throws_ok(
  format($$ delete from archivo_empresa where id = %L $$, current_setting('t.const2')),
  'P0001', 'Un papel del archivo no se borra: se retira, con motivo.', 'borrar una ficha se rechaza');
select throws_ok(
  format($$ update archivo_empresa set retirado_motivo = 'otro motivo' where id = %L $$, current_setting('t.lic')),
  'P0001', 'Esa ficha ya está retirada.', 'el motivo de un retiro no se reescribe');

set session_replication_role = replica;
select throws_ok(
  $$ insert into archivo_empresa (titulo, entidad, fecha_documento, vence_el, storage_path, nombre_archivo, mime, bytes, subido_por)
     values ('Al revés', 'SUNAT', '2026-09-08', '2026-01-01', '1a000000-0000-0000-0000-000000000002.pdf', 'x.pdf', 'application/pdf', 1,
             '00000000-0000-0000-0000-00000503a001') $$,
  '23514', null, 'la tabla misma rechaza un papel que vence antes de emitirse');
select throws_ok(
  $$ insert into archivo_empresa (titulo, entidad, fecha_documento, storage_path, nombre_archivo, mime, bytes, subido_por, retirado_at)
     values ('A medias', 'SUNAT', '2026-09-08', '1a000000-0000-0000-0000-000000000002.pdf', 'x.pdf', 'application/pdf', 1,
             '00000000-0000-0000-0000-00000503a001', now()) $$,
  '23514', null, 'y un retiro sin quién ni motivo');
set session_replication_role = origin;

-- ── G · Los archivos en Storage ──────────────────────────────────────────
select is(fn_archivo_libre('1a000000-0000-0000-0000-000000000001.pdf'), false, 'un archivo que usa una ficha no está libre');
select is(fn_archivo_libre('1a000000-0000-0000-0000-000000000009.pdf'), true,  'uno que nadie usa sí');

-- Storage nuevo prohíbe el DELETE directo salvo con esta marca; la política
-- de RLS es lo que se prueba, no ese freno.
select set_config('storage.allow_delete_query', 'true', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b004', true);
set local role authenticated;
select is(
  (select count(*)::int from storage.objects where bucket_id = 'archivo-empresa'),
  0, 'una integrante no ve ningún archivo del bucket');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, metadata)
     values ('archivo-empresa', '1a000000-0000-0000-0000-0000000000aa.pdf', '{"size": 1, "mimetype": "application/pdf"}') $$,
  '42501', null, 'ni sube uno');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b003', true);
set local role authenticated;
select is(
  (select count(*)::int from storage.objects where bucket_id = 'archivo-empresa'),
  0, 'la líder de equipo tampoco');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000503b001', true);
set local role authenticated;
select is(
  (select count(*)::int from storage.objects where bucket_id = 'archivo-empresa'),
  4, 'DO ve los cuatro');
select throws_ok(
  $$ insert into storage.objects (bucket_id, name, metadata)
     values ('archivo-empresa', 'Felipe DNI.pdf', '{"size": 1, "mimetype": "application/pdf"}') $$,
  '42501', null, 'DO no sube un archivo con nombres en la ruta');
delete from storage.objects where bucket_id = 'archivo-empresa' and name = '1a000000-0000-0000-0000-000000000001.pdf';
update storage.objects set metadata = '{"size": 1, "mimetype": "application/pdf"}'
 where bucket_id = 'archivo-empresa' and name = '1a000000-0000-0000-0000-000000000001.pdf';
delete from storage.objects where bucket_id = 'archivo-empresa' and name = '1a000000-0000-0000-0000-000000000009.pdf';
reset role;

select is(
  (select (metadata->>'size')::int from storage.objects where bucket_id = 'archivo-empresa' and name = '1a000000-0000-0000-0000-000000000001.pdf'),
  32768, 'el archivo que usa una ficha no se borró ni se pisó');
select is(
  (select count(*)::int from storage.objects where bucket_id = 'archivo-empresa' and name = '1a000000-0000-0000-0000-000000000009.pdf'),
  0, 'el huérfano sí se pudo limpiar');

select * from finish();
rollback;
