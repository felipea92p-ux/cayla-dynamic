-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 500_el_contrato_de_locacion_se_genera_y_se_firma.test.sql — la 0615
-- ============================================================================
-- Lo que hay que proteger acá:
-- (a) que solo DO genere, solo para quien cobra hoy por honorarios, con un RUC
--     de persona natural y con dónde estampar las dos firmas;
-- (b) que un contrato generado y SIN FIRMAR no cubra a nadie en el tablero;
-- (c) que cada persona firme solo el SUYO, una vez, con la copia de su firma de
--     ese momento, y que después nadie pueda cambiar esa firma;
-- (d) que el documento lo vea DO o su dueña, y nadie más;
-- (d2) que la firma de CAYLA se congele al generar, con quién la puso, y que
--      cambiar después el firmante o su firma no toque la del contrato;
-- (e) que lo que ya existía (los escaneos de la 0610) siga valiendo.
-- Fechas desde `fn_hoy_lima()`: una prueba con fechas fijas se vence sola.
-- ============================================================================
begin;
select plan(40);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000006150001', 'ZZG61', 'Sede generar', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-00000615a001', 'DoGen',   'Lab', '00000000-0000-0000-0000-000006150001', 'admin',      'x', '00000000-0000-0000-0000-00000615b001', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-00000615a005', 'Firma',   'Cayla', '00000000-0000-0000-0000-000006150001', 'admin',    'x', null,                                  '2020-01-01', 'planilla', 'Gerencia'),
  ('00000000-0000-0000-0000-00000615a002', 'Rosa',    'Rxh', '00000000-0000-0000-0000-000006150001', 'integrante', 'x', '00000000-0000-0000-0000-00000615b002', '2025-01-01', 'rxh',      null),
  ('00000000-0000-0000-0000-00000615a003', 'Otra',    'Rxh', '00000000-0000-0000-0000-000006150001', 'integrante', 'x', '00000000-0000-0000-0000-00000615b003', '2025-01-01', 'rxh',      null),
  ('00000000-0000-0000-0000-00000615a004', 'Plani',   'Lab', '00000000-0000-0000-0000-000006150001', 'integrante', 'x', '00000000-0000-0000-0000-00000615b004', '2023-01-01', 'planilla', 'Vendedora');
update personas set tipo_documento = 'dni', documento = '40006155' where id = '00000000-0000-0000-0000-00000615a005';
set session_replication_role = origin;

-- Quien firma por CAYLA en esta prueba. Su firma se guarda más abajo: primero
-- se comprueba que sin ella no se genera.
insert into configuracion (clave, valor, descripcion)
values ('firmante_empresa', jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000615a005', 'cargo', 'Gerencia General'), 'prueba 498')
on conflict (clave) do update set valor = excluded.valor;

-- La firma de Rosa (la de Otra no está configurada).
insert into firmas_escaneadas (persona_id, imagen) values
  ('00000000-0000-0000-0000-00000615a002', 'data:image/png;base64,ROSA1');

create function pg_temp.doc() returns text language sql as $$
  select '<article>Contrato de prueba · por CAYLA, DNI N.° 40006155 <!--FIRMA_EMPRESA--> <!--FIRMA_PERSONA--></article>' $$;
create function pg_temp.estado(p text) returns text language sql as $$
  select estado from fn_locaciones_tablero() where persona_id = p::uuid $$;
grant execute on function pg_temp.doc(), pg_temp.estado(text) to authenticated;

-- ── A · La tabla ─────────────────────────────────────────────────────────
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'contratos_locacion'
      and column_name in ('documento_html','honorarios','periodicidad','ruc_locador','firma_persona','firma_persona_confirmada_at',
                          'firma_empresa','firmante_empresa_id','firma_persona_ip','firma_persona_user_agent')),
  10, 'la tabla suma las diez columnas del contrato generado, con la firma de CAYLA y la evidencia de la firma');
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'contratos_locacion'
      and column_name in ('cargo','remuneracion_mensual','horas_semanales','jornada','sueldo','modalidad')),
  0, 'y ninguna de un contrato de trabajo: no hay por dónde meter cargo, horas ni sueldo');
