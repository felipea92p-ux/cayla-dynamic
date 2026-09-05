-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 293_un_terminal_no_marca_por_otra_sede.test.sql — defiende la 0370
-- ============================================================================
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   Que la puerta de ESCRITURA de marcajes no acepte a quien la de LECTURA
--   nunca ofreció. Si esto se pone rojo, un terminal vuelve a poder registrar
--   horas de gente de otra sede con solo tener su UUID — y la sede es lo que
--   decide el turno esperado, la tardanza y la movilidad de esa jornada.
--
-- LAS DOS MITADES, que es lo que de verdad se prueba aquí
--
--   Un candado que cierra siempre no es un candado: es una pantalla rota, y
--   alguien lo quita en la primera urgencia. Así que por cada movimiento que
--   tiene que rebotar hay otros que tienen que seguir entrando: la gente de la
--   propia sede, quien viaja entre sedes (0008), la marca atrasada de quien ya
--   cesó (0086), las escrituras que NO son del terminal (0342), la marca que
--   la cola offline entrega después de un cambio de sede, y el botón «Sí,
--   volví a entrar».
--
-- LAS TRES PUERTAS TIENEN CADA UNA SU CASO NEGATIVO, Y ESA ES LA LECCIÓN
--
--   La versión anterior de este archivo defendía la puerta de gracia con
--   aserciones que solo la ejercían por el lado fácil: TRES mutaciones
--   distintas del predicado —quitarle la comparación de sede, quitarle el
--   `anulada_at is null`, ensanchar la ventana a diez años— dejaban las trece
--   aserciones EN VERDE. Medía la puerta con la etiqueta de la puerta y no
--   probaba ni una forma de forzarla.
--
--   Por eso ahora cada puerta trae su pareja: la que tiene que ENTRAR y la que
--   tiene que REBOTAR.
--     · puerta 2 (cambio de sede auditado): entra la marca ANTERIOR al cambio,
--       rebota la POSTERIOR;
--     · puerta 3 (jornada ya viva aquí): entra la salida que la cierra, rebota
--       la que se apoya en una jornada de OTRA sede, y rebota la ENTRADA que
--       intenta apoyarse en la marca mala de ayer — el encadenamiento que
--       indultaba para siempre a la población que este defecto ya creó.
--
-- POR QUÉ EL DÍA DE LAS DOS «FUERA DE ALCANCE» TIENE QUE ESTAR VACÍO
--
--   Misma trampa, descubierta mutando. Si esas dos correcciones cayeran en un
--   día del que ya cuelga una jornada viva en esa sede, la puerta 3 las dejaría
--   pasar por su cuenta y la aserción mediría la puerta 3 llevando la etiqueta
--   del acotamiento a `origen`. Por eso caen en días de los que no cuelga nada.
--
-- POR QUÉ ALGUNAS COSAS SE MIDEN CON UN INSERT DIRECTO
--
--   `fn_registrar_marcaje` valida la máquina de estados ANTES de insertar, así
--   que una salida sin entrada abierta rebota por ella y nunca llega al
--   disparador: la aserción diría «rebotó» sin haber medido el candado. Donde
--   hace falta juzgar el disparador a solas, el movimiento es un `insert into
--   marcajes` directo — que sí pasa por él, y lo prueba el hecho de que quitarle
--   el acotamiento a `origen` pone rojas la 10 y la 11.
--
-- OJO AL `session_replication_role`
--
--   `replica` salta la FK contra auth.users, que en las pruebas no existe —
--   pero APAGA TAMBIÉN LOS DISPARADORES. Así que los fixtures van dentro del
--   bloque y todos los movimientos que se miden van FUERA. Si se mueve un
--   `insert into marcajes` hacia dentro, esta prueba pasa en verde sin que el
--   candado exista.
-- ============================================================================
begin;
select plan(22);

