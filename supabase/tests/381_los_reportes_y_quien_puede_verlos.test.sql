-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 381_los_reportes_y_quien_puede_verlos.test.sql
-- ============================================================================
-- Cubre la migración 0483: quién puede leer cada reporte. Es la prueba que más
-- vale de toda la funcionalidad (docs/plan-reportes.md, sección 16), porque un
-- error aquí no se ve en pantalla: se ve cuando la persona equivocada lee lo
-- que alguien contó de ella.
--
-- Recorre CADA celda de las dos tablas de la sección 7 del plan, mirando la
-- RLS tal como la ve cada persona con su sesión:
--   (a) reclamo y convivencia, según el nivel de la persona reportada;
--   (b) Título X: DO, la Gerencia General solo contra DO, una sola
--       investigadora, y la líder nunca;
--   (c) la mención excluye, sea involucrada o testigo;
--   (d) quien escribió ve pero no gestiona; las notas internas no son suyas;
--   (e) la líder ve la instrucción de una medida y nada más del caso;
--   (f) el bucket sigue la misma regla, y la evidencia registrada no se pisa;
--   (g) la foto: ascender a alguien no cambia quién ve un reporte viejo;
--   (h) lo que no se edita ni se borra, y lo que un cliente no escribe;
--   (i) la marca de Gerencia General no la cambia un admin por su cuenta;
--   (j) «quién lo va a leer», incluidos los dos casos sin nadie que reciba:
--       sin marca de Gerencia General y con la única `lider_do` inactiva.
--
-- Simulamos sesiones con set_config('request.jwt.claim.sub', ...) y
-- `set local role authenticated`, como la 380. Todo dentro de begin/rollback.
-- ============================================================================
begin;
select plan(70);

-- ── Semilla ──────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000c5001', 'ZZR01', 'Sede reportes 1', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000c5002', 'ZZR02', 'Sede reportes 2', true, 'tienda');

set session_replication_role = replica;
-- La regla mira a TODAS las personas activas con rol de panel. Para que «quién
-- lo va a leer» no dependa de quién más haya en la base, las demás dejan de
-- tener rol de panel mientras dure la prueba (se revierte con el rollback).
update personas set rol = 'integrante'
 where rol in ('supervisor_sede', 'lider_do', 'admin');
delete from configuracion where clave = 'gerencia_general';

insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-0000000c0001', 'Ana',   'Rep', '00000000-0000-0000-0000-0000000c5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000d0001', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000c0002', 'Bea',   'Rep', '00000000-0000-0000-0000-0000000c5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000d0002', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000c0003', 'Lia',   'Rep', '00000000-0000-0000-0000-0000000c5001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000d0003', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000c0004', 'Lea',   'Rep', '00000000-0000-0000-0000-0000000c5002', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000d0004', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000c0005', 'Dora',  'Rep', '00000000-0000-0000-0000-0000000c5001', 'lider_do',        'x', '00000000-0000-0000-0000-0000000d0005', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-0000000c0006', 'Gabi',  'Rep', '00000000-0000-0000-0000-0000000c5001', 'admin',           'x', '00000000-0000-0000-0000-0000000d0006', '2023-01-01', 'planilla', 'Gerencia General'),
  ('00000000-0000-0000-0000-0000000c0007', 'Otto',  'Rep', '00000000-0000-0000-0000-0000000c5001', 'admin',           'x', '00000000-0000-0000-0000-0000000d0007', '2023-01-01', 'planilla', 'Administración'),
  ('00000000-0000-0000-0000-0000000c0008', 'Dele',  'Rep', '00000000-0000-0000-0000-0000000c5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000d0008', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000c0009', 'Supa',  'Rep', '00000000-0000-0000-0000-0000000c5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000d0009', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000c0010', 'Carla', 'Rep', '00000000-0000-0000-0000-0000000c5001', 'integrante',      'x', '00000000-0000-0000-0000-0000000d0010', '2023-01-01', 'planilla', 'Vendedora');
