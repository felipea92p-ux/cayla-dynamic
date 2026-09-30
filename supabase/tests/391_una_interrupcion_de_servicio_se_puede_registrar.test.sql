-- ============================================================================
-- 391_una_interrupcion_de_servicio_se_puede_registrar.test.sql
-- ============================================================================
-- El caso que motivó la 0497, con fechas INVENTADAS (las reales de una persona no
-- se commitean): ingresó el 15/01/2025 y estuvo 71 días fuera (02/06 → 11/08/2025).
-- Cuenta que se comprueba a mano: 15/01/2025 + 71 días = 27/03/2025 (enero 31 →
-- +16, febrero 28 → +44, marzo 27 → +71).
--
-- Lo que esta prueba defiende, en el orden en que importa:
--   · el interruptor nace APAGADO y con él apagado nada cambia (regla legal sin
--     confirmar: no se decide en una migración);
--   · con él encendido cuenta SOLO lo aprobado y no anulado, y SOLO de un tipo
--     que suspenda (un permiso personal o «estudios» no recortan el año);
--   · los dos estados imposibles lo son en el esquema, no en una validación;
--   · el conteo se recorta a la ventana que se pregunta;
--   · las dos funciones son internas: `authenticated` no puede ejecutarlas.
-- ============================================================================
begin;
select plan(23);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000004a0', 'ZZIS1', 'Sede interrupción 1', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000004a1', 'InterrupcionDO', 'Laboratorio',
   '00000000-0000-0000-0000-0000000004a0', 'x', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000004a2', 'InterrupcionFuera', 'Laboratorio',
   '00000000-0000-0000-0000-0000000004a0', 'x', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004a3', 'InterrupcionSinNada', 'Laboratorio',
   '00000000-0000-0000-0000-0000000004a0', 'x', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004a4', 'InterrupcionTodoElTiempo', 'Laboratorio',
   '00000000-0000-0000-0000-0000000004a0', 'x', '2025-01-15', 'planilla');

-- ── 1 · El tipo existe, con sus interruptores, y el de suspender NACE APAGADO ─
select is(
  (select row(paga, requiere_documento, requiere_aprobacion, descuenta_vacaciones, suspende_record)::text
     from tipos_ausencia where codigo = 'licencia_sin_goce'),
  '(f,f,t,f,f)',
  'EL TIPO · no paga, no pide documento, SÍ pide aprobación, no gasta saldo y suspende_record nace APAGADO');

select is(
  (select count(*)::int from tipos_ausencia where suspende_record),
  0,
  'APAGADO · al pegar la migración ningún tipo suspende: nada cambia hasta que el laboralista responda');

-- ── 2 · Los dos estados imposibles lo son en el esquema ─────────────────────
select throws_ok(
  $$update tipos_ausencia set suspende_record = true where codigo = 'licencia_con_goce'$$,
  '23514', null,
  'IMPOSIBLE 1 · un tipo que PAGA no puede suspender el año: un día pagado es un día de servicio');

select throws_ok(
  $$update tipos_ausencia set suspende_record = true where codigo = 'vacaciones'$$,
  '23514', null,
  'IMPOSIBLE 2 · vacaciones no pueden suspender el año: gastan saldo, no tiempo de servicio');

-- ── 3 · Con el interruptor APAGADO, ni una licencia aprobada cuenta ─────────
-- Aprobada a propósito: si bastara con registrarla, «apagado» no significaría nada.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at) values
  ('00000000-0000-0000-0000-0000000004a2', 'licencia_sin_goce', '2025-06-02', '2025-08-11',
   'acuerdo', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004a1', now());

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-01-15', '2025-12-31'),
  0,
  'APAGADO · una licencia sin goce APROBADA y registrada no cuenta mientras el interruptor esté apagado');

select is(
  fn_fecha_ingreso_efectiva('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-12-31'),
  '2025-01-15'::date,
  'APAGADO · la fecha efectiva es exactamente la de ingreso: nadie ve un cambio');

-- ── 4 · Se enciende con UNA línea, sin migración, y lo ya registrado cuenta ─
update tipos_ausencia set suspende_record = true where codigo = 'licencia_sin_goce';

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-01-15', '2025-12-31'),
  71,
  'ENCENDIDO · los 71 días (02/06 → 11/08, ambos inclusive) cuentan, sin volver a registrar nada');

select is(
  fn_fecha_ingreso_efectiva('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-12-31'),
  '2025-03-27'::date,
  'ENCENDIDO · 15/01/2025 + 71 días = 27/03/2025: el año de servicio se corre lo que estuvo fuera');

select is(
  fn_fecha_ingreso_efectiva('00000000-0000-0000-0000-0000000004a3'::uuid, '2025-12-31'),
  '2025-01-15'::date,
  'SIN NADA · quien no tiene ninguna interrupción conserva su fecha de ingreso EXACTA');

-- ── 5 · El conteo se recorta a lo que se pregunta ───────────────────────────
select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-08-01', '2025-12-31'),
  11,
  'VENTANA · desde el 01/08 solo cuentan del 01/08 al 11/08 = 11');

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-01-15', '2025-06-10'),
  9,
  'VENTANA · hasta el 10/06 cuentan del 02/06 al 10/06 = 9 (una interrupción en curso cuenta hasta hoy)');

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-08-12', '2025-12-31'),
  0,
  'VENTANA · una ventana posterior a la licencia no cuenta nada');

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-12-31', '2025-01-15'),
  0,
  'VENTANA · fechas al revés dan 0, no negativos');

