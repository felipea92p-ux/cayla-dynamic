-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 380_las_boletas_oficiales_se_suben_y_se_publican.test.sql — la 0482 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) NADIE ve un archivo que no le toca —ni un borrador, ni una versión vieja,
--     ni la boleta de otra persona—,
-- (b) la constancia de recepción no cae sobre una versión que la persona no vio
--     y no se borra cuando después cambian el documento,
-- (c) si cambió el CONTENIDO de una boleta publicada, avisar es obligatorio
--     aunque DO diga que no,
-- (d) lo que ya es parte de una boleta no se edita, no se pisa y no se borra,
-- (e) anular deja rastro con motivo, y
-- (f) todos los grupos reciben boleta, también quien no tiene cuenta.
-- ============================================================================
begin;
select plan(81);

-- ── Sedes, personas y periodos ───────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000e0001', 'ZZB01', 'Sede boletas', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-0000000ea001', 'AdmBol',  'Lab', '00000000-0000-0000-0000-0000000e0001', 'admin',           'x', '00000000-0000-0000-0000-0000000eb001', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-0000000ea002', 'AnaBol',  'Lab', '00000000-0000-0000-0000-0000000e0001', 'integrante',      'x', '00000000-0000-0000-0000-0000000eb002', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000ea003', 'BeaBol',  'Lab', '00000000-0000-0000-0000-0000000e0001', 'integrante',      'x', '00000000-0000-0000-0000-0000000eb003', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000ea004', 'EncBol',  'Lab', '00000000-0000-0000-0000-0000000e0001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000eb004', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000ea005', 'CamiBol', 'Lab', '00000000-0000-0000-0000-0000000e0001', 'integrante',      'x', '00000000-0000-0000-0000-0000000eb005', '2023-01-01', 'practicante', 'Practicante'),
  ('00000000-0000-0000-0000-0000000ea006', 'JorgeBol','Lab', '00000000-0000-0000-0000-0000000e0001', 'integrante',      'x', null,                                   '2023-01-01', 'planilla', 'Costurero');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, tipo_vinculo, estado) values
  ('00000000-0000-0000-0000-0000000ea007', 'InactBol', 'Lab', '00000000-0000-0000-0000-0000000e0001', 'integrante', 'x', '2023-01-01', 'planilla', 'inactivo');
set session_replication_role = origin;

-- P1 pagado para planilla y practicante; P2 sin ninguna fila de pago (= abierto).
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000ef001', '2019-07-29', '2019-08-28', 'pagado'),
  ('00000000-0000-0000-0000-0000000ef002', '2019-08-29', '2019-09-27', 'abierto');
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at) values
  ('00000000-0000-0000-0000-0000000ef001', 'planilla',    'pagado', now()),
  ('00000000-0000-0000-0000-0000000ef001', 'practicante', 'pagado', now());