set session_replication_role = origin;

-- Gabi es la Gerencia General; Otto es admin y NO lo es. Como postgres, el
-- trigger lo deja pasar: es lo que haría el SQL Editor.
insert into configuracion (clave, valor, descripcion)
values ('gerencia_general', jsonb_build_object('persona_id', '00000000-0000-0000-0000-0000000c0006'::uuid), 'prueba');

-- Dele es la Delegada de la sede 1; Supa, su suplente.
insert into organos_titulo_x (sede_id, persona_id, papel, desde) values
  ('00000000-0000-0000-0000-0000000c5001', '00000000-0000-0000-0000-0000000c0008', 'delegada', '2026-01-01'),
  ('00000000-0000-0000-0000-0000000c5001', '00000000-0000-0000-0000-0000000c0009', 'suplente', '2026-01-01');

-- Once reportes, uno por fila de las tablas del plan. Ana escribe todos salvo
-- el ZT06, que lo escribe Lia sobre la empresa.
insert into reportes (id, codigo, autor_id, sede_id, tipo, via, fecha_hecho, relato) values
  ('00000000-0000-0000-0000-0000000c7001', 'ZT01', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'convivencia', '2026-09-20', 'sobre una colaboradora'),
  ('00000000-0000-0000-0000-0000000c7002', 'ZT02', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'convivencia', '2026-09-20', 'sobre la líder'),
  ('00000000-0000-0000-0000-0000000c7003', 'ZT03', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'convivencia', '2026-09-20', 'sobre DO'),
  ('00000000-0000-0000-0000-0000000c7004', 'ZT04', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'convivencia', '2026-09-20', 'sobre la Gerencia General'),
  ('00000000-0000-0000-0000-0000000c7005', 'ZT05', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'convivencia', '2026-09-20', 'sobre otro admin'),
  ('00000000-0000-0000-0000-0000000c7006', 'ZT06', '00000000-0000-0000-0000-0000000c0003', '00000000-0000-0000-0000-0000000c5001', 'empresa', 'reclamo',     '2026-09-20', 'la líder reclama sobre la empresa'),
  ('00000000-0000-0000-0000-0000000c7007', 'ZT07', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'reclamo',     '2026-09-20', 'la líder es testigo'),
  ('00000000-0000-0000-0000-0000000c7008', 'ZT08', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'titulo_x',    '2026-09-20', 'Título X sobre una colaboradora'),
  ('00000000-0000-0000-0000-0000000c7009', 'ZT09', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'titulo_x',    '2026-09-20', 'Título X sobre la Delegada'),
  ('00000000-0000-0000-0000-0000000c7010', 'ZT10', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'titulo_x',    '2026-09-20', 'Título X sobre DO'),
  ('00000000-0000-0000-0000-0000000c7011', 'ZT11', '00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'persona', 'titulo_x',    '2026-09-20', 'Título X sobre la Gerencia General');

insert into reporte_personas (reporte_id, persona_id, papel) values
  ('00000000-0000-0000-0000-0000000c7001', '00000000-0000-0000-0000-0000000c0002', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7002', '00000000-0000-0000-0000-0000000c0003', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7003', '00000000-0000-0000-0000-0000000c0005', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7004', '00000000-0000-0000-0000-0000000c0006', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7005', '00000000-0000-0000-0000-0000000c0007', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7007', '00000000-0000-0000-0000-0000000c0002', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7007', '00000000-0000-0000-0000-0000000c0003', 'testigo'),
  ('00000000-0000-0000-0000-0000000c7008', '00000000-0000-0000-0000-0000000c0002', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7009', '00000000-0000-0000-0000-0000000c0008', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7010', '00000000-0000-0000-0000-0000000c0005', 'involucrada'),
  ('00000000-0000-0000-0000-0000000c7011', '00000000-0000-0000-0000-0000000c0006', 'involucrada');

-- Un hilo con una nota interna, un evento, una medida y archivos.
insert into reporte_mensajes (reporte_id, autor_id, texto, interno) values
  ('00000000-0000-0000-0000-0000000c7001', '00000000-0000-0000-0000-0000000c0003', '¿Cuándo pasó exactamente?', false),
  ('00000000-0000-0000-0000-0000000c7001', '00000000-0000-0000-0000-0000000c0003', 'Nota: hablar primero con Bea.', true),
  ('00000000-0000-0000-0000-0000000c7008', '00000000-0000-0000-0000-0000000c0005', 'Mensaje del Título X', false);
insert into reporte_eventos (reporte_id, tipo, por, detalle) values
  ('00000000-0000-0000-0000-0000000c7001', 'accion', '00000000-0000-0000-0000-0000000c0003', '{"accion": "mediacion"}');
insert into reporte_medidas (reporte_id, para_persona_id, instruccion, creada_por) values
  ('00000000-0000-0000-0000-0000000c7008', '00000000-0000-0000-0000-0000000c0003',
   'Desde mañana, Bea pasa al turno tarde hasta nuevo aviso.', '00000000-0000-0000-0000-0000000c0005');

select set_config('t.f1', '00000000-0000-0000-0000-0000000c7001/f0000000-0000-0000-0000-0000000000a1.jpg', true);
select set_config('t.f2', '00000000-0000-0000-0000-0000000c7001/f0000000-0000-0000-0000-0000000000a2.pdf', true);
select set_config('t.f3', '00000000-0000-0000-0000-0000000c7008/f0000000-0000-0000-0000-0000000000a3.jpg', true);
insert into storage.objects (bucket_id, name, metadata) values
  ('reportes', current_setting('t.f1'), '{"size": 1000, "mimetype": "image/jpeg"}'),
  ('reportes', current_setting('t.f2'), '{"size": 2000, "mimetype": "application/pdf"}'),
  ('reportes', current_setting('t.f3'), '{"size": 3000, "mimetype": "image/jpeg"}');
-- f2 ya es evidencia registrada, y es interna (la subió quien gestiona).
insert into reporte_adjuntos (reporte_id, storage_path, subido_por, interno) values
  ('00000000-0000-0000-0000-0000000c7001', current_setting('t.f2'), '00000000-0000-0000-0000-0000000c0003', true);


-- ── (a)(b)(c)(d) Qué reportes ve cada persona, por RLS ──────────────────────
-- Una lista por persona: cada fallo dice exactamente qué reporte sobra o falta.

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0001', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes),
  'ZT01,ZT02,ZT03,ZT04,ZT05,ZT07,ZT08,ZT09,ZT10,ZT11',
  'Ana ve todo lo que ella escribió, y nada más');
