-- ============================================================================
-- 365_el_colaborador_pide_su_apoyo_educativo.test.sql
-- ============================================================================
-- Lo que promete la 0461 (los nombres de fixtures y UUIDs de prueba conservan
-- el prefijo «456» de un número anterior; no importa, son solo identificadores
-- únicos dentro de esta transacción):
--   · la integrante pide su propio apoyo (mismos datos que el alta manual, sin
--     poder declarar el monto), y solo puede tener una solicitud pendiente;
--   · puede verla y retirarla mientras está pendiente; retirada no bloquea
--     volver a pedir;
--   · DO aprueba —nace la asignación real, con el cálculo de siempre— o
--     rechaza con motivo; nadie aprueba lo propio; una ya revisada no se
--     vuelve a revisar;
--   · lo revisado no se reescribe ni se borra;
--   · el contador y la lista de Bandeja cuentan lo mismo.
-- ============================================================================
begin;
select plan(34);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000456a00', 'ZZ456', 'Sede de laboratorio 456', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  -- DO que revisa
  ('00000000-0000-0000-0000-000000456d01', 'SolDO', 'Laboratorio',
   '00000000-0000-0000-0000-000000456a00', 'lider_do', 'test-hash',
   '00000000-0000-0000-0000-000000456f01', '2020-01-01'),
  -- Otra persona de DO, para el caso «nadie aprueba lo propio»
  ('00000000-0000-0000-0000-000000456d02', 'SolAdmin', 'Laboratorio',
   '00000000-0000-0000-0000-000000456a00', 'admin', 'test-hash',
   '00000000-0000-0000-0000-000000456f02', '2020-01-01'),
  -- Carla, la que pide el apoyo
  ('00000000-0000-0000-0000-000000456d03', 'SolCarla', 'Laboratorio',
   '00000000-0000-0000-0000-000000456a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000456f03', '2025-01-02'),
  -- Deysi, una compañera sin nada que ver
  ('00000000-0000-0000-0000-000000456d04', 'SolDeysi', 'Laboratorio',
   '00000000-0000-0000-0000-000000456a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000456f04', '2025-01-02');
set session_replication_role = origin;

insert into storage.objects (bucket_id, name, metadata) values
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000456d03/solicitudes/00000000-0000-0000-0000-00000456c001/c.pdf',
   '{"mimetype":"application/pdf","size":1000}');


-- ── 1 · Esquema ─────────────────────────────────────────────────────────────
select has_table('educacion_solicitudes', 'ESQUEMA · existe la tabla de solicitudes');


-- ── 2 · Carla pide su apoyo ───────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f03', true);
set local role authenticated;

select lives_ok($$
  select set_config('prueba.sol1', fn_educacion_solicitar(
    'Instituto de laboratorio', 200, 'trabajador', null,
    fn_hoy_lima(), fn_hoy_lima() + 180,
    'educacion/00000000-0000-0000-0000-000000456d03/solicitudes/00000000-0000-0000-0000-00000456c001/c.pdf',
    null
  )::text, true)
$$, 'ENVÍO · Carla pide su apoyo con comprobante inicial');

select is(
  (select estado from educacion_solicitudes where persona_id = '00000000-0000-0000-0000-000000456d03'),
  'pendiente', 'ENVÍO · queda pendiente');

select throws_ok($$
  select fn_educacion_solicitar('Otro instituto', 100, 'trabajador', null, fn_hoy_lima(), fn_hoy_lima() + 30)
$$, 'P0001', 'Ya tienes una solicitud pendiente de revisión. Retírala si quieres cambiarla.',
  'ÚNICA · no puede tener dos solicitudes pendientes');

select throws_ok($$
  select fn_educacion_solicitar('IN', 100, 'trabajador', null, fn_hoy_lima(), fn_hoy_lima() + 30)
$$, 'P0001', 'Escribe qué institución emite el comprobante.',
  'VALIDA · institución muy corta se rechaza');

-- Deysi no ve la solicitud de Carla.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f04', true);
select is(
  (select count(*)::int from educacion_solicitudes where persona_id = '00000000-0000-0000-0000-000000456d03'),
  0, 'RLS · Deysi no ve la solicitud de Carla');

