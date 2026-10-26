-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 400_un_alta_que_se_parece_pide_confirmacion.test.sql — 0506
-- ============================================================================
-- Defiende la 0506. `fn_crear_persona` no miraba a nadie: el 2026-10-04 una
-- persona quedó registrada dos veces, con su nombre escrito corto («Marisol |
-- Quispe») la primera vez y completo («Marisol Aurora | Quispe Rivas») la
-- segunda. Ni el índice único de documento ni el de correo podían verlo: el alta
-- no captura el documento, y dos escrituras distintas de un nombre no chocan
-- contra ninguna restricción.
--
-- Los nombres de abajo son inventados a propósito: no se sube a git el nombre de
-- una persona real.
--
-- Esta prueba hace tres cosas:
--   1 · La REGLA de parecido, contra 66 casos con su veredicto esperado. Salieron
--       de una simulación de 6 000 parejas «la misma persona tecleada dos veces»
--       y 160 000 de personas distintas; aquí quedan los casos que cuentan.
--   2 · El GUARDIÁN: dar de alta a alguien parecido se niega, nombrando a quién;
--       con confirmación pasa; quien ya salió también cuenta.
--   3 · Los PERMISOS y la forma de la función: una sola versión (la 0297/0299
--       dejó dos y la llamada quedó ambigua), cerrada a anon.
--
-- «Aviso de más aceptado»: H05, H06 y H07 avisan aunque son (o pueden ser)
-- personas distintas —Quispe Quispe / Quispe Mamani, María / Mario, Daniel /
-- Daniela—. Se dejan así A PROPÓSITO y la prueba lo fija: avisar cuesta un clic,
-- no avisar cuesta una persona duplicada con su planilla.
-- ============================================================================
begin;
select plan(29);

-- ── 1 · LA REGLA ───────────────────────────────────────────────────────────
create temp table _casos (
  id text, tipo text, debe_avisar boolean,
  n1 text, a1 text, n2 text, a2 text
) on commit drop;

