-- ============================================================================
-- 424_un_pago_adelantado_cubre_varios_meses.test.sql
-- ============================================================================
-- Lo que promete la 0529:
--   · un pago adelantado se envía con sus meses (calendario, seguidos, con monto,
--     y con motivo si se corrigió) y queda por revisar como cualquier constancia;
--   · aprobado UNA vez, el calendario salta al pago siguiente al último mes
--     cubierto (mismo día del mes, o el último día si ese mes es más corto) y el
--     pago se enciende por el espejo de siempre; solo hacia adelante;
--   · lo enviado no se reescribe: ni los meses ni la cobertura;
--   · DO lo puede cargar a nombre de alguien, y nace aprobado;
--   · cada quien ve solo sus meses; lo pagado de la planilla solo lo ve DO;
--   · el historial cuenta los hechos, y a la integrante no le da nombres de DO
--     ni los motivos internos.
--
-- Las fechas se anclan a fn_hoy_lima(), salvo las que miden el borde del mes
-- (31 de enero): una fecha fija del pasado no caduca.
-- ============================================================================
begin;
select plan(50);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000529a00', 'ZZ529', 'Sede de laboratorio 529', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000529d01', 'AdeDO',  'Laboratorio', '00000000-0000-0000-0000-000000529a00', 'lider_do',   'test-hash', '00000000-0000-0000-0000-000000529f01', '2020-01-01'),
  ('00000000-0000-0000-0000-000000529d02', 'AdeAna', 'Laboratorio', '00000000-0000-0000-0000-000000529a00', 'integrante', 'test-hash', '00000000-0000-0000-0000-000000529f02', '2024-01-02'),
  ('00000000-0000-0000-0000-000000529d03', 'AdeBea', 'Laboratorio', '00000000-0000-0000-0000-000000529a00', 'integrante', 'test-hash', '00000000-0000-0000-0000-000000529f03', '2024-01-02');
set session_replication_role = origin;

insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por, frecuencia_pago, proxima_fecha_pago)
values
  -- Ana: un estudio que empezó hace tiempo, sin papel todavía (no cobra).
  ('00000000-0000-0000-0000-000000529b01', '00000000-0000-0000-0000-000000529d02',
   90, 'UPN de laboratorio', 120, 75, 'trabajador', '2025-12-01', fn_hoy_lima() + 300,
   '00000000-0000-0000-0000-000000529d01', 'mensual', null),
  -- Bea: el que le carga DO.
  ('00000000-0000-0000-0000-000000529b02', '00000000-0000-0000-0000-000000529d03',
   90, 'Instituto de Bea', 120, 75, 'trabajador', fn_hoy_lima() - 90, fn_hoy_lima() + 300,
   '00000000-0000-0000-0000-000000529d01', 'mensual', null);

insert into storage.objects (bucket_id, name, metadata)
select 'comprobantes',
       'educacion/00000000-0000-0000-0000-000000529d0' || x.p || '/entregas/00000000-0000-0000-0000-00000529e' || x.e || '/r.jpg',
       '{"mimetype":"image/jpeg","size":1000}'
  from (values ('2','001'), ('2','002'), ('3','003')) as x(p, e);

-- Los meses de un envío, en el formato de la pantalla.
create function public.t424_meses(p_desde date, p_n int, p_monto numeric) returns jsonb
language sql as $f$
  select jsonb_agg(jsonb_build_object('mes', (p_desde + make_interval(months => i))::date, 'monto', p_monto, 'origen', 'calculado') order by i)
    from generate_series(0, p_n - 1) i
$f$;
create function public.t424_archivo(p_persona text, p_entrega text) returns jsonb
language sql as $f$
  select jsonb_build_array(jsonb_build_object(
    'ruta', 'educacion/00000000-0000-0000-0000-000000529d0' || p_persona || '/entregas/00000000-0000-0000-0000-00000529e' || p_entrega || '/r.jpg',
    'nombre', 'r.jpg'))
$f$;
grant execute on function public.t424_meses(date, int, numeric), public.t424_archivo(text, text) to authenticated;