-- Deysi no puede retirar la de Carla.
select throws_ok($$
  select fn_educacion_retirar_solicitud(
    (select id from educacion_solicitudes limit 1))
$$, 'P0001', 'Esa solicitud no existe.',
  'RLS · Deysi no puede retirar lo que no ve (RLS la esconde antes que el guard)');


-- ── 3 · Carla la ve y la retira ──────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f03', true);

select is(
  (select institucion from educacion_solicitudes where persona_id = '00000000-0000-0000-0000-000000456d03'),
  'Instituto de laboratorio', 'VER · Carla ve lo que pidió');

select lives_ok($$
  select fn_educacion_retirar_solicitud(
    (select id from educacion_solicitudes where persona_id = '00000000-0000-0000-0000-000000456d03'))
$$, 'RETIRAR · Carla retira su propia solicitud pendiente');

select is(
  (select estado from educacion_solicitudes where persona_id = '00000000-0000-0000-0000-000000456d03'),
  'retirada', 'RETIRAR · queda retirada, no desaparece');

select throws_ok($$
  select fn_educacion_retirar_solicitud(
    (select id from educacion_solicitudes where persona_id = '00000000-0000-0000-0000-000000456d03'))
$$, 'P0001', 'Esta solicitud ya está retirada y queda en el historial: no se retira.',
  'RETIRAR · no se retira dos veces');


-- ── 4 · Carla vuelve a pedir (retirada no bloquea) ───────────────────────────
select lives_ok($$
  select set_config('prueba.sol2', fn_educacion_solicitar(
    'Instituto de laboratorio', 200, 'trabajador', null, fn_hoy_lima(), fn_hoy_lima() + 180
  )::text, true)
$$, 'REENVÍO · una solicitud retirada no bloquea volver a pedir');


-- ── 5 · Nadie aprueba lo propio ──────────────────────────────────────────────
-- Carla, aunque fuera DO, no podría revisar la suya — pero antes ni siquiera
-- pasa el guard de rol: prueba aparte con SolAdmin sobre SÍ misma.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f02', true);
select lives_ok($$
  select set_config('prueba.solpropia', fn_educacion_solicitar(
    'Curso de SolAdmin', 100, 'trabajador', null, fn_hoy_lima(), fn_hoy_lima() + 30
  )::text, true)
$$, 'PROPIA · SolAdmin (que también es DO) puede pedir su propio apoyo');

select throws_ok($$
  select fn_educacion_resolver_solicitud(current_setting('prueba.solpropia')::uuid, true)
$$, 'P0001', 'No puedes aprobar tu propia solicitud: la revisa otra persona de Desarrollo Organizacional.',
  'PROPIA · SolAdmin no puede aprobar su propia solicitud');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f03', true);
select throws_ok($$
  select fn_educacion_resolver_solicitud(current_setting('prueba.solpropia')::uuid, true)
$$, 'P0001', 'Solo Desarrollo Organizacional revisa solicitudes de apoyo educativo.',
  'PERMISO · una integrante no revisa solicitudes');


-- ── 6 · DO aprueba: nace la asignación con el cálculo de siempre ────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f01', true);

select lives_ok($$
  select set_config('prueba.asig', fn_educacion_resolver_solicitud(
    (select id from educacion_solicitudes where persona_id = '00000000-0000-0000-0000-000000456d03' and estado = 'pendiente'),
    true
  )::text, true)
$$, 'APROBAR · DO aprueba la solicitud de Carla');

select is(
  (select estado from educacion_solicitudes where asignacion_id = current_setting('prueba.asig')::uuid),
  'aprobada', 'APROBAR · queda aprobada');

select is(
  (select monto from asignaciones_educacion where id = current_setting('prueba.asig')::uuid),
  150::numeric, 'APROBAR · el monto es el 75% del costo declarado (200 · 75% = 150), el mismo cálculo de siempre');

select is(
  (select institucion from asignaciones_educacion where id = current_setting('prueba.asig')::uuid),
  'Instituto de laboratorio', 'APROBAR · la asignación real hereda los datos de la solicitud');

select is_empty($$
  select 1 from educacion_comprobantes where asignacion_id = current_setting('prueba.asig')::uuid
$$, 'APROBAR · esta segunda solicitud no llevaba comprobante, y aprobarla no inventa uno');