select is(
  (select has_function_privilege('anon', 'fn_locacion_generar(uuid,text,date,date,numeric,text,text,text)', 'EXECUTE')
       or has_function_privilege('anon', 'fn_confirmar_mi_firma_locacion(uuid)', 'EXECUTE')
       or has_function_privilege('anon', 'fn_locacion_documento(uuid)', 'EXECUTE')),
  false, 'nada de esto le responde a quien no inició sesión');

-- ── B · Generar ──────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b002","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Solo Desarrollo Organizacional genera contratos de locación.', 'la propia persona no se genera su contrato');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a004', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Solo se genera el contrato de quien cobra hoy por recibo por honorarios.', 'a alguien de planilla no se le genera una locación');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '20605964550', pg_temp.doc()) $$,
  'P0001', 'El RUC tiene que ser el de una persona natural: 11 dígitos que empiezan con 10.', 'un RUC de empresa no entra');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       0, 'mensual', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Faltan los honorarios.', 'sin honorarios no entra');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'semanal', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Elige cómo se pagan los honorarios: fijos al mes, por todo el servicio o en proporción a las horas.',
  'los honorarios son fijos al mes, por todo el servicio o en proporción a las horas');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', '<article>sin marcas</article>') $$,
  'P0001', 'El documento no tiene dónde llevar las firmas. Vuelve a generarlo.', 'un documento sin las marcas de firma no entra');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Quien firma por CAYLA todavía no tiene su firma guardada en «Mi firma»: sin ella, el contrato saldría sin la firma de CAYLA.',
  'sin la firma de quien firma por CAYLA no se genera: saldría sin firma de CAYLA para siempre');
reset role;
insert into firmas_escaneadas (persona_id, imagen) values
  ('00000000-0000-0000-0000-00000615a005', 'data:image/png;base64,CAYLA1');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000615a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', '<article>Otro firmante, DNI N.° 49999999 <!--FIRMA_EMPRESA--> <!--FIRMA_PERSONA--></article>') $$,
  'P0001', 'Cambió quién firma por CAYLA mientras se armaba el contrato. Cierra el formulario y vuelve a generarlo.',
  'un texto que nombra a otro firmante no entra: su firma caería bajo el nombre de otra persona');

select set_config('t.gen',
  fn_locacion_generar('00000000-0000-0000-0000-00000615a002', '  Fotografía de producto ', fn_hoy_lima(), fn_hoy_lima() + 180,
    1500.004, 'por_horas', ' 10700012345 ', pg_temp.doc())::text, true);
select is(
  (select row(servicio, honorarios, periodicidad, ruc_locador, fecha_firma, storage_path)::text from contratos_locacion
    where id = current_setting('t.gen')::uuid),
  row('Fotografía de producto', 1500.00::numeric(10,2), 'por_horas', '10700012345', null::date, null::text)::text,
  'se guarda sin firmar y sin escaneo, con el servicio y el RUC recortados, los honorarios en céntimos y en proporción a las horas');
select is(
  (select row(firma_empresa, firmante_empresa_id)::text from contratos_locacion where id = current_setting('t.gen')::uuid),
  row('data:image/png;base64,CAYLA1', '00000000-0000-0000-0000-00000615a005'::uuid)::text,
  'CAYLA firma al generar: se congela su firma de ese momento y quién la puso');

-- ── C · Sin firmar no cubre ─────────────────────────────────────────────
select is(pg_temp.estado('00000000-0000-0000-0000-00000615a002'), 'sin_firmar',
  'generado y sin firmar: lo que falta es la firma, no el contrato');