-- Rutas de los archivos: <periodo>/<persona>/<uuid>.<ext>
select set_config('t.ana1', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea002/f0000000-0000-0000-0000-000000000001.jpg', true);
select set_config('t.ana2', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea002/f0000000-0000-0000-0000-000000000002.jpg', true);
select set_config('t.ana3', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea002/f0000000-0000-0000-0000-000000000003.jpg', true);
select set_config('t.anapdf', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea002/f0000000-0000-0000-0000-000000000004.pdf', true);
select set_config('t.bea1', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea003/f0000000-0000-0000-0000-000000000005.jpg', true);
select set_config('t.cami1', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea005/f0000000-0000-0000-0000-000000000006.jpg', true);
select set_config('t.gigante1', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea003/f0000000-0000-0000-0000-000000000007.pdf', true);
select set_config('t.gigante2', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea003/f0000000-0000-0000-0000-000000000008.pdf', true);
select set_config('t.huerfano', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea003/f0000000-0000-0000-0000-000000000009.jpg', true);
select set_config('t.faltante', '00000000-0000-0000-0000-0000000ef001/00000000-0000-0000-0000-0000000ea002/f0000000-0000-0000-0000-00000000000a.jpg', true);

-- Lo que Storage guardaría al recibir cada archivo (peso y tipo salen de acá).
insert into storage.objects (bucket_id, name, metadata) values
  ('boletas', current_setting('t.ana1'),     '{"size": 1000, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.ana2'),     '{"size": 2000, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.ana3'),     '{"size": 3000, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.anapdf'),   '{"size": 4000, "mimetype": "application/pdf"}'),
  ('boletas', current_setting('t.bea1'),     '{"size": 1500, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.cami1'),    '{"size": 1200, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.gigante1'), '{"size": 300000000, "mimetype": "application/pdf"}'),
  ('boletas', current_setting('t.gigante2'), '{"size": 300000000, "mimetype": "application/pdf"}'),
  ('boletas', current_setting('t.huerfano'), '{"size": 900, "mimetype": "image/jpeg"}');

-- ── A · El bucket y los permisos ─────────────────────────────────────────
select is(
  (select count(*)::int from storage.buckets where id = 'boletas' and public is false and file_size_limit = 52428800),
  1, 'el bucket existe, es privado y limita a 50 MB por archivo');

select is(
  (select count(*)::int from pg_policies where schemaname = 'storage' and policyname like 'boletas\_%'),
  4, 'Storage tiene sus cuatro políticas (insert, select, update, delete)');

select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('fn_boleta_guardar_version','fn_boletas_publicar','fn_boleta_anular','fn_boleta_marcar_papel',
                           'fn_boletas_tablero','fn_boleta_versiones','fn_boleta_partes','fn_boleta_confirmar_recibo',
                           'fn_mis_boletas','fn_boleta_puede_ver','fn_boleta_archivo_libre')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'ninguna función de boletas le responde a quien no inició sesión');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proname in ('fn_boleta_guardar_version','fn_boletas_publicar','fn_boleta_anular','fn_boleta_marcar_papel',
                        'fn_boletas_tablero','fn_boleta_versiones','fn_boleta_partes','fn_boleta_confirmar_recibo',
                        'fn_mis_boletas','fn_boleta_puede_ver','fn_boleta_archivo_libre')),
  11, 'y las once las puede llamar quien sí inició sesión (un grant faltante fallaría en silencio)');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
set local role authenticated;
select throws_ok($$ insert into boletas (periodo_id, persona_id, creada_por) values ('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','00000000-0000-0000-0000-0000000ea002') $$,
  '42501', null, 'nadie inserta una boleta a mano: solo por las funciones');
select throws_ok($$ update boletas set estado = 'publicada' $$, '42501', null, 'ni actualiza una boleta a mano');
select throws_ok($$ insert into boletas_acuses (version_id, vista_at) values (gen_random_uuid(), now()) $$,
  '42501', null, 'ni escribe un acuse a mano');
select throws_ok($$ truncate boletas_versiones $$, '42501', null, 'ni vacía las versiones (truncate no pasa por RLS: lo detiene el permiso)');
reset role;

-- ── B · Quién puede subir, y qué se rechaza ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1')))) $$,
  'P0001', 'Solo Desarrollo Organizacional puede subir boletas.', 'una integrante no sube boletas');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb004', true);
select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1')))) $$,
  'P0001', 'Solo Desarrollo Organizacional puede subir boletas.', 'ni la líder de equipo: es plata de otras personas');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);
select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef002','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1')))) $$,
  'P0001', 'Ese periodo todavía no está pagado para el grupo de esa persona: la boleta oficial se sube cuando cierra.',
  'un periodo no pagado no admite boleta oficial');

select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen','[]'::jsonb) $$,
  'P0001', 'Agrega al menos una foto o un PDF.', 'sin hojas no hay boleta');

select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.bea1')))) $$,
  'P0001', 'Una de las hojas no corresponde a esta persona y periodo.', 'la hoja de OTRA persona no entra en esta boleta');

select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.faltante')))) $$,
  'P0001', 'Una de las hojas no llegó al almacén. Vuelve a subirla.', 'una ruta que no existe en Storage no entra (el archivo va primero)');

select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1')), jsonb_build_object('path', current_setting('t.ana1')))) $$,
  'P0001', 'Hay una hoja repetida.', 'una hoja repetida se rechaza');

select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','pdf',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1')))) $$,
  'P0001', 'Todas las hojas de una boleta tienen que ser del mismo tipo (fotos o PDF).', 'un JPG no pasa por PDF');

select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea003','pdf',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.gigante1')), jsonb_build_object('path', current_setting('t.gigante2')))) $$,
  'P0001', 'La boleta pasa el tope de 500 MB. Quita alguna hoja.', 'dos PDF de 300 MB pasan el tope de 500 MB por boleta');

select is((select count(*)::int from boletas), 0,
  'y ninguna de esas subidas fallidas dejó una boleta a medias');