-- ── 1 · Esquema ─────────────────────────────────────────────────────────────
select has_column('educacion_entregas', 'cubre_desde', 'ESQUEMA · la constancia sabe desde qué mes cubre');
select has_table('educacion_entrega_meses', 'ESQUEMA · y cada mes, con su monto');
select has_function('fn_educacion_enviar_adelantado', 'ESQUEMA · se envía con su propia función');


-- ── 2 · Ana envía: lo que no se acepta ──────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f02', true);

select throws_like($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e009', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual', t424_meses('2026-01-01', 1, 120), t424_archivo('2', '001')) $$,
  '%al menos dos meses%', 'MESES · un solo mes no es un pago adelantado');
select throws_like($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e009', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual', t424_meses('2026-01-01', 25, 120), t424_archivo('2', '001')) $$,
  '%como máximo 24%', 'MESES · más de 24 no');
select throws_like($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e009', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual',
    '[{"mes":"2026-01-01","monto":120,"origen":"calculado"},{"mes":"2026-03-01","monto":120,"origen":"calculado"}]', t424_archivo('2', '001')) $$,
  '%seguidos%', 'MESES · tienen que ser seguidos');
select throws_like($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e009', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual',
    '[{"mes":"2026-01-15","monto":120,"origen":"calculado"},{"mes":"2026-02-15","monto":120,"origen":"calculado"}]', t424_archivo('2', '001')) $$,
  '%día 1%', 'MESES · cada mes se indica por su día 1');
select throws_like($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e009', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual',
    '[{"mes":"2026-01-01","monto":180,"origen":"manual","motivo":"ab"},{"mes":"2026-02-01","monto":120,"origen":"calculado"}]', t424_archivo('2', '001')) $$,
  '%por qué%', 'MOTIVO · corregir un mes pide al menos 3 letras');
select throws_like($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e009', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual', t424_meses('2026-01-01', 3, 0), t424_archivo('2', '001')) $$,
  '%mayor que cero%', 'MONTO · el total no puede ser cero');
select throws_like($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e009', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual', t424_meses('2026-01-01', 3, 120), '[]') $$,
  '%al menos un archivo%', 'ARCHIVOS · sin recibo no se envía (lo exige el envío de siempre)');
reset role;
select is((select count(*)::int from educacion_entregas where id = '00000000-0000-0000-0000-00000529e009'), 0,
  'ATÓMICO · lo rechazado no deja ni la constancia');


-- ── 3 · Ana envía bien: enero a marzo, pagado el 31 de enero ─────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f02', true);
select lives_ok($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e001', '00000000-0000-0000-0000-000000529b01',
    '2026-01-31', 'cuota_mensual',
    '[{"mes":"2026-01-01","monto":180,"origen":"manual","motivo":"  incluye la matrícula "},
      {"mes":"2026-02-01","monto":110,"origen":"calculado"},
      {"mes":"2026-03-01","monto":110,"origen":"calculado"}]',
    t424_archivo('2', '001')) $$,
  'ENVIAR · Ana envía su pago adelantado de enero a marzo');
reset role;

select is((select estado from educacion_entregas where id = '00000000-0000-0000-0000-00000529e001'), 'pendiente',
  'ENVIAR · queda por revisar, como cualquier constancia');
select is((select cubre_desde || ' a ' || cubre_hasta from educacion_entregas where id = '00000000-0000-0000-0000-00000529e001'),
  '2026-01-01 a 2026-03-01', 'ENVIAR · sabe qué meses cubre');
select is((select proxima_fecha_pago from educacion_entregas where id = '00000000-0000-0000-0000-00000529e001'), '2026-04-30'::date,
  'CALENDARIO · el próximo pago es el mes siguiente al último cubierto; abril no tiene 31: el 30');
select is((select count(*)::int from educacion_entrega_meses where entrega_id = '00000000-0000-0000-0000-00000529e001'), 3,
  'MESES · una fila por mes');
