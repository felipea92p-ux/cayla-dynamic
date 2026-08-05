-- ============================================================================
-- 123_los_documentos_firmados.test.sql
-- ============================================================================
-- El plazo real: la RTF 05449-4-2007 desconoció la movilidad de 14 de 21
-- trabajadores porque no se exhibieron los convenios individuales. CAYLA tiene
-- que tener los suyos firmados antes del 28/08/2026.
--
-- Lo que este archivo vigila no es que se guarde un archivo — eso es fácil. Es
-- que el esquema haga IMPOSIBLES los estados que dejarían el expediente sin
-- valor el día que alguien lo revise:
--
--   · una declaración de ruta sin persona (indistinguible de la política de
--     empresa; con el candado del pago encendido, esa persona dejaría de cobrar
--     movilidad y el motivo estaría escondido en una fila que se ve normal),
--   · la política de empresa atribuida a alguien,
--   · una constancia de bono sin decir de qué año es,
--   · una negativa a firmar con un monto «firmado» adentro,
--   · un documento anulado sin motivo.
--
-- Y que el tablero se arme de quién cobra movilidad, no de una lista escrita a
-- mano: quien entra aparece pendiente solo, y un locador no aparece nunca.
-- ============================================================================
begin;
select plan(21);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000d0f00', 'ZZDOC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000d0f01', 'DocDO', 'Laboratorio',
        '00000000-0000-0000-0000-0000000d0f00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-0000000d0f09', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000d0f02', 'DocAna',  'Laboratorio', '00000000-0000-0000-0000-0000000d0f00', 'test-hash', '2025-01-02', 'planilla'),
  ('00000000-0000-0000-0000-0000000d0f03', 'DocBeto', 'Laboratorio', '00000000-0000-0000-0000-0000000d0f00', 'test-hash', '2025-01-02', 'planilla'),
  ('00000000-0000-0000-0000-0000000d0f04', 'DocLoca', 'Laboratorio', '00000000-0000-0000-0000-0000000d0f00', 'test-hash', '2025-01-02', 'rxh');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d0f09', true);


-- ── Los estados que el esquema tiene que hacer imposibles ──────────────────
select throws_ok(
  $$ insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, registrado_por)
     values ('individual', null, 'ruta', '2026-08-01', '00000000-0000-0000-0000-0000000d0f01') $$,
  '23514', null,
  'IMPOSIBLE · una declaración de ruta sin persona no entra');

select throws_ok(
  $$ insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, registrado_por)
     values ('empresa', '00000000-0000-0000-0000-0000000d0f02', 'politica', '2026-08-01', '00000000-0000-0000-0000-0000000d0f01') $$,
  '23514', null,
  'IMPOSIBLE · la política de empresa atribuida a una persona no entra');

select throws_ok(
  $$ insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, registrado_por)
     values ('individual', '00000000-0000-0000-0000-0000000d0f02', 'bono', '2026-08-01', '00000000-0000-0000-0000-0000000d0f01') $$,
  '23514', null,
  'IMPOSIBLE · una constancia de bono sin decir de qué año es no entra');

select throws_ok(
  $$ insert into documentos_firmados (alcance, persona_id, tipo, fecha_firma, es_negativa, monto_declarado, registrado_por)
     values ('individual', '00000000-0000-0000-0000-0000000d0f02', 'ruta', '2026-08-01', true, 10.00, '00000000-0000-0000-0000-0000000d0f01') $$,
  '23514', null,
  'IMPOSIBLE · una negativa a firmar no puede llevar un monto «firmado» adentro');

-- ── Registrar ──────────────────────────────────────────────────────────────
select lives_ok(
  $$ select fn_documento_registrar('ruta', '2026-08-01', '00000000-0000-0000-0000-0000000d0f02',
       'Casa – tienda TRU, 4 traslados', 10.00) $$,
  'ALTA · la declaración de ruta de una persona en planilla entra');

select is(
  (select alcance from documentos_firmados where persona_id = '00000000-0000-0000-0000-0000000d0f02'),
  'individual',
  'ALTA · el alcance NO se recibe: lo deduce del tipo, así que no se puede mentir');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-0000000d0f02' and campo_modificado = 'documento_firmado'),
  1,
  'ALTA · quedó rastro en la auditoría');

