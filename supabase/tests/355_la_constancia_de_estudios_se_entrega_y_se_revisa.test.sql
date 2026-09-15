-- ============================================================================
-- 355_la_constancia_de_estudios_se_entrega_y_se_revisa.test.sql
-- ============================================================================
-- Lo que promete la 0450, contado desde las dos puntas:
--   · la integrante envía, retira, corrige y reenvía SU constancia, y no ve ni
--     toca la de nadie más;
--   · DO aprueba o rechaza, con motivo, y nadie aprueba lo propio;
--   · una constancia pendiente o rechazada NUNCA enciende el pago — solo una
--     aprobada (decisión «solo alerta»);
--   · lo revisado no se reescribe ni se borra;
--   · una corrección de la asignación no deja a la vigencia nueva sin sustento.
--
-- Las fechas se anclan a fn_hoy_lima(): una fecha fija caduca el día que el
-- reloj real la pasa (le pasó a la 226).
-- ============================================================================
begin;
select plan(66);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000450a00', 'ZZ450', 'Sede de laboratorio 450', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  -- DO que revisa
  ('00000000-0000-0000-0000-000000450d01', 'EduDO', 'Laboratorio',
   '00000000-0000-0000-0000-000000450a00', 'lider_do', 'test-hash',
   '00000000-0000-0000-0000-000000450f01', '2020-01-01'),
  -- Ana, la que estudia
  ('00000000-0000-0000-0000-000000450d02', 'EduAna', 'Laboratorio',
   '00000000-0000-0000-0000-000000450a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000450f02', '2025-01-02'),
  -- Bea, una compañera sin nada que ver
  ('00000000-0000-0000-0000-000000450d03', 'EduBea', 'Laboratorio',
   '00000000-0000-0000-0000-000000450a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000450f03', '2025-01-02'),
  -- La otra persona de DO
  ('00000000-0000-0000-0000-000000450d04', 'EduAdmin', 'Laboratorio',
   '00000000-0000-0000-0000-000000450a00', 'admin', 'test-hash',
   '00000000-0000-0000-0000-000000450f04', '2020-01-01');
set session_replication_role = origin;

-- A1: el estudio de Ana, sin ningún papel todavía (no cobra).
insert into asignaciones_educacion
  (id, persona_id, monto, institucion, costo_declarado, cobertura_pct, beneficiario,
   vigente_desde, vigente_hasta, registrado_por)
values
  ('00000000-0000-0000-0000-000000450b01', '00000000-0000-0000-0000-000000450d02',
   90, 'UPN de laboratorio', 120, 75, 'trabajador',
   fn_hoy_lima() - 30, fn_hoy_lima() + 200, '00000000-0000-0000-0000-000000450d01'),
-- A2: un estudio de la propia DO.
  ('00000000-0000-0000-0000-000000450b02', '00000000-0000-0000-0000-000000450d01',
   90, 'Curso de la DO', 120, 75, 'trabajador',
   fn_hoy_lima() - 30, fn_hoy_lima() + 200, '00000000-0000-0000-0000-000000450d04');

