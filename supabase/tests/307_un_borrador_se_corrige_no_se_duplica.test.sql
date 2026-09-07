-- ============================================================================
-- 307_un_borrador_se_corrige_no_se_duplica.test.sql
-- ============================================================================
-- Lo que promete la 0387, con el accidente que la motiva delante: el 4 de
-- setiembre de 2026 la misma persona quedó en producción con DOS convenios de
-- prácticas idénticos —mismo tipo, mismo periodo, los dos sin firmar—, porque
-- la pantalla no sabía corregir y el gesto natural para arreglar una fecha era
-- volver a generar.
--
-- Se prueban las tres reglas Y sus tres excepciones, que es donde está el
-- criterio: el adendum queda fuera del candado de periodos (se monta sobre su
-- contrato por definición), editar solo mide contra lo YA FIRMADO (medirlo
-- contra los otros borradores encerraría justo a quien tiene dos pisados), y
-- FIRMAR no mide nada (un papel que existe se archiva siempre — la promesa de
-- la 0287/0312 que la prueba 246 vigila y que la primera versión de la 0387
-- rompió).
-- ============================================================================
begin;
select plan(25);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000d0b1e00', 'ZZDUP', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000d0b1e09', 'DupDO', 'Laboratorio',
        '00000000-0000-0000-0000-00000d0b1e00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-00000d0b1e09', '2020-01-01'),
       -- Sin rol de DO: comprueba que corregir un borrador está tan cerrado
       -- como generarlo.
       ('00000000-0000-0000-0000-00000d0b1e08', 'DupAjena', 'Laboratorio',
        '00000000-0000-0000-0000-00000d0b1e00', 'integrante', 'test-hash',
        '00000000-0000-0000-0000-00000d0b1e08', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000d0b1e01', 'DupAna',   'Laboratorio', '00000000-0000-0000-0000-00000d0b1e00', 'test-hash', '2022-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000d0b1e02', 'DupBeto',  'Laboratorio', '00000000-0000-0000-0000-00000d0b1e00', 'test-hash', '2022-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000d0b1e03', 'DupCarla', 'Laboratorio', '00000000-0000-0000-0000-00000d0b1e00', 'test-hash', '2022-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000d0b1e04', 'DupDora',  'Laboratorio', '00000000-0000-0000-0000-00000d0b1e00', 'test-hash', '2022-01-02', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000d0b1e09', true);

create or replace function _dup_generar(
  p_persona uuid, p_tipo text, p_inicio date, p_fin date, p_marca text,
  p_datos jsonb default null)
returns uuid language sql as $$
  select fn_contrato_registrar(
    p_persona_id := p_persona, p_tipo := p_tipo, p_cargo := 'Asesora',
    p_sede_id := '00000000-0000-0000-0000-00000d0b1e00',
    p_remuneracion_mensual := 1130, p_fecha_inicio := p_inicio,
    p_fecha_fin := p_fin, p_documento_html := p_marca,
    p_datos_formulario := p_datos);
$$;

create or replace function _dup_firmar(p_id uuid, p_dia date)
returns void language sql as $$
  select fn_contrato_registrar(p_id := p_id,
           p_storage_path := 'contratos/' || p_id::text || '.pdf', p_fecha_firma := p_dia);
$$;


-- ── LA SOBRECARGA · lo primero, porque su fallo no se ve al pegar ─────────
-- `p_datos_formulario` es un parámetro nuevo y los doce anteriores tienen
-- valor por defecto: sin el `drop function` explícito de la 0387, un
-- `create or replace` habría dejado DOS funciones con este nombre, la llamada
-- por nombre de la pantalla encajaría en las dos, y el generador de contratos
-- moriría con «function is not unique» — al abrir la pantalla, no al pegar la
-- migración. Es el accidente literal de la 0297/0299.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_contrato_registrar'),
  1, 'Queda UNA sola fn_contrato_registrar: la firma vieja se borró, no se dejó al lado');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_contratos_listar'),
  1, 'Y una sola fn_contratos_listar, pese al drop + create por las columnas nuevas');


