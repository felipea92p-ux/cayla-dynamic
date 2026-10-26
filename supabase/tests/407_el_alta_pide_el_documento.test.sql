-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 407_el_alta_pide_el_documento.test.sql — 0513
-- ============================================================================
-- Defiende la 0513. Hasta ella el alta no pedía el documento, así que el índice
-- único (0125) —el único freno exacto contra registrar dos veces a la misma
-- persona— nunca actuaba sobre un alta, y alguien llegó a escribir un DNI en el
-- apellido (0512).
--
--   1 · LA REGLA: dni 8 dígitos · ce 9-12 · pasaporte/PTP 6-12. Los bordes.
--   2 · EL CANDADO de la tabla: tipo y número van juntos y con su forma.
--   3 · EL ALTA: exige tipo y número, normaliza, y un documento repetido se
--       niega nombrando a quién —sin confirmación posible—.
--   4 · LA ESTACIÓN de retail entra sin documento y queda marcada por su puerta.
--   5 · LA CORRECCIÓN (fn_set_documento) usa la misma regla y deja el tipo en
--       el rastro; con 3 argumentos —como la llama la aprobación de «Lo mío»,
--       fn_aplicar_cambio_perfil— usa el tipo que la persona ya tenía.
--
-- Todos los nombres y números son inventados: no se sube a git un DNI real.
-- ============================================================================
begin;
select plan(35);

-- ── 1 · LA REGLA ───────────────────────────────────────────────────────────
select ok(fn_documento_forma_valida('dni', '01234567'), 'REGLA · DNI de 8 dígitos, con el cero adelante');
select ok(not fn_documento_forma_valida('dni', '1234567'), 'REGLA · DNI de 7 no');
select ok(not fn_documento_forma_valida('dni', '123456789'), 'REGLA · DNI de 9 no: eso es un carné');
select ok(not fn_documento_forma_valida('dni', '1234567A'), 'REGLA · DNI con una letra no');
select ok(fn_documento_forma_valida('ce', '001234567') and fn_documento_forma_valida('ce', 'AB1234567890'),
  'REGLA · carné de 9 (el actual) y de 12 con letras (los antiguos)');
select ok(not fn_documento_forma_valida('ce', '12345678') and not fn_documento_forma_valida('ce', '1234567890123'),
  'REGLA · carné de 8 (sería un DNI) o de 13 no');
select ok(fn_documento_forma_valida('pasaporte', 'AB1234') and fn_documento_forma_valida('pasaporte', 'AB123456'),
  'REGLA · pasaporte de 6 y de 8 con letras (uno colombiano)');
select ok(not fn_documento_forma_valida('pasaporte', 'AB123') and not fn_documento_forma_valida('otro', '12345678'),
  'REGLA · pasaporte de 5 no, y un tipo que no existe no');

-- ── 2 · EL CANDADO ─────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000040700', 'ZZ407', 'Sede de laboratorio 407', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso,
                      tipo_documento, documento) values
  ('00000000-0000-0000-0000-000000040701', 'Admin', 'Cuatrocientossiete', '00000000-0000-0000-0000-000000040700',
   'admin', 'x', '00000000-0000-0000-0000-0000000407a1', '2024-01-01', 'dni', '40700001'),
  ('00000000-0000-0000-0000-000000040702', 'Ya', 'Registrada', '00000000-0000-0000-0000-000000040700',
   'integrante', 'x', null, '2025-03-03', 'dni', '40700002'),
  ('00000000-0000-0000-0000-000000040704', 'Sin', 'Documento', '00000000-0000-0000-0000-000000040700',
   'integrante', 'x', null, '2025-03-03', null, null);
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, fecha_cese,
                      motivo_cese, tipo_documento, documento) values
  ('00000000-0000-0000-0000-000000040703', 'Ya', 'Salió', '00000000-0000-0000-0000-000000040700',
   'integrante', 'x', '2024-02-01', 'inactivo', '2026-01-31', 'renuncia', 'ce', '407000003');
set session_replication_role = origin;

select throws_ok(
  $$ update personas set tipo_documento = null where id = '00000000-0000-0000-0000-000000040702' $$,
  '23514', null, 'CANDADO · un número sin tipo no se puede guardar');
