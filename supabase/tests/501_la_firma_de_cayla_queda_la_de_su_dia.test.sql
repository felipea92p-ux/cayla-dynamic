-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- ============================================================================
-- 501_la_firma_de_cayla_queda_la_de_su_dia.test.sql — la 0616
-- ============================================================================
-- Lo que hay que proteger acá:
-- (a) que todo documento nazca con la firma de CAYLA de ese instante, quién
--     firmaba y con qué cargo, aunque la fila traiga otra cosa;
-- (b) que redibujar la firma o cambiar de firmante NO toque lo ya creado;
-- (c) que nadie la reescriba después, salvo un contrato que se corrige antes
--     de firmarse (su texto nuevo nombra al firmante de hoy);
-- (d) que sin firma guardada el documento igual nazca (con la línea en blanco)
--     en vez de frenar a quien firma su declaración;
-- (e) que las pantallas la reciban (fn_documentos_listar, fn_politica_salarial_vigente)
--     y que cada confirmación de un contrato guarde su IP y su navegador.
-- Datos inventados.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-00000616f000', 'ZZF616', 'Sede firma', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, tipo_vinculo, cargo, auth_user_id) values
  ('00000000-0000-0000-0000-00000616f0a1', 'Ana',   'Firmante', '00000000-0000-0000-0000-00000616f000', 'admin',      'x', '2020-01-01', 'planilla', 'Gerencia', null),
  ('00000000-0000-0000-0000-00000616f0b1', 'Bruno', 'Firmante', '00000000-0000-0000-0000-00000616f000', 'admin',      'x', '2020-01-01', 'planilla', 'Gerencia', null),
  ('00000000-0000-0000-0000-00000616f0c1', 'Cris',  'SinFirma', '00000000-0000-0000-0000-00000616f000', 'admin',      'x', '2020-01-01', 'planilla', 'Gerencia', null),
  ('00000000-0000-0000-0000-00000616f0d1', 'Dora',  'Equipo',   '00000000-0000-0000-0000-00000616f000', 'integrante', 'x', '2025-01-01', 'planilla', 'Vendedora',
   '00000000-0000-0000-0000-00000616f0d2');
update personas set tipo_documento = 'dni', documento = '40616001' where id = '00000000-0000-0000-0000-00000616f0a1';
update personas set tipo_documento = 'dni', documento = '40616002' where id = '00000000-0000-0000-0000-00000616f0b1';
set session_replication_role = origin;

insert into firmas_escaneadas (persona_id, imagen) values
  ('00000000-0000-0000-0000-00000616f0a1', 'data:image/png;base64,ANA1'),
  ('00000000-0000-0000-0000-00000616f0b1', 'data:image/png;base64,BRUNO1'),
  ('00000000-0000-0000-0000-00000616f0d1', 'data:image/png;base64,DORA');