-- ── Fixtures ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000028600', 'ZZ286A', 'Sede de laboratorio A', true),
  ('00000000-0000-0000-0000-000000028601', 'ZZ286B', 'Sede de laboratorio B', true),
  -- La C existe solo para una pregunta: que un cambio de sede auditado sirva
  -- de llave para LA SEDE DE LA QUE VINO y no para cualquiera.
  ('00000000-0000-0000-0000-000000028602', 'ZZ286C', 'Sede de laboratorio C', true);

set session_replication_role = replica;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado, visible_todas_sedes) values
  ('00000000-0000-0000-0000-000000028610', 'Ana',  'DeLaA',   '00000000-0000-0000-0000-000000028600', 'x', '2024-01-01', 'activo', false),
  ('00000000-0000-0000-0000-000000028611', 'Beto', 'DeLaB',   '00000000-0000-0000-0000-000000028601', 'x', '2024-01-01', 'activo', false),
  ('00000000-0000-0000-0000-000000028612', 'Cira', 'Viajera', '00000000-0000-0000-0000-000000028601', 'x', '2024-01-01', 'activo', true),
  ('00000000-0000-0000-0000-000000028614', 'Eva',  'Mudada',  '00000000-0000-0000-0000-000000028601', 'x', '2024-01-01', 'activo', false),
  -- Fabi es la de la cola offline: HOY todavía es de la A, y a mitad del
  -- archivo Desarrollo Organizacional la muda a la B.
  ('00000000-0000-0000-0000-000000028615', 'Fabi', 'EnTransito', '00000000-0000-0000-0000-000000028600', 'x', '2024-01-01', 'activo', false),
  -- Gina es la población que el defecto YA dejó en producción: es de la B y
  -- tiene marcas de AYER en la A, escritas cuando no había candado.
  ('00000000-0000-0000-0000-000000028616', 'Gina', 'MalMarcada', '00000000-0000-0000-0000-000000028601', 'x', '2024-01-01', 'activo', false),
  -- Iris es de la B y arrastra dos jornadas viejas en la A: una ABIERTA de
  -- hace 30 días y una CERRADA de ayer. Con las dos a la vez, una sola
  -- aserción mide las dos condiciones de la puerta 3 que nada más mide —que
  -- la jornada esté VIVA y que esté DENTRO de la ventana— porque relajar
  -- cualquiera de las dos le abre la puerta a una de esas jornadas.
  ('00000000-0000-0000-0000-000000028618', 'Iris', 'DosJornadas', '00000000-0000-0000-0000-000000028601', 'x', '2024-01-01', 'activo', false),
  -- Quien firma la auditoría del cambio de sede.
  ('00000000-0000-0000-0000-000000028617', 'Hilda', 'DeOrg', '00000000-0000-0000-0000-000000028600', 'x', '2024-01-01', 'activo', false);

-- Delia cesó hace 10 días. Estado, fecha y motivo van en el MISMO insert:
-- `personas_cese_coherente` (0086) no admite hacerlo en dos pasos.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash,
                      fecha_ingreso, estado, fecha_cese, motivo_cese) values
  ('00000000-0000-0000-0000-000000028613', 'Delia', 'Cesada', '00000000-0000-0000-0000-000000028600',
   'x', '2024-01-01', 'inactivo', fn_hoy_lima() - 10, 'renuncia');

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id) values
  ('00000000-0000-0000-0000-00000002860a', '00000000-0000-0000-0000-000000028600',
   'Mac mini de la sede A', true, '00000000-0000-0000-0000-00000002860e'),
  ('00000000-0000-0000-0000-00000002860b', '00000000-0000-0000-0000-000000028601',
   'Mac mini de la sede B', true, '00000000-0000-0000-0000-00000002860f');

-- Eva trabajaba en la sede A y ahora su base es la B: su historia en A quedó
-- con la sede vieja, porque `marcajes.sede_id` no se actualiza nunca. Esta
-- marca del día −20 es esa historia. Va aquí dentro a propósito: no es un
-- movimiento que se esté midiendo. Y los días −40 y −45 se dejan VACÍOS a
-- propósito — ver «POR QUÉ EL DÍA … TIENE QUE ESTAR VACÍO» arriba.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000028614',
        '00000000-0000-0000-0000-000000028600', 'entrada',
        ((fn_hoy_lima() - 20) + time '08:00') at time zone 'America/Lima', 'terminal');

