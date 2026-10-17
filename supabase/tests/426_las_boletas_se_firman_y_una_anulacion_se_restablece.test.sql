-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 426_las_boletas_se_firman_y_una_anulacion_se_restablece.test.sql — la 0532
-- ============================================================================
-- Lo que hay que proteger acá:
-- (a) una boleta se da por recibida FIRMÁNDOLA, y nadie la da por recibida a mano,
-- (b) la firma que se copia es la que la persona tenía ese día y no se cambia
--     ni se quita después, ni siquiera si la persona cambia su firma general,
-- (c) quien confirmó antes de la 0532 no queda roto ni se le agrega una firma,
-- (d) DO ve la constancia; la persona solo la de su boleta publicada; nadie más,
-- (e) anular se acuerda de cómo estaba, restablecer lo devuelve EXACTO (con su
--     firma) y solo dentro de las 48 horas, y
-- (f) el historial de anulaciones solo se agrega.
-- ============================================================================
begin;
select plan(53);

-- ── Sedes, personas y periodo ────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000f0001', 'ZZB02', 'Sede boletas firma', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-0000000fa001', 'DoFir',  'Lab', '00000000-0000-0000-0000-0000000f0001', 'admin',           'x', '00000000-0000-0000-0000-0000000fb001', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-0000000fa002', 'AnaFir', 'Lab', '00000000-0000-0000-0000-0000000f0001', 'integrante',      'x', '00000000-0000-0000-0000-0000000fb002', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000fa003', 'BeaFir', 'Lab', '00000000-0000-0000-0000-0000000f0001', 'integrante',      'x', '00000000-0000-0000-0000-0000000fb003', '2023-01-01', 'planilla', 'Vendedora'),
  ('00000000-0000-0000-0000-0000000fa004', 'LidFir', 'Lab', '00000000-0000-0000-0000-0000000f0001', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000fb004', '2023-01-01', 'planilla', 'Líder de equipo'),
  ('00000000-0000-0000-0000-0000000fa005', 'CamiFir','Lab', '00000000-0000-0000-0000-0000000f0001', 'integrante',      'x', '00000000-0000-0000-0000-0000000fb005', '2023-01-01', 'planilla', 'Vendedora');
set session_replication_role = origin;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000ff001', '2019-07-29', '2019-08-28', 'pagado');
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at) values
  ('00000000-0000-0000-0000-0000000ff001', 'planilla', 'pagado', now());

-- Ana y Cami tienen su firma guardada; Bea no.
insert into firmas_escaneadas (persona_id, imagen, tipo) values
  ('00000000-0000-0000-0000-0000000fa002', 'data:image/png;base64,AAAA', 'imagen'),
  ('00000000-0000-0000-0000-0000000fa005', 'data:image/png;base64,CCCC', 'imagen');

select set_config('t.ana1',  '00000000-0000-0000-0000-0000000ff001/00000000-0000-0000-0000-0000000fa002/f1000000-0000-0000-0000-000000000001.jpg', true);
select set_config('t.bea1',  '00000000-0000-0000-0000-0000000ff001/00000000-0000-0000-0000-0000000fa003/f1000000-0000-0000-0000-000000000002.jpg', true);
select set_config('t.cami1', '00000000-0000-0000-0000-0000000ff001/00000000-0000-0000-0000-0000000fa005/f1000000-0000-0000-0000-000000000003.jpg', true);
insert into storage.objects (bucket_id, name, metadata) values
  ('boletas', current_setting('t.ana1'),  '{"size": 1000, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.bea1'),  '{"size": 1000, "mimetype": "image/jpeg"}'),
  ('boletas', current_setting('t.cami1'), '{"size": 1000, "mimetype": "image/jpeg"}');

-- DO sube y publica las tres.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb001', true);
select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ff001','00000000-0000-0000-0000-0000000fa002','imagen', jsonb_build_array(jsonb_build_object('path', current_setting('t.ana1'))));
select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ff001','00000000-0000-0000-0000-0000000fa003','imagen', jsonb_build_array(jsonb_build_object('path', current_setting('t.bea1'))));
select fn_boleta_guardar_version('00000000-0000-0000-0000-0000000ff001','00000000-0000-0000-0000-0000000fa005','imagen', jsonb_build_array(jsonb_build_object('path', current_setting('t.cami1'))));
select fn_boletas_publicar('00000000-0000-0000-0000-0000000ff001');