insert into _casos values
  ('T01', 'T', true, 'Marisol', 'Quispe', 'Marisol Aurora', 'Quispe Rivas'),
  ('T02', 'T', true, 'Quispe Rivas', 'Marisol Aurora', 'Marisol Aurora', 'Quispe Rivas'),
  ('T03', 'T', true, 'Quispe', 'Marisol', 'Marisol Aurora', 'Quispe Rivas'),
  ('T04', 'T', true, 'Quispe Rivas Marisol Aurora', 'Quispe', 'Marisol Aurora', 'Quispe Rivas'),
  ('T05', 'T', true, 'Marisol Quispe', 'Aurora Rivas', 'Marisol Aurora', 'Quispe Rivas'),
  ('T06', 'T', true, 'María José', 'Huamán Pérez', 'Maria Jose', 'Huaman Perez'),
  ('T07', 'T', true, 'Ñusta', 'Nuñez Peña', 'Nusta', 'Nunez Pena'),
  ('T08', 'T', true, 'MARISOL AURORA', 'QUISPE RIVAS', 'marisol aurora', 'quispe rivas'),
  ('T09', 'T', true, 'Elena Nieves', 'Mamani Flores', 'Elena', 'Mamani Flores'),
  ('T10', 'T', true, 'Elena Nieves', 'Mamani Flores', 'Nieves', 'Mamani Flores'),
  ('T11', 'T', true, 'Elena Nieves', 'Mamani', 'Elena Nieves', 'Mamani Flores'),
  ('T12', 'T', true, 'Elena', 'Mamani', 'Elena Nieves', 'Mamani Flores'),
  ('T13', 'T', true, '  Marisol   Aurora ', 'Quispe  Rivas', 'Marisol Aurora', 'Quispe Rivas'),
  ('T14', 'T', true, E'Marisol\tAurora', E'Quispe Rivas', 'Marisol Aurora', 'Quispe Rivas'),
  ('T15', 'T', true, 'Rosa', 'De la Cruz Quispe', 'Rosa', 'Cruz Quispe'),
  ('T16', 'T', true, 'Pedro', 'Del Castillo Rojas', 'Pedro', 'Castillo'),
  ('T17', 'T', true, 'Carmen', 'De los Santos Flores', 'Carmen', 'Santos'),
  ('T18', 'T', true, 'Maria del Carmen', 'Quispe de la Cruz', 'Maria Carmen', 'Quispe Cruz'),
  ('T19', 'T', true, 'Maria-Jose', 'Huaman, Perez', 'Maria Jose', 'Huaman Perez'),
  ('T20', 'T', true, 'Marisol A.', 'Quispe Rivas', 'Marisol Aurora', 'Quispe Rivas'),
  ('T21', 'T', true, 'Ana Maria del Carmen Rosa', 'Quispe Mamani de la Cruz Flores', 'Ana Maria del Carmen Rosa', 'Quispe Mamani de la Cruz Flores'),
  ('T22', 'T', true, 'Ana', 'Quispe', 'Ana Maria del Carmen', 'Quispe Mamani de la Cruz'),
  ('T23', 'T', true, 'Pérez Gómez', 'José Luis', 'Jose Luis', 'Perez Gomez'),
  ('T24', 'T', true, 'Marisol Aurora', 'Quispe', 'Marisol Aurora', 'Quispe Rivas'),
  ('G01', 'GT', true, 'Marisol Aurora', 'Quispe', 'Marisol', 'Quispe Rivas'),
  ('G02', 'GT', true, 'Quispe', 'Marisol Aurora', 'Marisol', 'Quispe Rivas'),
  ('G03', 'GT', true, 'Maria Elena', 'Quispe Mamani', 'Maria', 'Quispe'),
  ('G04', 'GT', true, 'Maria', 'Quispe Mamani', 'Maria', 'Quispe Mamani'),
  ('G05', 'GT', true, 'Juan Carlos', 'Quispe Mamani', 'Juan Carlos', 'Quispe Mamani'),
  ('G06', 'GT', true, 'Marisol Aurora', 'Quispe Rivas', 'Marizol Aurora', 'Quispe Rivas'),
  ('G07', 'GT', true, 'Rosa', 'Condori Salinas', 'Rosa', 'Condori Salinis'),
  ('G08', 'GT', true, 'Lizbeth', 'Mamani Flores', 'Lizbeth', 'Mamani Florez'),
  ('G09', 'GT', true, 'Maria', 'Quispe', 'Maria', 'Quispe'),
  ('G10', 'GT', true, 'Maria', 'Quispe', 'Maria Elena', 'Quispe Mamani'),
  ('G11', 'GT', true, 'Quispe', 'Maria', 'Maria', 'Quispe'),
  ('G12', 'GT', true, 'Rosa', 'De la Cruz', 'Rosa', 'Cruz Mamani'),
  ('G13', 'GT', true, 'Marisol Aurora', 'Quispe Rivas', 'Marisol Auroar', 'Quispe Rivas'),
  ('G14', 'GT', true, 'Flor', 'Rosas Mamani', 'Rosas', 'Flor Mamani'),
  ('G15', 'GT', true, 'Elena Nieves', 'Mamani Flores', 'Elena Nievse', 'Mamani Flores'),
  ('H01', 'GF', false, 'Maria', 'Quispe', 'Maria', 'Flores'),
  ('H02', 'GF', false, 'Maria', 'Quispe', 'Rosa', 'Quispe'),
  ('H03', 'GF', false, 'Maria', 'Quispe Mamani', 'Maria', 'Quispe Flores'),
  ('H04', 'GF', false, 'Juan Carlos', 'Quispe', 'Juan Luis', 'Quispe'),
  ('H05', 'GF', true, 'Juan', 'Quispe Quispe', 'Juan', 'Quispe Mamani'),
  ('H06', 'GF', true, 'Maria', 'Quispe Mamani', 'Mario', 'Quispe Mamani'),
  ('H07', 'GF', true, 'Daniel', 'Quispe Mamani', 'Daniela', 'Quispe Mamani'),
  ('H08', 'GF', false, 'Jose Luis', 'Perez', 'Jose Luiz', 'Perez'),
  ('H09', 'GF', false, 'Ana', 'Quispe Mamani', 'Anna', 'Quispe Mamani'),
  ('H10', 'GF', false, 'Maria', 'Rojas Mamani', 'Mario', 'Rosas Mamani'),
  ('F01', 'F', false, 'Maria', 'Quispe', 'Maria', 'Flores'),
  ('F02', 'F', false, 'Maria', 'Quispe Mamani', 'Maria', 'Flores Rojas'),
  ('F03', 'F', false, 'Juan', 'Quispe Mamani', 'Rosa', 'Quispe Mamani'),
  ('F04', 'F', false, 'Quispe Mamani', 'Juan', 'Rosa', 'Quispe Mamani'),
  ('F05', 'F', false, 'Elena Nieves', 'Mamani Flores', 'Rosa Maria', 'Flores Mamani'),
  ('F06', 'F', false, 'Juan Carlos', 'Condori Rojas', 'Luis Alberto', 'Condori Rojas'),
  ('F07', 'F', false, 'Ana Lucia', 'Huaman Chavez', 'Pedro Pablo', 'Chavez Salinas'),
  ('F08', 'F', false, 'Jose Luis', 'Perez Gomez', 'Jose Luis', 'Rivas Rojas'),
  ('F09', 'F', false, 'Juan Carlos', 'Quispe', 'Carlos Alberto', 'Mamani'),
  ('F10', 'F', false, 'Marisol Aurora', 'Quispe Rivas', 'Rosa', 'Mamani'),
  ('F11', 'F', false, 'Marisol', 'Quispe', 'Rosa', 'Quispe'),
  ('F12', 'F', false, 'Marisol Aurora', 'Quispe Rivas', 'Marisol Aurora', 'Mamani Flores'),
  ('F13', 'F', false, 'Maria', 'De la Cruz', 'Rosa', 'De la Cruz'),
  ('F14', 'F', false, 'Ana', 'Del Castillo', 'Luis', 'Del Pino'),
  ('F15', 'F', false, 'Ana', 'Quispe', 'Ana Maria', 'Flores Rojas'),
  ('F16', 'F', false, 'Rosa Maria', 'Quispe', 'Maria Elena', 'Quispe'),
  ('F18', 'F', false, 'Maria Elena', 'Condori Salinas', 'Rosa Luz', 'Chavez Torres');

