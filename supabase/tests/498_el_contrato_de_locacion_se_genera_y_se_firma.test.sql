-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 498_el_contrato_de_locacion_se_genera_y_se_firma.test.sql — la 0612
-- ============================================================================
-- Lo que hay que proteger acá:
-- (a) que solo DO genere, solo para quien cobra hoy por honorarios, con un RUC
--     de persona natural y con dónde estampar las dos firmas;
-- (b) que un contrato generado y SIN FIRMAR no cubra a nadie en el tablero;
-- (c) que cada persona firme solo el SUYO, una vez, con la copia de su firma de
--     ese momento, y que después nadie pueda cambiar esa firma;
-- (d) que el documento lo vea DO o su dueña, y nadie más;
-- (e) que lo que ya existía (los escaneos de la 0610) siga valiendo.
-- Fechas desde `fn_hoy_lima()`: una prueba con fechas fijas se vence sola.
-- ============================================================================
begin;
select plan(32);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000006120001', 'ZZG61', 'Sede generar', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, cargo) values
  ('00000000-0000-0000-0000-00000612a001', 'DoGen',   'Lab', '00000000-0000-0000-0000-000006120001', 'admin',      'x', '00000000-0000-0000-0000-00000612b001', '2023-01-01', 'planilla', 'DO'),
  ('00000000-0000-0000-0000-00000612a002', 'Rosa',    'Rxh', '00000000-0000-0000-0000-000006120001', 'integrante', 'x', '00000000-0000-0000-0000-00000612b002', '2025-01-01', 'rxh',      null),
  ('00000000-0000-0000-0000-00000612a003', 'Otra',    'Rxh', '00000000-0000-0000-0000-000006120001', 'integrante', 'x', '00000000-0000-0000-0000-00000612b003', '2025-01-01', 'rxh',      null),
  ('00000000-0000-0000-0000-00000612a004', 'Plani',   'Lab', '00000000-0000-0000-0000-000006120001', 'integrante', 'x', '00000000-0000-0000-0000-00000612b004', '2023-01-01', 'planilla', 'Vendedora');
set session_replication_role = origin;

-- La firma de Rosa (la de Otra no está configurada).
insert into firmas_escaneadas (persona_id, imagen) values
  ('00000000-0000-0000-0000-00000612a002', 'data:image/png;base64,ROSA1');

create function pg_temp.doc() returns text language sql as $$
  select '<article>Contrato de prueba <!--FIRMA_EMPRESA--> <!--FIRMA_PERSONA--></article>' $$;
create function pg_temp.estado(p text) returns text language sql as $$
  select estado from fn_locaciones_tablero() where persona_id = p::uuid $$;
grant execute on function pg_temp.doc(), pg_temp.estado(text) to authenticated;

-- ── A · La tabla ─────────────────────────────────────────────────────────
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'contratos_locacion'
      and column_name in ('documento_html','honorarios','periodicidad','ruc_locador','firma_persona','firma_persona_confirmada_at')),
  6, 'la tabla suma las seis columnas del contrato generado');
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
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b002","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000612a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Solo Desarrollo Organizacional genera contratos de locación.', 'la propia persona no se genera su contrato');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000612a004', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Solo se genera el contrato de quien cobra hoy por recibo por honorarios.', 'a alguien de planilla no se le genera una locación');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000612a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '20605964550', pg_temp.doc()) $$,
  'P0001', 'El RUC tiene que ser el de una persona natural: 11 dígitos que empiezan con 10.', 'un RUC de empresa no entra');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000612a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       0, 'mensual', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Faltan los honorarios.', 'sin honorarios no entra');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000612a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'semanal', '10700012345', pg_temp.doc()) $$,
  'P0001', 'Elige cómo se pagan los honorarios: fijos al mes, por todo el servicio o en proporción a las horas.',
  'los honorarios son fijos al mes, por todo el servicio o en proporción a las horas');
select throws_ok(
  $$ select fn_locacion_generar('00000000-0000-0000-0000-00000612a002', 'Fotografía', fn_hoy_lima(), fn_hoy_lima() + 180,
       1500, 'mensual', '10700012345', '<article>sin marcas</article>') $$,
  'P0001', 'El documento no tiene dónde llevar las firmas. Vuelve a generarlo.', 'un documento sin las marcas de firma no entra');

select set_config('t.gen',
  fn_locacion_generar('00000000-0000-0000-0000-00000612a002', '  Fotografía de producto ', fn_hoy_lima(), fn_hoy_lima() + 180,
    1500.004, 'por_horas', ' 10700012345 ', pg_temp.doc())::text, true);
select is(
  (select row(servicio, honorarios, periodicidad, ruc_locador, fecha_firma, storage_path)::text from contratos_locacion
    where id = current_setting('t.gen')::uuid),
  row('Fotografía de producto', 1500.00::numeric(10,2), 'por_horas', '10700012345', null::date, null::text)::text,
  'se guarda sin firmar y sin escaneo, con el servicio y el RUC recortados, los honorarios en céntimos y en proporción a las horas');

-- ── C · Sin firmar no cubre ─────────────────────────────────────────────
select is(pg_temp.estado('00000000-0000-0000-0000-00000612a002'), 'sin_firmar',
  'generado y sin firmar: lo que falta es la firma, no el contrato');