-- ── C · Subir, que la persona no lo vea, publicar ────────────────────────
select is(
  (select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1')))) is not null),
  true, 'DO sube la boleta de Ana');

select is(
  (select estado from boletas where persona_id = '00000000-0000-0000-0000-0000000ea002'),
  'borrador', 'queda como borrador');

-- El id de la versión 1 de Ana, fijado ahora que es la única: después habrá otras versiones 1.
select set_config('t.v1', (select id::text from boletas_versiones where n = 1), true);

select is(
  (select bytes from boletas_partes where storage_path = current_setting('t.ana1')),
  1000::bigint, 'el peso sale de Storage (1000), no de lo que diga el navegador');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select is(
  (select estado from fn_mis_boletas() where periodo_id = '00000000-0000-0000-0000-0000000ef001'),
  null, 'Ana ve el periodo pagado como «aún no publicada»: el borrador no se le muestra');

set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'boletas' and name = current_setting('t.ana1')),
  0, 'y su archivo tampoco: mientras es borrador, ni su dueña lo abre');
reset role;

select throws_ok(
  $$ select * from fn_boleta_partes(current_setting('t.v1')::uuid) $$,
  'P0001', 'Esa boleta no está disponible.', 'ni por la función');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);
select is((select fn_boletas_publicar('00000000-0000-0000-0000-0000000ef001')), 1, 'DO publica: una boleta');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select is(
  (select estado || ' · vista=' || coalesce(vista_at::text, 'nunca') from fn_mis_boletas() where periodo_id = '00000000-0000-0000-0000-0000000ef001'),
  'publicada · vista=nunca', 'ahora Ana la ve publicada y todavía sin abrir');

set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'boletas' and name = current_setting('t.ana1')),
  1, 'y su archivo ya se abre');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb003', true);
set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'boletas'),
  0, 'Bea no abre ningún archivo de Ana');
reset role;

-- ── D · Primera apertura y confirmación, por versión ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select is((select count(*)::int from fn_boleta_partes(current_setting('t.v1')::uuid)),
  1, 'Ana pide las hojas de su boleta y le llega 1');

select is((select vista_at is not null from boletas_acuses), true, 'quedó escrita la primera apertura');

-- Envejecer la marca a mano (el trigger la protege, hay que apagarlo un momento):
-- sin esto la prueba pasaría aunque la función corriera la fecha a now().
alter table boletas_acuses disable trigger boletas_acuses_guardian;
update boletas_acuses set vista_at = '2020-01-01 00:00:00+00';
alter table boletas_acuses enable trigger boletas_acuses_guardian;

select lives_ok($$ select * from fn_boleta_partes(current_setting('t.v1')::uuid) $$,
  'abrirla otra vez no falla');
select is((select vista_at from boletas_acuses), '2020-01-01 00:00:00+00'::timestamptz,
  'y no corre la fecha de la primera apertura');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb003', true);
select throws_ok($$ select fn_boleta_confirmar_recibo(current_setting('t.v1')::uuid) $$,
  'P0001', 'Esa boleta no es tuya.', 'Bea no confirma la boleta de Ana');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select lives_ok($$ select fn_boleta_confirmar_recibo(current_setting('t.v1')::uuid) $$,
  'Ana confirma que la recibió');
select is((select recibida_at is not null from boletas_acuses), true, 'queda escrita la confirmación');
select lives_ok($$ select fn_boleta_confirmar_recibo(current_setting('t.v1')::uuid) $$,
  'confirmar dos veces no falla');

select throws_ok($$ update boletas_acuses set recibida_at = '2001-01-01' $$,
  'P0001', 'La fecha de la confirmación no se corre.', 'ni siquiera desde dentro se corre la fecha de la confirmación');
select throws_ok($$ delete from boletas_acuses $$,
  'P0001', 'Una confirmación de recepción no se borra.', 'y no se borra');

-- DO mirando la boleta de otra persona NO marca nada como recibido/abierto.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);
select is(
  (select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea003','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.bea1')))) is not null),
  true, 'DO sube la boleta de Bea');
select is((select count(*)::int from fn_boleta_partes((select v.id from boletas_versiones v join boletas b on b.id = v.boleta_id where b.persona_id = '00000000-0000-0000-0000-0000000ea003'))),
  1, 'DO abre la hoja de Bea para revisarla');
select is((select count(*)::int from boletas_acuses a join boletas_versiones v on v.id = a.version_id join boletas b on b.id = v.boleta_id
            where b.persona_id = '00000000-0000-0000-0000-0000000ea003'),
  0, 'y eso no cuenta como que Bea la abrió');

-- ── E · Editar = versión nueva; el aviso lo manda el contenido ───────────
-- Sumar una hoja: cambió el contenido, se avisa SIEMPRE aunque DO pida que no.
select is(
  (select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1')), jsonb_build_object('path', current_setting('t.ana2'))),
       false, null) is not null),
  true, 'DO agrega una segunda hoja a una boleta publicada, pidiendo NO avisar');