-- T = debe avisar · GT = gris, decidido avisar · F = no debe avisar ·
-- GF = gris, decidido no avisar (salvo los tres de arriba).
select is_empty(
  $$ select id, tipo, debe_avisar, fn_nombres_parecidos(n1, a1, n2, a2) as avisa
       from _casos
      where fn_nombres_parecidos(n1, a1, n2, a2) is distinct from debe_avisar
      order by id $$,
  'LA REGLA · los 66 casos dan el veredicto esperado (si falla, lista cuáles)');

select is_empty(
  $$ select id from _casos
      where fn_nombres_parecidos(n1, a1, n2, a2) is distinct from fn_nombres_parecidos(n2, a2, n1, a1) $$,
  'LA REGLA · es simétrica: da igual cuál de las dos altas fue la primera');

select is_empty(
  $$ select id from _casos where fn_nombres_parecidos(n1, a1, n2, a2) is null $$,
  'LA REGLA · nunca devuelve NULL (un NULL se leería como «no avisa»)');

select is(
  fn_nombre_clave('  María-José  DE LA Cruz Ñ. '),
  array['cruz','jose','maria']::text[],
  'LA CLAVE · sin tildes ni mayúsculas, sin partículas ni letras sueltas, ordenada');

select is(fn_nombres_parecidos('', '', '', ''), false,
  'LA REGLA · dos textos vacíos no son «la misma persona»');

-- Tilde DESCOMPUESTA (un PDF o un archivo de Mac trae «á» como «a» + una tilde
-- suelta): sin normalizar, la tilde caería en el filtro y «María» quedaría «mari».
select ok(
  fn_nombres_parecidos(normalize('María José', NFD), normalize('Huamán Pérez', NFD), 'Maria Jose', 'Huaman Perez'),
  'LA REGLA · el mismo nombre con tildes descompuestas (NFD) sigue siendo el mismo');

-- Las dos ramas «sin mirar campos» (c), en AMBOS órdenes: palabras repartidas a
-- medias entre nombres y apellidos. Sin esta aserción se podía borrar la mitad de
-- la regla y la prueba seguía en verde.
select ok(
  fn_nombres_parecidos('Rosa', 'Maria Quispe', 'Maria', 'Quispe')
  and fn_nombres_parecidos('Maria', 'Quispe', 'Rosa', 'Maria Quispe'),
  'LA REGLA · todas las palabras de una están en la otra aunque estén en el otro campo (los dos órdenes)');

-- ── 2 · EL GUARDIÁN ────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000040000', 'ZZ400', 'Sede de laboratorio', true);

-- Un admin que da de alta; una persona ya en el equipo; una que ya salió; y un
-- integrante, que NO puede ni preguntar quién existe.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000040001', 'Admin', 'Laboratorio', '00000000-0000-0000-0000-000000040000',
   'admin', 'x', '00000000-0000-0000-0000-0000000400a1', '2024-01-01'),
  ('00000000-0000-0000-0000-000000040002', 'Marisol', 'Quispe', '00000000-0000-0000-0000-000000040000',
   'integrante', 'x', null, '2026-10-03'),
  ('00000000-0000-0000-0000-000000040004', 'Soledad', 'Colque', '00000000-0000-0000-0000-000000040000',
   'integrante', 'x', '00000000-0000-0000-0000-0000000400a4', '2025-05-05');
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, fecha_cese, motivo_cese) values
  ('00000000-0000-0000-0000-000000040003', 'Elena Nieves', 'Mamani Flores', '00000000-0000-0000-0000-000000040000',
   'integrante', 'x', '2025-02-01', 'inactivo', '2026-01-31', 'renuncia');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000400a1', true);