select is(
  (select row(pendiente_firma, n_contratos, contrato_id is null)::text from fn_locaciones_tablero()
    where persona_id = '00000000-0000-0000-0000-00000612a002'),
  row(true, 0, true)::text, 'y no cuenta como contrato vigente');
select is(
  (select row(estado, es_digital)::text from fn_locaciones_listar('00000000-0000-0000-0000-00000612a002')),
  row('sin_firmar', true)::text, 'el historial lo dice: generado en Dynamic y sin firmar');
select throws_ok(
  $$ select fn_locacion_terminar(current_setting('t.gen')::uuid, fn_hoy_lima(), 'Ya no va el servicio') $$,
  'P0001', 'Ese contrato todavía no está firmado: si ya no va, se anula.', 'uno sin firmar no se termina: se anula');
reset role;

-- ── D · Firmar ──────────────────────────────────────────────────────────
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.gen')::uuid) $$,
  'P0001', 'No se encontró ese contrato.', 'otra persona no firma un contrato ajeno (ni sabe si existe)');
select is((select count(*)::int from fn_locacion_documento(current_setting('t.gen')::uuid)), 0,
  'ni puede leer su documento');
reset role;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b002","role":"authenticated"}', true);
set local role authenticated;
select is(
  (select position('<!--FIRMA_PERSONA-->' in documento_html) > 0 from fn_locacion_documento(current_setting('t.gen')::uuid)),
  true, 'su dueña lee su documento, con el lugar de su firma');
select lives_ok($$ select fn_confirmar_mi_firma_locacion(current_setting('t.gen')::uuid) $$, 'y lo firma');
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.gen')::uuid) $$,
  'P0001', 'Ya firmaste este contrato.', 'una sola vez');
reset role;

select is(
  (select row(fecha_firma = fn_hoy_lima(), firma_persona, firma_persona_confirmada_at is not null)::text
     from contratos_locacion where id = current_setting('t.gen')::uuid),
  row(true, 'data:image/png;base64,ROSA1', true)::text,
  'firmar le pone la fecha de hoy y la copia de su firma de ese momento');

-- Cambiar después la firma general no cambia la del contrato.
update firmas_escaneadas set imagen = 'data:image/png;base64,ROSA2' where persona_id = '00000000-0000-0000-0000-00000612a002';
select is((select firma_persona from contratos_locacion where id = current_setting('t.gen')::uuid),
  'data:image/png;base64,ROSA1', 'cambiar después su firma general no toca la del contrato ya firmado');
select throws_ok(
  $$ update contratos_locacion set firma_persona = 'data:image/png;base64,OTRA' where id = current_setting('t.gen')::uuid $$,
  'P0001', 'Ese contrato ya está firmado.', 'ni siquiera el sistema reescribe la firma de un contrato firmado');
select throws_ok(
  $$ update contratos_locacion set documento_html = documento_html || ' ' where id = current_setting('t.gen')::uuid $$,
  'P0001', 'Un contrato de locación no se edita: si tiene un dato mal, se anula y se registra de nuevo.',
  'ni el texto de lo que se firmó');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b001","role":"authenticated"}', true);
set local role authenticated;
select isnt(pg_temp.estado('00000000-0000-0000-0000-00000612a002'), 'sin_firmar',
  'firmado, ya cubre: deja de decir «sin firmar»');
select is(
  (select row(pendiente_firma, n_contratos)::text from fn_locaciones_tablero()
    where persona_id = '00000000-0000-0000-0000-00000612a002'),
  row(false, 1)::text, 'y cuenta como su contrato');
select is((select count(*)::int from fn_locacion_documento(current_setting('t.gen')::uuid)), 1, 'DO lee el documento');

-- Otra no tiene firma configurada: el error lo dice.
select set_config('t.otra',
  fn_locacion_generar('00000000-0000-0000-0000-00000612a003', 'Patronaje', fn_hoy_lima(), fn_hoy_lima() + 90,
    900, 'total', '10700099999', pg_temp.doc())::text, true);
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.otra')::uuid) $$,
  'P0001', 'Todavía no configuraste tu firma. Hazlo aquí mismo, arriba, antes de firmar.', 'sin firma configurada no se firma');
reset role;

-- Anular uno sin firmar: sí. Y anulado, su dueña ya no lo ve ni lo firma.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b001","role":"authenticated"}', true);
set local role authenticated;
select lives_ok($$ select fn_locacion_anular(current_setting('t.otra')::uuid, 'El servicio quedó mal escrito') $$,
  'uno sin firmar se anula');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b003","role":"authenticated"}', true);
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
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b001","role":"authenticated"}', true);
set local role authenticated;
select set_config('t.escaneo',
  fn_locacion_registrar('00000000-0000-0000-0000-00000612a003', 'Patronaje', fn_hoy_lima() - 10, fn_hoy_lima() + 200,
    fn_hoy_lima() - 10, '61200000-0000-0000-0000-000000000001.pdf', 'contrato.pdf')::text, true);
select is(pg_temp.estado('00000000-0000-0000-0000-00000612a003'), 'vigente', 'un escaneo de la 0610 sigue entrando y cubriendo');
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000612b003","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select fn_confirmar_mi_firma_locacion(current_setting('t.escaneo')::uuid) $$,
  'P0001', 'Ese contrato se firmó en papel: aquí no hay nada que firmar.', 'un escaneo no se «firma» de nuevo en pantalla');
reset role;

select * from finish();
rollback;
