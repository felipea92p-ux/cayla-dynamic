-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 292_un_codigo_de_sede_no_se_pisa_en_silencio.test.sql
-- ============================================================================
-- Cubre la 0367 (hallazgo 33 de la auditoría del 2026-09-03/04). Hasta ella,
-- `fn_guardar_sede` era un upsert ciego sobre `codigo`: crear una sede con un
-- código que ya existía le cambiaba el nombre y el tipo a la sede que ya lo
-- tenía, sin decir nada. Dos personas creando «LIM03» en pestañas distintas
-- veían las dos que no existía, guardaban las dos, y la segunda pisaba a la
-- primera. De `sedes` cuelgan marcajes, jornadas, horarios y la sede base de
-- cada persona: no es una etiqueta.
--
-- LO QUE SE FIJA ACÁ, y el orden importa:
--   1. un alta normal sigue creando, con su nombre y su tipo;
--   2. un alta con un código que ya existe LANZA — y no toca a la sede que ya
--      lo tenía, que es la mitad que de verdad importa: un error visible no
--      sirve de nada si el daño ya se hizo;
--   3. una edición que le pone a una sede el código de OTRA también lanza;
--   4. y la que un `unique` mal escrito rompería: guardar una sede dejándole
--      SU PROPIO código sigue funcionando, que es lo que hace la pantalla cada
--      vez que alguien corrige un nombre;
--   5. el camino histórico —editar por código, sin id, como hace la prueba
--      100— sigue vivo, y editar un código que no existe ya no crea nada por
--      su cuenta: lo dice y manda a «Agregar sede»;
--   6. el `codigo` de una sede sigue siendo inmutable: cambiarlo por uno
--      LIBRE tampoco pasa, y lo dice en vez de ignorarlo. Tres columnas
--      apuntan a la sede por texto y sin clave foránea —la tarifa de
--      movilidad por sede, la planilla ya pagada, el roster del terminal—,
--      así que un renombrado silencioso las dejaría huérfanas sin un error;
--   7. los mensajes están en español y dicen qué hacer;
--   8. el guard de permiso sigue en su sitio, y sigue siendo `is not true`.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-000000292001'::uuid, 'ZZ367A', 'Sede A de laboratorio', true, 'central'),
  ('00000000-0000-0000-0000-000000292002'::uuid, 'ZZ367B', 'Sede B de laboratorio', true, 'taller');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000292010'::uuid, 'SedeAdmin', 'Lab',
        '00000000-0000-0000-0000-000000292001'::uuid, 'admin', 'x',
        '00000000-0000-0000-0000-00000029201a'::uuid, '2024-01-01');
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000029201a', true);

-- ── 1. El alta normal ───────────────────────────────────────────────────────
select lives_ok(
  $$ select fn_guardar_sede('ZZ367C', 'Sede C de laboratorio', 'tienda', null, true) $$,
  'ALTA · crear una sede con un código libre sigue funcionando');

select is((select nombre || '/' || tipo from sedes where codigo = 'ZZ367C'),
          'Sede C de laboratorio/tienda',
          'ALTA · y queda con el nombre y el tipo que se pidieron');

-- ── 2. El alta duplicada ────────────────────────────────────────────────────
-- El defecto entero, en dos aserciones: que avise, y —lo que de verdad
-- importa— que la sede que ya tenía ese código quede intacta.
select throws_like(
  $$ select fn_guardar_sede('ZZ367A', 'Sede pisada por descuido', 'tienda', null, true) $$,
  '%Ya existe una sede con el código%',
  'ALTA REPETIDA · crear con un código que ya existe lanza en vez de pisar');

select is((select nombre || '/' || tipo from sedes where codigo = 'ZZ367A'),
          'Sede A de laboratorio/central',
          'ALTA REPETIDA · y la sede que ya tenía ese código no cambió ni de nombre ni de tipo');

-- El mensaje es para una persona, no para un log: dice el código, dice de
-- quién es, y dice qué apretar.
select throws_like(
  $$ select fn_guardar_sede('ZZ367A', 'Sede pisada por descuido', 'tienda', null, true) $$,
  '%usa «Editar» en su fila%',
  'ALTA REPETIDA · y el mensaje está en español y dice qué hacer');