select is(fn_reporte_puede_gestionar('00000000-0000-0000-0000-0000000c7001'), false,
  'pero no gestiona lo que escribió');
select is((select count(*)::int from reporte_mensajes where reporte_id = '00000000-0000-0000-0000-0000000c7001'), 1,
  'Ana ve la pregunta del hilo, no la nota interna');
select is((select count(*)::int from reporte_eventos), 0,
  'Ana no ve la línea de tiempo');
select is((select count(*)::int from storage.objects where bucket_id = 'reportes'), 2,
  'Ana abre los archivos de sus reportes, salvo el interno');
select is(fn_reporte_puede_ver_archivo('basura/sin-forma.jpg'), false,
  'una ruta mal formada no abre nada (y no revienta)');
select throws_ok($$ select fn_reporte_acceso(null, null, 'reclamo', null, 0::smallint, false, '{}') $$,
  '42501', null, 'la regla desnuda no la llama un cliente: respondería sobre cualquiera');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0002', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes), '',
  'Bea, la reportada, no ve ninguno de los tres que la mencionan');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0003', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes), 'ZT01,ZT06',
  'Lia (líder de la sede 1) gestiona el que es sobre una colaboradora, y ve el suyo; nada sobre ella, de nivel superior, donde es testigo ni del Título X');
