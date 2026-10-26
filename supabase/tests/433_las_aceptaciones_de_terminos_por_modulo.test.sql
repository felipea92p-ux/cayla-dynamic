-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/0540_....sql.
-- ============================================================================
-- 433_las_aceptaciones_de_terminos_por_modulo.test.sql
-- ============================================================================
-- Lo que esta prueba vigila:
--
--   1. Queda constancia con el texto exacto, el módulo y la versión — no un
--      «aceptó: sí», que no probaría QUÉ aceptó.
--   2. Aceptar dos veces la MISMA versión no duplica ni falla: contesta «ya
--      estaba». Es lo que absorbe el doble clic y las dos pestañas a la vez.
--   3. Una versión nueva SÍ agrega fila, y un módulo distinto también. Es lo
--      que hace que subir la versión de un módulo vuelva a pedirlo.
--   4. Los estados imposibles lo son de verdad: texto de relleno, módulo mal
--      escrito, versión 0 o vacía — tanto por la función como directo en la
--      tabla, que es la defensa que no depende de que alguien use la función.
--   5. Es una constancia: ni se edita ni se borra, ni siquiera quien es dueño
--      de la tabla; y nadie con sesión de usuario escribe directo.
--   6. RLS: cada quien ve las suyas; DO y admin ven todas; una compañera no ve
--      las ajenas. Y `fn_mis_aceptaciones_terminos()` devuelve SOLO las propias
--      aunque quien pregunte sea administrador.
--
-- Ojo con el punto 6: sin `set local role authenticated` la sesión de pgTAP
-- corre como dueña de la tabla y se salta RLS entera — la prueba pasaría sin
-- probar nada. Mismo patrón que 321/118/121/136.
--
-- Lo que esta prueba NO puede probar: dos escrituras en el MISMO milisegundo
-- desde dos conexiones. Una prueba pgTAP es una sola transacción. Lo que la
-- sostiene es el `unique` + `on conflict do nothing`, que sí se comprueba aquí
-- (puntos 2 y 4); la carrera real se midió aparte con dos sesiones psql.
-- ============================================================================
begin;
select plan(28);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000000f10b', 'ZZACE', 'Sede de laboratorio aceptaciones', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000f20b', 'AceAdmin', 'Lab', '00000000-0000-0000-0000-00000000f10b', 'admin', 'x', '00000000-0000-0000-0000-00000000faab', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000f30b', 'AceColab', 'Lab', '00000000-0000-0000-0000-00000000f10b', 'integrante', 'x', '00000000-0000-0000-0000-00000000fbbb', '2024-01-01');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000f40b', 'AceOtra', 'Lab', '00000000-0000-0000-0000-00000000f10b', 'integrante', 'x', '00000000-0000-0000-0000-00000000fccc', '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fbbb', true);

-- ── 1 · Queda constancia, con su texto, su módulo y su versión ──────────────
select is((select count(*)::int from fn_mis_aceptaciones_terminos()),
  0, 'DE PARTIDA · sin aceptar nada, no hay constancia');

select is((select fn_aceptar_terminos('general', 1,
    'Dynamic registra mis marcajes, ausencias y pagos; avisa, nunca sanciona solo, y mis datos solo los ven quienes deben.')),
  true, 'ACEPTA · la primera vez deja constancia y lo dice (true)');

select is((select texto from aceptaciones_terminos
           where persona_id = '00000000-0000-0000-0000-00000000f30b' and modulo = 'general' and version = 1),
  'Dynamic registra mis marcajes, ausencias y pagos; avisa, nunca sanciona solo, y mis datos solo los ven quienes deben.',
  'ACEPTA · se guarda el texto EXACTO que tenía delante, no un booleano');

-- ── 2 · La misma versión dos veces: no duplica y no falla ───────────────────
select is((select fn_aceptar_terminos('general', 1,
    'Dynamic registra mis marcajes, ausencias y pagos; avisa, nunca sanciona solo, y mis datos solo los ven quienes deben.')),
  false, 'DOBLE CLIC · aceptar la misma versión otra vez no falla: contesta que ya estaba (false)');

