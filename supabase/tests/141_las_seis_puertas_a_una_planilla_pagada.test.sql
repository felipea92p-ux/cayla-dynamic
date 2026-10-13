-- ============================================================================
-- 141_las_seis_puertas_a_una_planilla_pagada.test.sql
-- ============================================================================
-- El caso real, medido en producción el 2026-08-07:
--
--   Se comparó el esquema entero de producción contra el del repositorio,
--   función por función. El repositorio protege 19 funciones con el candado de
--   periodo pagado; producción tenía 13. Faltaban estas seis:
--
--     fn_set_feriado · fn_quitar_feriado · fn_set_turno · fn_quitar_turno
--     fn_set_horario_semanal · fn_set_descanso
--
--   Sus cuerpos se pidieron y se compararon línea a línea: producción era el
--   repositorio MENOS el bloque de guarda, ni una línea de más. La 0180 lo
--   repone.
--
-- QUÉ DEFIENDE ESTE ARCHIVO, Y QUÉ NO
--
--   Defiende: que ninguna de las seis deje tocar una fecha dentro de un
--   periodo PAGADO, y —la otra mitad, que se olvida— que fuera de un periodo
--   pagado las seis sigan funcionando. Un candado que cierra siempre no es un
--   candado: es una pantalla rota, y alguien lo quitaría en la primera urgencia.
--
--   NO defiende contra lo que pasó. Esto es lo importante y conviene decirlo:
--   la base local SIEMPRE tuvo el candado. Estas pruebas habrían pasado en
--   verde todos los días de julio y agosto mientras producción corría sin él.
--   Una prueba mira el repositorio; no mira producción. Lo que caza esa
--   diferencia es `scripts/sql-manual/huella_del_esquema.sql`, y por eso existe.
--
--   Lo que este archivo sí caza es a quien mañana reescriba una de las seis y
--   se deje el bloque por el camino — que es exactamente como se pierde, una
--   copia descuidada a la vez.
--
-- POR QUÉ SE PRUEBA EL COMPORTAMIENTO Y NO EL TEXTO
--   Se podría comprobar que `prosrc` contiene 'periodo ya PAGADO'. Sería más
--   corto y no valdría nada: pasaría con el bloque comentado. Aquí se llama a
--   la función de verdad y se exige el error. Se prueba la promesa, no la
--   forma de cumplirla.
--
-- DESDE QUÉ FECHA SE PUEDE BARRER CON `fn_hoy_lima()` FALSEADO
--   Solo desde el 2026-08-22. Los periodos de junio y agosto de 2026 son
--   fechas FIJAS y el tercero es relativo a hoy; el archivo da por hecho que
--   los dos fijos ya pasaron, y con un reloj real eso es siempre cierto. Con
--   un reloj falseado a antes del 22-ago-2026 deja de serlo, y falla por dos
--   motivos distintos que NO son un defecto del motor ni del archivo:
--     · 2026-04-01 … 04-22 (22 días): solo cae la aserción 13. Un horario que
--       empieza en hoy+45 queda ANTES del junio pagado, y el candado de
--       pagado lo rechaza —con razón—.
--     · 2026-04-23 … 08-21 (119 días, salvo el 21 y el 22 de junio): el
--       periodo relativo (hoy+10 … hoy+39) pisa junio o agosto y el archivo
--       entero aborta en el INSERT, con «periodos_sin_solape». El resto del
--       archivo sale como una cascada de «transaction is aborted»; el error
--       que importa es solo el primero.
--   Medido el 2026-10-11, día por día: de 2026-08-22 a 2032-12-31 (2 324
--   fechas) no falla ninguna. Por eso el CI, que corre con la fecha real, no
--   tiene nada que temer de esto.
-- ============================================================================
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000c600', 'ZZSEIS', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000c601', 'SeisAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c600', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000c609');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash)
values ('00000000-0000-0000-0000-00000000c602', 'SeisPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c600', 'test-hash');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c609', true);

-- ── El escenario: junio pagado, agosto abierto, y un pagado en el futuro ────
-- Dos periodos y no uno, porque la mitad que se olvida es la de abajo: que
-- fuera de lo pagado todo siga funcionando.
--
-- EL TERCERO LO OBLIGA LA 0444, y la razón es justo la que enseña el
-- encabezado de este archivo. Desde la 0444 `fn_set_horario_semanal` rechaza
-- toda fecha anterior a hoy, y lo hace ANTES de mirar si hay un periodo
-- pagado. Con el escenario de solo dos periodos —los dos ya en el pasado
-- real— la prueba del horario seguía en verde, pero pasaba por el motivo
-- equivocado: lo que saltaba era el candado de fecha, no el de planilla
-- pagada, y este archivo se habría quedado defendiendo cinco puertas de las
-- seis sin que nada avisara. Un periodo pagado en el FUTURO es la única forma
-- que queda de ejercitar de verdad el candado de pagado en esta función.
--
-- Dura 30 días (hoy+10 → hoy+39) y no menos porque `periodos_planilla` exige
-- entre 20 y 46 días de largo (0025). Un periodo de diez días revienta contra
-- ese check antes de llegar a probar nada.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-00000000c6aa', '2026-06-01', '2026-06-30', 'pagado'),
  ('00000000-0000-0000-0000-00000000c6bb', '2026-08-01', '2026-08-31', 'abierto'),
  ('00000000-0000-0000-0000-00000000c6cc', fn_hoy_lima() + 10, fn_hoy_lima() + 39, 'pagado');

