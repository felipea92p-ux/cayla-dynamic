-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Lo que sí se pega vive en supabase/migrations/.
-- ============================================================================
-- 302_el_roster_pregunta_la_regla_en_vez_de_copiarla.test.sql — defiende la 0382
-- ============================================================================
--
-- QUÉ DEFIENDE, Y POR QUÉ NO LO DEFENDÍA YA LA 293
--
--   La 0370 dejó «esta persona puede marcar en esta sede» con UNA sola
--   respuesta: `fn_persona_marca_en_sede`. La 0375, escrita el mismo día en
--   otra rama para quitarle `pin_hash` al kiosco, tuvo que cambiar la lista de
--   columnas de `terminal_roster` — y como `create or replace view` no deja
--   cambiar columnas, hizo `drop` + `create` reescribiendo el `where` desde la
--   0285. La copia volvió.
--
--   Nadie hizo nada mal, y NADA lo notó. `main` quedó en verde porque la
--   aserción que defiende la 0370 en la prueba 293 dice:
--
--       «la vista sigue ofreciendo a los mismos después de delegar»
--
--   …y eso siguió siendo cierto, porque la copia decía lo mismo que la
--   función. Medía el RESULTADO, no la ESTRUCTURA. Y el hook
--   `main-tiene-migraciones-que-no-tienes.sh` tampoco avisó: mira funciones, y
--   una vista no es una función.
--
--   Este archivo mide la estructura. Es la única forma de que el próximo
--   `drop view` + `create view` —que va a ocurrir, porque cualquier cambio de
--   columnas obliga a él— no vuelva a pasar en silencio.
--
-- LA MITAD QUE TIENE QUE ROMPERSE
--
--   Las dos primeras aserciones son las que de verdad trabajan, y se
--   comprobaron por mutación: devolviendo la vista a la copia inline de la
--   0375 —o sea, reproduciendo exactamente la regresión— las dos se ponen
--   rojas. Las demás son las de regresión: existen para que arreglar la
--   estructura no cambie a quién ve el terminal, que es lo que dejaría a una
--   sede de pie.
--
-- CUIDADO AL TOCARLO: la aserción del roster leído como `authenticated` va en
-- `lives_ok` y no en `is` a propósito — un «permission denied» dentro de un
-- `is` no sale como `not ok`, ABORTA la transacción y se lleva las aserciones
-- que falten. Es la firma «Bad plan» que se lee discreta y no lo es.
-- ============================================================================
begin;
select plan(9);

-- ── Fixtures ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000030200', 'ZZ302A', 'Sede de laboratorio A', true),
  ('00000000-0000-0000-0000-000000030201', 'ZZ302B', 'Sede de laboratorio B', true);

set session_replication_role = replica;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado, visible_todas_sedes) values
  -- De la sede del terminal: tiene que salir.
  ('00000000-0000-0000-0000-000000030210', 'Ana',  'DeLaA',   '00000000-0000-0000-0000-000000030200', 'x', '2024-01-01', 'activo', false),
  -- De la otra sede: NO tiene que salir.
  ('00000000-0000-0000-0000-000000030211', 'Beto', 'DeLaB',   '00000000-0000-0000-0000-000000030201', 'x', '2024-01-01', 'activo', false),
  -- Viaja entre sedes: sale en el roster de cualquiera. Es la mitad de la
  -- regla que una delegación mal hecha se come primero.
  ('00000000-0000-0000-0000-000000030212', 'Cira', 'Viajera', '00000000-0000-0000-0000-000000030201', 'x', '2024-01-01', 'activo', true);

-- Delia es de la sede A pero cesó: el roster filtra por `estado`, y eso se
-- queda en la VISTA y no en la función (ver el comentario de la 0382). Si
-- alguien moviera ese filtro dentro de `fn_persona_marca_en_sede`, el
-- disparador de escritura empezaría a rechazar la marca atrasada de quien ya
-- cesó — que la 0086 deja entrar a propósito, por FECHA.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado, fecha_cese, motivo_cese) values
  ('00000000-0000-0000-0000-000000030213', 'Delia', 'Cesada', '00000000-0000-0000-0000-000000030200',
   'x', '2024-01-01', 'inactivo', fn_hoy_lima() - 10, 'renuncia');

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id) values
  ('00000000-0000-0000-0000-00000003020a', '00000000-0000-0000-0000-000000030200',
   'Mac mini de la sede A', true, '00000000-0000-0000-0000-00000003020e');

set session_replication_role = origin;