-- Va acá y no antes: un UPDATE sobre una tabla vacía no viola nada, así que
-- puesto arriba la prueba pasaba sin haber comprobado el candado.
select throws_ok(
  $$ update documentos_firmados set anulado_at = now() where true $$,
  '23514', null,
  'IMPOSIBLE · anular sin motivo y sin quién lo hizo no entra');

-- Un locador no cobra movilidad (0117), así que pedirle su ruta es pedirle un
-- papel que no sostiene ningún pago suyo.
select throws_like(
  $$ select fn_documento_registrar('ruta', '2026-08-01', '00000000-0000-0000-0000-0000000d0f04', 'x', 10.00) $$,
  '%no está en planilla%',
  'RXH · a un locador no se le pide declaración de ruta');

select throws_like(
  $$ select fn_documento_registrar('politica', '2026-08-01', '00000000-0000-0000-0000-0000000d0f02') $$,
  '%no se atribuye a una persona%',
  'EMPRESA · la política de movilidad no se le carga a nadie');

select lives_ok(
  $$ select fn_documento_registrar('politica', '2026-07-01') $$,
  'EMPRESA · pero sí entra como documento de CAYLA, sin persona');

select throws_like(
  $$ select fn_documento_registrar('ruta', (fn_hoy_lima() + 1)::date, '00000000-0000-0000-0000-0000000d0f03', 'x', 10.00) $$,
  '%no puede ser futura%',
  'FECHA · no se puede firmar mañana');


-- ── Versionado: la última rige, la anterior queda ──────────────────────────
select lives_ok(
  $$ select fn_documento_registrar('ruta', '2026-08-04', '00000000-0000-0000-0000-0000000d0f02',
       'Se mudó: nueva casa – tienda TRU', 10.00) $$,
  'VERSIÓN · se mudó y firma otra: la anterior NO se pisa');

select is(
  (select count(*)::int from documentos_firmados
    where persona_id = '00000000-0000-0000-0000-0000000d0f02' and tipo = 'ruta'),
  2,
  'VERSIÓN · quedan las dos: un pago de agosto se defiende con el papel de agosto');

select is(
  (select count(*)::int from fn_documentos_listar('00000000-0000-0000-0000-0000000d0f02')
    where tipo = 'ruta' and vigente),
  1,
  'VERSIÓN · pero solo UNA está vigente, y es la más reciente');


-- ── El bono: uno por persona y por año ─────────────────────────────────────
select lives_ok(
  $$ select fn_documento_registrar('bono', '2026-03-10', '00000000-0000-0000-0000-0000000d0f02',
       null, null, 2026) $$,
  'BONO · la constancia del año entra');

select throws_ok(
  $$ select fn_documento_registrar('bono', '2026-03-11', '00000000-0000-0000-0000-0000000d0f02',
       null, null, 2026) $$,
  '23505', null,
  'BONO · una segunda del mismo año se rechaza: se paga y se firma una vez al año');


-- ── El tablero ─────────────────────────────────────────────────────────────
-- Ana firmó; Beto no. El locador no debe aparecer: no cobra movilidad.
select is(
  (select count(*)::int from fn_documentos_tablero()
    where persona_id = '00000000-0000-0000-0000-0000000d0f04'),
  0,
  'TABLERO · el locador NO aparece: no cobra movilidad, no tiene nada que firmar');

select is(
  (select count(*)::int from fn_documentos_tablero()
    where persona_id in ('00000000-0000-0000-0000-0000000d0f02',
                         '00000000-0000-0000-0000-0000000d0f03')),
  2,
  'TABLERO · y sí aparecen las dos personas en planilla');

select is(
  (select estado from fn_documentos_tablero() where persona_id = '00000000-0000-0000-0000-0000000d0f03'),
  'sin_ruta',
  'TABLERO · Beto aparece pendiente sin que nadie lo agregue: sale de quién está en planilla');


-- ── Anular no es borrar ────────────────────────────────────────────────────
select throws_like(
  $$ select fn_documento_anular(
       (select id from documentos_firmados where tipo = 'bono' limit 1), 'x') $$,
  '%por qué se anula%',
  'ANULAR · sin motivo no se anula: si el archivo era de otra persona, eso queda dicho');

select * from finish();
rollback;
