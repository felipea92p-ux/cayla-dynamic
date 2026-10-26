-- ============================================================================
-- 416_la_solicitud_educativa_pendiente_recibe_su_comprobante.test.sql
-- ============================================================================
-- Lo que promete la 0522:
--   · quien envió una solicitud SIN comprobante puede adjuntárselo mientras está
--     pendiente, y cambiarlo si se equivocó de archivo; queda rastro;
--   · solo la dueña, solo con un archivo que exista en SU carpeta de solicitudes;
--   · ni DO ni una compañera lo adjuntan por ella;
--   · revisada o retirada, el comprobante ya no se cambia;
--   · un update directo (aunque tuviera permiso) no cambia el comprobante, y lo
--     pedido (institución, costo…) sigue sin poder reescribirse;
--   · DO ve el comprobante en «Pendientes de revisión».
-- ============================================================================
begin;
select plan(25);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000522a00', 'ZZ522', 'Sede de laboratorio 522', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000522d01', 'AdjDO', 'Laboratorio',
   '00000000-0000-0000-0000-000000522a00', 'lider_do', 'test-hash',
   '00000000-0000-0000-0000-000000522f01', '2020-01-01'),
  ('00000000-0000-0000-0000-000000522d03', 'AdjDanixa', 'Laboratorio',
   '00000000-0000-0000-0000-000000522a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000522f03', '2025-01-02'),
  ('00000000-0000-0000-0000-000000522d04', 'AdjDeysi', 'Laboratorio',
   '00000000-0000-0000-0000-000000522a00', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000522f04', '2025-01-02');
set session_replication_role = origin;

-- Tres archivos ya subidos: dos de Danixa (carpetas distintas, como hace el
-- formulario: un uuid fresco por subida) y uno de Deysi.
insert into storage.objects (bucket_id, name, metadata) values
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf',
   '{"mimetype":"application/pdf","size":1000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c002/comprobante.png',
   '{"mimetype":"image/png","size":1000}'),
  ('comprobantes', 'educacion/00000000-0000-0000-0000-000000522d04/solicitudes/00000000-0000-0000-0000-00000522c003/comprobante.pdf',
   '{"mimetype":"application/pdf","size":1000}');

-- ── 1 · Danixa envía SIN comprobante (el caso real del 2026-10-16) ───────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f03', true);
set local role authenticated;

select lives_ok($$
  select set_config('prueba.sol', fn_educacion_solicitar(
    'UPN', 600, 'trabajador', null, fn_hoy_lima(), fn_hoy_lima() + 120, null, null)::text, true)
$$, 'ENVÍO · Danixa envía su solicitud sin comprobante');

select is((select comprobante_url from educacion_solicitudes where id = current_setting('prueba.sol')::uuid),
  null, 'ENVÍO · queda sin comprobante');

-- ── 2 · Lo adjunta después ───────────────────────────────────────────────────
select lives_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf')
$$, 'ADJUNTAR · Danixa adjunta el comprobante a su solicitud pendiente');

select is((select comprobante_url from educacion_solicitudes where id = current_setting('prueba.sol')::uuid),
  'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf',
  'ADJUNTAR · la solicitud guarda la ruta');

select is((select estado from educacion_solicitudes where id = current_setting('prueba.sol')::uuid),
  'pendiente', 'ADJUNTAR · sigue pendiente: adjuntar no la revisa');

-- ── 3 · Se equivocó de archivo: lo cambia, y queda el rastro ─────────────────
select lives_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c002/comprobante.png')
$$, 'CAMBIAR · Danixa cambia el archivo mientras sigue pendiente');

reset role;
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000522d03' and campo_modificado = 'educacion_solicitud_comprobante'),
  2, 'AUDITORÍA · adjuntar y cambiar dejan una fila cada uno');
select is(
  (select valor_anterior from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000522d03' and campo_modificado = 'educacion_solicitud_comprobante'
      and valor_anterior is not null),
  'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf',
  'AUDITORÍA · el cambio guarda la ruta anterior');

-- ── 4 · Lo que NO puede hacer ────────────────────────────────────────────────
set local role authenticated;

select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d04/solicitudes/00000000-0000-0000-0000-00000522c003/comprobante.pdf')
$$, 'P0001', 'El comprobante tiene que estar en tu carpeta de solicitudes.',
  'CARPETA · no puede apuntar al archivo de otra persona');

select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c999/comprobante.pdf')
$$, 'P0001', 'El archivo no llegó a subirse. Vuelve a intentarlo.',
  'EXISTE · no puede apuntar a un archivo que no se subió');