select throws_ok(
  $$ update personas set tipo_documento = 'dni' where id = '00000000-0000-0000-0000-000000040704' $$,
  '23514', null, 'CANDADO · un tipo sin número tampoco');
select throws_ok(
  $$ update personas set documento = '407000021' where id = '00000000-0000-0000-0000-000000040702' $$,
  '23514', null, 'CANDADO · un DNI de 9 dígitos se rechaza aunque venga por un UPDATE directo');
select lives_ok(
  $$ update personas set nombres = 'Sin' where id = '00000000-0000-0000-0000-000000040704' $$,
  'CANDADO · quien no tiene documento sigue editable: la obligación es del alta, no de la tabla');

-- ── 3 · EL ALTA ────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000407a1', true);
set role authenticated;

select throws_ok(
  $$ select fn_crear_persona('Nueva', 'Sintipo', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x') $$,
  'Falta el tipo de documento: DNI, carné de extranjería o pasaporte / PTP.',
  'ALTA · sin tipo de documento se niega (la pantalla vieja, que no lo manda, falla en voz alta)');
select throws_ok(
  $$ select fn_crear_persona('Nueva', 'Sinnumero', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '  ') $$,
  'Falta el número de documento. Es lo que impide registrar dos veces a la misma persona.',
  'ALTA · sin número se niega, y dice para qué sirve');
select throws_ok(
  $$ select fn_crear_persona('Nueva', 'Corta', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '4070001') $$,
  'El DNI tiene exactamente 8 dígitos.',
  'ALTA · un DNI de 7 dígitos se niega con el largo exacto, no con «inválido»');
select throws_ok(
  $$ select fn_crear_persona('Nueva', 'Larga', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'ce', '40700') $$,
  'El carné de extranjería tiene de 9 a 12 letras o números.',
  'ALTA · el mensaje sigue al tipo elegido');

select lives_ok(
  $$ select fn_crear_persona('Nueva', 'Normalizada', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', ' 4070-0010 ') $$,
  'ALTA · con su DNI entra (espacios y guion incluidos)');
select lives_ok(
  $$ select fn_crear_persona('Extranjera', 'Pasaporte', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'pasaporte', 'ab-123 456') $$,
  'ALTA · un pasaporte colombiano entra');

reset role;
select is(
  (select tipo_documento || ' ' || documento from personas where apellidos = 'Normalizada'),
  'dni 40700010',
  'ALTA · el número se guarda sin espacios ni guiones, y con su tipo');
select is(
  (select documento from personas where apellidos = 'Pasaporte'),
  'AB123456',
  'ALTA · y en mayúsculas: «ab-123 456» y «AB123456» son el mismo pasaporte para el índice único');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000407a1', true);
set role authenticated;
-- EL CASO QUE ESTO VINO A CERRAR: la misma persona, otro nombre, el mismo DNI.
select throws_like(
  $$ select fn_crear_persona('Yanina', 'Otronombre', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40700002') $$,
  'Ese documento ya lo tiene «Ya Registrada» (está en el equipo · ZZ407 · ingresó 03/03/2025)%',
  'ALTA · el mismo DNI con OTRO nombre se niega, y dice a quién pertenece (la regla de nombres no lo habría visto)');
select throws_like(
  $$ select fn_crear_persona('Otra', 'Persona', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', true, 'dni', '40700002') $$,
  'Ese documento ya lo tiene%',
  'ALTA · y NO se puede confirmar: «es otra persona» no aplica a dos personas con el mismo documento');
select throws_like(
  $$ select fn_crear_persona('Vuelve', 'Alguien', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'ce', '407000003') $$,
  '%(ya salió · ZZ407 · ingresó 01/02/2024)%reactívala desde su menú «•••»%',
  'ALTA · si ya salió, dice que se reactiva');

reset role;
create temp table _err (hint text, detail text) on commit drop;
do $$
declare v_hint text; v_detail text;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000407a1', true);
  perform fn_crear_persona('Yanina', 'Otronombre', '00000000-0000-0000-0000-000000040700',
                           'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40700002');
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint, v_detail = pg_exception_detail;
  insert into _err values (v_hint, v_detail);
end $$;
select is((select hint || ' · ' || detail from _err),
  'documento_repetido · 00000000-0000-0000-0000-000000040702',
  'LA PANTALLA · el error trae el marcador y el id de quien ya lo tiene, para «Ver en la lista»');

-- ── 4 · LA ESTACIÓN ────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000407a1', true);
set role authenticated;
select lives_ok(
  $$ select fn_crear_persona('ESTACIÓN — Caja 407', '(no es persona)', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, null, null, true) $$,
  'ESTACIÓN · entra sin documento');
select throws_ok(
  $$ select fn_crear_persona('ESTACIÓN — Almacén 407', '(no es persona)', '00000000-0000-0000-0000-000000040700',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40700099', true) $$,
  'Una estación de retail no lleva documento: no es una persona.',
  'ESTACIÓN · con documento se niega: si tiene DNI, es una persona');
select throws_ok(
  $$ select fn_crear_persona('ESTACIÓN — Jefa 407', '(no es persona)', '00000000-0000-0000-0000-000000040700',
                             'supervisor_sede', 'calidad_servicio', null, 'x', false, null, null, true) $$,
  'Una estación de retail no puede tener rol de líder ni de administración.',
  'ESTACIÓN · solo como integrante, igual que fn_set_cuenta_de_servicio');

reset role;
select is(
  (select p.cuenta_de_servicio::text || ' · ' || coalesce(p.documento, 'sin documento') || ' · ' ||
          (select count(*) from correcciones_auditoria a
            where a.persona_id = p.id and a.campo_modificado = 'personas.cuenta_de_servicio')
     from personas p where p.nombres = 'ESTACIÓN — Caja 407'),
  'true · sin documento · 1',
  'ESTACIÓN · queda marcada, y el rastro dice quién la marcó: pasó por fn_set_cuenta_de_servicio (0490)');

-- ── 5 · LA CORRECCIÓN ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000407a1', true);
set role authenticated;
select throws_ok(
  $$ select fn_set_documento('00000000-0000-0000-0000-000000040704', '407000040', null, 'dni') $$,
  'El DNI tiene exactamente 8 dígitos.',
  'CORRECCIÓN · la misma regla que el alta: un DNI de 9 se niega');
select throws_ok(
  $$ select fn_set_documento('00000000-0000-0000-0000-000000040704', '40700040', null) $$,
  'Falta el tipo de documento: DNI, carné de extranjería o pasaporte / PTP.',
  'CORRECCIÓN · con 3 argumentos (como la llama la aprobación de «Lo mío») y sin tipo previo, se niega y lo pide');
select lives_ok(
  $$ select fn_set_documento('00000000-0000-0000-0000-000000040704', '4070 0040', null, 'dni') $$,
  'CORRECCIÓN · la primera carga entra sin motivo (0344), normalizada');
select throws_like(
  $$ select fn_set_documento('00000000-0000-0000-0000-000000040704', '40700002', 'error de dedo') $$,
  'Ese documento ya lo tiene Ya Registrada%',
  'CORRECCIÓN · con 3 argumentos usa el tipo que ya tenía, y tampoco deja dos personas con el mismo documento');

reset role;
select is(
  (select valor_anterior || ' → ' || valor_nuevo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000040704' and campo_modificado = 'personas.documento'),
  '(vacío) → DNI 40700040',
  'CORRECCIÓN · el rastro dice también el tipo');

-- ── 6 · LA FORMA DE LAS FUNCIONES ──────────────────────────────────────────
select is(
  (select count(*)::int from pg_proc where proname in ('fn_crear_persona', 'fn_set_documento')
      and pronamespace = 'public'::regnamespace),
  2,
  'FIRMAS · una sola versión de cada una: dos harían ambigua la llamada de la pantalla');
select ok(
  not has_function_privilege('anon', 'fn_crear_persona(text,text,uuid,text,text,text,text,boolean,text,text,boolean)', 'execute')
  and has_function_privilege('authenticated', 'fn_documento_forma_valida(text,text)', 'execute'),
  'PERMISOS · anon no da de alta; y la regla SÍ la puede ejecutar authenticated: el CHECK la evalúa con sus permisos al editar una ficha');

select * from finish();
rollback;