select is((select count(*)::int from aceptaciones_terminos
           where persona_id = '00000000-0000-0000-0000-00000000f30b' and modulo = 'general'),
  1, 'DOBLE CLIC · sigue habiendo UNA sola fila, no dos');

-- ── 3 · Versión nueva y módulo distinto sí agregan ──────────────────────────
select is((select fn_aceptar_terminos('general', 2,
    'Versión dos de los términos de uso, con otra redacción que también tiene que quedar guardada entera.')),
  true, 'VERSIÓN NUEVA · aceptar la v2 agrega fila: así se vuelve a pedir tras un cambio');

select is((select count(*)::int from aceptaciones_terminos
           where persona_id = '00000000-0000-0000-0000-00000000f30b' and modulo = 'general'),
  2, 'VERSIÓN NUEVA · la v1 queda como historia, no se pisa');

select is((select fn_aceptar_terminos('boletas', 1,
    'Mi boleta es un documento personal con datos remunerativos; no la comparto y aviso de cualquier error antes de firmar.')),
  true, 'OTRO MÓDULO · aceptar boletas v1 es independiente de general');

select is((select count(*)::int from fn_mis_aceptaciones_terminos()),
  3, 'MIS ACEPTACIONES · devuelve las tres (general v1, general v2, boletas v1)');

-- ── 4 · Los estados que nunca deben existir ─────────────────────────────────
select throws_ok($$ select fn_aceptar_terminos('boletas', 2, '') $$,
  null, null, 'VACÍO · un texto vacío se rechaza');

select throws_ok($$ select fn_aceptar_terminos('boletas', 2, 'Acepto.') $$,
  null, null, 'RELLENO · un texto corto no es una constancia');

select throws_ok($$ select fn_aceptar_terminos('Boletas', 2,
    'Mi boleta es un documento personal con datos remunerativos; no la comparto y aviso de cualquier error.') $$,
  null, null, 'MÓDULO MAL ESCRITO · con mayúscula se rechaza');

select throws_ok($$ select fn_aceptar_terminos(null, 2,
    'Mi boleta es un documento personal con datos remunerativos; no la comparto y aviso de cualquier error.') $$,
  null, null, 'MÓDULO VACÍO · sin nombre de módulo se rechaza');

select throws_ok($$ select fn_aceptar_terminos('boletas', 0,
    'Mi boleta es un documento personal con datos remunerativos; no la comparto y aviso de cualquier error.') $$,
  null, null, 'VERSIÓN CERO · no existe la versión 0');

select throws_ok($$ select fn_aceptar_terminos('boletas', null,
    'Mi boleta es un documento personal con datos remunerativos; no la comparto y aviso de cualquier error.') $$,
  null, null, 'SIN VERSIÓN · una constancia sin versión no dice qué texto era');

-- Y la defensa que NO depende de la función: directo en la tabla, como dueño.
select throws_ok($$ insert into aceptaciones_terminos (persona_id, modulo, version, texto)
    values ('00000000-0000-0000-0000-00000000f30b', 'firma', 1, 'corto') $$,
  '23514', null, 'TABLA · el texto de relleno se rechaza aunque no se pase por la función');

select throws_ok($$ insert into aceptaciones_terminos (persona_id, modulo, version, texto)
    values ('00000000-0000-0000-0000-00000000f30b', 'general', 1,
            'Un duplicado escrito directo en la tabla, con texto suficiente para pasar el mínimo de largo.') $$,
  '23505', null, 'TABLA · dos aceptaciones de la misma versión no pueden existir, ni escritas directo');