select is((select avisar from boletas_versiones where n = 2), true,
  'pero el contenido cambió: se avisa igual (la regla vive en la base, no en la pantalla)');
select is((select count(*)::int from boletas_acuses), 1,
  'la constancia de la versión 1 sigue ahí, y la 2 empieza sin acuse');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select throws_ok($$ select fn_boleta_confirmar_recibo(current_setting('t.v1')::uuid) $$,
  'P0001', 'Tu boleta se actualizó: ábrela de nuevo antes de confirmar.',
  'confirmar la versión que ya no es la vigente se rechaza: el «recibí» no cae sobre lo que no vio');
select is(
  (select version_n::text || ' · vista=' || coalesce(vista_at::text, 'nunca') || ' · recibida=' || coalesce(recibida_at::text, 'nunca')
     from fn_mis_boletas() where periodo_id = '00000000-0000-0000-0000-0000000ef001'),
  '2 · vista=nunca · recibida=nunca', 'Ana ve la versión 2, limpia');

-- Solo reordenar: con «no avisar» se conserva la constancia.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select lives_ok($$ select fn_boleta_confirmar_recibo(
    (select v.id from boletas_versiones v join boletas b on b.id = v.boleta_id
      where b.persona_id = '00000000-0000-0000-0000-0000000ea002' and v.n = 2)) $$,
  'Ana confirma la versión 2');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);
select lives_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana2')), jsonb_build_object('path', current_setting('t.ana1'))),
       false, 'solo reordené') $$,
  'DO solo reordena las hojas y elige no avisar');
select is((select avisar from boletas_versiones where n = 3), false, 'la versión 3 quedó sin aviso');
select is(
  (select count(*)::int from boletas_acuses a join boletas_versiones v on v.id = a.version_id
    where v.n = 3 and a.recibida_at is not null),
  1, 'y hereda la confirmación: el contenido es el mismo');

select throws_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana2')), jsonb_build_object('path', current_setting('t.ana1')))) $$,
  'P0001', 'No hiciste ningún cambio: agrega, quita o reordena alguna hoja.', 'guardar sin cambios se rechaza');

-- Quitar una hoja: contenido distinto, versión 4; la hoja quitada deja de abrirse.
select lives_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana2')))) $$,
  'DO quita la primera hoja');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'boletas' and name = current_setting('t.ana1')),
  0, 'la hoja que ya no está en la versión vigente deja de abrirse para Ana');
select is((select count(*)::int from storage.objects where bucket_id = 'boletas' and name = current_setting('t.ana2')),
  1, 'y la que se conserva sigue abriéndose (el mismo archivo sirve a varias versiones)');
reset role;

-- ── F · Lo que ya es parte de una boleta no se toca ──────────────────────
select throws_ok($$ update boletas_versiones set nota = 'x' $$, 'P0001', null, 'una versión no se edita, ni siquiera desde dentro');
select throws_ok($$ delete from boletas_partes $$, 'P0001', null, 'una hoja no se borra');

-- Un archivo que una versión ya usa no se pisa ni se borra; uno que nadie usa
-- sí se puede limpiar. Se comprueba con `update` y con la función que decide
-- ambas cosas, y NO con un `delete`: Supabase puede rechazar un `delete` directo
-- sobre storage.objects (solo lo permite la API de Storage), y esta prueba tiene
-- que medir NUESTRA política, no ese freno.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);
select is((select fn_boleta_archivo_libre(current_setting('t.ana2'))), false, 'un archivo que una versión usa NO está libre');
select is((select fn_boleta_archivo_libre(current_setting('t.huerfano'))), true, 'y uno que nadie usa sí');

set local role authenticated;
update storage.objects set metadata = '{"size": 1, "mimetype": "image/jpeg"}'::jsonb
 where bucket_id = 'boletas' and name = current_setting('t.ana2');
reset role;
select is((select metadata->>'size' from storage.objects where bucket_id = 'boletas' and name = current_setting('t.ana2')),
  '2000', 'DO no puede pisar un archivo que una versión ya usa (el peso registrado no cambió)');

set local role authenticated;
update storage.objects set metadata = '{"size": 901, "mimetype": "image/jpeg"}'::jsonb
 where bucket_id = 'boletas' and name = current_setting('t.huerfano');
reset role;
select is((select metadata->>'size' from storage.objects where bucket_id = 'boletas' and name = current_setting('t.huerfano')),
  '901', 'pero sí puede reemplazar uno huérfano');

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'storage' and policyname = 'boletas_delete' and qual like '%fn_boleta_archivo_libre%'),
  1, 'y la política de borrado exige que el archivo esté libre');