insert into configuracion (clave, valor, descripcion)
values ('firmante_empresa', jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000616f0a1', 'cargo', 'Gerencia General'), 'prueba 501')
on conflict (clave) do update set valor = excluded.valor;

create function pg_temp.firma(p_id uuid) returns text language sql as $$
  select row(firma_empresa, firmante_empresa_id, firmante_empresa_cargo)::text from contratos_generados where id = p_id $$;

-- ── A · Nace con la firma de ese instante ───────────────────────────────
insert into contratos_generados (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual,
                                 fecha_inicio, fecha_fin, documento_html, generado_por)
values ('00000000-0000-0000-0000-00000616fc01', '00000000-0000-0000-0000-00000616f0d1', 'nuevo', 'Vendedora',
        '00000000-0000-0000-0000-00000616f000', 1500, '2026-01-01', '2026-12-31',
        '<p>Firma por CAYLA: DNI 40616001</p>', '00000000-0000-0000-0000-00000616f0a1');
select is(pg_temp.firma('00000000-0000-0000-0000-00000616fc01'),
  row('data:image/png;base64,ANA1', '00000000-0000-0000-0000-00000616f0a1'::uuid, 'Gerencia General')::text,
  'un contrato nace con la firma de CAYLA de ese instante, quién firmaba y su cargo');

insert into contratos_generados (id, persona_id, tipo, cargo, sede_id, remuneracion_mensual,
                                 fecha_inicio, fecha_fin, documento_html, generado_por,
                                 firma_empresa, firmante_empresa_id, firmante_empresa_cargo)
values ('00000000-0000-0000-0000-00000616fc02', '00000000-0000-0000-0000-00000616f0d1', 'nuevo', 'Vendedora',
        '00000000-0000-0000-0000-00000616f000', 1500, '2026-01-01', '2026-12-31',
        '<p>Firma por CAYLA: DNI 40616001</p>', '00000000-0000-0000-0000-00000616f0a1',
        'data:image/png;base64,FALSA', '00000000-0000-0000-0000-00000616f0b1', 'Otro cargo');
select is(pg_temp.firma('00000000-0000-0000-0000-00000616fc02'),
  row('data:image/png;base64,ANA1', '00000000-0000-0000-0000-00000616f0a1'::uuid, 'Gerencia General')::text,
  'lo que traiga la fila se pisa: nadie crea un documento con la firma de otra persona');

-- ── B · Lo que pase después no lo toca ──────────────────────────────────
update firmas_escaneadas set imagen = 'data:image/png;base64,ANA2', actualizado_at = now()
 where persona_id = '00000000-0000-0000-0000-00000616f0a1';
update configuracion set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000616f0b1', 'cargo', 'Gerencia')
 where clave = 'firmante_empresa';
select is(pg_temp.firma('00000000-0000-0000-0000-00000616fc01'),
  row('data:image/png;base64,ANA1', '00000000-0000-0000-0000-00000616f0a1'::uuid, 'Gerencia General')::text,
  'redibujar la firma y cambiar de firmante no tocan un contrato ya creado');

-- ── C · Nadie la reescribe; un contrato corregido sin firmar sí se vuelve a firmar ──
select throws_ok(
  $$ update contratos_generados set firma_empresa = 'data:image/png;base64,OTRA'
      where id = '00000000-0000-0000-0000-00000616fc01' $$,
  'P0001', 'La firma de CAYLA de un documento no se cambia: es la de su día.',
  'la firma de CAYLA no se reescribe');
select throws_ok(
  $$ update contratos_generados set firmante_empresa_id = '00000000-0000-0000-0000-00000616f0b1'
      where id = '00000000-0000-0000-0000-00000616fc01' $$,
  'P0001', 'La firma de CAYLA de un documento no se cambia: es la de su día.',
  'ni quién la puso');
select lives_ok(
  $$ update contratos_generados set copia_entregada_at = now() where id = '00000000-0000-0000-0000-00000616fc01' $$,
  'lo demás de la fila se sigue escribiendo igual');

update contratos_generados set documento_html = '<p>Corregido. Firma por CAYLA: DNI 40616002</p>'
 where id = '00000000-0000-0000-0000-00000616fc02';
select is(pg_temp.firma('00000000-0000-0000-0000-00000616fc02'),
  row('data:image/png;base64,BRUNO1', '00000000-0000-0000-0000-00000616f0b1'::uuid, 'Gerencia')::text,
  'un contrato corregido antes de firmarse vuelve a nacer con el firmante de hoy');

update contratos_generados set fecha_firma = '2026-01-02', registrado_por = '00000000-0000-0000-0000-00000616f0d1',
       firma_persona = 'data:image/png;base64,DORA',
       firma_persona_confirmada_at = now()
 where id = '00000000-0000-0000-0000-00000616fc01';
update contratos_generados set documento_html = documento_html || ' '
 where id = '00000000-0000-0000-0000-00000616fc01';
select is(pg_temp.firma('00000000-0000-0000-0000-00000616fc01'),
  row('data:image/png;base64,ANA1', '00000000-0000-0000-0000-00000616f0a1'::uuid, 'Gerencia General')::text,
  'firmado, aunque se toque su texto, la firma de CAYLA sigue siendo la de su día');

-- ── D · Los otros dos documentos ────────────────────────────────────────
insert into documentos_firmados (id, alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
                                 es_negativa, registrado_por, firma_persona, firma_persona_confirmada_at)
values ('00000000-0000-0000-0000-00000616fd01', 'individual', '00000000-0000-0000-0000-00000616f0d1', 'ruta',
        '2026-03-02', 'Casa - tienda', 12.00, false, '00000000-0000-0000-0000-00000616f0d1',
        'data:image/png;base64,DORA', now());
select is(
  (select row(firma_empresa, firmante_empresa_id, firmante_empresa_cargo)::text from documentos_firmados
    where id = '00000000-0000-0000-0000-00000616fd01'),
  row('data:image/png;base64,BRUNO1', '00000000-0000-0000-0000-00000616f0b1'::uuid, 'Gerencia')::text,
  'una declaración de ruta nace con la firma de CAYLA de ese instante (y ya no choca con la regla de la 0531)');
select throws_ok(
  $$ update documentos_firmados set firma_empresa = null where id = '00000000-0000-0000-0000-00000616fd01' $$,
  'P0001', 'La firma de CAYLA de un documento no se cambia: es la de su día.',
  'tampoco se borra');

insert into politica_salarial (version, documento, huella_cuadro)
values ((select coalesce(max(version), 0) + 1 from politica_salarial), 'Politica de laboratorio para la prueba 501', 'huella-501');
select is(
  (select row(firma_empresa, firmante_empresa_id)::text from politica_salarial
    where huella_cuadro = 'huella-501'),
  row('data:image/png;base64,BRUNO1', '00000000-0000-0000-0000-00000616f0b1'::uuid)::text,
  'una versión de la política salarial nace con la firma de quien la publica por CAYLA');

insert into documentos_firmados (id, alcance, persona_id, tipo, fecha_firma, storage_path, registrado_por)
values ('00000000-0000-0000-0000-00000616fd03', 'individual', '00000000-0000-0000-0000-00000616f0d1', 'ruta',
        '2026-03-03', 'documentos/escaneo-501.pdf', '00000000-0000-0000-0000-00000616f0d1');
select is(
  (select row(firma_empresa, firmante_empresa_id)::text from documentos_firmados
    where id = '00000000-0000-0000-0000-00000616fd03'),
  row(null::text, null::uuid)::text,
  'un papel escaneado no recibe firma congelada: la de CAYLA está en el papel');

-- ── E · Sin firma guardada, el documento nace igual ────────────────────
update configuracion set valor = jsonb_build_object('persona_id', '00000000-0000-0000-0000-00000616f0c1', 'cargo', 'Gerencia')
 where clave = 'firmante_empresa';
select lives_ok(
  $$ insert into documentos_firmados (id, alcance, persona_id, tipo, fecha_firma, ruta_declarada, monto_declarado,
                                      es_negativa, registrado_por, firma_persona, firma_persona_confirmada_at)
     values ('00000000-0000-0000-0000-00000616fd02', 'individual', '00000000-0000-0000-0000-00000616f0d1', 'ruta',
             '2026-04-02', 'Casa - tienda', 12.00, false, '00000000-0000-0000-0000-00000616f0d1',
             'data:image/png;base64,DORA', now()) $$,
  'si quien firma por CAYLA no tiene su firma guardada, la declaración igual se firma');
select is(
  (select row(firma_empresa, firmante_empresa_id)::text from documentos_firmados
    where id = '00000000-0000-0000-0000-00000616fd02'),
  row(null::text, '00000000-0000-0000-0000-00000616f0c1'::uuid)::text,
  'y queda con quién firmaba y la línea en blanco, no con la firma de otra persona');

-- ── F · Lo que reciben las pantallas, y la evidencia de cada confirmación ──
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000616f0d2","role":"authenticated"}', true);
select set_config('request.headers', '{"x-forwarded-for":" 198.51.100.4 , 10.0.0.9","user-agent":"Prueba/501"}', true);
set local role authenticated;
select is(
  (select row(firma_empresa, firmante_empresa_nombre, firmante_empresa_cargo)::text
     from fn_documentos_listar() where id = '00000000-0000-0000-0000-00000616fd01'),
  row('data:image/png;base64,BRUNO1', 'Bruno Firmante', 'Gerencia')::text,
  'Lo mío › Movilidad recibe la firma de CAYLA de su declaración, con el nombre y el cargo de ese día');
select is(
  fn_politica_salarial_vigente() ->> 'firma_empresa', 'data:image/png;base64,BRUNO1',
  'la política vigente trae la firma con que se publicó');
select lives_ok(
  $$ select fn_confirmar_mi_firma_contrato('00000000-0000-0000-0000-00000616fc01') $$,
  'la persona vuelve a confirmar su contrato');
reset role;
select is(
  (select row(ip, user_agent)::text from confirmaciones_firma_contrato
    where contrato_id = '00000000-0000-0000-0000-00000616fc01' order by confirmada_at desc, id desc limit 1),
  row('198.51.100.4', 'Prueba/501')::text,
  'y esa confirmación guarda la IP (la primera de la cadena, sin espacios) y el navegador');

select * from finish();
rollback;