-- La jornada mala de Gina: una entrada de AYER en la sede A, que es lo que el
-- defecto escribía. Queda ABIERTA a propósito, que es el caso PEOR: si la
-- puerta 3 pudiera abrir jornada, esta le daría llave para hoy, la de hoy para
-- mañana, y el candado no mordería jamás a quien más falta le hace.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000028616',
   '00000000-0000-0000-0000-000000028600', 'entrada',
   ((fn_hoy_lima() - 1) + time '08:00') at time zone 'America/Lima', 'terminal');

-- Las dos jornadas de Iris en la sede A: la de hace 30 días sin cerrar
-- (ABIERTA, fuera de la ventana) y la de ayer completa (CERRADA, dentro).
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000028618',
   '00000000-0000-0000-0000-000000028600', 'entrada',
   ((fn_hoy_lima() - 30) + time '08:00') at time zone 'America/Lima', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000028618',
   '00000000-0000-0000-0000-000000028600', 'entrada',
   ((fn_hoy_lima() - 1) + time '08:00') at time zone 'America/Lima', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000028618',
   '00000000-0000-0000-0000-000000028600', 'salida_final',
   ((fn_hoy_lima() - 1) + time '18:00') at time zone 'America/Lima', 'terminal');

-- Beto vino de la sede C y lo mudaron a la B, por la puerta de la 0342. Ese
-- cambio es una llave — pero solo de la C.
insert into correcciones_auditoria
  (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
values ('00000000-0000-0000-0000-000000028611', 'personas.sede_base_id', 'ZZ286C', 'ZZ286B',
        'Cambio de sede base — puede mover la tarifa de movilidad del periodo abierto.',
        '00000000-0000-0000-0000-000000028617');

set session_replication_role = origin;   -- ← los disparadores vuelven a estar vivos

-- Las jornadas de esos fixtures se calcularon con los disparadores apagados:
-- se reconstruyen a mano para que la puerta 3 tenga qué mirar.
do $recalculo$ begin
  perform fn_recalcular_jornada('00000000-0000-0000-0000-000000028616', fn_hoy_lima() - 1);
  perform fn_recalcular_jornada('00000000-0000-0000-0000-000000028618', fn_hoy_lima() - 30);
  perform fn_recalcular_jornada('00000000-0000-0000-0000-000000028618', fn_hoy_lima() - 1);
end $recalculo$;

-- ── El candado existe ───────────────────────────────────────────────────────
-- Por sí sola esta aserción no vale nada: un disparador mal escrito existe
-- igual. Las de abajo intentan de verdad cada movimiento.
select ok(
  exists (select 1 from pg_trigger
           where tgname = 'trg_marcaje_sede_permitida'
             and tgrelid = 'public.marcajes'::regclass
             and not tgisinternal),
  'EXISTE · el candado de sede está puesto sobre marcajes');

select ok(
  exists (select 1 from pg_trigger
           where tgname = 'trg_marcaje_no_posterior_al_cese'
             and tgrelid = 'public.marcajes'::regclass
             and not tgisinternal),
  'EXISTE · y el candado del cese (0086) sigue donde estaba');

-- ── La sesión del terminal de la sede A ─────────────────────────────────────
-- En un `do` y no en un `select`: un select suelto imprime una fila en medio
-- del flujo TAP que pg_prove tiene que ignorar. Mejor no darle nada que ignorar.
do $sesion$ begin
  perform set_config('request.jwt.claim.sub',
                     '00000000-0000-0000-0000-00000002860e', true);
end $sesion$;

-- ── La puerta de LECTURA sigue diciendo lo mismo ────────────────────────────
-- La 0370 reescribe `terminal_roster` (0285) para que su condición de sede la
-- responda `fn_persona_marca_en_sede`. Si esa delegación cambia a quién ofrece
-- la vista, el terminal deja de pintar a alguien que sí puede marcar — una
-- sede entera de pie sin poder fichar. Tienen que salir los de la sede A
-- (Ana, Fabi, Hilda) y Cira, que viaja; no Beto, Eva ni Gina (son de la B) ni
-- Delia (cesó).
select is(
  (select string_agg(nombres, ',' order by nombres) from terminal_roster
    where id::text like '00000000-0000-0000-0000-0000000286%'),
  'Ana,Cira,Fabi,Hilda',
  'ROSTER · la vista sigue ofreciendo a los mismos después de delegar la regla de sede');

-- Y ahora con el ROL de verdad. La aserción de arriba corre como `postgres`,
-- que salta RLS y tiene todos los privilegios: con ella sola, `revoke execute
-- on fn_persona_marca_en_sede from authenticated` deja la prueba entera en
-- verde mientras las cuatro Mac mini reciben «permission denied for function»
-- al pintar su lista. El grant que la 0370 llama «no opcional» lo sostiene
-- esta aserción y ninguna otra.
select ok(
  has_function_privilege('authenticated', 'fn_persona_marca_en_sede(uuid,uuid)', 'execute'),
  'GRANT · authenticated puede ejecutar la regla de sede — sin eso el roster no se pinta');

-- Y el comportamiento, no solo el catálogo: leído con el ROL de verdad. Va en
-- `lives_ok` y no en `is` a propósito — un «permission denied» dentro de un
-- `is` no sale como `not ok`: ABORTA la transacción y se lleva por delante las
-- aserciones que faltan, que es la firma «Bad plan» que se lee discreta y no
-- lo es. `lives_ok` lo captura y lo reporta.
set local role authenticated;
select lives_ok(
  $$ select count(*) from terminal_roster $$,
  'GRANT · y una sesión authenticated de verdad —no postgres— puede LEER el roster');
reset role;

-- ── LA MITAD QUE TIENE QUE REBOTAR ──────────────────────────────────────────
select throws_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028611'::uuid, 'entrada'::tipo_marca,
       now(), gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  'Esta persona no está habilitada para marcar en la sede ZZ286A. Si vino de visita, Desarrollo Organizacional puede habilitarla para marcar en todas las sedes.',
  'BLOQUEADO · el terminal de A no registra horas de alguien cuya sede es la B');