select is((select motivo from educacion_entrega_meses where entrega_id = '00000000-0000-0000-0000-00000529e001' and mes = '2026-01-01'),
  'incluye la matrícula', 'MESES · el motivo de lo corregido, sin los espacios de los bordes');
select is((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000529b01'), null,
  'SOLO ALERTA · por revisar no enciende el pago');


-- ── 4 · Lo enviado no se reescribe ──────────────────────────────────────────
select throws_like($$ update educacion_entrega_meses set monto = 1 where entrega_id = '00000000-0000-0000-0000-00000529e001' $$,
  '%no se cambian%', 'INMUTABLE · los meses no se tocan');
select throws_like($$ delete from educacion_entrega_meses where entrega_id = '00000000-0000-0000-0000-00000529e001' $$,
  '%no se cambian%', 'INMUTABLE · ni se borran');
select throws_like($$ update educacion_entregas set cubre_hasta = '2026-06-01' where id = '00000000-0000-0000-0000-00000529e001' $$,
  '%no se cambian%', 'INMUTABLE · ni se estira la cobertura');
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f02', true);
select throws_like($$ insert into educacion_entrega_meses (entrega_id, mes, monto, origen) values ('00000000-0000-0000-0000-00000529e001', '2026-04-01', 1, 'calculado') $$,
  '%permission denied%', 'INMUTABLE · un cliente no escribe la tabla de meses');


-- ── 5 · Quién ve qué ────────────────────────────────────────────────────────
select is((select count(*)::int from fn_educacion_coberturas() where entrega_id = '00000000-0000-0000-0000-00000529e001'), 3,
  'VER · Ana ve sus meses');
select throws_like($$ select * from fn_educacion_apoyo_pagado(null) $$, '%Solo Desarrollo Organizacional%',
  'VER · lo pagado en la planilla, no');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f03', true);
select is((select count(*)::int from fn_educacion_coberturas() where entrega_id = '00000000-0000-0000-0000-00000529e001'), 0,
  'VER · Bea no ve los de Ana');
reset role;
set local role anon;
select throws_like($$ select * from fn_educacion_coberturas() $$, '%permission denied%', 'VER · sin sesión, nada');
reset role;


-- ── 6 · DO aprueba UNA vez ──────────────────────────────────────────────────
-- El calendario de Ana estaba en febrero: el pago adelantado se hizo ANTES de los meses que cubre.
update asignaciones_educacion set proxima_fecha_pago = '2026-02-28' where id = '00000000-0000-0000-0000-000000529b01';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f01', true);
select lives_ok($$ select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000529e001', true) $$,
  'APROBAR · DO aprueba el pago adelantado con la función de siempre');
select is((select count(*)::int from fn_educacion_coberturas() where entrega_id = '00000000-0000-0000-0000-00000529e001'), 3,
  'VER · DO ve los meses de todos');
reset role;

select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000529b01'), '2026-04-30'::date,
  'CALENDARIO · al aprobar salta al pago siguiente al último mes cubierto');
select isnt((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000529b01'), null,
  'PAGO · aprobado, el espejo de siempre enciende el pago');


-- ── 7 · Solo hacia adelante ─────────────────────────────────────────────────
-- DO fija a mano un pago posterior; un adelantado que llega después no lo retrasa.
update asignaciones_educacion set proxima_fecha_pago = '2026-12-15' where id = '00000000-0000-0000-0000-000000529b01';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f02', true);
select lives_ok($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e002', '00000000-0000-0000-0000-000000529b01',
    '2026-04-10', 'cuota_mensual', t424_meses('2026-04-01', 2, 110), t424_archivo('2', '002')) $$,
  'ENVIAR · un segundo pago adelantado, abril y mayo');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f01', true);
select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000529e002', true);
reset role;
select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000529b01'), '2026-12-15'::date,
  'CALENDARIO · nunca hacia atrás de lo que DO fijó');