set role authenticated;

-- EL CASO REAL: el mismo nombre, escrito completo, cuando ya está escrito corto.
select throws_like(
  $$ select fn_crear_persona('Marisol Aurora', 'Quispe Rivas', '00000000-0000-0000-0000-000000040000',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40000001') $$,
  'Ya hay alguien registrado que se parece: «Marisol Quispe» (está en el equipo · ZZ400 · ingresó 03/10/2026)%',
  'BLOQUEADO · dar de alta «Marisol Aurora Quispe Rivas» cuando ya está «Marisol Quispe» se niega, y dice A QUIÉN se parece');

-- Quien ya salió también cuenta: se reactiva, no se vuelve a crear.
select throws_like(
  $$ select fn_crear_persona('Elena', 'Mamani', '00000000-0000-0000-0000-000000040000',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40000002') $$,
  '%«Elena Nieves Mamani Flores» (ya salió · ZZ400 · ingresó 01/02/2025)%',
  'BLOQUEADO · quien ya salió del equipo también cuenta: se reactiva, no se registra otra vez');

-- Lo que NO es la misma persona pasa sin preguntar nada.
select lives_ok(
  $$ select fn_crear_persona('Marisol', 'Condori', '00000000-0000-0000-0000-000000040000',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40000003') $$,
  'PERMITIDO · mismo nombre de pila con otro apellido es otra persona: no avisa');

select lives_ok(
  $$ select fn_crear_persona('Rosa', 'Huanca', '00000000-0000-0000-0000-000000040000',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40000004') $$,
  'PERMITIDO · un nombre que no se parece a nadie se da de alta como siempre');

-- Con confirmación, pasa: los homónimos reales existen.
select lives_ok(
  $$ select fn_crear_persona('Marisol Aurora', 'Quispe Rivas', '00000000-0000-0000-0000-000000040000',
                             'integrante', 'calidad_servicio', null, 'x', true, 'dni', '40000005') $$,
  'PERMITIDO · con p_confirmo_distinta = true, quien da de alta asume que es otra persona');

-- Un NULL en la confirmación NO la da por hecha: solo `true` abre la puerta.
select throws_like(
  $$ select fn_crear_persona('Marisol Aurora', 'Quispe Rivas', '00000000-0000-0000-0000-000000040000',
                             'integrante', 'calidad_servicio', null, 'x', null, 'dni', '40000006') $$,
  'Ya hay alguien registrado que se parece:%',
  'BLOQUEADO · p_confirmo_distinta = NULL se lee como «no confirmó», no como «sí»');

reset role;
select is(
  (select count(*)::int from personas where nombres = 'Marisol Aurora' and apellidos = 'Quispe Rivas'),
  1,
  'La persona confirmada quedó creada UNA vez: lo bloqueado de antes no dejó nada a medias');

-- Y ahora ya hay DOS parecidas: sin confirmar vuelve a negarse (no se «acostumbra»).
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000400a1', true);
set role authenticated;
select throws_like(
  $$ select fn_crear_persona('Marisol Aurora', 'Quispe Rivas', '00000000-0000-0000-0000-000000040000',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40000007') $$,
  'Ya hay alguien registrado que se parece:%',
  'BLOQUEADO · confirmar una vez no abre la puerta para siempre: la siguiente alta igual vuelve a preguntar');

-- El marcador estable que la pantalla lee (error.hint), sin leer el texto.
reset role;
create temp table _hint (hint text, sqlstate text) on commit drop;
do $$
declare v_hint text; v_state text;
begin
  perform fn_crear_persona('Elena', 'Mamani', '00000000-0000-0000-0000-000000040000',
                           'integrante', 'calidad_servicio', null, 'x', false, 'dni', '40000008');
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  v_state := sqlstate;
  insert into _hint values (v_hint, v_state);
end $$;
select is((select hint from _hint), 'persona_parecida',
  'LA PANTALLA · el error trae el marcador «persona_parecida» en el hint');
select is((select sqlstate from _hint), 'P0001',
  'LA PANTALLA · y es un P0001 normal: mensajeDeError lo muestra tal cual, sin prefijo');

-- Las validaciones de siempre siguen primero: un rol inválido NO se disfraza de «parecida».
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000400a1', true);
set role authenticated;
select throws_ok(
  $$ select fn_crear_persona('Marisol Aurora', 'Quispe Rivas', '00000000-0000-0000-0000-000000040000',
                             'gerente', 'calidad_servicio', null, 'x', false, 'dni', '40000009') $$,
  'Rol inválido: gerente',
  'SIN ROMPER LO VIEJO · un rol inválido sigue dando su propio error aunque el nombre se parezca');

-- ── 3 · A QUIÉN SE PARECE, y quién puede preguntarlo ───────────────────────
select is(
  (select array_agg(nombres || ' ' || apellidos || ' · ' || estado order by nombres, apellidos)
     from fn_personas_parecidas('Marisol', 'Quispe')),
  array['Marisol Quispe · activo', 'Marisol Aurora Quispe Rivas · activo']::text[],
  'LA PREGUNTA · devuelve a quienes se parecen, con su estado (la recién confirmada también)');

select is(
  (select sede_codigo from fn_personas_parecidas('Elena', 'Mamani')),
  'ZZ400',
  'LA PREGUNTA · y su sede, para que quien confirma vea de quién se trata');

select is((select count(*)::int from fn_personas_parecidas('', 'Quispe')), 0,
  'LA PREGUNTA · con el nombre vacío no devuelve a nadie, en vez de «todos»');

select throws_ok(
  $$ select * from fn_personas_parecidas(repeat('ab ', 60), 'Quispe') $$,
  'Nombres y apellidos no pueden pasar de 120 caracteres cada uno.',
  'LA PREGUNTA · un texto enorme se rechaza antes de comparar (la comparación es cuadrática y corre con el candado tomado)');

reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000400a4', true);
set role authenticated;
select throws_ok(
  $$ select * from fn_personas_parecidas('Marisol', 'Quispe') $$,
  'Solo un administrador o líder puede ver si alguien ya está registrado.',
  'PERMISOS · un integrante no puede preguntar quién está registrado');
reset role;

-- ── 4 · LA FORMA DE LA FUNCIÓN ─────────────────────────────────────────────
select is((select count(*)::int from pg_proc where proname = 'fn_crear_persona'), 1,
  'UNA SOLA VERSIÓN · fn_crear_persona no quedó con dos firmas (la 0297/0299 dejó dos y la llamada quedó ambigua)');

select ok(
  has_function_privilege('authenticated', 'fn_crear_persona(text,text,uuid,text,text,text,text,boolean,text,text,boolean)', 'execute')
  and has_function_privilege('authenticated', 'fn_personas_parecidas(text,text)', 'execute'),
  'PERMISOS · quien inició sesión puede llamar a las dos funciones que usa la pantalla');

select ok(
  not has_function_privilege('anon', 'fn_crear_persona(text,text,uuid,text,text,text,text,boolean,text,text,boolean)', 'execute')
  and not has_function_privilege('anon', 'fn_personas_parecidas(text,text)', 'execute'),
  'PERMISOS · quien no inició sesión no puede llamar a ninguna de las dos');

select ok(
  not has_function_privilege('authenticated', 'fn_nombre_clave(text)', 'execute')
  and not has_function_privilege('authenticated', 'fn_tipeo_de_una_letra(text,text)', 'execute')
  and not has_function_privilege('authenticated', 'fn_nombres_compatibles(text[],text[],text[],text[])', 'execute')
  and not has_function_privilege('authenticated', 'fn_nombres_parecidos(text,text,text,text)', 'execute'),
  'PERMISOS · las cuatro piezas de la regla no se abren a la API: solo las llaman las dos de arriba');

select ok(
  (select prosrc from pg_proc where proname = 'fn_crear_persona') like '%pg_advisory_xact_lock%',
  'UNA ALTA A LA VEZ · el candado que pone en fila a dos altas simultáneas sigue dentro');

-- El candado tiene que tomarse ANTES de preguntar a quién se parece: tomado
-- después no sirve de nada (las dos altas ya habrían pasado la comprobación).
-- Se probó a mano con dos sesiones: con el candado, dos altas del mismo nombre
-- dejan UNA fila; sin él, DOS.
select ok(
  position('pg_advisory_xact_lock' in (select prosrc from pg_proc where proname = 'fn_crear_persona'))
    < position('fn_personas_parecidas' in (select prosrc from pg_proc where proname = 'fn_crear_persona')),
  'UNA ALTA A LA VEZ · y se toma ANTES de comprobar los parecidos, no después');

select * from finish();
rollback;