select is(fn_reporte_puede_gestionar('00000000-0000-0000-0000-0000000c7001'), true,
  'Lia gestiona el ZT01');
select is(fn_reporte_puede_gestionar('00000000-0000-0000-0000-0000000c7006'), false,
  'Lia no gestiona su propio reclamo: nadie resuelve su propio caso');
select is((select count(*)::int from reporte_mensajes where reporte_id = '00000000-0000-0000-0000-0000000c7001'), 2,
  'Lia ve el hilo completo, con la nota interna');
select is((select count(*)::int from reporte_eventos), 1,
  'Lia ve la línea de tiempo del caso que gestiona');
select is((select count(*)::int from reporte_medidas), 1,
  'Lia ve la instrucción de la medida del Título X…');
select is((select count(*)::int from reporte_mensajes where reporte_id = '00000000-0000-0000-0000-0000000c7008'), 0,
  '…pero ni el hilo de ese caso…');
select is((select count(*)::int from reporte_personas where reporte_id = '00000000-0000-0000-0000-0000000c7008'), 0,
  '…ni a quién menciona');
select is((select count(*)::int from storage.objects where bucket_id = 'reportes'), 2,
  'Lia abre los dos archivos del ZT01 y ninguno del Título X');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0004', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes), '',
  'Lea, líder de OTRA sede, no ve nada de la sede 1');
select is((select count(*)::int from storage.objects where bucket_id = 'reportes'), 0,
  'ni abre sus archivos');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0005', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes),
  'ZT01,ZT02,ZT04,ZT05,ZT06,ZT07,ZT08,ZT09,ZT11',
  'Dora (DO) ve todo salvo lo que la menciona: incluso lo que es sobre la Gerencia General (48.2-bis)');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0006', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes),
  'ZT01,ZT02,ZT03,ZT05,ZT06,ZT07,ZT10',
  'Gabi (Gerencia General) ve reclamos y convivencia salvo el suyo, y del Título X solo el que es contra DO (48.2)');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0007', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes), '',
  'Otto tiene rol admin pero no es la Gerencia General: no ve ningún reporte');
select is((select count(*)::int from storage.objects where bucket_id = 'reportes'), 0,
  'ni ningún archivo');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0008', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes), 'ZT08,ZT10,ZT11',
  'Dele (Delegada) investiga el Título X de su sede, salvo la queja sobre ella');
select is((select count(*)::int from storage.objects where bucket_id = 'reportes'), 1,
  'y abre el archivo del caso que investiga');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0009', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes), 'ZT09',
  'Supa (suplente) investiga solo cuando la Delegada está mencionada: una sola investigadora por caso');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0010', true);
set local role authenticated;
select is((select coalesce(string_agg(codigo, ',' order by codigo), '') from reportes), '',
  'Carla, sin rol de panel y sin reportes propios, no ve nada');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
set local role authenticated;
select is((select count(*)::int from reportes), 0,
  'una sesión sin ficha enlazada no ve nada');
reset role;


-- ── Los niveles, calculados desde la foto ───────────────────────────────────
select is((select string_agg(codigo || '=' || nivel, ',' order by codigo) from reportes),
  'ZT01=0,ZT02=1,ZT03=2,ZT04=3,ZT05=2,ZT06=0,ZT07=0,ZT08=0,ZT09=0,ZT10=2,ZT11=3',
  'el nivel de cada reporte es el máximo de sus involucradas; la testigo del ZT07 no lo sube');
select is((select rol::text from reporte_personas
            where reporte_id = '00000000-0000-0000-0000-0000000c7005'
              and persona_id = '00000000-0000-0000-0000-0000000c0007'),
  'admin', 'la foto guarda el rol de la persona mencionada');


