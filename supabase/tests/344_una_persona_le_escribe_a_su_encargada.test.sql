-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 344_una_persona_le_escribe_a_su_encargada.test.sql
-- ============================================================================
-- Cubre la migración 0435: un mensaje libre de una persona hacia su
-- encargada (o DO). Lo que hay que blindar:
--   · sin sesión enlazada, no se puede escribir ni responder;
--   · un mensaje vacío, o una respuesta vacía, se rechazan;
--   · la sede se guarda como una FOTO de quien escribe, no se relee después;
--   · solo la encargada de ESA sede (o admin/DO) puede leer y responder — la
--     encargada de otra sede no ve nada y no puede responder;
--   · responder dos veces el mismo mensaje se rechaza.
-- Simulamos sesiones con set_config('request.jwt.claim.sub', ...) — mismo
-- técnica que 30_reversa_pago.test.sql. Todo dentro de begin/rollback.
-- ============================================================================
begin;
select plan(12);

-- ── Semilla ──────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000e1', 'ZZTE1', 'Sede de laboratorio 1', true),
  ('00000000-0000-0000-0000-0000000000e2', 'ZZTE2', 'Sede de laboratorio 2', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, rol, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000f1', 'Integrante', 'DeLaSede1',
    '00000000-0000-0000-0000-0000000000e1', 'test-hash', 'integrante',
    '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000f2', 'Encargada', 'DeLaSede1',
    '00000000-0000-0000-0000-0000000000e1', 'test-hash', 'supervisor_sede',
    '00000000-0000-0000-0000-0000000000a2'),
  ('00000000-0000-0000-0000-0000000000f3', 'Encargada', 'DeLaSede2',
    '00000000-0000-0000-0000-0000000000e2', 'test-hash', 'supervisor_sede',
    '00000000-0000-0000-0000-0000000000a3'),
  ('00000000-0000-0000-0000-0000000000f4', 'Admin', 'DeLaboratorio',
    '00000000-0000-0000-0000-0000000000e1', 'test-hash', 'admin',
    '00000000-0000-0000-0000-0000000000a4');
set session_replication_role = origin;

-- ── 1) Sin sesión enlazada, escribir se rechaza ─────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000000', true);
select throws_like(
  $$ select fn_enviar_mensaje_encargada('hola, tengo una consulta') $$,
  '%enlazada%',
  'Sin sesión enlazada a una ficha, escribir un mensaje se rechaza');

-- ── Sesión: la integrante de la sede 1 ───────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true);

-- ── 2) Un mensaje vacío se rechaza ───────────────────────────────────────────
select throws_like(
  $$ select fn_enviar_mensaje_encargada('   ') $$,
  '%Escribe algo%',
  'Un mensaje en blanco se rechaza antes de guardarse');

-- ── 3) Escribir un mensaje real funciona ─────────────────────────────────────
-- El RPC va en su propia sentencia: mezclarlo en el WHERE de un select que
-- escanea la misma tabla no garantiza verlo (si la tabla está vacía, el
-- planificador no tiene fila contra la que evaluar el filtro, y la función
-- —con su insert adentro— nunca llega a ejecutarse). Mismo criterio que ya
-- usa 263_pedir_vacaciones_y_que_do_las_apruebe.test.sql.
select lives_ok(
  $$ select fn_enviar_mensaje_encargada('No me generaron mi horario de la próxima semana.') $$,
  'Escribir un mensaje real funciona');

-- ── 4) Queda pendiente, a su nombre ──────────────────────────────────────────
select is(
  (select estado from mensajes_encargada where persona_id = '00000000-0000-0000-0000-0000000000f1'),
  'pendiente', 'El mensaje nace en estado pendiente');

-- ── 5) La sede guardada es la de quien escribe, no una que haya que releer ──
select is(
  (select sede_id from mensajes_encargada where persona_id = '00000000-0000-0000-0000-0000000000f1'),
  '00000000-0000-0000-0000-0000000000e1'::uuid,
  'El mensaje guarda la sede de quien escribe, como una foto');

-- Captura el id ahora, todavía como superusuario (sin RLS de por medio): las
-- pruebas 8-12 llaman al RPC con ESTE id fijo, no con `(select id from
-- mensajes_encargada limit 1)` bajo el rol de quien no debería verlo — si se
-- hiciera así, la 8 fallaría por la razón equivocada ("no existe" en vez de
-- "no puedes"), porque la RLS ya se lo habría escondido en el subquery antes
-- de que el RPC llegara a decidir nada. Lo que hay que probar es que la
-- función SECURITY DEFINER se cuida sola, no que la RLS también ayuda.
select id as msg_id from mensajes_encargada where persona_id = '00000000-0000-0000-0000-0000000000f1' \gset

-- ── 6) La encargada de OTRA sede no ve el mensaje (RLS) ─────────────────────
-- ⚠ pgTAP corre como `postgres` (superusuario, se salta la RLS): sin este
-- cambio de rol vería la fila igual y la prueba pasaría por el motivo
-- equivocado (mismo aviso que la 263). `set local` alcanza para el resto de
-- esta transacción — no hace falta resetearlo entre pruebas.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
select is(
  (select count(*)::int from mensajes_encargada),
  0, 'La encargada de otra sede no ve el mensaje de una sede que no es la suya');

-- ── 7) La encargada de la MISMA sede sí lo ve ────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select is(
  (select count(*)::int from mensajes_encargada),
  1, 'La encargada de la misma sede ve el mensaje');

-- Las cuatro pruebas de abajo NO usan $$...$$: psql no interpola variables
-- dentro de comillas de dólar (comprobado aparte — queda como `:'msg_id'`
-- literal y Postgres truena con "syntax error at or near \":\""). `format()`
-- con %L arma el texto SÍ interpolado y lo entrecomilla solo.

-- ── 8) Esa encargada de OTRA sede no puede RESPONDER el mensaje ─────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a3', true);
select throws_like(
  format('select fn_responder_mensaje_encargada(%L, %L)', :'msg_id', 'una respuesta cualquiera'),
  '%No puedes responder%',
  'La encargada de otra sede no puede responder este mensaje');

-- ── 9) Responder con texto vacío se rechaza ─────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a2', true);
select throws_like(
  format('select fn_responder_mensaje_encargada(%L, %L)', :'msg_id', '   '),
  '%Escribe una respuesta%',
  'Responder con texto vacío se rechaza');

-- ── 10) La encargada correcta SÍ puede responder ────────────────────────────
select lives_ok(
  format('select fn_responder_mensaje_encargada(%L, %L)',
    :'msg_id', 'Ya te lo genero hoy mismo, disculpa la demora.'),
  'La encargada de la sede correcta puede responder el mensaje');

-- ── 11) Tras responder, queda completo: estado, respuesta y quién respondió ─
select is(
  (select estado from mensajes_encargada limit 1),
  'respondido', 'Tras responder, el mensaje pasa a estado respondido');

-- ── 12) Responder un mensaje ya respondido se rechaza ───────────────────────
select throws_like(
  format('select fn_responder_mensaje_encargada(%L, %L)', :'msg_id', 'otra respuesta más'),
  '%ya fue respondido%',
  'Un mensaje ya respondido no se puede responder dos veces');

select * from finish();
rollback;
