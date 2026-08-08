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

-- ── El escenario: junio pagado, agosto abierto ──────────────────────────────
-- Dos periodos y no uno, porque la mitad que se olvida es la de abajo: que
-- fuera de lo pagado todo siga funcionando.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-00000000c6aa', '2026-06-01', '2026-06-30', 'pagado'),
  ('00000000-0000-0000-0000-00000000c6bb', '2026-08-01', '2026-08-31', 'abierto');

-- ── 1 · Las seis puertas, cerradas sobre junio ──────────────────────────────
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
-- empieza en mayo recalcula junio, que ya se pagó.
select throws_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-00000000c602'::uuid,
       '2026-05-01'::date, '{"1":{"e":"09:00","s":"18:00","r":60}}'::jsonb) $$,
  'P0001', null,
  'HORARIO · no se puede hacer regir un horario que alcanza a junio pagado');

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

select lives_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-00000000c602'::uuid,
       '2026-09-01'::date, '{"1":{"e":"09:00","s":"18:00","r":60}}'::jsonb) $$,
  'ABIERTO · sí se puede hacer regir un horario que empieza después de lo pagado');

select * from finish();
rollback;
