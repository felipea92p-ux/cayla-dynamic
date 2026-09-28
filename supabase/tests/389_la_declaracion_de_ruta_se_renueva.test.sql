-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. Se corre:
--   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 389_la_declaracion_de_ruta_se_renueva.test.sql — 0492
-- ============================================================================
-- Lo que se defiende:
--
--   1. EL CRITERIO. Incompleta = firma digital sin pasaje; vencida = 12 meses;
--      el papel escaneado y la negativa nunca están «por renovar».
--   2. QUE EL TABLERO Y EL CANDADO DIGAN LO MISMO. Si el tablero avisa
--      «renueva», la firma tiene que dejar pasar; si está al día, el candado
--      de la 0425 sigue cerrado.
--   3. QUE LA PLANILLA NO SE ENTERE. Una declaración por renovar sigue
--      contando como declaración para pagar la movilidad: la misma pregunta
--      que hace fn_planilla_calcular_nucleo (existe una firmada, no anulada,
--      no negativa) tiene que seguir contestando que sí.
-- ============================================================================
begin;
select plan(13);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, tipo_vinculo, auth_user_id) values
  -- Firmó con la versión corta (sin pasaje): incompleta.
  ('00000000-0000-0000-0000-000000389001', 'Prueba', 'Corta',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000389011'),
  -- Firmó completa hace más de un año: vencida.
  ('00000000-0000-0000-0000-000000389002', 'Prueba', 'Vieja',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000389012'),
  -- Firmó completa hace poco: al día.
  ('00000000-0000-0000-0000-000000389003', 'Prueba', 'AlDia',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000389013'),
  -- Papel escaneado de hace poco: sin pasaje en columnas, pero NO incompleta.
  ('00000000-0000-0000-0000-000000389004', 'Prueba', 'Papel',
   (select id from sedes where codigo = 'TRU'), 'integrante', 'test-hash', 'planilla',
   '00000000-0000-0000-0000-000000389014');
set session_replication_role = origin;

insert into firmas_escaneadas (persona_id, imagen, tipo)
select id, 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', 'imagen'
  from personas where id::text like '00000000-0000-0000-0000-00000038900_';

-- Las filas se insertan directo, con la tarifa vigente de TRU como monto, para
-- que el candado de la 0425 (monto = tarifa) las considere «al día» y lo único
-- que decida sea el criterio nuevo.
insert into documentos_firmados
  (alcance, persona_id, tipo, fecha_firma, monto_declarado, registrado_por,
   firma_persona, firma_persona_confirmada_at, ruta_distrito, ruta_provincia,
   ruta_medios_ida, ruta_medios_vuelta, ruta_costo_pasaje, ruta_gasto_diario)
values
  ('individual', '00000000-0000-0000-0000-000000389001', 'ruta', fn_hoy_lima() - 10, 10.00,
   '00000000-0000-0000-0000-000000389001', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', now(), 'Trujillo', 'Trujillo', 1, 1, null, null),
  ('individual', '00000000-0000-0000-0000-000000389002', 'ruta', fn_hoy_lima() - 400, 10.00,
   '00000000-0000-0000-0000-000000389002', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', now(), 'Trujillo', 'Trujillo', 1, 1, 2.50, 5.00),
  ('individual', '00000000-0000-0000-0000-000000389003', 'ruta', fn_hoy_lima() - 10, 10.00,
   '00000000-0000-0000-0000-000000389003', 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==', now(), 'Trujillo', 'Trujillo', 1, 1, 2.50, 5.00),
  -- Papel: sin firma digital (firma_persona_confirmada_at null) y sin columnas.
  ('individual', '00000000-0000-0000-0000-000000389004', 'ruta', fn_hoy_lima() - 10, 10.00,
   '00000000-0000-0000-0000-000000389004', null, null, null, null, null, null, null, null);

-- ── 1 · El criterio ────────────────────────────────────────────────────────
select is(fn_ruta_por_renovar(fn_hoy_lima() - 10, now(), null, false), 'incompleta',
  'INCOMPLETA · firma digital sin costo de pasaje (la versión corta de la 0425/0426)');
select is(fn_ruta_por_renovar(fn_hoy_lima() - 10, null, null, false), null,
  'PAPEL · el escaneo no tiene firma digital, y el papel siempre traía el pasaje: no es incompleta');
select is(fn_ruta_por_renovar((fn_hoy_lima() - interval '12 months')::date, now(), 2.50, false), 'vencida',
  'VENCIDA · el día que cumple 12 meses ya toca renovarla');
select is(fn_ruta_por_renovar((fn_hoy_lima() - interval '12 months')::date + 1, now(), 2.50, false), null,
  'AL DÍA · un día antes de cumplir el año, todavía no');
select is(fn_ruta_por_renovar(fn_hoy_lima() - 400, now(), null, true), null,
  'NEGATIVA · una negativa no se renueva: tiene su propio estado');

-- ── 2 · El tablero y el candado dicen lo mismo ─────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000389011', true);
select is((select ruta_por_renovar from fn_documentos_tablero(true)), 'incompleta',
  'TABLERO · a quien firmó la versión corta le avisa «incompleta»');
select lives_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,2.50) $$,
  'CANDADO · incompleta: puede volver a firmar sola, sin pedir revisión');
select is((select ruta_por_renovar from fn_documentos_tablero(true)), null,
  'RENOVADA · la firma nueva pasa a ser la vigente y el aviso desaparece');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000389012', true);
select is((select ruta_por_renovar from fn_documentos_tablero(true)), 'vencida',
  'TABLERO · a quien firmó hace más de un año le avisa «vencida»');
select lives_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,2.50) $$,
  'CANDADO · vencida: puede volver a firmar sola');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000389013', true);
select throws_ok(
  $$ select fn_confirmar_mi_declaracion_ruta('Trujillo','Trujillo',1,1,2.50) $$,
  'P0001',
  'Ya tienes una declaración de ruta firmada y vigente. Si algo cambió, pide una revisión en vez de volver a firmar.',
  'CANDADO · al día y completa: sigue cerrado, como desde la 0425');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000389014', true);
select is((select ruta_por_renovar from fn_documentos_tablero(true)), null,
  'PAPEL · el tablero no le pide renovar a quien firmó en papel hace poco');

-- ── 3 · La planilla no se entera ───────────────────────────────────────────
-- La misma pregunta que hace fn_planilla_calcular_nucleo (0491, «decl»): si
-- existe una declaración firmada, no anulada y no negativa. La vencida de
-- «Vieja» ya se renovó arriba; la de hace 400 días sigue ahí, sin anular, y
-- con ella sola tiene que bastar — se comprueba sobre esa fila puntual.
select ok(
  exists (select 1 from documentos_firmados d
           where d.tipo = 'ruta' and d.persona_id = '00000000-0000-0000-0000-000000389002'
             and d.anulado_at is null and not d.es_negativa
             and d.fecha_firma = fn_hoy_lima() - 400)
  and not exists (select 1 from pg_proc
                   where proname = 'fn_planilla_calcular_nucleo'
                     and prosrc like '%fn_ruta_por_renovar%'),
  'PAGO · una declaración por renovar sigue contando para la planilla, y la planilla no usa el criterio nuevo');

select * from finish();
rollback;