-- ── ANA · el candado 1: un solo borrador sin firmar por tipo ───────────────
select lives_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e01', 'convenio_practicas',
       '2026-09-03', '2026-12-03', '<p>ana convenio</p>', '{"cargo":"Asesora"}'::jsonb) $$,
  'El primer convenio se genera sin problema');

select is(
  (select datos_formulario->>'cargo' from contratos_generados where documento_html = '<p>ana convenio</p>'),
  'Asesora', 'Y guarda la foto de lo que se tecleó, para poder reabrirlo');

select throws_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e01', 'convenio_practicas',
       '2026-09-03', '2026-12-03', '<p>ana convenio DOS</p>') $$,
  'P0001',
  'Esa persona ya tiene un documento de ese tipo sin firmar. Edítalo o anúlalo: no se generan dos.',
  'EL ACCIDENTE DE GEISON: el segundo convenio idéntico ya no entra');

-- Mismo tipo, fechas COMPLETAMENTE distintas: sigue sobrando. Un borrador sin
-- firmar se corrige; la fecha nueva es justamente lo que se corrige.
select throws_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e01', 'convenio_practicas',
       '2028-01-01', '2028-06-30', '<p>ana convenio LEJOS</p>') $$,
  'P0001',
  'Esa persona ya tiene un documento de ese tipo sin firmar. Edítalo o anúlalo: no se generan dos.',
  'Y tampoco entra con otras fechas: lo que sobra es el segundo borrador, no el periodo');

-- Otro tipo, pero pisando los mismos días: candado 2.
select throws_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e01', 'nuevo',
       '2026-10-01', '2027-03-31', '<p>ana contrato pisado</p>') $$,
  'P0001',
  'Esas fechas se pisan con otro documento vigente de esa persona. Cambia el periodo, o anula el anterior si ya no vale.',
  'Otro tipo, pero cubriendo los mismos días: tampoco');

-- LA EXCEPCIÓN: el adendum se monta sobre su contrato por definición.
select lives_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e01', 'adendum',
       '2026-10-01', '2026-12-03', '<p>ana adendum</p>') $$,
  'Un adendum SÍ puede pisar el periodo: no define un vínculo, modifica el que hay');

-- Pero el candado 1 sí lo alcanza: dos adendums sin firmar son dos borradores.
select throws_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e01', 'adendum',
       '2026-10-01', '2026-12-03', '<p>ana adendum DOS</p>') $$,
  'P0001',
  'Esa persona ya tiene un documento de ese tipo sin firmar. Edítalo o anúlalo: no se generan dos.',
  'Aunque el adendum quede fuera del candado de periodos, duplicarlo sigue sobrando');

-- Anular libera: es la salida que la pantalla ofrece al lado del aviso.
select fn_contrato_anular((select id from contratos_generados where documento_html = '<p>ana convenio</p>'),
                          'se eligió la modalidad equivocada');
select lives_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e01', 'convenio_practicas',
       '2026-09-03', '2026-12-03', '<p>ana convenio bueno</p>') $$,
  'Anulado el anterior, el convenio nuevo entra: anular es la salida, y funciona');


-- ── BETO · lo que NO se bloquea, que importa tanto como lo que sí ──────────
select _dup_generar('00000000-0000-0000-0000-00000d0b1e02', 'nuevo',
                    '2026-01-01', '2026-12-31', '<p>beto nuevo</p>');
select _dup_firmar((select id from contratos_generados where documento_html = '<p>beto nuevo</p>'), '2026-01-05');

select lives_ok(
  $$ select _dup_generar('00000000-0000-0000-0000-00000d0b1e02', 'renovacion',
       '2027-01-01', '2027-12-31', '<p>beto renovacion</p>') $$,
  'La renovación que empieza al día siguiente del vencimiento entra: no se pisan');

-- LA PROMESA DE LA 0287/0312, que la primera versión de la 0387 rompió: un
-- papel firmado se archiva SIEMPRE, aunque su periodo pise a otro ya firmado.
insert into contratos_generados
  (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin,
   documento_html, generado_por)
values
  ('00000000-0000-0000-0000-00000d0b1e02', 'nuevo', 'Asesora',
   '00000000-0000-0000-0000-00000d0b1e00', 1130, '2026-06-01', '2026-12-31',
   '<p>beto papel pisado</p>', '00000000-0000-0000-0000-00000d0b1e09');

