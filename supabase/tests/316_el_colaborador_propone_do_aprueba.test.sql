-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0399_....sql.
-- ============================================================================
-- 316_el_colaborador_propone_do_aprueba.test.sql
-- ============================================================================
-- Lo que esta prueba vigila, por orden de importancia:
--
--   1. Que el valor real NO cambie hasta que DO aprueba (celular, el caso
--      simple sin documento).
--   2. Que un campo que exige documento se rechace sin uno adjunto
--      (estado_civil), y se acepte con uno (familiar_nuevo).
--   3. Que "familiar_nuevo" no cree una tabla propia: al aprobarse, la fila
--      aparece en `derechohabientes` (la tabla que ya existía).
--   4. Que la auto-escritura directa quede cerrada en las tres funciones que
--      esta migración modificó (fn_set_datos_personales,
--      fn_set_derechohabiente, fn_cerrar_derechohabiente) — sin esto, la
--      promesa de "no cambia hasta aprobar" es solo de interfaz.
--   5. Que dos solicitudes seguidas sobre el mismo campo reemplacen, no
--      acumulen — salvo familiar_nuevo, que sí admite varias en paralelo.
--   6. Que rechazar exija motivo, y que ninguna solicitud se resuelva dos veces.
--   7. Que estado_civil/hijos_menores generen la tarea de seguimiento a
--      planilla al aprobarse, y que alguien que no es DO no pueda resolver
--      ni la solicitud ni esa tarea.
-- ============================================================================
begin;
select plan(23);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000c10a', 'ZZPRF', 'Sede de laboratorio perfil', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c20a', 'PerfAdmin', 'Lab', '00000000-0000-0000-0000-00000000c10a', 'admin', 'x', '00000000-0000-0000-0000-00000000caaa', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c30a', 'PerfColab', 'Lab', '00000000-0000-0000-0000-00000000c10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000cbbb', '2024-01-01');
set session_replication_role = origin;

-- ── DE PARTIDA · el catálogo trae sus campos, no una lista a mano ──────────
-- 12 y no los 11 que agregó esta migración: la 0401 sumó `foto_dni`. El número
-- se actualiza cuando una migración agrega un campo — que es justo lo que esta
-- aserción existe para obligar a notar.
select is((select count(*)::int from catalogo_campos_perfil), 13,
  'DE PARTIDA · el catálogo tiene sus 13 campos (11 de la 0399 + foto_dni de la 0401 + documento de la 0513)');

-- ── 1 · Celular: propone, no cambia hasta aprobar ───────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cbbb', true);

select lives_ok($$ select fn_crear_solicitud_perfil(
    'celular', jsonb_build_object('celular', '987654321')) $$,
  'CELULAR · la propia persona puede proponer un cambio sin documento');

select is((select celular from datos_personales where persona_id = '00000000-0000-0000-0000-00000000c30a'),
  null, 'CELULAR · el valor real NO cambió todavía — sigue pendiente');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caaa', true);
select fn_resolver_solicitud_perfil(
  (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'celular'),
  true, null);

select is((select celular from datos_personales where persona_id = '00000000-0000-0000-0000-00000000c30a'),
  '987654321', 'CELULAR · recién al aprobar, el valor real cambia');

-- Resolver la misma solicitud dos veces se rechaza.
select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'celular'),
    true, null) $$,
  null, null, 'CELULAR · una solicitud ya resuelta no se vuelve a resolver');

-- ── 2 · estado_civil exige documento ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cbbb', true);

select throws_ok($$ select fn_crear_solicitud_perfil(
    'estado_civil', jsonb_build_object('estado_civil', 'casado')) $$,
  null, null, 'ESTADO CIVIL · sin documento adjunto, se rechaza');

select lives_ok($$ select fn_crear_solicitud_perfil(
    'estado_civil', jsonb_build_object('estado_civil', 'casado'),
    array['solicitud/00000000-0000-0000-0000-00000000c30a/dni.jpg']) $$,
  'ESTADO CIVIL · con un documento adjunto, se acepta');

-- ── 3 · familiar_nuevo no crea tabla propia: cae en `derechohabientes` ──────
select lives_ok($$ select fn_crear_solicitud_perfil(
    'familiar_nuevo',
    jsonb_build_object('nombres','Ana','apellidos','Perez','vinculo','hijo','fecha_nacimiento','2020-01-01'),
    array['solicitud/00000000-0000-0000-0000-00000000c30a/partida.jpg']) $$,
  'FAMILIAR · con partida adjunta, se acepta');

-- familiar_nuevo SÍ admite varias solicitudes pendientes en paralelo — a
-- diferencia de cualquier otro campo. Se comprueba ANTES de resolver a Ana:
-- una vez resuelta, ya no cuenta como pendiente.
select fn_crear_solicitud_perfil(
  'familiar_nuevo', jsonb_build_object('nombres','Luis','apellidos','Gomez','vinculo','conyuge'),
  array['solicitud/00000000-0000-0000-0000-00000000c30a/matrimonio.jpg']);