-- El mensaje NO lo pinta la Mac mini —`marcar/page.tsx` descarta el texto del
-- servidor y muestra el suyo— sino que queda en los logs y en la pantalla de
-- marcas apartadas que mira Desarrollo Organizacional. Por eso importa igual
-- que no diga de qué sede es esa persona ni cómo se llama: esos logs los ve
-- más gente que DO.
select throws_like(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028611'::uuid, 'entrada'::tipo_marca,
       now(), gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  '%no está habilitada%',
  'BLOQUEADO · y el aviso no filtra el nombre ni la sede de esa persona');

-- ── LA MITAD QUE TIENE QUE SEGUIR ENTRANDO ──────────────────────────────────
select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028610'::uuid, 'entrada'::tipo_marca,
       now(), gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  'PERMITIDO · quien es de la sede del terminal marca como siempre');

select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028612'::uuid, 'entrada'::tipo_marca,
       now(), gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  'VIAJERA · quien rota entre sedes (visible_todas_sedes, 0008) marca en A aunque su base sea B');

-- La marca atrasada de quien ya cesó, con FECHA anterior a su cese. Es el caso
-- que la 0086 protege por escrito y que un `estado = activo` en el candado de
-- sede habría roto: esa persona sí trabajó ese día.
select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028613'::uuid, 'entrada'::tipo_marca,
       ((fn_hoy_lima() - 15) + time '08:00') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  'CESE · la marca atrasada de quien ya cesó, anterior a su cese, sigue entrando');