-- ── G · Anular deja rastro con motivo ────────────────────────────────────
select throws_ok(
  $$ select fn_boleta_anular((select id from boletas where persona_id = '00000000-0000-0000-0000-0000000ea002'), 'no') $$,
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado junto a la boleta.', 'anular sin motivo se rechaza');
select lives_ok(
  $$ select fn_boleta_anular((select id from boletas where persona_id = '00000000-0000-0000-0000-0000000ea002'), 'se subió la boleta de otra persona') $$,
  'DO anula con motivo');
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-0000000ea002' and campo_modificado = 'boletas.estado' and valor_nuevo = 'anulada'),
  1, 'y queda en la auditoría');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select is((select estado from fn_mis_boletas() where periodo_id = '00000000-0000-0000-0000-0000000ef001'), null,
  'Ana deja de verla');
set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'boletas'), 0, 'y de abrir sus archivos');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);
select lives_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.ana3')))) $$,
  'subir de nuevo después de anular es posible');
select is((select estado from boletas where persona_id = '00000000-0000-0000-0000-0000000ea002'), 'borrador',
  'y arranca otra vez como borrador');

-- ── H · Todos los grupos reciben boleta, también quien no tiene cuenta ────
select lives_ok(
  $$ select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea005','imagen',
       jsonb_build_array(jsonb_build_object('path', current_setting('t.cami1')))) $$,
  'una practicante también tiene boleta');
select is((select fn_boletas_publicar('00000000-0000-0000-0000-0000000ef001', array['00000000-0000-0000-0000-0000000ea005'::uuid])), 1,
  'y DO puede publicar solo a algunas personas');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb005', true);
select is((select estado from fn_mis_boletas() where periodo_id = '00000000-0000-0000-0000-0000000ef001'), 'publicada',
  'la practicante la ve');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);
select lives_ok($$ select fn_boleta_marcar_papel('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea006') $$,
  'DO anota la entrega en papel de quien no tiene cuenta');
select throws_ok($$ select fn_boleta_marcar_papel('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea006') $$,
  'P0001', 'Esa persona ya tiene boleta en este periodo.', 'no se anota dos veces');

-- ── I · El tablero de DO ─────────────────────────────────────────────────
select is((select count(*)::int from fn_boletas_tablero('00000000-0000-0000-0000-0000000ef001') where nombre like '%Bol Lab'), 6,
  'el tablero lista a las 6 personas activas (la inactiva sin boleta no sale)');
select is((select tiene_cuenta from fn_boletas_tablero('00000000-0000-0000-0000-0000000ef001') where nombre like 'JorgeBol%'), false,
  'y dice quién no tiene cuenta');
select is((select estado from fn_boletas_tablero('00000000-0000-0000-0000-0000000ef001') where nombre like 'JorgeBol%'), 'papel',
  'con su entrega en papel');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);
select throws_ok($$ select * from fn_boletas_tablero('00000000-0000-0000-0000-0000000ef001') $$,
  'P0001', 'Solo Desarrollo Organizacional ve las boletas de todos.', 'una integrante no ve el tablero');

-- ── J · Los estados imposibles ───────────────────────────────────────────
select throws_ok(
  $$ insert into boletas (periodo_id, persona_id, creada_por) values ('00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-0000000ea002','00000000-0000-0000-0000-0000000ea001') $$,
  '23505', null, 'dos boletas de la misma persona y periodo no existen');
select throws_ok(
  $$ update boletas set estado = 'anulada', anulada_at = now(), anulada_por = '00000000-0000-0000-0000-0000000ea001', anulada_motivo = 'ab'
      where persona_id = '00000000-0000-0000-0000-0000000ea002' $$,
  '23514', null, 'una boleta anulada sin motivo de verdad no existe');
select throws_ok(
  $$ insert into boletas_partes (version_id, tipo, orden, storage_path, mime, bytes)
     select v.id, 'imagen', 99, current_setting('t.ana1'), 'application/pdf', 10 from boletas_versiones v limit 1 $$,
  '23514', null, 'una hoja PDF dentro de una versión de fotos no existe');
select throws_ok(
  $$ insert into boletas_partes (version_id, tipo, orden, storage_path, mime, bytes)
     select v.id, 'imagen', 98, 'ruta-sin-forma', 'image/jpeg', 10 from boletas_versiones v limit 1 $$,
  '23514', null, 'una ruta sin la forma <periodo>/<persona>/<archivo> no entra');

select * from finish();
rollback;