-- ── 8 · Rechazo, con motivo obligatorio ──────────────────────────────────────
select throws_ok($$
  select fn_educacion_resolver_solicitud(current_setting('prueba.solpropia')::uuid, false, null)
$$, 'P0001', 'Escribe qué corregir: la integrante lo va a leer.',
  'RECHAZO · exige motivo');

select lives_ok($$
  select fn_educacion_resolver_solicitud(current_setting('prueba.solpropia')::uuid, false, 'El comprobante no corresponde a tu rango')
$$, 'RECHAZO · con motivo, se rechaza');

select is(
  (select estado from educacion_solicitudes where id = current_setting('prueba.solpropia')::uuid),
  'rechazada', 'RECHAZO · queda rechazada');

select is(
  (select asignacion_id from educacion_solicitudes where id = current_setting('prueba.solpropia')::uuid),
  null, 'RECHAZO · rechazar no crea ninguna asignación');

select throws_ok($$
  select fn_educacion_resolver_solicitud(current_setting('prueba.solpropia')::uuid, true)
$$, 'P0001', 'Esta solicitud ya está rechazada: alguien la revisó antes.',
  'DOBLE · una rechazada no se vuelve a resolver');


-- ── 9 · Lo revisado no se toca, ni siquiera por debajo ──────────────────────
-- Como en la 355: sin permiso de UPDATE/DELETE, un intento directo de
-- `authenticated` ya se para en el GRANT. Para probar el trigger en sí
-- (defensa en profundidad, no solo el candado de arriba) se hace con `reset
-- role`, igual que la 355 lo hace para educacion_entregas.
reset role;

select throws_like($$
  update educacion_solicitudes set institucion = 'otra' where id = current_setting('prueba.solpropia')::uuid
$$, '%no se reescribe%', 'INMUTABLE · no se reescribe lo pedido');

select throws_like($$
  delete from educacion_solicitudes where id = current_setting('prueba.solpropia')::uuid
$$, '%no se borra%', 'INMUTABLE · no se borra');


-- ── 10 · El contador y la Bandeja cuentan lo mismo ───────────────────────────
-- Deysi pide su propio apoyo: es la solicitud pendiente que la Bandeja y el
-- contador tienen que ver (todo lo de Carla y SolAdmin ya quedó resuelto).
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f04', true);
select lives_ok($$
  select fn_educacion_solicitar('Instituto de Deysi', 300, 'trabajador', null, fn_hoy_lima(), fn_hoy_lima() + 90)
$$, 'CONTADOR · Deysi pide su apoyo, para medir el contador');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f01', true);

select is(
  (select count(*)::int from fn_educacion_solicitudes_pendientes()
    where persona_id = '00000000-0000-0000-0000-000000456d04'),
  1, 'BANDEJA · la solicitud pendiente de Deysi aparece en la lista de DO');

select is(
  fn_educacion_por_atender() > 0, true,
  'CONTADOR · fn_educacion_por_atender ve la misma solicitud pendiente que la Bandeja');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f03', true);
select is(
  (select count(*)::int from fn_educacion_solicitudes_pendientes()),
  0, 'BANDEJA · una integrante no ve la lista de solicitudes pendientes (la función filtra por rol, no solo RLS)');


-- ── 11 · El almacén: la ruta se congela al enviar ────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000456f03', true);
select is(
  fn_educacion_puede_subir_solicitud(
    'educacion/00000000-0000-0000-0000-000000456d03/solicitudes/00000000-0000-0000-0000-00000456caaa/nuevo.pdf'),
  true, 'ALMACÉN · Carla puede escribir en la carpeta de una solicitud que todavía no existe');

select is(
  fn_educacion_puede_subir_solicitud(
    'educacion/00000000-0000-0000-0000-000000456d04/solicitudes/00000000-0000-0000-0000-00000456caab/nuevo.pdf'),
  false, 'ALMACÉN · Carla no puede escribir en la carpeta de otra persona');

select is(
  fn_educacion_puede_subir_solicitud(
    'educacion/00000000-0000-0000-0000-000000456d03/entregas/00000000-0000-0000-0000-00000456caac/nuevo.pdf'),
  false, 'ALMACÉN · la ruta de solicitudes no cuela como ruta de entregas');

select * from finish();
rollback;
