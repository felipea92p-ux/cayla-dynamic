-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 405_do_toma_el_caso_y_lo_devuelve.test.sql
-- ============================================================================
-- La 0511 deja a DO tomar el caso que inició una líder, y devolvérselo.
-- Lo que fija esta prueba, en orden de importancia:
--   · Mientras DO tiene el caso, la líder no lo toca por NINGÚN camino: ni
--     por una función del expediente, ni por un UPDATE, ni agregándole un
--     adjunto. Tampoco otra líder de la sede.
--   · La persona sancionada no queda atrapada: puede seguir respondiendo a su
--     propio memo aunque DO tenga el caso, incluso si es líder.
--   · Un proceso sin sesión no queda bloqueado.
--   · Tomar y devolver exigen motivo, dejan historial, y no se hacen dos
--     veces. La practicante de DO puede tomar (tramitar no es imponer).
--   · Solo se toma lo que inició una líder, y no lo anulado. Solo se devuelve
--     a quien todavía puede tramitarlo.
--   · El porqué de cada traspaso lo lee la líder; la persona sancionada no.
-- ============================================================================
begin;
select plan(28);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000c0e01', 'ZZTC1', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000000c0e11', 'Gerencia',   'Lab', '00000000-0000-0000-0000-0000000c0e01', 'admin',           'x', '00000000-0000-0000-0000-0000000c0ea1', '2020-01-01', 'activo', 'planilla',    null),
  ('00000000-0000-0000-0000-0000000c0e12', 'DoPractica', 'Lab', '00000000-0000-0000-0000-0000000c0e01', 'lider_do',        'x', '00000000-0000-0000-0000-0000000c0ea2', '2025-01-01', 'activo', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-0000000c0e14', 'LiderUno',   'Lab', '00000000-0000-0000-0000-0000000c0e01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000c0ea4', '2021-01-01', 'activo', 'planilla',    null),
  ('00000000-0000-0000-0000-0000000c0e15', 'LiderDos',   'Lab', '00000000-0000-0000-0000-0000000c0e01', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000c0ea5', '2021-01-01', 'activo', 'planilla',    null),
  ('00000000-0000-0000-0000-0000000c0e17', 'Integrante', 'Lab', '00000000-0000-0000-0000-0000000c0e01', 'integrante',      'x', '00000000-0000-0000-0000-0000000c0ea7', '2023-01-01', 'activo', 'planilla',    null);
set session_replication_role = origin;

create function pg_temp.como(p_auth uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_auth::text, ''), true);
$$;

-- Tres casos que inicia LiderUno sobre la integrante, y uno que inicia DO.
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea4');   -- LiderUno
create temp table _c as select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0e17', '53.1', 'd', 'amonestacion',
  fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Usó el teléfono mientras atendía a una clienta en caja.') as id;
create temp table _a as select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0e17', '53.1', 'b', 'verbal',
  fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Dejó el mostrador desordenado al cierre de turno.') as id;
create temp table _r as select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0e17', '53.1', 'f', 'verbal',
  fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Se ausentó del piso de ventas sin avisar durante media hora.') as id;
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea1');   -- Gerencia
create temp table _g as select fn_expediente_crear_conducta('00000000-0000-0000-0000-0000000c0e17', '53.2', 'g', 'amonestacion',
  fn_hoy_lima() - 3, fn_hoy_lima() - 2, 'Cerró la caja sin cuadrar y sin avisar a nadie.') as id;

-- ── TOMAR ───────────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea4');   -- LiderUno
select throws_like(format($$ select fn_expediente_tomar_caso(%L, 'Me lo quedo para revisarlo.') $$, (select id from _c)),
  '%Solo Desarrollo Organizacional%', 'TOMAR · una líder no toma casos: eso es de DO');

select pg_temp.como('00000000-0000-0000-0000-0000000c0ea2');   -- DoPractica
select throws_like(format($$ select fn_expediente_tomar_caso(%L, 'Revisar') $$, (select id from _c)),
  '%Escribe por qué%', 'TOMAR · sin un motivo que la líder pueda leer, no se toma');
select lives_ok(format($$ select fn_expediente_tomar_caso(%L, 'El uso del teléfono fue en un día sin clientas; lo reviso yo.') $$, (select id from _c)),
  'TOMAR · la practicante de DO toma el caso: tramitar no es imponer');
select is((select tomado_por from expediente_disciplinario where id = (select id from _c)),
  '00000000-0000-0000-0000-0000000c0e12'::uuid, 'TOMAR · consta quién lo tiene');
select is((select accion || ':' || por::text from expediente_traspasos where expediente_id = (select id from _c)),
  'tomar:00000000-0000-0000-0000-0000000c0e12', 'TOMAR · y el traspaso queda en el historial con su autora');

select pg_temp.como('00000000-0000-0000-0000-0000000c0ea1');   -- Gerencia
select throws_like(format($$ select fn_expediente_tomar_caso(%L, 'Lo quiero ver yo también.') $$, (select id from _c)),
  '%ya lo tomó DoPractica Lab%', 'TOMAR · no se toma dos veces, y dice quién lo tiene');
select throws_like(format($$ select fn_expediente_tomar_caso(%L, 'Lo reviso desde Gerencia.') $$, (select id from _g)),
  '%no lo inició una líder%', 'TOMAR · lo que abrió DO ya está con DO');
select lives_ok(format($$ select fn_expediente_anular(%L, 'Registrado por error, era otra persona.') $$, (select id from _a)),
  'DE PARTIDA · DO anula un caso de la líder');
select throws_like(format($$ select fn_expediente_tomar_caso(%L, 'Ya no importa, pero lo intento.') $$, (select id from _a)),
  '%anulado%', 'TOMAR · lo anulado no se toma');

-- ── EL CANDADO ──────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea4');   -- LiderUno
select throws_like(format($$ select fn_expediente_comunicar_cargos(%L) $$, (select id from _c)),
  '%lo tomó DoPractica Lab%', 'CANDADO · la líder no sigue tramitando por una función del expediente');

-- El descargo previo que enciende la 0566 se interpone ANTES del candado que
-- esta prueba mide: `fn_expediente_firmar` corta en su primera puerta (0455)
-- porque los cargos no se comunicaron, y entonces nunca llega al UPDATE donde
-- salta el trigger del caso tomado (0511). Relajar el patrón a '%' convertiría
-- una aserción sobre ESE candado en una aserción sobre cualquier error, así que
-- lo que se hace es cumplir el trámite del art. 55.2 primero.
--
-- Va sembrado a mano, como en la 205, porque no hay camino por función que deje
-- el plazo ya vencido dentro de una prueba: `fn_expediente_comunicar_cargos`
-- vence siempre en el futuro. Y va DESPUÉS de la aserción de arriba, que
-- necesita `cargos_comunicados_at` en null para alcanzar su propio mensaje.
-- Sin sesión, porque el candado bloquearía este UPDATE si lo hiciera la líder
-- —lo demuestra la aserción de «ni lo toca por un UPDATE»—.
select pg_temp.como(null);
update expediente_disciplinario
   set cargos_comunicados_at = now() - interval '5 days',
       descargo_vence_at     = now() - interval '2 days',
       descargo_acogido      = 'sin_descargo'
 where id = (select id from _c);
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea4');   -- LiderUno otra vez

select throws_like(format($$ select fn_expediente_firmar(%L, null) $$, (select id from _c)),
  '%lo tomó%', 'CANDADO · ni lo firma');
select throws_like(format($$ update expediente_disciplinario set observacion = 'nota de la líder' where id = %L $$, (select id from _c)),
  '%lo tomó%', 'CANDADO · ni lo toca por un UPDATE: el candado es de la fila, no de una función');
select throws_like(format($$ insert into expediente_adjuntos (documento_id, storage_path, subido_por) values (%L, 'lab/prueba-405.pdf', '00000000-0000-0000-0000-0000000c0e14') $$, (select id from _c)),
  '%ya no le puedes agregar%', 'CANDADO · ni le agrega un adjunto');
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea5');   -- LiderDos
select throws_like(format($$ update expediente_disciplinario set observacion = 'nota de otra líder' where id = %L $$, (select id from _c)),
  '%lo tomó%', 'CANDADO · ni otra líder de la sede');

select pg_temp.como('00000000-0000-0000-0000-0000000c0ea2');   -- DoPractica
select lives_ok(format($$ update expediente_disciplinario set observacion = 'nota de DO' where id = %L $$, (select id from _c)),
  'CANDADO · DO sí trabaja el caso que tomó');
select pg_temp.como(null);                                       -- sin sesión
select lives_ok(format($$ update expediente_disciplinario set observacion = 'proceso nocturno' where id = %L $$, (select id from _c)),
  'CANDADO · un proceso sin sesión no queda bloqueado');

-- ── QUIÉN LEE EL PORQUÉ ─────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea4');   -- LiderUno
set local role authenticated;
select is((select count(*)::int from expediente_traspasos), 1,
  'HISTORIAL · la líder lee por qué DO tomó su caso');
reset role;
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea7');   -- Integrante
set local role authenticated;
select is((select count(*)::int from expediente_traspasos), 0,
  'HISTORIAL · la persona sancionada no: es una conversación interna sobre cómo tramitar');
reset role;

-- ── DEVOLVER ────────────────────────────────────────────────────────────────
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea4');   -- LiderUno
select throws_like(format($$ select fn_expediente_devolver_caso(%L, 'Ya lo revisaste, devuélvemelo.') $$, (select id from _c)),
  '%Solo Desarrollo Organizacional%', 'DEVOLVER · la líder no se lo devuelve sola');
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea1');   -- Gerencia
select throws_like(format($$ select fn_expediente_devolver_caso(%L, 'Ok') $$, (select id from _c)),
  '%Escribe por qué%', 'DEVOLVER · sin motivo no se devuelve');
select lives_ok(format($$ select fn_expediente_devolver_caso(%L, 'Revisado: el hecho está bien descrito, sigue tú.') $$, (select id from _c)),
  'DEVOLVER · Gerencia devuelve el caso, aunque no sea quien lo tomó');
select is((select tomado_por from expediente_disciplinario where id = (select id from _c)), null,
  'DEVOLVER · el caso vuelve a la sede');
select is((select string_agg(accion, ',' order by hecho_at, accion desc) from expediente_traspasos where expediente_id = (select id from _c)),
  'tomar,devolver', 'DEVOLVER · y el historial guarda las dos vueltas');
select throws_like(format($$ select fn_expediente_devolver_caso(%L, 'Lo devuelvo otra vez por si acaso.') $$, (select id from _c)),
  '%no hay nada que devolver%', 'DEVOLVER · no se devuelve lo que no está tomado');
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea4');   -- LiderUno
select lives_ok(format($$ update expediente_disciplinario set observacion = 'de vuelta conmigo' where id = %L $$, (select id from _c)),
  'DEVOLVER · y la líder vuelve a poder trabajarlo');

-- Devolver a quien ya no puede tramitar lo dejaría en manos de nadie.
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea1');   -- Gerencia
select lives_ok(format($$ select fn_expediente_tomar_caso(%L, 'Lo tomo mientras se resuelve el cambio de rol.') $$, (select id from _r)),
  'DE PARTIDA · DO toma otro caso de LiderUno');
-- `replica` porque tocar una persona de prueba revalida su cuenta ficticia
-- contra auth.users, igual que al insertarla.
set session_replication_role = replica;
update personas set tipo_vinculo = 'rxh' where id = '00000000-0000-0000-0000-0000000c0e14';
set session_replication_role = origin;
select throws_like(format($$ select fn_expediente_devolver_caso(%L, 'Lo devuelvo a quien lo inició.') $$, (select id from _r)),
  '%se queda con Desarrollo Organizacional%', 'DEVOLVER · si quien lo inició dejó de estar en planilla, el caso se queda con DO');
set session_replication_role = replica;
update personas set tipo_vinculo = 'planilla' where id = '00000000-0000-0000-0000-0000000c0e14';
set session_replication_role = origin;

-- ── LA PERSONA SANCIONADA NO QUEDA ATRAPADA ─────────────────────────────────
-- El caso tomado, entregado, y ella ascendida a líder después: el candado mira
-- el rol, y por eso tiene que mirar también de quién es el documento.
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea1');   -- Gerencia
update expediente_disciplinario
   set estado = 'entregado', firmante_id = '00000000-0000-0000-0000-0000000c0e11', firmado_at = now(),
       correlativo = 'LAB/TC-1', medio_entrega = 'fisico', entregado_at = now()
 where id = (select id from _r);
set session_replication_role = replica;
update personas set rol = 'supervisor_sede' where id = '00000000-0000-0000-0000-0000000c0e17';
set session_replication_role = origin;
select pg_temp.como('00000000-0000-0000-0000-0000000c0ea7');   -- la sancionada, ahora líder
select lives_ok(format($$ select fn_rechazar_firma_memo(%L) $$, (select id from _r)),
  'SANCIONADA · responde a su propio memo aunque DO tenga el caso y ella sea líder');

select * from finish();
rollback;