select is((select count(*)::int from solicitudes_cambio_perfil
           where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'familiar_nuevo' and estado = 'pendiente'),
  2, 'FAMILIAR EN PARALELO · dos altas de familiar conviven pendientes a la vez');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caaa', true);
select fn_resolver_solicitud_perfil(
  (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'familiar_nuevo' and valor_propuesto->>'nombres' = 'Ana'),
  true, null);

select is((select count(*)::int from derechohabientes
           where persona_id = '00000000-0000-0000-0000-00000000c30a' and nombres = 'Ana' and apellidos = 'Perez'),
  1, 'FAMILIAR · aparece en `derechohabientes`, no en una tabla nueva');

-- Y la de estado_civil, aprobada, deja tarea de seguimiento a planilla.
select fn_resolver_solicitud_perfil(
  (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'estado_civil'),
  true, null);

select is((select count(*)::int from seguimiento_planilla_por_solicitud
           where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'estado_civil' and estado = 'pendiente'),
  1, 'SEGUIMIENTO · aprobar estado_civil deja una tarea pendiente para DO');

-- ── 4 · La auto-escritura directa queda cerrada en las tres funciones ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cbbb', true);

select throws_ok($$ select fn_set_datos_personales(
    '00000000-0000-0000-0000-00000000c30a'::uuid, p_celular => '000') $$,
  null, null, 'PUERTA CERRADA · fn_set_datos_personales ya no acepta la propia persona');

select throws_ok($$ select fn_set_derechohabiente(
    null, '00000000-0000-0000-0000-00000000c30a'::uuid, 'Otro', 'Nombre', 'conyuge') $$,
  null, null, 'PUERTA CERRADA · fn_set_derechohabiente ya no acepta la propia persona');

select throws_ok($$ select fn_cerrar_derechohabiente(
    (select id from derechohabientes where persona_id = '00000000-0000-0000-0000-00000000c30a' limit 1)) $$,
  null, null, 'PUERTA CERRADA · fn_cerrar_derechohabiente ya no acepta la propia persona');

-- Y DO sigue pudiendo, sin pasar por ninguna solicitud (edición directa intacta).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caaa', true);
select lives_ok($$ select fn_set_datos_personales(
    '00000000-0000-0000-0000-00000000c30a'::uuid, p_celular => '111222333') $$,
  'DO SIGUE PUDIENDO · la edición directa de Administración no se tocó');

-- ── 5 · Reemplazo: dos solicitudes seguidas del mismo campo ─────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cbbb', true);
select fn_crear_solicitud_perfil('direccion', jsonb_build_object('direccion', 'Av. Uno 123'));
select fn_crear_solicitud_perfil('direccion', jsonb_build_object('direccion', 'Av. Dos 456'));

select is((select count(*)::int from solicitudes_cambio_perfil
           where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'direccion' and estado = 'pendiente'),
  1, 'REEMPLAZO · como máximo una solicitud pendiente por campo');

select is((select count(*)::int from solicitudes_cambio_perfil
           where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'direccion' and estado = 'reemplazada'),
  1, 'REEMPLAZO · la anterior queda etiquetada, nunca borrada');

-- ── 6 · Rechazo exige motivo ─────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caaa', true);

select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'direccion' and estado = 'pendiente'),
    false, null) $$,
  null, null, 'RECHAZO · sin motivo, se rechaza el rechazo');

select fn_resolver_solicitud_perfil(
  (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'direccion' and estado = 'pendiente'),
  false, 'no corresponde a esta prueba');

select is((select estado from solicitudes_cambio_perfil
           where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'direccion' and estado = 'rechazado'),
  'rechazado', 'RECHAZO · con motivo, queda rechazada y con su motivo');

-- ── 7 · Solo DO resuelve — ni la solicitud ni la tarea de seguimiento ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cbbb', true);

select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil where persona_id = '00000000-0000-0000-0000-00000000c30a' and campo = 'familiar_nuevo' and estado = 'pendiente' limit 1),
    true, null) $$,
  null, null, 'SOLO DO · la propia persona no puede resolver su solicitud');

select throws_ok($$ select fn_resolver_seguimiento_planilla(
    (select id from seguimiento_planilla_por_solicitud where persona_id = '00000000-0000-0000-0000-00000000c30a' limit 1)) $$,
  null, null, 'SOLO DO · la propia persona no puede cerrar la tarea de seguimiento');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000caaa', true);
select lives_ok($$ select fn_resolver_seguimiento_planilla(
    (select id from seguimiento_planilla_por_solicitud where persona_id = '00000000-0000-0000-0000-00000000c30a' limit 1),
    'Confirmado con SUNAT') $$,
  'SEGUIMIENTO · DO sí puede cerrarla, con nota');

select is((select estado from seguimiento_planilla_por_solicitud
           where persona_id = '00000000-0000-0000-0000-00000000c30a' limit 1),
  'resuelta', 'SEGUIMIENTO · queda resuelta');

select * from finish();
rollback;