-- ── (f) La evidencia registrada no se pisa ──────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0003', true);
set local role authenticated;
update storage.objects set metadata = '{"size": 1, "mimetype": "image/jpeg"}'
 where bucket_id = 'reportes' and name = current_setting('t.f2');
update storage.objects set metadata = '{"size": 1, "mimetype": "image/jpeg"}'
 where bucket_id = 'reportes' and name = current_setting('t.f1');
reset role;
select is((select (metadata ->> 'size')::int from storage.objects where name = current_setting('t.f2')), 2000,
  'un archivo ya registrado como evidencia no se pisa, ni siquiera quien gestiona');
select is((select (metadata ->> 'size')::int from storage.objects where name = current_setting('t.f1')), 1,
  'uno todavía libre sí (es la subida a medio camino)');


-- ── (h) Lo que no se edita ni se borra ──────────────────────────────────────
select throws_like($$ update reportes set nivel = 0 where codigo = 'ZT02' $$,
  '%no baja%', 'el nivel de un reporte no baja');
select throws_like($$ update reportes set relato = 'otra cosa' where codigo = 'ZT01' $$,
  '%no se reescribe%', 'lo que se reportó no se reescribe');
select throws_like($$ update reportes set autor_id = '00000000-0000-0000-0000-0000000c0010' where codigo = 'ZT01' $$,
  '%no se reescribe%', 'ni cambia de autora');
select throws_like($$ delete from reportes where codigo = 'ZT01' $$,
  '%no se borra%', 'un reporte no se borra');
select throws_like($$ update reporte_mensajes set texto = 'editado' $$,
  '%solo se agrega%', 'un mensaje no se edita');
select throws_like($$ delete from reporte_personas where reporte_id = '00000000-0000-0000-0000-0000000c7001' $$,
  '%solo se agrega%', 'una mención no se borra (bajaría el nivel por la puerta de atrás)');
select throws_like($$ delete from reporte_eventos $$,
  '%solo se agrega%', 'el rastro no se borra');
select throws_like($$ update reporte_adjuntos set interno = false $$,
  '%solo se agrega%', 'un adjunto registrado no cambia');

update reportes set estado = 'cerrado', cerrado_at = now(), cierre_resultado = 'resuelto',
                    cierre_texto = 'Se conversó y se ajustó el proceso.'
 where codigo = 'ZT06';
select throws_like($$ update reportes set estado = 'en_revision', cerrado_at = null where codigo = 'ZT06' $$,
  '%no se reabre%', 'un reporte cerrado no se reabre');
select throws_like($$ update reportes set estado = 'cerrado', cerrado_at = now() where codigo = 'ZT05' $$,
  '%chk_reporte_cierre_completo%', 'no se cierra sin resultado ni respuesta escrita');
select throws_like($$ insert into reportes (autor_id, sede_id, tipo, via, fecha_hecho, relato, ticket)
                      values ('00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001',
                              'empresa', 'reclamo', '2026-09-20', 'x', 'T-123') $$,
  '%chk_reporte_ticket_solo_clienta%', 'el número de ticket solo va en reportes sobre una clienta');

insert into reportes (autor_id, sede_id, tipo, via, fecha_hecho, relato)
values ('00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-0000000c5001', 'idea', 'reclamo', '2026-09-20', 'una idea');
select ok((select codigo ~ '^R-[0-9]{4}-[0-9]{4,}$' from reportes where relato = 'una idea'),
  'el código nace solo, legible, sin nombrar a nadie');

-- Un cliente no escribe nada directo: todo entra por funciones (paso 2).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0005', true);
set local role authenticated;
select throws_ok($$ insert into reportes (autor_id, sede_id, tipo, via, fecha_hecho, relato)
                    values ('00000000-0000-0000-0000-0000000c0005', '00000000-0000-0000-0000-0000000c5001', 'idea', 'reclamo', '2026-09-20', 'x') $$,
  '42501', null, 'ni DO inserta un reporte a mano');
select throws_ok($$ update reportes set estado = 'en_revision' where codigo = 'ZT01' $$,
  '42501', null, 'ni lo actualiza a mano');