-- ── 5 · Es una constancia: no se edita, no se borra, no se escribe directo ──
select throws_ok($$ update aceptaciones_terminos
      set texto = 'Un texto distinto, escrito después, para que la constancia diga otra cosa distinta.'
    where persona_id = '00000000-0000-0000-0000-00000000f30b' and modulo = 'general' and version = 1 $$,
  null, null, 'INMUTABLE · una constancia no se edita, ni siquiera siendo dueño de la tabla');

select throws_ok($$ delete from aceptaciones_terminos
    where persona_id = '00000000-0000-0000-0000-00000000f30b' $$,
  null, null, 'INMUTABLE · una constancia no se borra');

set local role authenticated;
select throws_ok($$ insert into aceptaciones_terminos (persona_id, modulo, version, texto)
    values ('00000000-0000-0000-0000-00000000f30b', 'firma', 1,
            'Una constancia escrita directo por un usuario, sin pasar por la función, que no debe poder existir.') $$,
  '42501', null, 'SIN ESCRITURA DIRECTA · un usuario no inserta en la tabla, solo por la función');
reset role;

-- La otra capa, la que no depende de RLS: los permisos mismos. Supabase le da
-- todo a `authenticated` en toda tabla nueva; si la migración no lo quita, la
-- escritura quedaría protegida solo por RLS y por el trigger (la 0404 y la 0480
-- ya enseñaron esto). Se mira el permiso, no el resultado de intentar escribir.
select is((select string_agg(p, ',' order by p) from unnest(array['INSERT','UPDATE','DELETE','TRUNCATE']) p
            where has_table_privilege('authenticated', 'aceptaciones_terminos', p)),
  null, 'PERMISOS · un usuario autenticado no tiene permiso de escribir en la tabla, ni de vaciarla');

select is(has_table_privilege('anon', 'aceptaciones_terminos', 'SELECT'),
  false, 'PERMISOS · quien no inició sesión no puede ni leerla');

-- ── 6 · RLS de verdad, con el rol puesto ────────────────────────────────────
set local role authenticated;

select is((select count(*)::int from aceptaciones_terminos
           where persona_id = '00000000-0000-0000-0000-00000000f30b'),
  3, 'RLS · la propia persona ve sus tres constancias');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fccc', true);
set local role authenticated;

select is((select count(*)::int from aceptaciones_terminos
           where persona_id = '00000000-0000-0000-0000-00000000f30b'),
  0, 'RLS · una compañera cualquiera no ve la constancia ajena');

-- Y la otra mitad de la regla, la que se olvida: que quien SÍ puede, pueda.
-- Sin esta aserción, borrar la policy de admin dejaría la prueba en verde.
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000faab', true);
set local role authenticated;

select is((select count(*)::int from aceptaciones_terminos
           where persona_id = '00000000-0000-0000-0000-00000000f30b'),
  3, 'RLS · un administrador sí ve las constancias ajenas: es lo que le deja responder «quién no aceptó»');

select is((select count(*)::int from fn_mis_aceptaciones_terminos()),
  0, 'MIS ACEPTACIONES · un administrador que pregunta por las SUYAS no recibe las de otras personas');

reset role;

-- ── Una sesión que no es de ninguna persona no puede aceptar ────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000fffff', true);
select throws_ok($$ select fn_aceptar_terminos('general', 1,
    'Dynamic registra mis marcajes, ausencias y pagos; avisa, nunca sanciona solo, y mis datos solo los ven quienes deben.') $$,
  null, 'No se encontró tu persona.', 'SIN PERSONA · una sesión sin persona no deja constancia a nombre de nadie');

-- ── Y la versión es por persona: lo que aceptó una no cuenta para otra ──────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000fccc', true);
select is((select fn_aceptar_terminos('general', 1,
    'Dynamic registra mis marcajes, ausencias y pagos; avisa, nunca sanciona solo, y mis datos solo los ven quienes deben.')),
  true, 'POR PERSONA · que otra ya aceptara la v1 no cuenta como aceptada para ésta');

select * from finish();
rollback;