-- ── 8 · DO lo carga a nombre de Bea ─────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f01', true);
select lives_ok($$ select fn_educacion_enviar_adelantado('00000000-0000-0000-0000-00000529e003', '00000000-0000-0000-0000-000000529b02',
    fn_hoy_lima() - 5, 'cuota_mensual', t424_meses(date_trunc('month', fn_hoy_lima())::date, 3, 120), t424_archivo('3', '003')) $$,
  'DO · carga el pago adelantado de Bea');
reset role;
select is((select estado from educacion_entregas where id = '00000000-0000-0000-0000-00000529e003'), 'aprobada',
  'DO · nace aprobado, como lo que DO carga a nombre de alguien');
select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000529b02'),
  (select proxima_fecha_pago from educacion_entregas where id = '00000000-0000-0000-0000-00000529e003'),
  'DO · y el calendario ya se movió al cargarlo');


-- ── 9 · Lo pagado en la planilla ────────────────────────────────────────────
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado, pagado_at) values
  ('00000000-0000-0000-0000-000000529c01', '2031-01-29', '2031-02-28', 'pagado', now());
insert into planilla_pagada_detalle (periodo_id, persona_id, version, origen, nombre, sede_codigo, pago_base, total, fila, monto_educacion, grupo) values
  ('00000000-0000-0000-0000-000000529c01', '00000000-0000-0000-0000-000000529d02', 1, 'pago', 'AdeAna Laboratorio', 'ZZ529', 910, 1000, '{}', 90, 'planilla'),
  ('00000000-0000-0000-0000-000000529c01', '00000000-0000-0000-0000-000000529d02', 2, 'pago', 'AdeAna Laboratorio', 'ZZ529', 920, 1000, '{}', 80, 'planilla');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f01', true);
select is((select monto from fn_educacion_apoyo_pagado('2031-01-01') where persona_id = '00000000-0000-0000-0000-000000529d02'),
  80.00::numeric, 'PLANILLA · cuenta la foto vigente (la de mayor versión), no la suma de versiones');
select is((select mes from fn_educacion_apoyo_pagado('2031-01-01') where persona_id = '00000000-0000-0000-0000-000000529d02'),
  '2031-02-01'::date, 'PLANILLA · el mes de un periodo es el de su cierre (29 ene – 28 feb = febrero)');
reset role;


-- ── 10 · El historial ───────────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f01', true);
select ok((select count(*) from fn_educacion_historial('00000000-0000-0000-0000-000000529d02')
            where fuente = 'envio' and entrega_id = '00000000-0000-0000-0000-00000529e001' and cubre_desde = '2026-01-01') = 1,
  'HISTORIAL · el envío trae los meses que cubre');
select ok((select count(*) from fn_educacion_historial('00000000-0000-0000-0000-000000529d02')
            where campo = 'educacion_entrega' and valor_anterior is null) = 0,
  'HISTORIAL · el envío no sale dos veces (su fila de auditoría se lee de la constancia)');
select ok((select bool_and(quien is not null) from fn_educacion_historial('00000000-0000-0000-0000-000000529d02')
            where fuente = 'auditoria'),
  'HISTORIAL · DO ve quién hizo cada cosa');
select ok((select count(*) from fn_educacion_historial(null) where persona_id = '00000000-0000-0000-0000-000000529d03') > 0
       and (select count(*) from fn_educacion_historial(null) where persona_id = '00000000-0000-0000-0000-000000529d02') > 0,
  'HISTORIAL · el general de DO trae a todas las personas');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000529f02', true);
select is((select count(*)::int from fn_educacion_historial('00000000-0000-0000-0000-000000529d03')
            where persona_id = '00000000-0000-0000-0000-000000529d03'), 0,
  'HISTORIAL · Ana pide el de Bea y no recibe nada de Bea (la base le da siempre el suyo)');
select ok((select count(*) from fn_educacion_historial()) > 0
       and (select bool_and(persona_id = '00000000-0000-0000-0000-000000529d02') from fn_educacion_historial()),
  'HISTORIAL · Ana ve el suyo');
select ok((select bool_and(quien is null) from fn_educacion_historial()), 'HISTORIAL · sin nombres de quién de DO lo hizo');
reset role;

select * from finish();
rollback;