select throws_ok($$ insert into reporte_mensajes (reporte_id, autor_id, texto)
                    values ('00000000-0000-0000-0000-0000000c7001', '00000000-0000-0000-0000-0000000c0005', 'x') $$,
  '42501', null, 'ni escribe en el hilo a mano');
select throws_ok($$ insert into organos_titulo_x (sede_id, persona_id, papel, desde)
                    values ('00000000-0000-0000-0000-0000000c5001', '00000000-0000-0000-0000-0000000c0005', 'designada', '2026-01-01') $$,
  '42501', null, 'ni se nombra investigadora a sí misma');
select is((select count(*)::int from organos_titulo_x where sede_id = '00000000-0000-0000-0000-0000000c5001'), 2,
  'pero sí puede leer quién investiga en cada sede (48.6: es información publicada)');
reset role;


-- ── (i) La marca de Gerencia General ────────────────────────────────────────
select is(fn_gerencia_general_id(), '00000000-0000-0000-0000-0000000c0006'::uuid,
  'la Gerencia General es la persona marcada, no cualquier admin');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0007', true);
set local role authenticated;
select throws_like(
  $$ update configuracion set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-0000000c0007'::uuid)
      where clave = 'gerencia_general' $$,
  '%SQL Editor%', 'Otto, admin, no puede marcarse como Gerencia General aunque la RLS le deje escribir configuracion');
select throws_like($$ delete from configuracion where clave = 'gerencia_general' $$,
  '%SQL Editor%', 'ni borrar la marca');
reset role;

select throws_like(
  $$ update configuracion set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-0000000c0010'::uuid)
      where clave = 'gerencia_general' $$,
  '%rol admin%', 'ni desde el SQL Editor se marca a alguien sin rol admin');
select throws_like(
  $$ update configuracion set valor = jsonb_build_object('persona_id', gen_random_uuid()) where clave = 'gerencia_general' $$,
  '%no existe%', 'ni a alguien que no existe');
select throws_like(
  $$ update configuracion set valor = '{"persona_id": "no-es-un-uuid"}' where clave = 'gerencia_general' $$,
  '%identificador%', 'ni con un identificador mal escrito');