select lives_ok(
  $$ select _dup_firmar((select id from contratos_generados where documento_html = '<p>beto papel pisado</p>'), '2026-06-05') $$,
  'Un escaneo firmado se registra aunque pise a otro firmado: el papel existe');


-- ── CARLA · corregir un borrador en su sitio ──────────────────────────────
select _dup_generar('00000000-0000-0000-0000-00000d0b1e03', 'renovacion',
                    '2026-01-01', '2026-12-31', '<p>carla v1</p>', '{"cargo":"Asesora"}'::jsonb);
-- `generado_at` a mano, y no es adorno: `now()` es constante dentro de una
-- transacción, así que comparar generado_at contra editado_at no distinguiría
-- nada. Con una marca propia sí se puede afirmar que corregir NO la movió.
update contratos_generados set generado_at = '2026-01-15 09:00+00'
 where documento_html = '<p>carla v1</p>';

select lives_ok(
  $$ select fn_contrato_editar(
       p_id := (select id from contratos_generados where documento_html = '<p>carla v1</p>'),
       p_tipo := 'renovacion', p_cargo := 'Encargada de tienda',
       p_remuneracion_mensual := 1500, p_fecha_inicio := '2026-02-01',
       p_fecha_fin := '2027-01-31', p_documento_html := '<p>carla v2</p>',
       p_datos_formulario := '{"cargo":"Encargada de tienda"}'::jsonb) $$,
  'Un borrador se corrige en su sitio');

select is(
  (select count(*)::int from contratos_generados where persona_id = '00000000-0000-0000-0000-00000d0b1e03'),
  1, 'Y sigue siendo UN documento: corregir no crea otro al lado');

select row_eq(
  $$ select cargo, fecha_inicio, fecha_fin, remuneracion_mensual, documento_html
       from contratos_generados where persona_id = '00000000-0000-0000-0000-00000d0b1e03' $$,
  row('Encargada de tienda'::text, '2026-02-01'::date, '2027-01-31'::date,
      1500::numeric(10,2), '<p>carla v2</p>'::text)::record,
  'Con el cargo, las fechas, el sueldo y el texto nuevos');

select is(
  (select editado_por from contratos_generados where persona_id = '00000000-0000-0000-0000-00000d0b1e03'),
  '00000000-0000-0000-0000-00000d0b1e09'::uuid,
  'Queda anotado quién lo corrigió');

select ok(
  exists (select 1 from correcciones_auditoria
           where persona_id = '00000000-0000-0000-0000-00000d0b1e03'
             and campo_modificado = 'contrato_editado'
             and valor_anterior like '%2026-01-01%'
             and valor_nuevo    like '%2026-02-01%'),
  'Y la auditoría guarda de qué a qué: un documento que se firma no cambia en silencio');

select is(
  (select generado_at from contratos_generados where persona_id = '00000000-0000-0000-0000-00000d0b1e03'),
  '2026-01-15 09:00+00'::timestamptz,
  'generado_at no se mueve al corregir: es lo que ordena el archivo y el tablero');

select is(
  (select editado_por from fn_contratos_listar('00000000-0000-0000-0000-00000d0b1e03')),
  'DupDO Laboratorio', 'Y la pantalla lo puede decir: fn_contratos_listar devuelve quién');


-- ── LO QUE fn_contrato_editar SE NIEGA A HACER ────────────────────────────
select throws_ok(
  $$ select fn_contrato_editar(
       p_id := (select id from contratos_generados where documento_html = '<p>beto nuevo</p>'),
       p_tipo := 'nuevo', p_cargo := 'Asesora', p_remuneracion_mensual := 1130,
       p_fecha_inicio := '2026-01-01', p_fecha_fin := '2026-12-31',
       p_documento_html := '<p>beto reescrito</p>') $$,
  'P0001',
  'Ese contrato ya está firmado: no se edita. Usa un adendum, o anúlalo con su motivo.',
  'LA LÍNEA QUE NO SE CRUZA: un contrato firmado no se reescribe por detrás');

