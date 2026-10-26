-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 442_una_alerta_solo_se_marca_leida.test.sql — la 0550
-- ============================================================================
-- Defiende la 0550. Antes de ella, la política `alertas_marcar_leida_propia`
-- (0003) dejaba a la dueña de una fila reescribir por PostgREST CUALQUIER
-- columna de sus propias alertas —`estado`, `intentos`, `tipo`, `payload`…—,
-- porque una política de RLS filtra filas, no columnas. Lo que la dueña debe
-- seguir pudiendo es marcar leída; todo lo demás lo escriben las funciones de
-- la cola (SECURITY DEFINER, corren como `postgres`).
--
-- Esta prueba defiende cuatro cosas, y las cuatro hacen falta:
--   1. que lo prohibido siga prohibido, columna por columna (una a una, para
--      que un rojo diga CUÁL se abrió);
--   2. que lo permitido siga permitido (marcar leída) — un freno que también
--      detiene eso rompería la única razón de la política;
--   3. que quien escribe la cola de verdad (las funciones, llamadas con el rol
--      que las llama de verdad, `service_role`) NO se detenga;
--   4. que el diseño sea de lista PERMITIDA: una columna agregada mañana nace
--      cerrada.
--
-- OJO CON EL `session_replication_role`. Igual que en la 232 y la 271: montar
-- el fixture con `= replica` y no devolverlo a `origin` ANTES de simular el
-- ataque apaga en silencio todos los triggers de la sesión, incluido el que
-- esta prueba defiende.
-- ============================================================================
begin;
select plan(33);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000044201', 'ZZ442', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000004421a', 'integrante-442@local'),
  ('00000000-0000-0000-0000-00000004421b', 'otra-442@local'),
  ('00000000-0000-0000-0000-00000004421c', 'do-442@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese) values
  ('00000000-0000-0000-0000-000000044211', 'Integrante', 'Duena',  '00000000-0000-0000-0000-000000044201',
   'integrante', 'activo', 'x', '00000000-0000-0000-0000-00000004421a', '2024-01-01', null),
  ('00000000-0000-0000-0000-000000044212', 'Integrante', 'Otra',   '00000000-0000-0000-0000-000000044201',
   'integrante', 'activo', 'x', '00000000-0000-0000-0000-00000004421b', '2024-01-01', null),
  ('00000000-0000-0000-0000-000000044213', 'Lider',      'DO',     '00000000-0000-0000-0000-000000044201',
   'lider_do',   'activo', 'x', '00000000-0000-0000-0000-00000004421c', '2024-01-01', null);
set session_replication_role = origin;

-- Tres alertas: un auto_cierre de la integrante, uno de la otra, y un aviso de
-- vencimiento cuya dueña es la persona de DO (así llegan: persona_id = destinatario).
insert into alertas (id, persona_id, tipo, canal, payload, created_at) values
  ('00000000-0000-0000-0000-000000044221', '00000000-0000-0000-0000-000000044211', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-01'), '2026-10-01 18:00:00-05'),
  -- La de la otra persona va con fecha de HOY: la reserva del despacho solo toma
  -- avisos de los últimos 7 días (0362), y el punto 7 la reserva de verdad.
  ('00000000-0000-0000-0000-000000044222', '00000000-0000-0000-0000-000000044212', 'auto_cierre', 'push',
   jsonb_build_object('fecha', '2026-10-01'), now() - interval '1 hour'),
  ('00000000-0000-0000-0000-000000044223', '00000000-0000-0000-0000-000000044213', 'contrato_por_vencer', 'email',
   jsonb_build_object('persona', 'Alguien', 'dias_restantes', 12), '2026-10-01 18:00:00-05');

-- ── 0 · El freno existe y corre con quien escribe ──────────────────────────
select is(
  (select count(*)::int from pg_trigger
    where tgname = 'trg_alertas_solo_leida_directo' and tgrelid = 'alertas'::regclass and tgenabled = 'O'),
  1, 'El freno existe en alertas y está activo');

-- Si alguien lo marcara SECURITY DEFINER, current_user valdría siempre `postgres`
-- y no frenaría nada, sin dar ningún error: la falla más callada posible.
select is(
  (select prosecdef from pg_proc where proname = 'fn_bloquear_alertas_directo' and pronamespace = 'public'::regnamespace),
  false, 'El freno NO es SECURITY DEFINER (si lo fuera, current_user sería siempre postgres y dejaría pasar todo)');

-- ── 1 · LO PERMITIDO: la dueña marca leída ─────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004421a', true);
set role authenticated;

select lives_ok(
  $$ update alertas set leido_at = '2026-10-02 08:00:00-05' where id = '00000000-0000-0000-0000-000000044221' $$,
  'PERMITIDO · la dueña marca su alerta como leída');

reset role;
select is(
  (select leido_at from alertas where id = '00000000-0000-0000-0000-000000044221'),
  '2026-10-02 08:00:00-05'::timestamptz,
  'La marca de leída quedó escrita: el freno no se llevó puesto lo único que la política permite');

-- ── 2 · LO PROHIBIDO, columna por columna ──────────────────────────────────
-- Cada una por separado: si mañana alguien abre una, el rojo dice cuál. Cada
-- valor es DISTINTO del que ya tiene la fila: poner `intentos = 0` donde ya vale
-- 0 no es un cambio y el freno, con razón, lo deja pasar.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004421a', true);
set role authenticated;

select throws_ok(
  $$ update alertas set estado = 'enviado' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · la dueña no puede darse su aviso por «enviado» (estado)');
select throws_ok(
  $$ update alertas set estado = 'fallido' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · ni «fallido» (estado)');
-- 'descartada' es el estado que agrega la 0548. Con o sin esa migración puesta,
-- el freno salta ANTES de que el check de estados opine, así que esta línea dice
-- lo mismo en los dos mundos.
select throws_ok(
  $$ update alertas set estado = 'descartada' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · ni «descartada» (estado, el que agrega la 0548)');
select throws_ok(
  $$ update alertas set intentos = 2 where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede tocar la cuenta de intentos (intentos)');
select throws_ok(
  $$ update alertas set enviado_at = now() where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede fingir una fecha de envío (enviado_at)');
select throws_ok(
  $$ update alertas set nota_fallo = 'todo bien' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede escribir la nota del fallo (nota_fallo)');
select throws_ok(
  $$ update alertas set procesando_desde = now() where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede reservarse la fila (procesando_desde)');
select throws_ok(
  $$ update alertas set ultimo_intento_at = now() where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede tocar la fecha del último intento (ultimo_intento_at)');
select throws_ok(
  $$ update alertas set tipo = 'contrato_por_vencer' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede cambiar el tipo de aviso (tipo: decide qué plantilla de correo sale)');
select throws_ok(
  $$ update alertas set canal = 'email' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede cambiar el canal (canal)');
select throws_ok(
  $$ update alertas set payload = jsonb_build_object('persona', 'texto inventado') where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede escribir el contenido del correo (payload: sale tal cual en el asunto y el cuerpo)');
select throws_ok(
  $$ update alertas set created_at = now() where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede rejuvenecer su aviso para que entre en la ventana de despacho (created_at)');
select throws_ok(
  $$ update alertas set id = '00000000-0000-0000-0000-0000000442ff' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · ni cambiarle el id');

-- El contrabando: marcar leída y, de paso, mover otra cosa en la misma sentencia.
select throws_ok(
  $$ update alertas set leido_at = now(), estado = 'enviado' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · «leída» no sirve de pasaporte para colar otro campo en la misma sentencia');

-- Mover la fila a otra persona: ya lo frenaba el `with check` de la política, pero
-- el freno salta antes — da lo mismo, y queda dicho.
select throws_ok(
  $$ update alertas set persona_id = '00000000-0000-0000-0000-000000044212' where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · no puede pasarle su fila a otra persona (persona_id)');

reset role;

-- ── 3 · Nada se movió ──────────────────────────────────────────────────────
-- El resultado de verdad: tras los quince intentos, la fila sigue como la dejó
-- el sistema (salvo la marca de leída, que sí era suya).
select is(
  (select row(estado, intentos, enviado_at, nota_fallo, procesando_desde, ultimo_intento_at, tipo, canal, payload, created_at, persona_id)::text
     from alertas where id = '00000000-0000-0000-0000-000000044221'),
  (select row('pendiente', 0, null::timestamptz, null::text, null::timestamptz, null::timestamptz, 'auto_cierre', 'push',
              jsonb_build_object('fecha', '2026-10-01'), '2026-10-01 18:00:00-05'::timestamptz,
              '00000000-0000-0000-0000-000000044211'::uuid)::text),
  'La fila quedó EXACTAMENTE como estaba: ningún intento movió nada');

-- ── 4 · La fila de otra persona sigue siendo de otra persona ───────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004421a', true);
set role authenticated;
select lives_ok(
  $$ update alertas set leido_at = now() where id = '00000000-0000-0000-0000-000000044222' $$,
  'La dueña intenta marcar leída la alerta de OTRA persona: no falla, no encuentra la fila');
reset role;
select is(
  (select leido_at from alertas where id = '00000000-0000-0000-0000-000000044222'),
  null::timestamptz,
  'La alerta de la otra persona sigue sin leer: la política de filas no se tocó');

-- ── 5 · INSERT y DELETE siguen cerrados (por RLS, no por este freno) ───────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004421a', true);
set role authenticated;
select throws_ok(
  $$ insert into alertas (persona_id, tipo, canal) values ('00000000-0000-0000-0000-000000044211', 'auto_cierre', 'push') $$,
  '42501', null,
  'BLOQUEADO · la dueña no puede fabricarse una alerta (no hay política de INSERT)');
select lives_ok(
  $$ delete from alertas where id = '00000000-0000-0000-0000-000000044221' $$,
  'La dueña intenta borrar su alerta: no falla, no encuentra la fila (no hay política de DELETE)');
reset role;
select is(
  (select count(*)::int from alertas where id = '00000000-0000-0000-0000-000000044221'),
  1, 'La alerta sigue ahí: no se pudo borrar');

-- ── 6 · El aviso de vencimiento: su dueña es la persona de DO ──────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004421c', true);
set role authenticated;
select throws_ok(
  $$ update alertas set estado = 'enviado', intentos = 3 where id = '00000000-0000-0000-0000-000000044223' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · quien es de DO tampoco puede silenciar su propio aviso de vencimiento');
select lives_ok(
  $$ update alertas set leido_at = now() where id = '00000000-0000-0000-0000-000000044223' $$,
  'PERMITIDO · pero sí marcarlo como leído');
reset role;

-- ── 7 · QUIEN ESCRIBE LA COLA DE VERDAD NO SE DETIENE ───────────────────────
-- El despacho llama a estas funciones con la llave de servicio (rol
-- `service_role`); dentro corren como `postgres`, su dueño. Es la prueba de que
-- el freno no corta el único camino legítimo.
set role service_role;
select is(
  (select fn_alertas_reservar('00000000-0000-0000-0000-000000044222')),
  true, 'FUNCIONA · fn_alertas_reservar, llamada con la llave de servicio, reserva la fila (estado y contadores)');
select lives_ok(
  $$ select fn_marcar_alerta_resultado('00000000-0000-0000-0000-000000044222', true, null) $$,
  'FUNCIONA · fn_marcar_alerta_resultado, llamada con la llave de servicio, cierra la reserva');
reset role;
select is(
  (select row(estado, intentos, enviado_at is not null, procesando_desde)::text
     from alertas where id = '00000000-0000-0000-0000-000000044222'),
  (select row('enviado', 1, true, null::timestamptz)::text),
  'Las dos funciones dejaron la fila enviada, con un intento y sin reserva: el freno dejó pasar a quien debía');

-- Lo contrario, también dicho: la llave de servicio por sí sola, escribiendo
-- directo, NO pasa. Es a propósito (ver «SE ROMPE SI» de la 0550).
set role service_role;
select throws_ok(
  $$ update alertas set estado = 'pendiente' where id = '00000000-0000-0000-0000-000000044222' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · la llave de servicio escribiendo DIRECTO tampoco pasa: tiene que ser por una función');
reset role;

-- Y el SQL Editor (postgres) corrige a mano lo que haga falta.
select lives_ok(
  $$ update alertas set estado = 'pendiente', nota_fallo = 'corregida a mano' where id = '00000000-0000-0000-0000-000000044222' $$,
  'FUNCIONA · una corrección a mano desde el SQL Editor (postgres) sigue pudiendo');

-- ── 8 · LISTA PERMITIDA: una columna nueva nace cerrada ────────────────────
-- Así creció el hueco original: la 0354 y la 0362 agregaron cuatro columnas y
-- cada una nació escribible por la dueña sin que nadie lo decidiera. Se agrega
-- una en esta transacción (se deshace con el rollback) y se intenta escribirla.
alter table alertas add column zz442_columna_futura int;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004421a', true);
set role authenticated;
select throws_ok(
  $$ update alertas set zz442_columna_futura = 1 where id = '00000000-0000-0000-0000-000000044221' $$,
  'Una alerta solo se puede marcar como leída; lo demás lo mueve el despacho de avisos, no un update directo.',
  'BLOQUEADO · una columna agregada MAÑANA ya nace cerrada para la dueña (lista permitida, no prohibida)');
reset role;

select * from finish();
rollback;