-- ── (j) «Quién lo va a leer», antes de enviar ───────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0001', true);
select is(
  (select array_agg(cargo order by cargo) from fn_reporte_quien_lo_leera('convivencia', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0002']::uuid[], '{}')),
  array['Desarrollo Organizacional', 'Gerencia General', 'La líder de equipo de la sede'],
  'sobre una colaboradora: la líder, DO y la Gerencia General');
select is(
  (select array_agg(cargo order by cargo) from fn_reporte_quien_lo_leera('convivencia', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0002']::uuid[], array['00000000-0000-0000-0000-0000000c0003']::uuid[])),
  array['Desarrollo Organizacional', 'Gerencia General'],
  'si la líder es testigo, la línea deja de nombrarla');
select is(
  (select array_agg(cargo order by cargo) from fn_reporte_quien_lo_leera('convivencia', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0003']::uuid[], '{}')),
  array['Desarrollo Organizacional', 'Gerencia General'],
  'sobre la líder: DO y la Gerencia General');
select is(
  (select array_agg(cargo order by cargo) from fn_reporte_quien_lo_leera('convivencia', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0005']::uuid[], '{}')),
  array['Gerencia General'],
  'sobre DO: solo la Gerencia General (43-A.5)');
select is(
  (select array_agg(cargo order by cargo) from fn_reporte_quien_lo_leera('convivencia', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0006']::uuid[], '{}')),
  array['Desarrollo Organizacional'],
  'sobre la Gerencia General: solo DO (48.2-bis)');
select is(
  (select array_agg(cargo order by cargo) from fn_reporte_quien_lo_leera('titulo_x', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0002']::uuid[], '{}')),
  array['Desarrollo Organizacional', 'Quien investiga el hostigamiento sexual en la sede'],
  'Título X: DO y quien investiga; la líder, nunca');
select is(
  (select array_agg(cargo order by cargo) from fn_reporte_quien_lo_leera('titulo_x', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0005']::uuid[], '{}')),
  array['Gerencia General', 'Quien investiga el hostigamiento sexual en la sede'],
  'Título X contra DO: la Gerencia General y quien investiga (48.2)');

-- Con la única lider_do inactiva, un reporte sobre la Gerencia General se
-- queda sin nadie que lo reciba. La pantalla del paso 3 tiene que decirlo
-- ANTES de enviar: por eso esto devuelve vacío y no un error.
set session_replication_role = replica;
update personas set estado = 'inactivo', fecha_cese = '2026-09-25'
 where id = '00000000-0000-0000-0000-0000000c0005';
set session_replication_role = origin;
select is(
  (select array_agg(cargo) from fn_reporte_quien_lo_leera('convivencia', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0006']::uuid[], '{}')),
  null,
  'sin DO activa, un reporte sobre la Gerencia General no tiene quién lo reciba: la lista sale vacía');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0005', true);
set local role authenticated;
select is((select count(*)::int from reportes), 0,
  'y la DO inactiva ya no ve nada');
reset role;
set session_replication_role = replica;
update personas set estado = 'activo', fecha_cese = null
 where id = '00000000-0000-0000-0000-0000000c0005';
set session_replication_role = origin;

-- Sin marca de Gerencia General (Gabi deja de estar activa), nadie la
-- reemplaza por tener rol admin: Otto sigue sin ver nada.
set session_replication_role = replica;
update personas set estado = 'inactivo', fecha_cese = '2026-09-25'
 where id = '00000000-0000-0000-0000-0000000c0006';
set session_replication_role = origin;
select is(fn_gerencia_general_id(), null,
  'una marca que apunta a alguien inactivo no le da a nadie la vista de la Gerencia General');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0001', true);
select is(
  (select array_agg(cargo) from fn_reporte_quien_lo_leera('convivencia', '00000000-0000-0000-0000-0000000c5001',
     array['00000000-0000-0000-0000-0000000c0005']::uuid[], '{}')),
  null,
  'sin Gerencia General, un reporte sobre DO tampoco tiene quién lo reciba');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0007', true);
set local role authenticated;
select is((select count(*)::int from reportes), 0,
  'y Otto, admin, no hereda la vista por tener el rol');
reset role;
set session_replication_role = replica;
update personas set estado = 'activo', fecha_cese = null
 where id = '00000000-0000-0000-0000-0000000c0006';
set session_replication_role = origin;


-- ── (g) La foto: ascender a alguien no cambia un reporte viejo ──────────────
-- Bea pasa a ser líder. El ZT01 era sobre una colaboradora y lo sigue siendo:
-- su nivel no se recalcula en vivo, y Lia lo sigue gestionando.
set session_replication_role = replica;
update personas set rol = 'supervisor_sede' where id = '00000000-0000-0000-0000-0000000c0002';
set session_replication_role = origin;
select is((select nivel from reportes where codigo = 'ZT01'), 0::smallint,
  'ascender a la reportada no sube el nivel de un reporte que ya existía');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0003', true);
set local role authenticated;
select ok((select count(*) = 1 from reportes where codigo = 'ZT01'),
  'y la líder que lo gestionaba lo sigue gestionando');
reset role;
-- Pero mencionarla DE NUEVO en otro reporte sí toma su rol de hoy.
insert into reporte_personas (reporte_id, persona_id, papel)
values ('00000000-0000-0000-0000-0000000c7006', '00000000-0000-0000-0000-0000000c0002', 'involucrada');
select is((select nivel from reportes where codigo = 'ZT06'), 1::smallint,
  'una mención nueva toma la foto del rol de hoy y sube el nivel');

select * from finish();
rollback;
