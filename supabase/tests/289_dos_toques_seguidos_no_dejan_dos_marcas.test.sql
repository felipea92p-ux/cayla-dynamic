-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 289_dos_toques_seguidos_no_dejan_dos_marcas.test.sql
-- ============================================================================
-- Cubre la 0363 (hallazgo 21 de la auditoría del 2026-09-03/04): un doble
-- toque en el terminal —dos llamadas con client_uuid DISTINTO, del mismo tipo,
-- a segundos de distancia— deja UNA marca, y la segunda llamada devuelve la
-- misma fila que la primera (éxito silencioso, como un reintento).
--
-- Y fija los límites, que son lo que de verdad importa de un dedupe:
--   · a diez minutos ya NO es un doble toque: la máquina de estados lo
--     rechaza como siempre;
--   · una corrección con sesión de admin no se dedupe: dos entradas a 30 s
--     son dos filas, porque las correcciones no pasan por aquí a propósito;
--   · la idempotencia por client_uuid sigue intacta;
--   · un día normal entero sigue entrando (4 marcas, 4 filas);
--   · la salida_final del robot (auto_cierre) NO cuenta como toque anterior:
--     la salida real que llega a un minuto la REEMPLAZA (0320 / reconciliación)
--     en vez de perderse, y recién el tercer toque se dedupe contra la real;
--   · salió, volvió y salió otra vez en 90 s son TRES marcas reales: un toque
--     repetido lo es de la ÚLTIMA marca, y entre esas dos hubo un retorno.
--
-- Lo que esta prueba NO puede medir es la carrera de verdad —dos
-- transacciones a la vez—: eso lo cuida el pg_advisory_xact_lock, cuya
-- presencia se comprueba en el prosrc, y se midió a mano con dos sesiones de
-- psql al escribir la 0363 (ver su encabezado y el reporte del paquete).
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000289001', 'ZZTAP', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-000000289002', 'terminal-tap@local');
-- Admin con sesión, para el caso de la corrección (patrón de la prueba 256).
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000289006', 'TapAdmin', 'Lab',
        '00000000-0000-0000-0000-000000289001', 'admin', 'x',
        '00000000-0000-0000-0000-00000028900a', '2024-01-01');
set session_replication_role = origin;

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-000000289003', '00000000-0000-0000-0000-000000289001',
        'Terminal de laboratorio', true, '00000000-0000-0000-0000-000000289002');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000289004', 'TapDoble',    'Lab', '00000000-0000-0000-0000-000000289001', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000289005', 'TapNormal',   'Lab', '00000000-0000-0000-0000-000000289001', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000289007', 'TapCorregida','Lab', '00000000-0000-0000-0000-000000289001', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000289008', 'TapRobot',    'Lab', '00000000-0000-0000-0000-000000289001', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000289009', 'TapSaleDos',  'Lab', '00000000-0000-0000-0000-000000289001', 'x', '2024-01-01');

-- ── 1 · Doble toque en la entrada: T y T+3 s, client_uuid distintos ────────
create temp table t_toques (orden int, marcaje_id uuid);

insert into t_toques
select 1, (fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289004', 'entrada',
  timestamptz '2026-08-10 09:00:00-05:00', '00000000-0000-0000-0000-000000289101',
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null)).id;

insert into t_toques
select 2, (fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289004', 'entrada',
  timestamptz '2026-08-10 09:00:03-05:00', '00000000-0000-0000-0000-000000289102',
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null)).id;

select is(
  (select marcaje_id from t_toques where orden = 2),
  (select marcaje_id from t_toques where orden = 1),
  'el segundo toque de entrada (3 s después, otro client_uuid) devuelve LA MISMA marca que el primero'
);

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289004' and tipo = 'entrada'),
  1,
  'y en marcajes hay UNA entrada, no dos'
);