select is(
  (select row(pendiente_firma, n_contratos, contrato_id is null)::text from fn_locaciones_tablero()
    where persona_id = '00000000-0000-0000-0000-00000615a002'),
  row(true, 0, true)::text, 'y no cuenta como contrato vigente');
select is(
  (select row(estado, es_digital)::text from fn_locaciones_listar('00000000-0000-0000-0000-00000615a002')),
  row('sin_firmar', true)::text, 'el historial lo dice: generado en Dynamic y sin firmar');
select throws_ok(
  $$ select fn_locacion_terminar(current_setting('t.gen')::uuid, fn_hoy_lima(), 'Ya no va el servicio') $$,
  'P0001', 'Ese contrato todavía no está firmado: si ya no va, se anula.', 'uno sin firmar no se termina: se anula');
reset role;

-- ── D · Firmar ──────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.gen')::uuid) $$,
  'P0001', 'No se encontró ese contrato.', 'otra persona no firma un contrato ajeno (ni sabe si existe)');
select is((select count(*)::int from fn_locacion_documento(current_setting('t.gen')::uuid)), 0,
  'ni puede leer su documento');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b002","role":"authenticated"}', true);
set local role authenticated;
select is(
  (select position('<!--FIRMA_PERSONA-->' in documento_html) > 0 from fn_locacion_documento(current_setting('t.gen')::uuid)),
  true, 'su dueña lee su documento, con el lugar de su firma');
select set_config('request.headers', '{"x-forwarded-for":"203.0.113.7, 10.0.0.1","user-agent":"Prueba/498"}', true);
select lives_ok($$ select fn_confirmar_mi_firma_locacion(current_setting('t.gen')::uuid) $$, 'y lo firma');
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.gen')::uuid) $$,
  'P0001', 'Ya firmaste este contrato.', 'una sola vez');
select is(
  (select row(generado_at is not null, firmado_at is not null)::text
     from fn_locacion_documento(current_setting('t.gen')::uuid)),
  row(true, true)::text, 'su documento trae cuándo firmó cada parte, para estamparlo bajo cada firma');
select is(
  (select firma_empresa from fn_locacion_documento(current_setting('t.gen')::uuid)),
  'data:image/png;base64,CAYLA1', 'y la firma de CAYLA congelada, no la de hoy');
reset role;

select is(
  (select row(fecha_firma = fn_hoy_lima(), firma_persona, firma_persona_confirmada_at is not null)::text
     from contratos_locacion where id = current_setting('t.gen')::uuid),
  row(true, 'data:image/png;base64,ROSA1', true)::text,
  'firmar le pone la fecha de hoy y la copia de su firma de ese momento');
select is(
  (select row(firma_persona_ip, firma_persona_user_agent)::text from contratos_locacion where id = current_setting('t.gen')::uuid),
  row('203.0.113.7', 'Prueba/498')::text,
  'y anota desde qué IP y con qué navegador firmó: la primera IP de la cadena, como la declaración de ruta');

-- Cambiar después la firma general no cambia la del contrato.
update firmas_escaneadas set imagen = 'data:image/png;base64,ROSA2' where persona_id = '00000000-0000-0000-0000-00000615a002';
select is((select firma_persona from contratos_locacion where id = current_setting('t.gen')::uuid),
  'data:image/png;base64,ROSA1', 'cambiar después su firma general no toca la del contrato ya firmado');
-- Lo mismo del lado de CAYLA: otra firma del firmante, y después otro firmante.
update firmas_escaneadas set imagen = 'data:image/png;base64,CAYLA2' where persona_id = '00000000-0000-0000-0000-00000615a005';
update configuracion set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000615a001', 'cargo', 'DO')
 where clave = 'firmante_empresa';
select is(
  (select row(firma_empresa, firmante_empresa_id)::text from contratos_locacion where id = current_setting('t.gen')::uuid),
  row('data:image/png;base64,CAYLA1', '00000000-0000-0000-0000-00000615a005'::uuid)::text,
  'redibujar la firma de CAYLA o cambiar de firmante no toca la de un contrato ya generado');