-- ── 6 · Una interrupción EN CURSO cuenta hasta la fecha que se pregunta ─────
-- Preguntada el 15/06 —dentro de la licencia— solo han pasado 14 días de ella
-- (02/06 → 15/06): la fecha efectiva se corre 14, no los 71 que durará entera.
select is(
  fn_fecha_ingreso_efectiva('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-06-15'),
  '2025-01-29'::date,
  'EN CURSO · el 15/06 lleva 14 días fuera: 15/01/2025 + 14 = 29/01/2025');

-- ── 7 · Nunca servicio negativo ─────────────────────────────────────────────
-- Estuvo fuera desde el mismo día de su ingreso. El 10/03 lleva 55 días fuera y
-- 55 de calendario: 15/01 + 55 = 11/03, que sería POSTERIOR a la fecha que se
-- pregunta. Sin el tope, age() daría años negativos.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at) values
  ('00000000-0000-0000-0000-0000000004a4', 'licencia_sin_goce', '2025-01-15', '2025-05-31',
   'acuerdo', '00000000-0000-0000-0000-0000000004a1',
   '00000000-0000-0000-0000-0000000004a1', now());

select is(
  fn_fecha_ingreso_efectiva('00000000-0000-0000-0000-0000000004a4'::uuid, '2025-03-10'),
  '2025-03-10'::date,
  'TOPE · quien estuvo fuera todo el tiempo tiene cero servicio, no negativo: la fecha efectiva se queda en la pregunta');

select is(
  fn_fecha_ingreso_efectiva('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-01-01'),
  '2025-01-15'::date,
  'ANTES DEL INGRESO · devuelve la fecha de ingreso (los que llaman ya cortan antes con «todavía no ingresaba»)');

-- ── 8 · Solo cuenta lo APROBADO, NO ANULADO y de un tipo que SUSPENDA ───────
-- Tres ausencias de otra persona, una por cada forma de NO contar.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at, anulada_at, anulada_por, anulada_motivo) values
  -- anulada: aprobada, pero anulada con motivo.
  ('00000000-0000-0000-0000-0000000004a3', 'licencia_sin_goce', '2025-03-01', '2025-03-10', 'x',
   '00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000004a1', now(),
   now(), '00000000-0000-0000-0000-0000000004a1', 'error de digitación');
-- pendiente: registrada, nadie la aprobó todavía (aprobada_at nulo).
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-0000000004a3', 'licencia_sin_goce', '2025-04-01', '2025-04-10', 'x',
   '00000000-0000-0000-0000-0000000004a1');
-- de otro tipo: unos estudios NO suspenden, aunque tampoco paguen.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at) values
  ('00000000-0000-0000-0000-0000000004a3', 'estudios', '2025-05-05', '2025-05-15', 'x',
   '00000000-0000-0000-0000-0000000004a1', '00000000-0000-0000-0000-0000000004a1', now());

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a3'::uuid, '2025-01-15', '2025-12-31'),
  0,
  'NO CUENTAN · ni la anulada, ni la pendiente de aprobar, ni unos estudios (que no suspenden)');

-- Al aprobar la pendiente, empieza a contar; al anular la aprobada, deja de hacerlo.
update ausencias set aprobada_at = now(), aprobada_por = '00000000-0000-0000-0000-0000000004a1'
 where persona_id = '00000000-0000-0000-0000-0000000004a3' and fecha_inicio = '2025-04-01';

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a3'::uuid, '2025-01-15', '2025-12-31'),
  10,
  'APROBAR · la pendiente pasa a contar en cuanto alguien la aprueba (01/04 → 10/04 = 10)');

update ausencias set anulada_at = now(), anulada_por = '00000000-0000-0000-0000-0000000004a1', anulada_motivo = 'error de digitación'
 where persona_id = '00000000-0000-0000-0000-0000000004a3' and fecha_inicio = '2025-04-01';

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a3'::uuid, '2025-01-15', '2025-12-31'),
  0,
  'ANULAR · anulada con motivo, deja de contar');

-- ── 9 · Apagar el interruptor apaga el efecto, sin tocar los datos ──────────
update tipos_ausencia set suspende_record = false where codigo = 'licencia_sin_goce';

select is(
  fn_dias_suspendidos('00000000-0000-0000-0000-0000000004a2'::uuid, '2025-01-15', '2025-12-31'),
  0,
  'REVERSIBLE · apagado otra vez, la licencia sigue registrada pero deja de contar');

-- ── 10 · Ninguna de las dos es ejecutable por un cliente ─────────────────────
select is(
  (has_function_privilege('authenticated', 'fn_dias_suspendidos(uuid,date,date)', 'execute')
   or has_function_privilege('anon', 'fn_dias_suspendidos(uuid,date,date)', 'execute')),
  false,
  'INTERNA · fn_dias_suspendidos no la ejecuta ni authenticated ni anon');

select is(
  (has_function_privilege('authenticated', 'fn_fecha_ingreso_efectiva(uuid,date)', 'execute')
   or has_function_privilege('anon', 'fn_fecha_ingreso_efectiva(uuid,date)', 'execute')),
  false,
  'INTERNA · fn_fecha_ingreso_efectiva no la ejecuta ni authenticated ni anon');

-- ── 11 · Volver a pegar la migración no pisa el interruptor ─────────────────
update tipos_ausencia set suspende_record = true where codigo = 'licencia_sin_goce';
insert into tipos_ausencia
  (codigo, nombre, paga, requiere_documento, requiere_aprobacion,
   descuenta_vacaciones, suspende_record, alerta_desde, ventana_alerta_dias, orden)
values ('licencia_sin_goce', 'Licencia sin goce de haber', false, false, true, false, false, null, null, 65)
on conflict (codigo) do nothing;

select is(
  (select suspende_record from tipos_ausencia where codigo = 'licencia_sin_goce'),
  true,
  'IDEMPOTENTE · repegar el insert (do nothing) NO apaga un interruptor que alguien ya encendió');

select * from finish();
rollback;