select set_config('t.ana', (select v.id::text from boletas_versiones v join boletas b on b.id = v.boleta_id where b.persona_id = '00000000-0000-0000-0000-0000000fa002'), true);
select set_config('t.bea', (select v.id::text from boletas_versiones v join boletas b on b.id = v.boleta_id where b.persona_id = '00000000-0000-0000-0000-0000000fa003'), true);
select set_config('t.cami', (select v.id::text from boletas_versiones v join boletas b on b.id = v.boleta_id where b.persona_id = '00000000-0000-0000-0000-0000000fa005'), true);
select set_config('t.bol_ana', (select id::text from boletas where persona_id = '00000000-0000-0000-0000-0000000fa002'), true);
select set_config('t.bol_cami', (select id::text from boletas where persona_id = '00000000-0000-0000-0000-0000000fa005'), true);

-- ── A · Las funciones y los permisos ─────────────────────────────────────
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and p.proname in ('fn_boleta_firmar','fn_boleta_constancia','fn_boleta_restablecer','fn_boleta_anulaciones')),
  4, 'las cuatro funciones nuevas las puede llamar quien inició sesión');
select is_empty(
  $q$ select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname in ('fn_boleta_firmar','fn_boleta_constancia','fn_boleta_restablecer','fn_boleta_anulaciones',
                           'fn_boletas_tablero','fn_mis_boletas','fn_boleta_anular','fn_boleta_confirmar_recibo')
         and has_function_privilege('anon', p.oid, 'EXECUTE') $q$,
  'y ninguna le responde a quien no inició sesión (las recreadas tampoco perdieron el revoke)');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('fn_boletas_tablero','fn_mis_boletas')
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')),
  2, 'las dos que se borraron y se crearon de nuevo conservan el grant a authenticated');

-- ── B · La firma ─────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb002', true);
select throws_ok($$ select fn_boleta_firmar(current_setting('t.ana')::uuid) $$,
  'P0001', 'Ábrela con «Ver» antes de firmarla.', 'no se firma lo que no se abrió');
select lives_ok($$ select * from fn_boleta_partes(current_setting('t.ana')::uuid) $$, 'Ana abre su boleta');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb003', true);
select throws_ok($$ select fn_boleta_firmar(current_setting('t.ana')::uuid) $$,
  'P0001', 'Esa boleta no es tuya.', 'Bea no firma la boleta de Ana');
select lives_ok($$ select * from fn_boleta_partes(current_setting('t.bea')::uuid) $$, 'Bea abre la suya');
select throws_ok($$ select fn_boleta_firmar(current_setting('t.bea')::uuid) $$,
  'P0001', 'Todavía no tienes una firma guardada: créala y vuelve a firmar.',
  'Bea no tiene firma guardada: no puede firmar (la pantalla se la hace crear)');
select is((select count(*)::int from boletas_acuses where firma is not null), 0, 'y nada quedó firmado a medias');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb002', true);
select lives_ok($$ select fn_boleta_firmar(current_setting('t.ana')::uuid) $$, 'Ana firma');
select is(
  (select (a.recibida_at is not null and a.firma = 'data:image/png;base64,AAAA')
     from boletas_acuses a where a.version_id = current_setting('t.ana')::uuid),
  true, 'queda escrita su firma, copiada de la que tenía guardada');

-- La firma general cambia después: la de la boleta NO.
update firmas_escaneadas set imagen = 'data:image/png;base64,ZZZZ' where persona_id = '00000000-0000-0000-0000-0000000fa002';
select is((select firma from boletas_acuses where version_id = current_setting('t.ana')::uuid),
  'data:image/png;base64,AAAA', 'si Ana cambia su firma después, su boleta conserva la que usó ese día');
select lives_ok($$ select fn_boleta_firmar(current_setting('t.ana')::uuid) $$, 'firmar dos veces no falla');
select is((select firma from boletas_acuses where version_id = current_setting('t.ana')::uuid),
  'data:image/png;base64,AAAA', 'ni cambia la firma ni la fecha de la primera vez');

-- ── C · Lo que el guardián no deja ───────────────────────────────────────
select throws_ok($$ update boletas_acuses set firma = 'data:image/png;base64,OTRA' where version_id = current_setting('t.ana')::uuid $$,
  'P0001', 'La firma de una boleta no se cambia ni se quita.', 'la firma puesta no se cambia');
select throws_ok($$ update boletas_acuses set firma = null where version_id = current_setting('t.ana')::uuid $$,
  'P0001', 'La firma de una boleta no se cambia ni se quita.', 'ni se quita');
select throws_ok($$ insert into boletas_acuses (version_id, vista_at, recibida_at) values (current_setting('t.cami')::uuid, now(), now()) $$,
  'P0001', 'Una boleta se da por recibida firmándola.', 'nadie da una boleta por recibida sin firma (ni desde dentro)');
select throws_ok($$ update boletas_acuses set recibida_at = now() where version_id = current_setting('t.bea')::uuid $$,
  'P0001', 'Una boleta se da por recibida firmándola.', 'ni actualizando un acuse que estaba abierto');