-- Vuelve el firmante de la prueba, para lo que sigue.
update configuracion set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000615a005', 'cargo', 'Gerencia General')
 where clave = 'firmante_empresa';
select throws_ok(
  $$ update contratos_locacion set firma_persona = 'data:image/png;base64,OTRA' where id = current_setting('t.gen')::uuid $$,
  'P0001', 'Ese contrato ya está firmado.', 'ni siquiera el sistema reescribe la firma de un contrato firmado');
select throws_ok(
  $$ update contratos_locacion set firma_empresa = 'data:image/png;base64,OTRA' where id = current_setting('t.gen')::uuid $$,
  'P0001', 'Un contrato de locación no se edita: si tiene un dato mal, se anula y se registra de nuevo.',
  'ni el sistema reescribe la firma de CAYLA');
select throws_ok(
  $$ update contratos_locacion set documento_html = documento_html || ' ' where id = current_setting('t.gen')::uuid $$,
  'P0001', 'Un contrato de locación no se edita: si tiene un dato mal, se anula y se registra de nuevo.',
  'ni el texto de lo que se firmó');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b001","role":"authenticated"}', true);
set local role authenticated;
select isnt(pg_temp.estado('00000000-0000-0000-0000-00000615a002'), 'sin_firmar',
  'firmado, ya cubre: deja de decir «sin firmar»');
select is(
  (select row(pendiente_firma, n_contratos)::text from fn_locaciones_tablero()
    where persona_id = '00000000-0000-0000-0000-00000615a002'),
  row(false, 1)::text, 'y cuenta como su contrato');
select is((select count(*)::int from fn_locacion_documento(current_setting('t.gen')::uuid)), 1, 'DO lee el documento');

-- Otra no tiene firma configurada: el error lo dice.
select set_config('t.otra',
  fn_locacion_generar('00000000-0000-0000-0000-00000615a003', 'Patronaje', fn_hoy_lima(), fn_hoy_lima() + 90,
    900, 'total', '10700099999', pg_temp.doc())::text, true);
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.otra')::uuid) $$,
  'P0001', 'Todavía no configuraste tu firma. Hazlo aquí mismo, arriba, antes de firmar.', 'sin firma configurada no se firma');
reset role;

-- Anular uno sin firmar: sí. Y anulado, su dueña ya no lo ve ni lo firma.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b001","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select fn_locacion_anular(current_setting('t.otra')::uuid, 'El servicio quedó mal escrito') $$,
  'uno sin firmar se anula');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b003","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from fn_locacion_documento(current_setting('t.otra')::uuid)), 0,
  'anulado, su dueña ya no lo ve');
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.otra')::uuid) $$,
  'P0001', 'Ese contrato está anulado.', 'ni lo firma');
reset role;

-- ── E · Lo de la 0610 sigue valiendo ────────────────────────────────────
insert into storage.objects (bucket_id, name, metadata) values
  ('contratos-locacion', '61200000-0000-0000-0000-000000000001.pdf', '{"size": 1000, "mimetype": "application/pdf"}');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b001","role":"authenticated"}', true);
set local role authenticated;
select set_config('t.escaneo',
  fn_locacion_registrar('00000000-0000-0000-0000-00000615a003', 'Patronaje', fn_hoy_lima() - 10, fn_hoy_lima() + 200,
    fn_hoy_lima() - 10, '61200000-0000-0000-0000-000000000001.pdf', 'contrato.pdf')::text, true);
select is(pg_temp.estado('00000000-0000-0000-0000-00000615a003'), 'vigente', 'un escaneo de la 0610 sigue entrando y cubriendo');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000615b003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.escaneo')::uuid) $$,
  'P0001', 'Ese contrato se firmó en papel: aquí no hay nada que firmar.', 'un escaneo no se «firma» de nuevo en pantalla');
reset role;

select * from finish();
rollback;