select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid, null)
$$, 'P0001', 'El comprobante tiene que estar en tu carpeta de solicitudes.',
  'NULL · una ruta vacía se rechaza');

select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/constancias/00000000-0000-0000-0000-00000522c001/comprobante.pdf')
$$, 'P0001', 'El comprobante tiene que estar en tu carpeta de solicitudes.',
  'CARPETA · otra subcarpeta de su propia persona tampoco vale');

select throws_ok($$
  select fn_educacion_solicitud_adjuntar('00000000-0000-0000-0000-00000522ffff'::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf')
$$, 'P0001', 'Esa solicitud no existe.', 'EXISTE · una solicitud inventada se rechaza');

-- Deysi no adjunta a la solicitud de Danixa.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f04', true);
select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d04/solicitudes/00000000-0000-0000-0000-00000522c003/comprobante.pdf')
$$, 'P0001', 'Solo quien envió la solicitud puede adjuntarle el comprobante.',
  'DUEÑA · una compañera no adjunta a la solicitud ajena');

-- DO tampoco lo adjunta por ella.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f01', true);
select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf')
$$, 'P0001', 'Solo quien envió la solicitud puede adjuntarle el comprobante.',
  'DUEÑA · DO no adjunta por la integrante');

-- Alguien sin ficha enlazada.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f99', true);
select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf')
$$, 'P0001', 'Tu cuenta no está enlazada con tu ficha.', 'NULL-SAFE · sin ficha no pasa');

-- ── 5 · DO ve el comprobante en sus pendientes ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f01', true);
select is(
  (select comprobante_url from fn_educacion_solicitudes_pendientes() where id = current_setting('prueba.sol')::uuid),
  'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c002/comprobante.png',
  'DO · ve el comprobante vigente en Pendientes de revisión');

-- ── 6 · El trigger cierra la puerta directa ─────────────────────────────────
reset role;
-- Aunque un cliente tuviera permiso de UPDATE —privilegio y política—, el
-- trigger lo frena. (Se conceden solo dentro de esta transacción: todo se
-- revierte al final.)
grant update on educacion_solicitudes to authenticated;
create policy lab_update_abierto on educacion_solicitudes for update to authenticated using (true) with check (true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f03', true);
set local role authenticated;

select throws_like($$
  update educacion_solicitudes set comprobante_url = 'educacion/x/solicitudes/y/z.pdf'
   where id = current_setting('prueba.sol')::uuid
$$, '%fn_educacion_solicitud_adjuntar%', 'TRIGGER · el comprobante no se cambia con un update directo');

select throws_like($$
  update educacion_solicitudes set costo_declarado = 1 where id = current_setting('prueba.sol')::uuid
$$, '%no se reescribe%', 'TRIGGER · lo pedido sigue sin poder reescribirse');

reset role;

-- ── 7 · Revisada o retirada, el comprobante queda como estaba ───────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f03', true);
set local role authenticated;
select lives_ok($$
  select fn_educacion_retirar_solicitud(current_setting('prueba.sol')::uuid)
$$, 'RETIRADA · Danixa retira su solicitud');

select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf')
$$, 'P0001', 'Esta solicitud ya está retirada: su comprobante no se cambia.',
  'RETIRADA · una solicitud retirada ya no recibe comprobante');

reset role;
select throws_like($$
  update educacion_solicitudes set comprobante_url = null where id = current_setting('prueba.sol')::uuid
$$, '%ya está retirada%', 'TRIGGER · ni siquiera una función puede cambiar el comprobante de una solicitud cerrada');

-- Rechazada: lo mismo.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f03', true);
set local role authenticated;
select lives_ok($$
  select set_config('prueba.sol2', fn_educacion_solicitar(
    'UPN', 600, 'trabajador', null, fn_hoy_lima(), fn_hoy_lima() + 120, null, null)::text, true)
$$, 'RECHAZADA · Danixa envía otra solicitud');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f01', true);
select lives_ok($$
  select fn_educacion_resolver_solicitud(current_setting('prueba.sol2')::uuid, false, 'Falta el comprobante')
$$, 'RECHAZADA · DO la rechaza');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000522f03', true);
select throws_ok($$
  select fn_educacion_solicitud_adjuntar(current_setting('prueba.sol2')::uuid,
    'educacion/00000000-0000-0000-0000-000000522d03/solicitudes/00000000-0000-0000-0000-00000522c001/comprobante.pdf')
$$, 'P0001', 'Esta solicitud ya está rechazada: su comprobante no se cambia.',
  'RECHAZADA · una solicitud rechazada no recibe comprobante: se corrige y se envía otra');

select * from finish();
rollback;