-- ── EL ACOTAMIENTO A origen = 'terminal' ────────────────────────────────────
-- Las dos caen en días VACÍOS de Eva (−40 y −45), y Eva hoy es de la sede B.
-- Ahí ninguna de las tres puertas del candado las ayuda: la de sede dice que no
-- (su base es B), la del cambio auditado tampoco (a Eva nadie la mudó por la
-- puerta de la 0342) y la de la jornada viva tampoco (no hay nada esos días).
-- Lo único que las deja entrar es que no vienen del terminal.
select lives_ok(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000028614',
             '00000000-0000-0000-0000-000000028600', 'entrada',
             ((fn_hoy_lima() - 40) + time '08:00') at time zone 'America/Lima',
             'admin_correccion', 'revisada') $$,
  'FUERA DE ALCANCE · una corrección con la sede antigua de quien se mudó (0342) sigue entrando');

-- Y la carga de historia, que por definición trae la sede de entonces para
-- gente que hoy está en otra.
select lives_ok(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000028614',
             '00000000-0000-0000-0000-000000028600', 'entrada',
             ((fn_hoy_lima() - 45) + time '08:00') at time zone 'America/Lima',
             'import_historico', 'normal') $$,
  'FUERA DE ALCANCE · la importación histórica con la sede de entonces sigue entrando');

-- ── PUERTA 2 · podía marcar aquí CUANDO SE HIZO la marca ────────────────────
-- El caso que la primera versión de la 0370 decía cubrir y perdía entera: la
-- cola offline entrega la ENTRADA un rato DESPUÉS de que DO mudara a esa
-- persona. La entrada es la primera marca del día, así que no hay ninguna
-- marca viva en la que apoyarse: solo el hecho fechado del cambio de sede.
--
-- El `update` + el `insert` de auditoría son lo que hace `fn_set_sede_base`
-- (0342) en un solo acto. Aquí van sueltos porque esa función exige una sesión
-- de admin autenticada, y esta prueba corre con la sesión del TERMINAL: pedirle
-- las dos a la vez la volvería una prueba de permisos y no del candado.
update personas set sede_base_id = '00000000-0000-0000-0000-000000028601'
 where id = '00000000-0000-0000-0000-000000028615';
-- `corregido_at` y la marca de abajo se anclan LOS DOS a `now()` —la misma
-- marca de tiempo en TODA esta transacción (una sola `begin`, línea 68)—, con
-- un desfase relativo constante entre ambos. Así `corregido_at >=
-- timestamp_marca` se cumple sin importar a qué hora del día ni de qué huso
-- corra CI.
--
-- La primera versión de este arreglo fijó `corregido_at` a una hora ABSOLUTA
-- de Lima (09:01) mientras la marca seguía relativa a `now()` — dos relojes
-- distintos que solo coinciden en la dirección correcta antes de las ~09:31
-- hora Lima. Pasada esa hora, la comparación se invierte y la puerta 2 vuelve
-- a rebotar: confirmado el 2026-09-05 a las 10:26 Lima, el mismo síntoma que
-- decía resuelto. Antes de eso, con el `now()` de columna por defecto sin
-- fijar nada, fallaba de 00:00 a 09:00 Lima (el push que fusionó el PR #161
-- corrió a las 00:07 Lima y se llevó `db-tests` entero por delante). Ningún
-- ancla que mezcle un reloj absoluto con uno relativo es segura; los dos
-- valores tienen que venir del mismo `now()`.
insert into correcciones_auditoria
  (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por, corregido_at)
values ('00000000-0000-0000-0000-000000028615', 'personas.sede_base_id', 'ZZ286A', 'ZZ286B',
        'Cambio de sede base — puede mover la tarifa de movilidad del periodo abierto.',
        '00000000-0000-0000-0000-000000028617',
        now() - interval '15 minutes');

select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028615'::uuid, 'entrada'::tipo_marca,
       now() - interval '30 minutes',
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  'PUERTA 2 · la ENTRADA que la cola entrega tras el cambio de sede entra: es una jornada real');