-- ── 2 · A diez minutos ya no es un doble toque: la máquina de estados manda ─
-- Con una entrada abierta, otra `entrada` no es lo que se espera: el error
-- de estado de siempre («tipo entrada no válido…»), no un éxito silencioso.
select throws_like(
  $$select fn_registrar_marcaje(
      '00000000-0000-0000-0000-000000289004', 'entrada',
      timestamptz '2026-08-10 09:10:00-05:00', '00000000-0000-0000-0000-000000289103',
      'terminal', '00000000-0000-0000-0000-000000289003',
      '00000000-0000-0000-0000-000000289001', null)$$,
  '%no válido%',
  'una entrada 10 minutos después NO se dedupe: la rechaza la máquina de estados como siempre'
);

-- ── 3 · Doble toque en la salida final: el hueco más ancho ─────────────────
-- Antes de la 0363 esto dejaba DOS salidas finales sin ninguna carrera:
-- con la jornada cerrada v_esperado es null y salida_final se acepta con null.
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289004', 'salida_final',
  timestamptz '2026-08-10 17:00:00-05:00', '00000000-0000-0000-0000-000000289104',
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289004', 'salida_final',
  timestamptz '2026-08-10 17:00:05-05:00', '00000000-0000-0000-0000-000000289105',
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289004' and tipo = 'salida_final'),
  1,
  'dos toques de salida_final a 5 s dejan UNA salida final'
);

select is(
  (select timestamp_marca from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289004' and tipo = 'salida_final'),
  timestamptz '2026-08-10 17:00:00-05:00',
  'y la que queda es la del PRIMER toque, que es la hora real'
);

-- ── 4 · La idempotencia por client_uuid sigue como estaba ──────────────────
select is(
  (select (fn_registrar_marcaje(
     '00000000-0000-0000-0000-000000289004', 'entrada',
     timestamptz '2026-08-10 09:00:00-05:00', '00000000-0000-0000-0000-000000289101',
     'terminal', '00000000-0000-0000-0000-000000289003',
     '00000000-0000-0000-0000-000000289001', null)).id),
  (select marcaje_id from t_toques where orden = 1),
  'repetir el MISMO client_uuid sigue devolviendo la misma fila (idempotencia de siempre)'
);

-- ── 5, 6 y 7 · La función es la de la 0363, y es una sola ─────────────────
select ok(
  (select prosrc from pg_proc where proname = 'fn_registrar_marcaje') like '%pg_advisory_xact_lock%',
  'fn_registrar_marcaje toma el candado de transacción por persona'
);

select ok(
  (select prosrc from pg_proc where proname = 'fn_registrar_marcaje') like '%CAMBIO 0363%',
  'fn_registrar_marcaje lleva el marcador CAMBIO 0363'
);

select is(
  (select count(*)::int from pg_proc where proname = 'fn_registrar_marcaje'),
  1,
  'hay exactamente UNA fn_registrar_marcaje: la firma no cambió, no hay sobrecargas'
);

-- ── 8 · Un día normal entero sigue entrando: 4 marcas, 4 filas ─────────────
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289005', 'entrada',
  timestamptz '2026-08-10 09:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289005', 'salida_almuerzo',
  timestamptz '2026-08-10 13:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289005', 'retorno_almuerzo',
  timestamptz '2026-08-10 14:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289005', 'salida_final',
  timestamptz '2026-08-10 18:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289005' and anulada_at is null),
  4,
  'entrada → salida_almuerzo → retorno_almuerzo → salida_final: las 4 marcas entran'
);

-- ── 9 · El robot NO es un toque anterior: la salida real lo reemplaza ──────
-- Sin el filtro `m.origen = 'terminal'` de la 0363, la salida real de las
-- 21:01 «encontraría» la salida_final sintética de las 21:00 del auto-cierre,
-- la devolvería y nunca llegaría a la reconciliación que existe para
-- reemplazarla: la hora real de la persona se perdería. Se imita al robot con
-- el mismo insert que hace fn_auto_cierre (origen auto_cierre, pendiente).
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289008', 'entrada',
  timestamptz '2026-08-10 13:00:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