-- Lo que el almacén dice de cada archivo. El tipo y el peso se validan contra
-- esto, no contra lo que declara el navegador.
insert into storage.objects (bucket_id, name, metadata) values
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e001/p1.jpg', '{"mimetype":"image/jpeg","size":1000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e001/p2.pdf', '{"mimetype":"application/pdf","size":2000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e003/foto.webp', '{"mimetype":"image/webp","size":1000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e033/grande.pdf', '{"mimetype":"application/pdf","size":20000000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e004/r.jpg', '{"mimetype":"image/jpeg","size":1000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e005/s.jpg', '{"mimetype":"image/jpeg","size":1000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d01/entregas/00000000-0000-0000-0000-00000450e006/d.pdf', '{"mimetype":"application/pdf","size":1000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e007/do.pdf', '{"mimetype":"application/pdf","size":1000}');

-- Dos periodos lejanos para medir el plazo sin chocar con los reales.
insert into periodos_planilla (fecha_ini, fecha_fin, estado, pagado_at) values
  ('2031-01-01', '2031-01-30', 'pagado', now()),
  ('2031-01-31', '2031-03-01', 'pagado', now());


-- ── 1 · Esquema ─────────────────────────────────────────────────────────────
select has_table('educacion_entregas', 'ESQUEMA · existe la tabla de entregas');

select is(
  (select familia_id from asignaciones_educacion where id = '00000000-0000-0000-0000-000000450b01'),
  '00000000-0000-0000-0000-000000450b01'::uuid,
  'FAMILIA · una asignación nueva es su propia familia');


-- ── 2 · Ana envía ───────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f02', true);
set local role authenticated;

select lives_ok($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e001', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima(), 'cuota_mensual', fn_hoy_lima() + 30,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e001/p1.jpg","nombre":"Página 1.jpg"},
      {"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e001/p2.pdf","nombre":"Anexo.pdf"}]'::jsonb) $$,
  'ENVIAR · Ana envía su constancia con dos archivos');

select is((select estado from educacion_entregas where id = '00000000-0000-0000-0000-00000450e001'),
  'pendiente', 'ENVIAR · lo que envía la interesada queda pendiente de revisión');

select is((select count(*)::int from educacion_entrega_archivos where entrega_id = '00000000-0000-0000-0000-00000450e001'),
  2, 'ENVIAR · una entrega, dos archivos');

select is((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000450b01'),
  null, 'SOLO ALERTA · una constancia pendiente NO enciende el pago');

select throws_like($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e002', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima(), 'cuota_mensual', null,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e002/x.jpg"}]'::jsonb) $$,
  '%pendiente%', 'ENVIAR · no hay dos constancias pendientes para el mismo pago');

select throws_like($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e003', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima() - 1, 'cuota_mensual', null,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e003/foto.webp","nombre":"foto.webp"}]'::jsonb) $$,
  '%PDF, JPG ni PNG%', 'ARCHIVO · un formato fuera de PDF, JPG o PNG se rechaza, según el almacén');

select throws_like($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e033', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima() - 1, 'cuota_mensual', null,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e033/grande.pdf","nombre":"grande.pdf"}]'::jsonb) $$,
  '%10 MB%', 'ARCHIVO · más de 10 MB se rechaza');

select throws_like($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e008', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima() - 1, 'cuota_mensual', null,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e001/p1.jpg","nombre":"ajeno.jpg"}]'::jsonb) $$,
  '%carpeta de este envío%', 'ARCHIVO · no se puede colgar el archivo de otro envío');

select throws_like($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e009', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima() + 3, 'cuota_mensual', null, '[{"ruta":"x"}]'::jsonb) $$,
  '%todavía no llega%', 'FECHA · la constancia de un pago que aún no ocurre no se sube');

select throws_like($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e010', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima() - 2, 'cuota_mensual', null,
    (select jsonb_agg(jsonb_build_object('ruta', 'r' || g)) from generate_series(1, 11) g)) $$,
  '%hasta 10 archivos%', 'ARCHIVO · una entrega admite hasta 10 archivos');

select throws_like($$
  select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e001', true) $$,
  '%Solo Desarrollo Organizacional%', 'PERMISO · la integrante no aprueba');

select is(
  (select estado_constancia from fn_educacion_situacion()),
  'pendiente_revision', 'SITUACIÓN · Ana ve su estudio pendiente de revisión');

select lives_ok($$ select fn_educacion_retirar_entrega('00000000-0000-0000-0000-00000450e001') $$,
  'RETIRAR · mientras está pendiente, Ana puede retirarla');

select throws_like($$ select fn_educacion_retirar_entrega('00000000-0000-0000-0000-00000450e001') $$,
  '%retirada%', 'RETIRAR · lo retirado no se vuelve a retirar');

select is((select count(*)::int from educacion_entregas where id = '00000000-0000-0000-0000-00000450e001'),
  1, 'RETIRAR · retirar no borra: la entrega sigue en el historial');


-- ── 3 · Bea, que no tiene nada que ver ──────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f03', true);

select throws_like($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e011', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima(), 'otro', null, '[{"ruta":"x"}]'::jsonb) $$,
  '%Solo la propia integrante%', 'PERMISO · una compañera no envía por Ana');

select is((select count(*)::int from educacion_entregas), 0,
  'RLS · una compañera no ve las constancias de Ana');

select is((select count(*)::int from educacion_entrega_archivos), 0,
  'RLS · ni sus archivos');

select is((select count(*)::int from fn_educacion_situacion()), 0,
  'RLS · ni su estudio en la situación');

select is(fn_educacion_puede_subir_entrega(
    'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e099/x.jpg'),
  false, 'ALMACÉN · una compañera no puede subir a la carpeta de Ana');


-- ── 4 · Ana reenvía; DO rechaza; Ana corrige; DO aprueba ────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f02', true);

select is(fn_educacion_puede_subir_entrega(
    'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e099/x.jpg'),
  true, 'ALMACÉN · Ana sí sube a su carpeta, para un envío que todavía no existe');

select lives_ok($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e004', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima(), 'cuota_mensual', fn_hoy_lima() + 30,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e004/r.jpg","nombre":"r.jpg"}]'::jsonb) $$,
  'ENVIAR · Ana vuelve a enviar');

select is(fn_educacion_puede_subir_entrega(
    'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e004/otro.jpg'),
  false, 'ALMACÉN · una vez enviada, esa carpeta ya no acepta archivos');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f01', true);

select throws_like($$
  select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e004', false, 'ilegible', null) $$,
  '%qué tiene que corregir%', 'RECHAZO · sin comentario no se rechaza');

select throws_like($$
  select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e004', false, 'ilegible', 'no') $$,
  '%qué tiene que corregir%', 'RECHAZO · el comentario tiene al menos 3 caracteres');

select throws_like($$
  select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e004', false, null, 'no se lee') $$,
  '%motivo del rechazo%', 'RECHAZO · sin categoría no se rechaza');

select lives_ok($$
  select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e004', false, 'ilegible', 'No se lee la fecha del pago') $$,
  'RECHAZO · con categoría y comentario sí');

select is((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000450b01'),
  null, 'SOLO ALERTA · una constancia rechazada tampoco enciende el pago');

select is((select estado_constancia from fn_educacion_situacion() where asignacion_id = '00000000-0000-0000-0000-000000450b01'),
  'rechazada', 'SITUACIÓN · el estudio de Ana queda en «rechazada»');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f02', true);

select lives_ok($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e005', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima(), 'cuota_mensual', fn_hoy_lima() + 30,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e005/s.jpg","nombre":"s.jpg"}]'::jsonb,
    null, '00000000-0000-0000-0000-00000450e004') $$,
  'CORREGIR · Ana corrige la rechazada con un envío nuevo');

select is((select reemplaza_a from educacion_entregas where id = '00000000-0000-0000-0000-00000450e005'),
  '00000000-0000-0000-0000-00000450e004'::uuid, 'CORREGIR · el envío nuevo dice a cuál corrige');

select is((select estado from educacion_entregas where id = '00000000-0000-0000-0000-00000450e004'),
  'rechazada', 'CORREGIR · y la rechazada sigue rechazada en el historial');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f01', true);

select lives_ok($$ select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e005', true) $$,
  'APROBAR · DO aprueba');

select isnt((select comprobante_url from asignaciones_educacion where id = '00000000-0000-0000-0000-000000450b01'),
  null, 'APROBAR · solo una constancia aprobada enciende el espejo que lee la planilla');

select is((select proxima_fecha_pago from asignaciones_educacion where id = '00000000-0000-0000-0000-000000450b01'),
  fn_hoy_lima() + 30, 'CALENDARIO · aprobar avanza la próxima fecha de pago a la que declaró Ana');

select is((select estado_constancia from fn_educacion_situacion() where asignacion_id = '00000000-0000-0000-0000-000000450b01'),
  'al_dia', 'SITUACIÓN · con el próximo pago en el futuro, el estudio está al día');

select throws_like($$ select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e005', false, 'otro', 'otra vez') $$,
  '%ya está aprobada%', 'CONCURRENCIA · lo ya revisado no se vuelve a revisar');


-- ── 5 · Lo revisado no se toca, ni siquiera por debajo ──────────────────────
reset role;

select throws_like($$ update educacion_entregas set nota = 'retocada' where id = '00000000-0000-0000-0000-00000450e005' $$,
  '%no se reescribe%', 'INMUTABLE · lo que se envió no se reescribe');

select throws_like($$ update educacion_entregas set estado = 'rechazada', motivo_categoria = 'otro', motivo_comentario = 'cambio'
                       where id = '00000000-0000-0000-0000-00000450e005' $$,
  '%su revisión no se cambia%', 'INMUTABLE · una aprobada no pasa a rechazada');

select throws_like($$ delete from educacion_entregas where id = '00000000-0000-0000-0000-00000450e005' $$,
  '%no se borra%', 'INMUTABLE · una entrega no se borra');

select throws_like($$ delete from educacion_entrega_archivos where entrega_id = '00000000-0000-0000-0000-00000450e005' $$,
  '%no se cambia ni se borra%', 'INMUTABLE · sus archivos tampoco');

select ok(fn_educacion_ruta_congelada(
    'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e005/s.jpg'),
  'ALMACÉN · el archivo de una constancia enviada queda congelado, también para DO');


-- ── 6 · El plazo sale de los periodos, no del calendario ────────────────────
select is(fn_educacion_plazo('2031-01-10'), '2031-01-25'::date,
  'PLAZO · cinco días antes del cierre del periodo en que cae el pago');

select is(fn_educacion_plazo('2031-01-28'), '2031-02-24'::date,
  'PLAZO · si el pago cae después de ese día, el plazo pasa al periodo siguiente');

select is(fn_educacion_plazo('2035-06-01'), null::date,
  'PLAZO · sin periodo creado, el plazo queda por confirmar');


-- ── 7 · Un pago que ya llegó sin constancia ─────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f01', true);
set local role authenticated;

select lives_ok($$ select fn_educacion_fijar_calendario('00000000-0000-0000-0000-000000450b01', 'mensual', fn_hoy_lima() - 1) $$,
  'CALENDARIO · DO fija un pago que ya ocurrió');

-- El estado se compara contra la misma regla aplicada al plazo real de hoy: los
-- periodos de la base local y los de CI no son los mismos.
select is(
  (select estado_constancia from fn_educacion_situacion() where asignacion_id = '00000000-0000-0000-0000-000000450b01'),
  (select case when p is null then 'falta_enviar'
               when p < fn_hoy_lima() then 'vencida'
               when p - fn_hoy_lima() <= 7 then 'por_vencer'
               else 'falta_enviar' end
     from (select fn_educacion_plazo(fn_hoy_lima() - 1) as p) x),
  'SITUACIÓN · un pago pasado sin constancia se mide contra su plazo');


-- ── 8 · Nadie aprueba lo propio; DO carga a nombre de otra ──────────────────
select lives_ok($$
  select fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e006', '00000000-0000-0000-0000-000000450b02',
    fn_hoy_lima(), 'curso_taller', null,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d01/entregas/00000000-0000-0000-0000-00000450e006/d.pdf"}]'::jsonb) $$,
  'PROPIO · la DO envía la constancia de su propio curso');

select throws_like($$ select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e006', true) $$,
  '%propia constancia%', 'PROPIO · y no la puede aprobar ella misma');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f04', true);
select lives_ok($$ select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e006', true) $$,
  'PROPIO · la aprueba la otra persona de DO');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f01', true);
select is(
  fn_educacion_enviar_entrega(
    '00000000-0000-0000-0000-00000450e007', '00000000-0000-0000-0000-000000450b01',
    fn_hoy_lima(), 'otro', null,
    '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e007/do.pdf"}]'::jsonb),
  '00000000-0000-0000-0000-00000450e007'::uuid,
  'A NOMBRE · DO carga la constancia de Ana');
select is((select estado || '/' || origen from educacion_entregas where id = '00000000-0000-0000-0000-00000450e007'),
  'aprobada/do', 'A NOMBRE · lo que carga DO queda aprobado, con su origen dicho');


-- ── 9 · «Ya no voy a pagar» ────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f03', true);
select throws_like($$ select fn_educacion_avisar_fin('00000000-0000-0000-0000-000000450b01', 'no es mío') $$,
  '%propia integrante%', 'AVISO · una compañera no avisa por Ana');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f02', true);
select lives_ok($$ select fn_educacion_avisar_fin('00000000-0000-0000-0000-000000450b01', 'Conseguí una beca completa') $$,
  'AVISO · Ana avisa que deja de pagar');
select throws_like($$ select fn_educacion_avisar_fin('00000000-0000-0000-0000-000000450b01', 'otra vez') $$,
  '%Ya avisaste%', 'AVISO · no se duplica mientras DO no lo atiende');

-- EL CONTADOR del menú contra las listas que abre. Si se separan, el número
-- rojo miente.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f01', true);
select is(
  fn_educacion_por_atender(),
  (select count(*)::int from fn_educacion_entregas_pendientes())
  + (select count(*)::int from fn_educacion_situacion()
      where estado_constancia = 'vencida'
         or (estado_constancia = 'sin_calendario' and vigencia in ('vigente', 'por_terminar')))
  + (select count(*)::int from fn_educacion_avisos_fin_pendientes()),
  'EL CONTADOR · dice lo mismo que las listas que abre');

select lives_ok($$ select fn_bandeja_marcar_visto('entrega_educacion', '00000000-0000-0000-0000-00000450e005') $$,
  'BANDEJA · una entrega de educación se puede marcar como vista');


-- ── 10 · Corregir la asignación no le quita el sustento ─────────────────────
select lives_ok($$
  select set_config('prueba.a3', fn_educacion_registrar(
    '00000000-0000-0000-0000-000000450d02'::uuid, 'Curso corto de laboratorio', 100::numeric,
    'trabajador', fn_hoy_lima(), fn_hoy_lima() + 100)::text, true) $$,
  'FAMILIA · DO registra un segundo estudio de Ana');

reset role;
insert into storage.objects (bucket_id, name, metadata) values
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e012/c.pdf', '{"mimetype":"application/pdf","size":1000}');
set local role authenticated;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f02', true);
select fn_educacion_enviar_entrega(
  '00000000-0000-0000-0000-00000450e012', current_setting('prueba.a3')::uuid,
  fn_hoy_lima(), 'pago_ciclo', null,
  '[{"ruta":"educacion/00000000-0000-0000-0000-000000450d02/entregas/00000000-0000-0000-0000-00000450e012/c.pdf"}]'::jsonb);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f01', true);
select fn_educacion_resolver_entrega('00000000-0000-0000-0000-00000450e012', true);

select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-000000450d02'::uuid, 'Curso corto de laboratorio', 140::numeric,
    'trabajador', fn_hoy_lima(), fn_hoy_lima() + 100, null, null, null,
    current_setting('prueba.a3')::uuid, 'el comprobante decía 140') $$,
  'FAMILIA · DO corrige el costo: se abre una vigencia nueva');

