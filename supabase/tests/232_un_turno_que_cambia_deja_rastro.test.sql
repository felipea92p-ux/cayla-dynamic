-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 232_un_turno_que_cambia_deja_rastro.test.sql
-- ============================================================================
-- El turno del día MANDA sobre el horario base: `jornada-esperada.ts` pregunta
-- primero por el turno y solo después cae al horario semanal. O sea que el
-- turno decide qué se esperaba de esa persona ese día, y de ahí sale si llegó
-- tarde, si salió antes o si faltó.
--
-- Hasta la 0298, las tres funciones que escriben turnos no anotaban nada — ni
-- siquiera `fn_quitar_turno`, que BORRA la fila. Reescribir un turno podía hacer
-- desaparecer una falta sin dejar huella, en un sistema cuyo principio escrito
-- es que toda edición manual deja rastro.
--
-- Esta prueba comprueba las tres, y sobre todo que el rastro diga lo que HABÍA
-- antes: un libro que solo dice «alguien cambió algo» no sirve para nada.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000023200', 'ZZTUR', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000023201', 'TurAdmin', 'Lab',
        '00000000-0000-0000-0000-000000023200', 'admin', 'x',
        '00000000-0000-0000-0000-0000000232ff', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000023202', 'TurPersona', 'Lab',
        '00000000-0000-0000-0000-000000023200', 'x', '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000232ff', true);


-- ── 1 y 2 · Crear un turno donde no había: se anota, y se sabe quién ────────

select fn_set_turno('00000000-0000-0000-0000-000000023202', '2026-09-10', '09:00', '15:30');

select is(
  (select valor_anterior || ' → ' || valor_nuevo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023202'
      and campo_modificado = 'turnos.horario'),
  '(sin turno) → 09:00–15:30',
  'Poner un turno donde no había queda anotado, y el rastro dice que antes no había nada');

select is(
  (select creado_por from turnos
    where persona_id = '00000000-0000-0000-0000-000000023202' and fecha = '2026-09-10'),
  '00000000-0000-0000-0000-000000023201'::uuid,
  'La fila guarda QUIÉN lo puso — el dato que las tres funciones calculaban y tiraban');


-- ── 3 · Cambiarlo dice qué decía antes ─────────────────────────────────────
-- Se comprueba por el PAR (antes → después) y no por «la última fila»: dentro de
-- una transacción `now()` es constante, así que `corregido_at` es idéntico en
-- todas las filas y el `id` es un uuid aleatorio. No hay orden cronológico que
-- valga acá dentro, y pedirlo daba tres falsos rojos.

select fn_set_turno('00000000-0000-0000-0000-000000023202', '2026-09-10', '13:00', '21:00');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023202'
      and campo_modificado = 'turnos.horario'
      and valor_anterior = '09:00–15:30' and valor_nuevo = '13:00–21:00'),
  1,
  'Pisar un turno guarda el horario que había antes, no solo el nuevo');


-- ── 4 · Guardar lo mismo no ensucia el libro ────────────────────────────────

select fn_set_turno('00000000-0000-0000-0000-000000023202', '2026-09-10', '13:00', '21:00');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023202'
      and campo_modificado = 'turnos.horario'),
  2,
  'Volver a guardar el MISMO turno no escribe otra fila: un libro con ruido no se lee');


-- ── 5 y 6 · Pasar a descanso ────────────────────────────────────────────────

select fn_set_descanso('00000000-0000-0000-0000-000000023202', '2026-09-10');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023202'
      and campo_modificado = 'turnos.horario'
      and valor_anterior = '13:00–21:00' and valor_nuevo = 'descanso'),
  1,
  'Marcar descanso queda anotado: ese día deja de poder contarse como falta');

select is(
  (select es_descanso from turnos
    where persona_id = '00000000-0000-0000-0000-000000023202' and fecha = '2026-09-10'),
  true,
  'Y el turno quedó efectivamente como descanso');


-- ── 7 y 8 · Quitarlo, que es la que borra la fila ──────────────────────────

select fn_quitar_turno('00000000-0000-0000-0000-000000023202', '2026-09-10');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023202'
      and campo_modificado = 'turnos.horario'
      and valor_anterior = 'descanso' and valor_nuevo = '(sin turno)'),
  1,
  'Quitar el turno deja el valor anterior ESCRITO — la fila se borra, el rastro no');

select is(
  (select count(*)::int from turnos
    where persona_id = '00000000-0000-0000-0000-000000023202' and fecha = '2026-09-10'),
  0,
  'La fila del turno sí desaparece: lo que se conserva es la anotación, no el turno');


-- ── 9 · Quitar donde no hay nada no inventa una anotación ──────────────────

select fn_quitar_turno('00000000-0000-0000-0000-000000023202', '2026-09-11');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000023202'
      and campo_modificado = 'turnos.horario'),
  4,
  'Quitar un turno que no existía no escribe nada: no pasó nada que anotar');


select * from finish();
rollback;
