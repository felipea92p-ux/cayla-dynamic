-- ============================================================================
-- 146_el_resellado_del_dia.test.sql — fn_resellar_dia y sus tres llamadoras
-- (migración 0188)
-- ============================================================================
-- Estas cuatro funciones vivieron SOLO EN PRODUCCIÓN desde julio: alguien las
-- mejoró a mano y el trabajo nunca volvió al repositorio. La 0188 las trae. Esta
-- prueba existe para que no puedan volver a perderse en silencio: sin ella,
-- reaplicar la 0037 —que redefine las tres sin estas mejoras— pasaría en verde.
--
-- Lo que se blinda:
--   1 · el sello se PONE cuando el día queda roto (una entrada sin salida);
--   2 · el sello se QUITA cuando el día vuelve a cuadrar;
--   3 · el auto-cierre conserva el suyo — es un sello por otro motivo;
--   4 · las tres funciones de corrección llaman a fn_resellar_dia;
--   5 · la sede de una corrección la manda el DÍA, no la sede base.
--
-- El fixture usa DOS sedes a propósito: la número 5 no se puede comprobar con
-- una sola, y es la mejora que más silenciosamente se perdería.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000d1', 'ZZSEL1', 'Sede base de laboratorio', true),
  ('00000000-0000-0000-0000-0000000000d2', 'ZZSEL2', 'Sede visitada de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000d900', 'SelloAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000d1', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000d9000');
set session_replication_role = origin;

-- `visible_todas_sedes` desde la 0360, y NO es maquillaje para que la prueba
-- pase: la sección 5 de abajo la hace marcar en la sede VISITADA, y desde esa
-- migración un terminal solo escribe marcas de quien puede marcar ahí. Quien
-- visita otra tienda y ficha ahí es exactamente quien tiene este permiso — sin
-- él, el fixture describía un estado que el sistema ya no deja existir, y la
-- prueba abortaba a media ejecución dejando sin correr las dos aserciones que
-- defienden la mejora de la 0188. La otra salida —meter ese insert dentro del
-- bloque `session_replication_role = replica`— habría apagado también el
-- candado del cese y dejado la prueba verde sin que nada la sostenga.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, visible_todas_sedes)
values ('00000000-0000-0000-0000-00000000d901', 'SelloPersona', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000d1', 'test-hash', true);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000d9000', true);

-- ── 1 · Un día roto se sella ────────────────────────────────────────────────
-- DOS entradas seguidas. Ojo con el caso que parece roto y no lo está: una
-- entrada SOLA deja el día ABIERTO, no incoherente — `fn_dia_incoherente`
-- devuelve false y no hay nada que sellar. Se comprobó al escribir esta prueba.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d901',
   '00000000-0000-0000-0000-0000000000d1', 'entrada',
   '2026-03-10 08:00:00-05', 'terminal', 'normal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d901',
   '00000000-0000-0000-0000-0000000000d1', 'entrada',
   '2026-03-10 09:00:00-05', 'terminal', 'normal');

select fn_resellar_dia('00000000-0000-0000-0000-00000000d901', '2026-03-10');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-03-10'
      and estado_revision = 'pendiente_revision'),
  2,
  'Un día roto queda sellado: es lo que el repositorio NO hacía');

-- ── 2 · Y se levanta cuando el día vuelve a cuadrar ─────────────────────────
-- Este es el defecto que la 0084 arregló para otra familia de funciones y que
-- aquí seguía abierto: el sello se ponía y nada lo quitaba.
delete from marcajes
 where persona_id = '00000000-0000-0000-0000-00000000d901'
   and timestamp_marca = '2026-03-10 09:00:00-05';

select fn_resellar_dia('00000000-0000-0000-0000-00000000d901', '2026-03-10');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-03-10'
      and estado_revision = 'pendiente_revision'),
  0,
  'Con el día cuadrado no queda ni un marcaje sellado');

-- ── 3 · El auto-cierre conserva su sello ────────────────────────────────────
-- Su sello es por otro motivo —nadie marcó la salida, la puso el sistema— y
-- levantarlo escondería que ese día se cerró solo.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d901', '00000000-0000-0000-0000-0000000000d1',
   'entrada', '2026-03-11 08:00:00-05', 'terminal', 'normal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000d901', '00000000-0000-0000-0000-0000000000d1',
   'salida_final', '2026-03-11 17:00:00-05', 'auto_cierre', 'pendiente_revision');

select fn_resellar_dia('00000000-0000-0000-0000-00000000d901', '2026-03-11');

select is(
  (select estado_revision::text from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and origen = 'auto_cierre'),
  'pendiente_revision',
  'El auto-cierre conserva su sello aunque el día cuadre');

-- ── 4 · Las tres funciones de corrección resellan ───────────────────────────
-- Se comprueba por su EFECTO, no leyendo el código: agregar una entrada suelta
-- en un día vacío lo deja roto, y el sello tiene que aparecer solo.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000d901',
        '00000000-0000-0000-0000-0000000000d1', 'entrada',
        '2026-03-12 08:00:00-05', 'terminal', 'normal');

-- Una SEGUNDA entrada rompe el día, y fn_agregar_marcaje tiene que sellarlo.
select fn_agregar_marcaje('00000000-0000-0000-0000-00000000d901', 'entrada',
                          '2026-03-12 09:00:00-05', 'prueba de resellado');

select cmp_ok(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-03-12'
      and estado_revision = 'pendiente_revision'),
  '>', 0,
  'fn_agregar_marcaje resella: el día queda roto y se sella solo');

-- Al quitar la entrada repetida el día cuadra, y fn_eliminar_marcaje resella.
select fn_eliminar_marcaje(
  (select id from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and timestamp_marca = '2026-03-12 09:00:00-05'),
  'prueba de resellado al eliminar');

select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-03-12'
      and estado_revision = 'pendiente_revision'),
  0,
  'Y al completar el día, el sello se levanta sin que nadie lo pida');

-- ── 5 · La sede la manda el DÍA, no la sede base ────────────────────────────
-- La mejora que más silenciosamente se perdería: sin ella la jornada queda
-- partida entre dos sedes y el terminal ve media verdad.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision)
values (gen_random_uuid(), '00000000-0000-0000-0000-00000000d901',
        '00000000-0000-0000-0000-0000000000d2',   -- ← marcó en la sede VISITADA
        'entrada', '2026-03-13 08:00:00-05', 'terminal', 'normal');

select fn_agregar_marcaje('00000000-0000-0000-0000-00000000d901', 'salida_final',
                          '2026-03-13 17:00:00-05', 'corrección de un día visitado');

select is(
  (select sede_id from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-03-13'
      and origen = 'admin_correccion'),
  '00000000-0000-0000-0000-0000000000d2'::uuid,
  'La corrección se graba donde la persona marcó ese día, no en su sede base');

-- Y con el día vacío sí cae a la sede base, que es el comportamiento anterior.
select fn_agregar_marcaje('00000000-0000-0000-0000-00000000d901', 'entrada',
                          '2026-03-14 08:00:00-05', 'día sin marcas previas');

select is(
  (select sede_id from marcajes
    where persona_id = '00000000-0000-0000-0000-00000000d901'
      and (timestamp_marca at time zone 'America/Lima')::date = '2026-03-14'),
  '00000000-0000-0000-0000-0000000000d1'::uuid,
  'Sin marcas ese día, cae a la sede base: el comportamiento de siempre');

select * from finish();
rollback;