reset role;
select isnt(
  (select a.comprobante_url from asignaciones_educacion a
    where a.familia_id = current_setting('prueba.a3')::uuid
    order by a.vigente_desde desc, a.id desc limit 1),
  null, 'FAMILIA · la vigencia nueva sigue sustentada por la constancia aprobada');

select is(
  (select count(*)::int from educacion_entregas e join asignaciones_educacion a on a.id = e.asignacion_id
    where a.familia_id = current_setting('prueba.a3')::uuid),
  1, 'FAMILIA · y la constancia no se duplicó al corregir');

select lives_ok($$ set constraints all immediate $$,
  'FAMILIA · ninguna entrega quedó colgando de una vigencia borrada');


-- ── 11 · La puerta de la 0290 y lo que ya no se hace ────────────────────────
insert into educacion_comprobantes (id, asignacion_id, storage_path, mes_cubierto, subido_por)
values ('00000000-0000-0000-0000-00000450c001', '00000000-0000-0000-0000-000000450b02',
        'educacion/00000000-0000-0000-0000-000000450d01/viejo.pdf', date_trunc('month', fn_hoy_lima())::date,
        '00000000-0000-0000-0000-000000450d04');

select is((select estado || '/' || origen from educacion_entregas where id = '00000000-0000-0000-0000-00000450c001'),
  'aprobada/do', 'PUERTA · un papel que entra por la tabla de la 0290 queda como entrega aprobada, con el mismo id');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000450f01', true);
set local role authenticated;
select throws_like($$ select fn_educacion_quitar_comprobante('00000000-0000-0000-0000-00000450c001', 'se subió mal') $$,
  '%no se quita%', 'PUERTA · quitar un comprobante aprobado se niega, con la explicación');
reset role;


select * from finish();
rollback;