-- Y el caso negativo, sin el cual la puerta 2 sería un salvoconducto vitalicio:
-- una marca fechada DESPUÉS del cambio de sede no la ampara ningún cambio. Se
-- mide con un insert directo y no por `fn_registrar_marcaje` para que juzgue el
-- disparador y no la máquina de estados. Mutar `ca.corregido_at >=
-- new.timestamp_marca` la pone roja.
select throws_like(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000028615',
             '00000000-0000-0000-0000-000000028600', 'entrada',
             ((fn_hoy_lima() + 3) + time '08:00') at time zone 'America/Lima', 'terminal') $$,
  '%no está habilitada%',
  'PUERTA 2 · pero una marca POSTERIOR al cambio no entra: el cambio ampara el pasado, no el futuro');

-- ── PUERTA 3 · esta marca continúa una jornada ya viva aquí ─────────────────
-- Ana marcó su entrada en A esta mañana (aserción 7); ahora la mudan a la B y
-- la cola offline entrega su salida, hecha en el terminal de A. Sin esta puerta
-- esa marca real se aparta a los 90 segundos y se pierde una jornada de verdad.
-- Y a Ana la mudan SIN dejar auditoría a propósito: así la puerta 2 no puede
-- salvarla y lo único que la sostiene es la jornada abierta.
update personas set sede_base_id = '00000000-0000-0000-0000-000000028601'
 where id = '00000000-0000-0000-0000-000000028610';

select lives_ok(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028610'::uuid, 'salida_final'::tipo_marca,
       now() + interval '2 hours', gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  'PUERTA 3 · la salida que llega tarde cierra la jornada abierta aunque le hayan cambiado la sede');

-- El botón «Sí, volví a entrar». `fn_reabrir_dia` escribe DOS marcas con
-- origen 'terminal', y una de ellas —`retorno_otro`— lleva `now()`: un
-- instante POSTERIOR al cambio de sede, así que la puerta 2 no puede
-- ampararlo. Es el único otro camino que escribe como terminal, y hasta ahora
-- ninguna aserción lo tocaba: quien estrechara el predicado del candado rompía
-- ese botón en las cuatro sedes con el suite entero en verde.
--
-- Se mide con Fabi justamente porque ya está mudada: lo único que la sostiene
-- es que su jornada de hoy en la A sigue viva.
--
-- `now()` otra vez y no una hora fija (ver la nota de la PUERTA 2, arriba):
-- esta salida solo necesita ser POSTERIOR a la entrada de Fabi, y una hora
-- de Lima fija podía quedar antes de `now() - interval '30 minutes'` según
-- a qué hora corriera CI.
do $cierra_fabi$ begin
  perform fn_registrar_marcaje(
    '00000000-0000-0000-0000-000000028615'::uuid, 'salida_final'::tipo_marca,
    now() + interval '30 minutes',
    gen_random_uuid(), 'terminal'::origen_marca,
    '00000000-0000-0000-0000-00000002860a'::uuid, null, null);
end $cierra_fabi$;

select lives_ok(
  $$ select fn_reabrir_dia('00000000-0000-0000-0000-000000028615'::uuid,
                           'Volvió a entrar por inventario') $$,
  'PUERTA 3 · el botón «Sí, volví a entrar» sigue funcionando para quien ya fue mudada de sede');

-- Y su caso negativo: la jornada viva tiene que ser de ESTA sede. Beto es de la
-- B y tiene su jornada de hoy abierta allá; eso no puede abrirle la puerta del
-- terminal de A. Mutar `j.sede_id = new.sede_id` la pone roja.
do $sesion_b$ begin
  perform set_config('request.jwt.claim.sub',
                     '00000000-0000-0000-0000-00000002860f', true);
end $sesion_b$;
do $abre_beto$ begin
  perform fn_registrar_marcaje(
    '00000000-0000-0000-0000-000000028611'::uuid, 'entrada'::tipo_marca,
    (fn_hoy_lima() + time '08:00') at time zone 'America/Lima',
    gen_random_uuid(), 'terminal'::origen_marca,
    '00000000-0000-0000-0000-00000002860b'::uuid, null, null);
end $abre_beto$;
do $sesion_a$ begin
  perform set_config('request.jwt.claim.sub',
                     '00000000-0000-0000-0000-00000002860e', true);
end $sesion_a$;