values (gen_random_uuid(), '00000000-0000-0000-0000-000000289008',
        '00000000-0000-0000-0000-000000289001', 'salida_final',
        timestamptz '2026-08-10 21:00:00-05:00', 'auto_cierre', 'pendiente_revision');

insert into t_toques
select 11, (fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289008', 'salida_final',
  timestamptz '2026-08-10 21:01:00-05:00', '00000000-0000-0000-0000-000000289111',
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null)).id;
insert into t_toques
select 12, (fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289008', 'salida_final',
  timestamptz '2026-08-10 21:01:05-05:00', '00000000-0000-0000-0000-000000289112',
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null)).id;

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289008'
      and tipo = 'salida_final' and anulada_at is null),
  1,
  'robot a las 21:00 + salida real a las 21:01 + rebote a los 5 s: UNA salida final viva'
);

select is(
  (select timestamp_marca::text || ' ' || origen::text from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289008'
      and tipo = 'salida_final' and anulada_at is null),
  (timestamptz '2026-08-10 21:01:00-05:00')::text || ' terminal',
  'y la viva es la REAL de las 21:01 del terminal, no la que adivinó el robot'
);

select is(
  (select marcaje_id from t_toques where orden = 12),
  (select marcaje_id from t_toques where orden = 11),
  'y el tercer toque devuelve esa misma marca real, no una nueva'
);

-- ── 10 · Salió, volvió y salió otra vez en 90 s: TRES marcas reales ────────
-- Un toque repetido lo es de la ÚLTIMA marca. Aquí entre las dos
-- salida_personal hay un retorno_personal, así que la segunda salida no es un
-- rebote: la persona volvió a salir. Sin la condición «nada entre medias» se
-- devolvía la salida de las 10:00:00 y la persona quedaba «dentro» estando
-- fuera (medido en la revisión del paquete).
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289009', 'entrada',
  timestamptz '2026-08-10 09:00:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289009', 'salida_personal',
  timestamptz '2026-08-10 10:00:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289009', 'retorno_personal',
  timestamptz '2026-08-10 10:00:40-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000289003',
  '00000000-0000-0000-0000-000000289001', null);

select is(
  (select (fn_registrar_marcaje(
     '00000000-0000-0000-0000-000000289009', 'salida_personal',
     timestamptz '2026-08-10 10:01:30-05:00', gen_random_uuid(),
     'terminal', '00000000-0000-0000-0000-000000289003',
     '00000000-0000-0000-0000-000000289001', null)).timestamp_marca),
  timestamptz '2026-08-10 10:01:30-05:00',
  'la segunda salida_personal, con un retorno entre medias, entra con SU hora: no se dedupe'
);

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289009' and anulada_at is null),
  4,
  'entrada → salida_personal → retorno_personal → salida_personal en 90 s: 4 marcas vivas'
);

-- ── 11 · Una corrección con sesión de admin NO se dedupe ───────────────────
-- El alcance queda fijado: dos entradas a 30 s por Correcciones son dos
-- filas. Lo hace una persona con sesión, a propósito, y deja su rastro.
-- (Va al final porque cambia la sesión: con el sub de un admin, las llamadas
-- de terminal de arriba fallarían por «el terminal autenticado no coincide».)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000028900a', true);

select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289007', 'entrada',
  timestamptz '2026-08-10 09:00:00-05:00', '00000000-0000-0000-0000-000000289106',
  'admin_correccion', null,
  '00000000-0000-0000-0000-000000289001', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000289007', 'entrada',
  timestamptz '2026-08-10 09:00:30-05:00', '00000000-0000-0000-0000-000000289107',
  'admin_correccion', null,
  '00000000-0000-0000-0000-000000289001', null);

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-000000289007' and tipo = 'entrada'),
  2,
  'dos entradas por Correcciones a 30 s son DOS filas: las correcciones no se deduplican'
);

select * from finish();
rollback;