-- La sesión del terminal de la sede A. Sin esto `fn_sede_actual_terminal()`
-- devuelve null y la vista no ofrece a nadie — que es su freno, no un fallo.
do $sesion$ begin
  perform set_config('request.jwt.claim.sub',
                     '00000000-0000-0000-0000-00000003020e', true);
end $sesion$;


-- ══ LO QUE TIENE QUE ROMPERSE SI LA COPIA VUELVE ═══════════════════════════
--
-- Comprobado por mutación: devolviendo el `where` de la vista a la copia
-- inline de la 0375, estas dos se ponen rojas y ninguna otra del archivo.

select ok(
  position('fn_persona_marca_en_sede' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) > 0,
  'ESTRUCTURA · el roster PREGUNTA la regla de sede, no la lleva copiada');

-- La de arriba sola no basta: alguien podría dejar la llamada a la función Y
-- la copia al lado, unidas por un `or`, y la vista seguiría «delegando»
-- mientras la copia decide de verdad. `visible_todas_sedes` es la huella de
-- esa copia — dentro de la función vive, en la vista no tiene por qué estar.
select ok(
  position('visible_todas_sedes' in
           pg_get_viewdef('public.terminal_roster'::regclass, true)) = 0,
  'ESTRUCTURA · y no queda ninguna copia inline al lado de la llamada');


-- ══ LO QUE NO TIENE QUE CAMBIAR ════════════════════════════════════════════
--
-- Un arreglo de estructura que cambie a quién ve el terminal deja una sede sin
-- poder fichar. Estas cuatro son las que impiden que «limpiar» cueste eso.

select is(
  (select string_agg(nombres, ',' order by nombres) from terminal_roster
    where id::text like '00000000-0000-0000-0000-0000000302%'),
  'Ana,Cira',
  'ROSTER · salen la de esta sede y la que viaja; no la de la otra sede ni la cesada');

-- SEIS columnas y no las cinco de la 0375: la 0381 (el mismo día, en otra
-- rama) le agregó `foto_url` a esta misma vista sin saber de esta migración,
-- y la 0382 se corrigió antes de pegarse para conservarla. Ver su cabecera
-- para el relato completo — es el mismo patrón 0370/0375 una tercera vez.
select is(
  (select string_agg(attname, ',' order by attnum) from pg_attribute
    where attrelid = 'public.terminal_roster'::regclass
      and attnum > 0 and not attisdropped),
  'id,nombres,apellidos,foto_url,sede_codigo,sede_nombre,prueba_dias,prueba_plazo',
  'COLUMNAS · las seis de la 0381 —con foto_url conservada por la 0382— y, al final, las dos de la prueba (0539)');

-- La 0375 existe para que el hash NO viaje al navegador. Que la 0382 reescriba
-- la vista es exactamente la ocasión de devolverlo sin querer.
select ok(
  position('pin_hash' in pg_get_viewdef('public.terminal_roster'::regclass, true)) = 0,
  'PIN · el hash sigue sin viajar al navegador (0375)');

-- `security_invoker = false` es lo que deja a la vista saltarse la RLS de
-- `personas`. Con `true`, el terminal recibe cero filas y la sede se queda de
-- pie sin que nada dé error.
select ok(
  coalesce((select array_to_string(reloptions, ',') from pg_class
             where oid = 'public.terminal_roster'::regclass), '')
    like '%security_invoker=false%',
  'PERMISOS · la vista sigue resolviendo como su dueño, no como quien la lee');


-- ══ Y QUE EL TERMINAL DE VERDAD PUEDA LEERLA ═══════════════════════════════
--
-- Las de arriba corren como `postgres`, que salta RLS y puede todo. Con ellas
-- solas, `revoke execute on fn_persona_marca_en_sede from authenticated` deja
-- este archivo entero en verde mientras las cuatro Mac mini reciben
-- «permission denied for function» al pintar su lista.

select ok(
  has_function_privilege('authenticated', 'fn_persona_marca_en_sede(uuid,uuid)', 'execute'),
  'GRANT · authenticated puede ejecutar la regla — sin eso el roster no se pinta');

select ok(
  has_table_privilege('authenticated', 'public.terminal_roster', 'select'),
  'GRANT · y sigue pudiendo leer la vista (el create or replace los conserva)');

set local role authenticated;
select lives_ok(
  $$ select count(*) from terminal_roster $$,
  'GRANT · y una sesión authenticated de verdad —no postgres— la lee sin reventar');
reset role;

select * from finish();
rollback;