select throws_like(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000028611',
             '00000000-0000-0000-0000-000000028600', 'salida_final',
             (fn_hoy_lima() + time '18:00') at time zone 'America/Lima', 'terminal') $$,
  '%no está habilitada%',
  'PUERTA 3 · una jornada abierta en OTRA sede no sirve de llave para esta');

-- Y las otras dos condiciones de la puerta 3, que nada más mide. Iris es de la
-- B y arrastra en la A una jornada ABIERTA de hace 30 días y una CERRADA de
-- ayer. Su salida de hoy tiene que rebotar: la de ayer está dentro de la
-- ventana pero muerta, y la de hace 30 días está viva pero fuera. Relajar
-- cualquiera de las dos —quitar el `estado in (…)` o ensanchar la ventana— le
-- abre la puerta a una de ellas y esta aserción se pone roja.
select throws_like(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000028618',
             '00000000-0000-0000-0000-000000028600', 'salida_final',
             (fn_hoy_lima() + time '18:00') at time zone 'America/Lima', 'terminal') $$,
  '%no está habilitada%',
  'PUERTA 3 · ni una jornada muerta de ayer ni una viva de hace un mes sirven de llave');

-- Y el caso negativo que le faltaba a la puerta 2: un cambio de sede auditado
-- es llave de la sede DE LA QUE VINO, no de cualquiera. A Beto lo mudaron de
-- la C a la B; eso no puede dejar entrar su marca en la A. Mutar
-- `s.id = new.sede_id` la pone roja.
select throws_like(
  $$ insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000028611',
             '00000000-0000-0000-0000-000000028600', 'entrada',
             ((fn_hoy_lima() - 50) + time '08:00') at time zone 'America/Lima', 'terminal') $$,
  '%no está habilitada%',
  'PUERTA 2 · el cambio de sede es llave de la sede de la que vino, no de cualquiera');

-- ── LA CADENA SE CORTA ──────────────────────────────────────────────────────
-- Gina es de la sede B y tiene una jornada ABIERTA de ayer en la A: es la
-- población que este mismo defecto dejó en producción antes de que hubiera
-- candado. Su jornada está viva y es de ayer, o sea que cumple TODO lo que la
-- puerta 3 pide menos una cosa — no es una continuación, es una entrada nueva.
-- Si la puerta 3 pudiera ABRIR jornada, esa marca mala autorizaría la de hoy,
-- la de hoy la de mañana, y el candado no mordería nunca a quien más falta le
-- hace. Lo único que corta la cadena es el `new.tipo <> 'entrada'`: quitarlo
-- pone roja esta aserción y solo esta.
select throws_like(
  $$ select fn_registrar_marcaje(
       '00000000-0000-0000-0000-000000028616'::uuid, 'entrada'::tipo_marca,
       (fn_hoy_lima() + time '08:00') at time zone 'America/Lima',
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000002860a'::uuid, null, null) $$,
  '%no está habilitada%',
  'CADENA · la marca mala de ayer no autoriza la ENTRADA de hoy: la puerta 3 nunca abre jornada');

-- ── La regla de sede, y que sea null-safe por sí sola ───────────────────────
select ok(
  fn_persona_marca_en_sede('00000000-0000-0000-0000-000000028611'::uuid,
                           '00000000-0000-0000-0000-000000028601'::uuid) is true,
  'REGLA · quien es de una sede marca en la suya');

-- Sin terminal autenticado `fn_sede_actual_terminal()` devuelve null. Si la
-- función no lo cortara dentro, el `or visible_todas_sedes` daría TRUE por su
-- cuenta y sería un null colándose como autorizado (0078). Se pregunta por
-- CIRA y no por otra: con alguien que no viaja, quitarle a la función el
-- `p_sede_id is not null` no cambia la respuesta y la aserción no mediría nada.
select ok(
  fn_persona_marca_en_sede('00000000-0000-0000-0000-000000028612'::uuid, null::uuid) is not true,
  'NULL-SAFE · sin sede no autoriza a nadie, ni siquiera a quien viaja entre sedes');

select * from finish();
rollback;
