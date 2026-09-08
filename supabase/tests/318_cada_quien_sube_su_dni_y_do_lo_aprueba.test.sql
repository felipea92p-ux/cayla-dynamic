-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0401_....sql.
-- ============================================================================
-- 318_cada_quien_sube_su_dni_y_do_lo_aprueba.test.sql
-- ============================================================================
-- Lo que esta prueba vigila, por orden de importancia:
--
--   1. Que la foto del DNI NO entre a la ficha hasta que DO aprueba — ni la
--      primera vez ni en una actualización. Es la promesa entera de la 0401.
--   2. Que las dos caras sean obligatorias, distintas entre sí, y que las dos
--      vayan también como adjuntos (que es lo que las hace visibles en
--      /admin/bandeja para quien va a aprobarlas).
--   3. Que no se pueda proponer como DNI propio una ruta de OTRA persona.
--   4. Que al aprobar quede rastro en `correcciones_auditoria`: «quién aprobó
--      qué DNI y cuándo» tiene que responderse sin abrir el almacén.
--   5. Que una ruta ya aprobada quede congelada — el candado que impide
--      reemplazar los bytes de un papel que DO ya miró.
--   6. Que «Guardar ficha» desde Administración no borre las rutas del DNI.
--      Es el accidente que ya ocurrió con las tres `foto_*_url` (ver el
--      comentario en admin/datos-personales/page.tsx): esa función es un
--      upsert que reemplaza, y las columnas nuevas quedan fuera a propósito.
--
-- LO QUE NO COMPRUEBA, Y POR QUÉ
--   Las políticas de storage no se ejercitan acá: harían falta filas en
--   `storage.objects` y un bucket real. Lo que sí se prueba es la función que
--   esas políticas consultan, `fn_solicitud_perfil_ruta_congelada`, que es
--   donde vive la decisión.
-- ============================================================================
begin;
select plan(20);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000d10a', 'ZZDNI', 'Sede de laboratorio DNI', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d20a', 'DniAdmin', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'admin', 'x', '00000000-0000-0000-0000-00000000daaa', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d30a', 'DniColab', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000dbbb', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000d40a', 'DniOtra', 'Lab', '00000000-0000-0000-0000-00000000d10a', 'integrante', 'x', '00000000-0000-0000-0000-00000000dccc', '2024-01-01');
set session_replication_role = origin;


-- ── DE PARTIDA · el campo vive en el catálogo, no escrito a mano ────────────
select is((select count(*)::int from catalogo_campos_perfil), 12,
  'DE PARTIDA · el catálogo tiene sus 12 campos (los 11 de la 0399 + foto_dni)');

select is((select requiere_documento from catalogo_campos_perfil where campo = 'foto_dni'), true,
  'DE PARTIDA · foto_dni exige documento adjunto');

select is((select columnas from catalogo_campos_perfil where campo = 'foto_dni'),
  array['foto_dni_anverso_ruta','foto_dni_reverso_ruta'],
  'DE PARTIDA · el catálogo declara las dos columnas, en ese orden');


-- ── 1 · Lo que NO se puede proponer ─────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dbbb', true);

select throws_ok($$ select fn_crear_solicitud_perfil(
    'foto_dni',
    jsonb_build_object('foto_dni_anverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/a.jpg'),
    array['solicitud/00000000-0000-0000-0000-00000000d30a/a.jpg']) $$,
  null, null, 'UNA SOLA CARA · sin el reverso, se rechaza');

select throws_ok($$ select fn_crear_solicitud_perfil(
    'foto_dni',
    jsonb_build_object('foto_dni_anverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/a.jpg',
                       'foto_dni_reverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/a.jpg'),
    array['solicitud/00000000-0000-0000-0000-00000000d30a/a.jpg']) $$,
  null, null, 'MISMA IMAGEN · anverso y reverso no pueden ser el mismo archivo');

-- Sin ir como adjunto, la cara no aparecería en /admin/bandeja: DO aprobaría a
-- ciegas una imagen que no puede mirar.
select throws_ok($$ select fn_crear_solicitud_perfil(
    'foto_dni',
    jsonb_build_object('foto_dni_anverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/a.jpg',
                       'foto_dni_reverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/b.jpg'),
    array['solicitud/00000000-0000-0000-0000-00000000d30a/a.jpg']) $$,
  null, null, 'SIN ADJUNTAR · una cara que no va también como adjunto se rechaza');

-- El caso que hace daño de verdad: apuntar al DNI de otra persona.
select throws_ok($$ select fn_crear_solicitud_perfil(
    'foto_dni',
    jsonb_build_object('foto_dni_anverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d40a/a.jpg',
                       'foto_dni_reverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/b.jpg'),
    array['solicitud/00000000-0000-0000-0000-00000000d40a/a.jpg',
          'solicitud/00000000-0000-0000-0000-00000000d30a/b.jpg']) $$,
  null, null, 'DE OTRA PERSONA · una ruta fuera de tu carpeta se rechaza');


-- ── 2 · Propone, y la ficha NO cambia ───────────────────────────────────────
select lives_ok($$ select fn_crear_solicitud_perfil(
    'foto_dni',
    jsonb_build_object('foto_dni_anverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/anverso1.jpg',
                       'foto_dni_reverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/reverso1.jpg'),
    array['solicitud/00000000-0000-0000-0000-00000000d30a/anverso1.jpg',
          'solicitud/00000000-0000-0000-0000-00000000d30a/reverso1.jpg']) $$,
  'PROPONE · con las dos caras, de su carpeta y adjuntas, se acepta');