select throws_ok($$ insert into boletas_acuses (version_id, vista_at, firma) values (current_setting('t.cami')::uuid, now(), 'data:image/png;base64,AAAA') $$,
  '23514', null, 'una firma sin «recibida» no existe');
select throws_ok($$ insert into boletas_acuses (version_id, vista_at, recibida_at, firma) values (current_setting('t.cami')::uuid, now(), now(), 'no-es-una-imagen') $$,
  '23514', null, 'y la firma tiene que ser una imagen');

-- Quien confirmó ANTES de la 0532 (recibida sin firma) no queda roto: sus
-- aperturas siguen funcionando y no se le agrega una firma después.
alter table boletas_acuses disable trigger boletas_acuses_guardian;
update boletas_acuses set recibida_at = now() where version_id = current_setting('t.bea')::uuid;
alter table boletas_acuses enable trigger boletas_acuses_guardian;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb003', true);
select lives_ok($$ select * from fn_boleta_partes(current_setting('t.bea')::uuid) $$,
  'quien confirmó antes de la 0532 sigue pudiendo abrir su boleta');
select throws_ok($$ update boletas_acuses set firma = 'data:image/png;base64,AAAA' where version_id = current_setting('t.bea')::uuid $$,
  'P0001', 'Esa boleta se confirmó antes de que hubiera firma: no se le agrega después.', 'y no se le agrega una firma después');
select is((select (select f.estado from fn_mis_boletas() f where f.periodo_id = '00000000-0000-0000-0000-0000000ff001')
                  || ' · firmada=' || (select f.firmada::text from fn_mis_boletas() f where f.periodo_id = '00000000-0000-0000-0000-0000000ff001')),
  'publicada · firmada=false', 'su confirmación vieja figura como no firmada (la pantalla la llama «confirmada»)');

-- «Confirmar que la recibí» se retiró, con un mensaje que dice qué hacer.
select throws_ok($$ select fn_boleta_confirmar_recibo(current_setting('t.bea')::uuid) $$,
  'P0001', 'Las boletas ahora se firman: recarga la página y usa «Firmar».', 'la confirmación vieja ya no se puede usar');

-- ── D · La constancia: quién la ve ───────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb001', true);
select is((select firma from fn_boleta_constancia(current_setting('t.ana')::uuid)), 'data:image/png;base64,AAAA',
  'DO ve la firma de Ana en la constancia');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb002', true);
select is((select recibida_at is not null from fn_boleta_constancia(current_setting('t.ana')::uuid)), true,
  'Ana ve la constancia de su boleta');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb005', true);
select throws_ok($$ select * from fn_boleta_constancia(current_setting('t.ana')::uuid) $$,
  'P0001', 'Esa boleta no está disponible.', 'Cami no ve la constancia de Ana');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb004', true);
select throws_ok($$ select * from fn_boleta_constancia(current_setting('t.ana')::uuid) $$,
  'P0001', 'Esa boleta no está disponible.', 'la líder de equipo tampoco: es plata de otras personas');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb001', true);
select is((select firmada from fn_boletas_tablero('00000000-0000-0000-0000-0000000ff001') where nombre like 'AnaFir%'), true,
  'el tablero de DO dice que Ana firmó');
select is((select firmada from fn_boletas_tablero('00000000-0000-0000-0000-0000000ff001') where nombre like 'CamiFir%'), false,
  'y que Cami no');

-- ── E · DO anula una boleta firmada ──────────────────────────────────────
select throws_ok($$ select fn_boleta_anular(current_setting('t.bol_ana')::uuid, 'no') $$,
  'P0001', 'Escribe el motivo (al menos 5 letras): queda anotado junto a la boleta.', 'anular sin motivo se rechaza');
select lives_ok($$ select fn_boleta_anular(current_setting('t.bol_ana')::uuid, 'Se subió la boleta de otra persona') $$,
  'DO anula la boleta firmada de Ana');
select is((select estado || ' · ' || estado_previo from boletas where id = current_setting('t.bol_ana')::uuid), 'anulada · publicada',
  'la boleta se acuerda de cómo estaba');
select is((select count(*)::int from boletas_anulaciones where boleta_id = current_setting('t.bol_ana')::uuid and restablecida_at is null), 1,
  'y la anulación entra al historial');
select is((select firma from boletas_acuses where version_id = current_setting('t.ana')::uuid), 'data:image/png;base64,AAAA',
  'anular no toca la firma: el acuse cuelga de la versión');