select throws_ok(
  $$ select fn_contrato_editar(
       p_id := (select id from contratos_generados where documento_html = '<p>ana convenio</p>'),
       p_tipo := 'convenio_practicas', p_cargo := 'Asesora', p_remuneracion_mensual := 1130,
       p_fecha_inicio := '2026-09-03', p_fecha_fin := '2026-12-03',
       p_documento_html := '<p>ana anulado reescrito</p>') $$,
  'P0001',
  'Ese contrato está anulado: ya no se corrige, se genera uno nuevo.',
  'Un anulado tampoco: lo que se declaró nulo se queda como quedó');

select throws_ok(
  $$ select fn_contrato_editar(
       p_id := (select id from contratos_generados where documento_html = '<p>carla v2</p>'),
       p_tipo := 'indefinido', p_cargo := 'Asesora', p_remuneracion_mensual := 1130,
       p_fecha_inicio := '2026-02-01', p_fecha_fin := '2027-01-31',
       p_documento_html := '<p>carla v3</p>') $$,
  'P0001', 'Un contrato indefinido no lleva fecha de fin.',
  'Corregir valida igual que generar: un indefinido con fecha de fin no pasa');


-- ── DORA · la indulgencia deliberada al editar ────────────────────────────
-- Dos borradores pisados como los de Geison, metidos a mano porque la 0387 ya
-- no deja crearlos. Los dos tienen que poder abrirse para corregirse: si el
-- candado de periodos mirara a los otros borradores, cada uno pisaría al otro y
-- ninguno se podría arreglar — una trampa cerrada sobre los datos que esta
-- migración viene a rescatar.
insert into contratos_generados
  (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin,
   documento_html, generado_por)
values
  ('00000000-0000-0000-0000-00000d0b1e04', 'convenio_practicas', 'Practicante',
   '00000000-0000-0000-0000-00000d0b1e00', 1130, '2026-09-03', '2026-12-03',
   '<p>dora A</p>', '00000000-0000-0000-0000-00000d0b1e09'),
  ('00000000-0000-0000-0000-00000d0b1e04', 'convenio_practicas', 'Practicante',
   '00000000-0000-0000-0000-00000d0b1e00', 1130, '2026-09-03', '2026-12-03',
   '<p>dora B</p>', '00000000-0000-0000-0000-00000d0b1e09');

select lives_ok(
  $$ select fn_contrato_editar(
       p_id := (select id from contratos_generados where documento_html = '<p>dora A</p>'),
       p_tipo := 'convenio_practicas', p_cargo := 'Practicante',
       p_remuneracion_mensual := 1130, p_fecha_inicio := '2026-09-04',
       p_fecha_fin := '2026-12-04', p_documento_html := '<p>dora A corregido</p>') $$,
  'Con dos borradores pisados, editar uno SÍ se puede: es como se sale del enredo');

-- Pero pisar un contrato FIRMADO al corregir sigue cerrado.
select _dup_firmar((select id from contratos_generados where documento_html = '<p>dora B</p>'), '2026-09-05');
select throws_ok(
  $$ select fn_contrato_editar(
       p_id := (select id from contratos_generados where documento_html = '<p>dora A corregido</p>'),
       p_tipo := 'convenio_practicas', p_cargo := 'Practicante',
       p_remuneracion_mensual := 1130, p_fecha_inicio := '2026-09-03',
       p_fecha_fin := '2026-12-03', p_documento_html := '<p>dora A otra vez</p>') $$,
  'P0001',
  'Esas fechas se pisan con un contrato ya firmado de esa persona. Cambia el periodo, o anula el firmado si ya no vale.',
  'Corregir un borrador hasta pisar un contrato FIRMADO sí se rechaza');


-- ── EL PERMISO ────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000d0b1e08', true);
select throws_ok(
  $$ select fn_contrato_editar(
       p_id := (select id from contratos_generados where documento_html = '<p>dora A corregido</p>'),
       p_tipo := 'convenio_practicas', p_cargo := 'Practicante',
       p_remuneracion_mensual := 9999, p_fecha_inicio := '2026-09-04',
       p_fecha_fin := '2026-12-04', p_documento_html := '<p>colada</p>') $$,
  'P0001', 'Solo Desarrollo Organizacional corrige contratos.',
  'Corregir un borrador está tan cerrado como generarlo');

select * from finish();
rollback;