-- ── 3. Renombrar al código de otra ──────────────────────────────────────────
select throws_like(
  $$ select fn_guardar_sede('ZZ367B', 'Sede A con el código de la B', null,
                            '00000000-0000-0000-0000-000000292001'::uuid, false) $$,
  '%ya lo usa la sede%',
  'EDICIÓN · ponerle a una sede el código que ya tiene OTRA lanza');

select is((select nombre from sedes where codigo = 'ZZ367B'),
          'Sede B de laboratorio',
          'EDICIÓN · y la sede dueña de ese código tampoco se movió');

-- ── 4. Su propio código ─────────────────────────────────────────────────────
-- El caso que rompe un `unique` escrito sin el `id <> v_id`: guardar una sede
-- sin cambiarle el código. Es lo que hace la pantalla cada vez que alguien
-- corrige un nombre, así que romperlo dejaría Sedes sin poder editar nada.
select lives_ok(
  $$ select fn_guardar_sede('ZZ367A', 'Sede A renombrada', null,
                            '00000000-0000-0000-0000-000000292001'::uuid, false) $$,
  'EDICIÓN · guardar una sede dejándole SU PROPIO código sigue funcionando');

select is((select nombre || '/' || tipo from sedes where codigo = 'ZZ367A'),
          'Sede A renombrada/central',
          'EDICIÓN · el nombre se guardó y el tipo no se borró (p_tipo null = «no lo toques»)');

-- ── 5. El camino histórico: editar por código, sin id ───────────────────────
select lives_ok(
  $$ select fn_guardar_sede('ZZ367B', 'Sede B renombrada') $$,
  'EDICIÓN SIN ID · la llamada de dos argumentos sigue renombrando por código');

select is((select nombre || '/' || tipo from sedes where codigo = 'ZZ367B'),
          'Sede B renombrada/taller',
          'EDICIÓN SIN ID · y tampoco le borra el tipo');

select throws_like(
  $$ select fn_guardar_sede('ZZ367Z', 'Sede que nadie creó') $$,
  '%usa «Agregar sede»%',
  'EDICIÓN SIN ID · editar un código que no existe ya no lo crea por su cuenta: manda a «Agregar sede»');

-- Un id que ya no está —la sede se desactivó y alguien tenía la pantalla
-- abierta— tampoco puede terminar creando una sede nueva.
select throws_like(
  $$ select fn_guardar_sede('ZZ367C', 'Sede fantasma', null,
                            '00000000-0000-0000-0000-000000292099'::uuid, false) $$,
  '%ya no existe%',
  'EDICIÓN · un id que no existe lanza en vez de crear una sede por su cuenta');

-- ── 6. El código no se cambia, ni siquiera por uno libre ────────────────────
-- El caso que la 0367 abrió sin querer: la edición por `id` podía escribir el
-- `codigo`, cosa que el upsert de la 0099 no podía hacer. Y de ese texto
-- cuelgan, sin clave foránea, `parametros_laborales.sede_codigo` —la tarifa de
-- movilidad de esa sede, o sea plata—, `planilla_pagada_detalle.sede_codigo` y
-- `terminal_roster.sede_codigo`. Renombrar los dejaría huérfanos en silencio.
select throws_like(
  $$ select fn_guardar_sede('ZZ367Y', 'Sede A con otro código', null,
                            '00000000-0000-0000-0000-000000292001'::uuid, false) $$,
  '%no se cambia una vez creada%',
  'EDICIÓN · cambiarle el código a uno LIBRE también lanza, y lo dice');

select is((select codigo || '/' || nombre from sedes
            where id = '00000000-0000-0000-0000-000000292001'::uuid),
          'ZZ367A/Sede A renombrada',
          'EDICIÓN · y la sede conserva su código: no se renombró en silencio');

-- ── 7. El permiso ───────────────────────────────────────────────────────────
-- El guard va primero que todo lo demás, y con `is not true`: sin sesión
-- reconocible, `fn_es_admin_o_lider()` no autoriza.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002920ff', true);
select throws_like(
  $$ select fn_guardar_sede('ZZ367D', 'Sede de quien no puede', 'tienda', null, true) $$,
  '%Solo un administrador o líder%',
  'PERMISO · quien no es administradora ni líder no puede crear una sede');

select * from finish();
rollback;