select is((select fa.restablecible_hasta is not null and fa.anulada_motivo = 'Se subió la boleta de otra persona'
             from fn_boletas_tablero('00000000-0000-0000-0000-0000000ff001') fa where fa.nombre like 'AnaFir%'),
  true, 'el tablero dice hasta cuándo se puede restablecer y por qué se anuló');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb002', true);
select is((select estado || ' · version=' || coalesce(version_id::text, 'ninguna') || ' · firmada=' || firmada::text
             from fn_mis_boletas() where periodo_id = '00000000-0000-0000-0000-0000000ff001'),
  'anulada · version=ninguna · firmada=false', 'Ana ve «en revisión»: sin versión, sin archivos y sin fechas');
set local role authenticated;
select is((select count(*)::int from storage.objects where bucket_id = 'boletas'), 0, 'y no abre sus archivos');
reset role;

-- ── F · Restablecer ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb004', true);
select throws_ok($$ select fn_boleta_restablecer(current_setting('t.bol_ana')::uuid) $$,
  'P0001', 'Solo Desarrollo Organizacional puede restablecer una boleta.', 'la líder de equipo no restablece');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb001', true);
select throws_ok($$ select fn_boleta_restablecer(current_setting('t.bol_cami')::uuid) $$,
  'P0001', 'Esa boleta no está anulada.', 'solo se restablece lo anulado');
select lives_ok($$ select fn_boleta_restablecer(current_setting('t.bol_ana')::uuid) $$, 'DO restablece la boleta de Ana');
select is((select estado || ' · ' || coalesce(estado_previo, 'sin previo') from boletas where id = current_setting('t.bol_ana')::uuid),
  'publicada · sin previo', 'vuelve como estaba');
select is((select firma from boletas_acuses where version_id = current_setting('t.ana')::uuid), 'data:image/png;base64,AAAA',
  'con su firma intacta: Ana no tiene que firmar otra vez');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb002', true);
select is((select estado || ' · firmada=' || firmada::text from fn_mis_boletas() where periodo_id = '00000000-0000-0000-0000-0000000ff001'),
  'publicada · firmada=true', 'Ana la vuelve a ver, firmada');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb001', true);
select is((select restablecida_at is not null from boletas_anulaciones where boleta_id = current_setting('t.bol_ana')::uuid), true,
  'y el historial anota que se restableció');

-- ── G · El plazo de 48 horas ─────────────────────────────────────────────
select fn_boleta_anular(current_setting('t.bol_cami')::uuid, 'Los montos están mal, el contador la corrige');
-- Se envejece la anulación 49 horas (el trigger protege la fecha: se apaga un momento).
alter table boletas_anulaciones disable trigger boletas_anulaciones_guardian;
update boletas_anulaciones set anulada_at = now() - interval '49 hours' where boleta_id = current_setting('t.bol_cami')::uuid;
alter table boletas_anulaciones enable trigger boletas_anulaciones_guardian;
update boletas set anulada_at = now() - interval '49 hours' where id = current_setting('t.bol_cami')::uuid;
select throws_ok($$ select fn_boleta_restablecer(current_setting('t.bol_cami')::uuid) $$,
  'P0001', 'Pasaron más de 48 horas desde que se anuló: ya no se puede restablecer. Sube una boleta nueva.',
  'pasadas las 48 horas ya no se restablece');
select is((select estado from boletas where id = current_setting('t.bol_cami')::uuid), 'anulada', 'y la boleta sigue anulada');

-- A las 47 horas todavía se puede.
update boletas set anulada_at = now() - interval '47 hours' where id = current_setting('t.bol_cami')::uuid;
select lives_ok($$ select fn_boleta_restablecer(current_setting('t.bol_cami')::uuid) $$, 'a las 47 horas todavía se puede');

-- ── H · El historial solo se agrega ──────────────────────────────────────
select is((select count(*)::int from fn_boleta_anulaciones(current_setting('t.bol_ana')::uuid)), 1, 'DO ve el historial de Ana');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fb002', true);
select throws_ok($$ select * from fn_boleta_anulaciones(current_setting('t.bol_ana')::uuid) $$,
  'P0001', 'Solo Desarrollo Organizacional ve el historial de una boleta.', 'la persona no lo ve');
set local role authenticated;
select throws_ok($$ insert into boletas_anulaciones (boleta_id, anulada_por, motivo) values (gen_random_uuid(), gen_random_uuid(), 'abcdef') $$,
  '42501', null, 'nadie escribe una anulación a mano');
reset role;
select throws_ok($$ delete from boletas_anulaciones $$, 'P0001', 'Una anulación no se borra: queda en el historial.', 'una anulación no se borra');
select throws_ok($$ update boletas_anulaciones set motivo = 'otro motivo distinto' $$, 'P0001', 'Una anulación no se edita.', 'ni se edita');

select * from finish();
rollback;