-- ── 1 · Las seis puertas, cerradas sobre lo ya pagado ──────────────────────
-- El feriado se crea primero en agosto y se mueve la fecha a mano, porque
-- fn_quitar_feriado sobre una fecha sin feriado fallaría por «no hay feriado»
-- y la prueba pasaría por el motivo equivocado — el error diría lo que
-- queremos oír sin que el candado exista.
insert into feriados (fecha, nombre) values ('2026-06-15', 'Feriado de laboratorio');

select throws_ok(
  $$ select fn_set_feriado('2026-06-15'::date, 'Cambiado a la fuerza') $$,
  'P0001', null,
  'FERIADO · no se puede crear ni renombrar un feriado dentro de junio pagado');

select throws_ok(
  $$ select fn_quitar_feriado('2026-06-15'::date) $$,
  'P0001', null,
  'FERIADO · no se puede borrar un feriado dentro de junio pagado');

select throws_ok(
  $$ select fn_set_turno('00000000-0000-0000-0000-00000000c602'::uuid,
                         '2026-06-15'::date, '09:00'::time, '18:00'::time) $$,
  'P0001', null,
  'TURNO · no se puede poner un turno dentro de junio pagado');

select throws_ok(
  $$ select fn_quitar_turno('00000000-0000-0000-0000-00000000c602'::uuid, '2026-06-15'::date) $$,
  'P0001', null,
  'TURNO · no se puede quitar un turno dentro de junio pagado');

select throws_ok(
  $$ select fn_set_descanso('00000000-0000-0000-0000-00000000c602'::uuid, '2026-06-15'::date) $$,
  'P0001', null,
  'DESCANSO · no se puede marcar descanso dentro de junio pagado');

-- El horario no mira una fecha suelta: mira hacia adelante. Un horario que
-- empieza dentro de cinco días alcanza el periodo pagado que empieza en diez.
--
-- SE EXIGE EL MENSAJE, no solo 'P0001'. Con la fecha en el pasado —como
-- estaba— este mismo throws_ok pasaba con el error de la 0444 («ya pasó») sin
-- que el candado de pagado existiera siquiera. Es exactamente la trampa que
-- el comentario del feriado, veinte líneas más arriba, ya describe: «el error
-- diría lo que queremos oír sin que el candado exista». Nombrar el mensaje es
-- lo que hace imposible volver a caer en ella.
select throws_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-00000000c602'::uuid,
       fn_hoy_lima() + 5, '{"1":{"e":"09:00","s":"18:00","r":60}}'::jsonb, 'Prueba pgTAP.') $$,
  'P0001',
  'Ese horario tocaría un periodo ya PAGADO (recalcula las jornadas desde esa fecha en adelante). Reabre el periodo primero.',
  'HORARIO · no se puede hacer regir un horario que alcanza un periodo pagado');

-- ── 2 · El feriado de junio sigue intacto ───────────────────────────────────
-- No basta con que la función se queje: tiene que no haber tocado nada. Una
-- excepción lanzada DESPUÉS de escribir dejaría el dato cambiado y la prueba
-- de arriba en verde.
select is(
  (select nombre from feriados where fecha = '2026-06-15'),
  'Feriado de laboratorio',
  'INTACTO · el feriado de junio conserva su nombre, no se escribió nada');

-- ── 3 · La otra mitad: en agosto, abierto, las seis funcionan ───────────────
select lives_ok(
  $$ select fn_set_feriado('2026-08-15'::date, 'Feriado de agosto') $$,
  'ABIERTO · sí se puede crear un feriado en agosto');

select lives_ok(
  $$ select fn_quitar_feriado('2026-08-15'::date) $$,
  'ABIERTO · sí se puede quitar un feriado en agosto');

select lives_ok(
  $$ select fn_set_turno('00000000-0000-0000-0000-00000000c602'::uuid,
                         '2026-08-14'::date, '09:00'::time, '18:00'::time) $$,
  'ABIERTO · sí se puede poner un turno en agosto');

select lives_ok(
  $$ select fn_quitar_turno('00000000-0000-0000-0000-00000000c602'::uuid, '2026-08-14'::date) $$,
  'ABIERTO · sí se puede quitar un turno en agosto');

select lives_ok(
  $$ select fn_set_descanso('00000000-0000-0000-0000-00000000c602'::uuid, '2026-08-14'::date) $$,
  'ABIERTO · sí se puede marcar descanso en agosto');

-- La otra mitad del par de arriba, y por eso la fecha no es cualquiera: tiene
-- que caer DESPUÉS del periodo pagado futuro (que termina a los 39 días)
-- para que el candado de pagado no tenga nada que decir, y a la vez no ser pasada,
-- para que el de la 0444 tampoco. La fecha fija original (2026-09-01) ya no
-- sirve para ninguna de las dos cosas: quedó en el pasado real.
select lives_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-00000000c602'::uuid,
       fn_hoy_lima() + 45, '{"1":{"e":"09:00","s":"18:00","r":60}}'::jsonb, 'Prueba pgTAP.') $$,
  'ABIERTO · sí se puede hacer regir un horario que empieza después de lo pagado');

select * from finish();
rollback;
