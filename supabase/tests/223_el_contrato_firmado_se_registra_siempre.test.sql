-- ============================================================================
-- 223_el_contrato_firmado_se_registra_siempre.test.sql
-- ============================================================================
-- El apartado de contratos (0272) llegó a producción SIN UNA SOLA PRUEBA, y la
-- auditoría del 2026-08-24 encontró en él tres defectos que ninguna de las
-- pruebas de interfaz podía ver porque viven en la función SQL:
--
--   1. Quien CESÓ entre imprimir y firmar no podía registrar su contrato
--      firmado NUNCA: `fn_set_fin_contrato` corta con «ya está inactiva», y
--      con ella caía toda la operación. El papel de quien ya no está es
--      precisamente el que hay que archivar.
--   2. Una adenda no movía la fecha de vencimiento, así que una prórroga
--      dejaba a la persona marcada como vencida estando al día.
--   3. `p_storage_path` era texto libre: se podía apuntar la fila de una
--      persona al escaneo de otra, y como el permiso del archivo se resuelve
--      por el uuid del NOMBRE, la primera se quedaba sin poder abrir su propio
--      contrato y la segunda lo veía.
--
-- Y vigila lo que el propio contrato promete: que los dos trámites con plazo
-- —copia y comunicación al MTPE— no se puedan anotar sobre un borrador sin
-- firmar, que es dar por hecho un trámite imposible.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000c07a000', 'ZZCON', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000c07a001', 'ConDO', 'Laboratorio',
        '00000000-0000-0000-0000-00000c07a000', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-00000c07a009', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000c07a002', 'ConAna',  'Laboratorio', '00000000-0000-0000-0000-00000c07a000', 'test-hash', '2025-01-02', 'planilla'),
  ('00000000-0000-0000-0000-00000c07a003', 'ConBeto', 'Laboratorio', '00000000-0000-0000-0000-00000c07a000', 'test-hash', '2025-01-02', 'planilla');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000c07a009', true);


-- ── Generar el borrador ────────────────────────────────────────────────────
select lives_ok(
  $$ select fn_contrato_registrar(
       p_persona_id := '00000000-0000-0000-0000-00000c07a002',
       p_tipo := 'renovacion', p_cargo := 'Asesora',
       p_sede_id := '00000000-0000-0000-0000-00000c07a000',
       p_remuneracion_mensual := 1130, p_fecha_inicio := '2026-01-01',
       p_fecha_fin := '2026-12-31', p_documento_html := '<p>contrato</p>') $$,
  'Se genera el borrador de un contrato');

select is(
  (select count(*)::int from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
  1, 'Queda una fila, y sin firma: es un borrador');

select is(
  (select storage_path from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
  null, 'El borrador nace SIN escaneo — lo congelado es el texto, no un documento firmado');


-- ── Los dos trámites no se anotan sobre un borrador ────────────────────────
select throws_ok(
  $$ select fn_contrato_marcar_tramite(
       (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
       'copia') $$,
  'Ese contrato todavía no está firmado.',
  'No se puede anotar la entrega de copia de un contrato que nadie firmó');

select throws_ok(
  $$ select fn_contrato_marcar_tramite(
       (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
       'mtpe') $$,
  'Ese contrato todavía no está firmado.',
  'Ni la comunicación al MTPE');


-- ── El escaneo tiene que ser EL DE ESTE CONTRATO ───────────────────────────
select throws_ok(
  $$ select fn_contrato_registrar(
       p_id := (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
       p_storage_path := 'contratos/00000000-0000-0000-0000-0000deadbeef.pdf',
       p_fecha_firma := '2026-01-05') $$,
  'La ruta del escaneo no corresponde a este contrato.',
  'No se puede apuntar un contrato al escaneo de otro');


-- ── Registrar la firma de alguien ACTIVO mueve su vencimiento ──────────────
select lives_ok(
  $$ select fn_contrato_registrar(
       p_id := (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
       p_storage_path := 'contratos/' || (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002')::text || '.pdf',
       p_fecha_firma := '2026-01-05') $$,
  'Se registra el escaneo firmado');

select is(
  (select fecha_fin_contrato from personas where id = '00000000-0000-0000-0000-00000c07a002'),
  '2026-12-31'::date,
  'Y recién ahí se movió su fecha de vencimiento');

select throws_ok(
  $$ select fn_contrato_registrar(
       p_id := (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
       p_storage_path := 'contratos/' || (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002')::text || '.pdf',
       p_fecha_firma := '2026-01-06') $$,
  'Ese contrato ya tiene un escaneo registrado.',
  'Un escaneo ya registrado no se pisa en silencio');


-- ── Ahora sí, los dos trámites ─────────────────────────────────────────────
select lives_ok(
  $$ select fn_contrato_marcar_tramite(
       (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
       'copia', '2026-01-06') $$,
  'Con el contrato firmado, la entrega de copia se anota');

select is(
  (select copia_entregada_at from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a002'),
  '2026-01-06'::date,
  'Y queda la FECHA, no un «sí»: es lo único que prueba cuándo se hizo');


-- ── EL DEFECTO QUE MOTIVÓ ESTA PRUEBA ──────────────────────────────────────
-- Beto firma su contrato y cesa antes de que alguien suba el escaneo. Su
-- contrato firmado TIENE que poder archivarse igual: es el papel que sustenta
-- lo que se le pagó.
select fn_contrato_registrar(
  p_persona_id := '00000000-0000-0000-0000-00000c07a003',
  p_tipo := 'renovacion', p_cargo := 'Asesora',
  p_sede_id := '00000000-0000-0000-0000-00000c07a000',
  p_remuneracion_mensual := 1130, p_fecha_inicio := '2026-01-01',
  p_fecha_fin := '2026-12-31', p_documento_html := '<p>contrato</p>');

-- Con su fecha de cese: `personas_cese_coherente` no admite un inactivo sin
-- ella, y esa es justamente la situación real que se quiere reproducir.
update personas set estado = 'inactivo', fecha_cese = '2026-01-04'
 where id = '00000000-0000-0000-0000-00000c07a003';

select lives_ok(
  $$ select fn_contrato_registrar(
       p_id := (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a003'),
       p_storage_path := 'contratos/' || (select id from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a003')::text || '.pdf',
       p_fecha_firma := '2026-01-05') $$,
  'Quien cesó entre imprimir y firmar SÍ puede tener su contrato archivado');

select isnt(
  (select storage_path from contratos_generados where persona_id = '00000000-0000-0000-0000-00000c07a003'),
  null,
  'Y el escaneo queda registrado, no huérfano en el bucket');


-- ── El tablero parte de las PERSONAS ───────────────────────────────────────
-- Ana tiene contrato firmado; Beto ya no está activo. Lo que importa es que la
-- función se arme de la gente y no de los contratos: quien no tiene ninguno
-- tiene que aparecer, que es la pregunta que el historial no sabía responder.
select ok(
  (select count(*) from fn_contratos_tablero()
    where persona_id = '00000000-0000-0000-0000-00000c07a002') = 1,
  'El tablero lista a quien está en planilla, con su contrato al lado');

select * from finish();
rollback;