select is((select foto_dni_anverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  null, 'PROPONE · la ficha NO tiene todavía ninguna foto — sigue pendiente');


-- ── 3 · DO aprueba, y recién ahí entra ──────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000daaa', true);
select fn_resolver_solicitud_perfil(
  (select id from solicitudes_cambio_perfil
    where persona_id = '00000000-0000-0000-0000-00000000d30a' and campo = 'foto_dni' and estado = 'pendiente'),
  true, null);

select is((select foto_dni_anverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  'solicitud/00000000-0000-0000-0000-00000000d30a/anverso1.jpg',
  'APRUEBA · el anverso entra a la ficha');

select is((select foto_dni_reverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  'solicitud/00000000-0000-0000-0000-00000000d30a/reverso1.jpg',
  'APRUEBA · el reverso entra a la ficha');

select is((select count(*)::int from correcciones_auditoria
           where persona_id = '00000000-0000-0000-0000-00000000d30a'
             and campo_modificado = 'datos_personales.foto_dni'),
  1, 'AUDITORÍA · aprobar un DNI deja rastro de quién y cuándo');


-- ── 4 · El candado sobre lo ya aprobado ─────────────────────────────────────
select is(fn_solicitud_perfil_ruta_congelada('solicitud/00000000-0000-0000-0000-00000000d30a/anverso1.jpg'),
  true, 'CANDADO · la ruta de un DNI aprobado queda congelada');

select is(fn_solicitud_perfil_ruta_congelada('solicitud/00000000-0000-0000-0000-00000000d30a/nunca-subida.jpg'),
  false, 'CANDADO · una ruta que nadie aprobó no está congelada');


-- ── 5 · Actualizar el DNI: se propone otra vez, y hasta aprobar manda la vieja ─
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dbbb', true);
select fn_crear_solicitud_perfil(
  'foto_dni',
  jsonb_build_object('foto_dni_anverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/anverso2.jpg',
                     'foto_dni_reverso_ruta', 'solicitud/00000000-0000-0000-0000-00000000d30a/reverso2.jpg'),
  array['solicitud/00000000-0000-0000-0000-00000000d30a/anverso2.jpg',
        'solicitud/00000000-0000-0000-0000-00000000d30a/reverso2.jpg']);

select is((select foto_dni_anverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  'solicitud/00000000-0000-0000-0000-00000000d30a/anverso1.jpg',
  'ACTUALIZA · mientras no se apruebe, la ficha sigue con el DNI anterior');

-- La cara nueva todavía no está congelada: nadie decidió nada sobre ella, así
-- que quien la subió puede corregirla o retirarla.
select is(fn_solicitud_perfil_ruta_congelada('solicitud/00000000-0000-0000-0000-00000000d30a/anverso2.jpg'),
  false, 'CANDADO · un adjunto de una solicitud pendiente sigue siendo de quien lo subió');

-- Y la propia persona no puede aprobarse el DNI, obviamente.
select throws_ok($$ select fn_resolver_solicitud_perfil(
    (select id from solicitudes_cambio_perfil
      where persona_id = '00000000-0000-0000-0000-00000000d30a' and campo = 'foto_dni' and estado = 'pendiente'),
    true, null) $$,
  null, null, 'SOLO DO · nadie se aprueba su propio DNI');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000daaa', true);
select fn_resolver_solicitud_perfil(
  (select id from solicitudes_cambio_perfil
    where persona_id = '00000000-0000-0000-0000-00000000d30a' and campo = 'foto_dni' and estado = 'pendiente'),
  true, null);

select is((select foto_dni_anverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  'solicitud/00000000-0000-0000-0000-00000000d30a/anverso2.jpg',
  'ACTUALIZA · al aprobar, la ficha pasa al DNI nuevo');

-- `valor_anterior` es lo único que deja escrito de QUÉ DNI se venía. Sin esta
-- rama (la que la 0401 le agregó a fn_snapshot_valor_actual) la solicitud
-- guardaría `{}` y esa pregunta no tendría respuesta en ningún lado.
select is((select valor_anterior->>'foto_dni_anverso_ruta' from solicitudes_cambio_perfil
           where persona_id = '00000000-0000-0000-0000-00000000d30a' and campo = 'foto_dni'
             and valor_propuesto->>'foto_dni_anverso_ruta' like '%anverso2.jpg'),
  'solicitud/00000000-0000-0000-0000-00000000d30a/anverso1.jpg',
  'DE QUÉ SE VENÍA · la solicitud guardó el DNI anterior en `valor_anterior`');


-- ── 6 · «Guardar ficha» no pisa el DNI ──────────────────────────────────────
-- fn_set_datos_personales es un upsert que REEMPLAZA cada columna que nombra.
-- Las dos del DNI quedan fuera de su lista a propósito: si estuvieran, cada
-- «Guardar ficha» en /admin/datos-personales las borraría, y además habría una
-- segunda forma de escribirlas sin pasar por la aprobación.
select fn_set_datos_personales('00000000-0000-0000-0000-00000000d30a'::uuid, p_celular => '999888777');

select is((select foto_dni_anverso_ruta from datos_personales where persona_id = '00000000-0000-0000-0000-00000000d30a'),
  'solicitud/00000000-0000-0000-0000-00000000d30a/anverso2.jpg',
  'GUARDAR FICHA · editar la ficha desde Administración no borra las rutas del DNI');

select * from finish();
rollback;
