-- ============================================================================
-- 230_una_suspension_no_pasa_del_tope.test.sql
-- ============================================================================
-- El defecto que cierra (0294): `fn_expediente_set_suspension` escribía
-- cualquier número de días sin mirar el Reglamento ni el historial.
--
-- Medido el 2026-08-25 sobre un borrador real de segunda suspensión por
-- tardanzas: el generador propuso 2 días y el editor aceptó **10** — 26, 27,
-- 28, 29 y 31 de agosto, y del 1 al 5 de septiembre. Nueve días de sueldo de
-- más, y un memo que se funda en el numeral 19.2 d) incumpliendo en su parte
-- resolutiva el tope de tres del numeral 54.5 que ese mismo Reglamento fija.
--
-- LA INVARIANTE QUE DEFIENDE:
--
--   Lo que el editor acepta, el Reglamento lo permite.
--
-- Los tres límites son los que el generador YA aplicaba desde la 0235. La
-- prueba los fija en el editor para que no puedan volver a separarse: si
-- alguien afloja uno de los dos lados, esto se cae.
--
-- POR QUÉ EL HORARIO ES DE LOS SIETE DÍAS
--   La suspensión se fija en días LABORABLES (0075) y `fn_dias_suspension` se
--   niega si no encuentra ninguno. Con un horario de lunes a sábado, una
--   prueba que corriera un domingo mediría otra cosa. Los siete días hacen que
--   el resultado no dependa del día en que se ejecute.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000002e0', 'ZZTOP', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-0000000002e1', 'TopeAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000002e0', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000002e9');
set session_replication_role = origin;

-- Tres situaciones: quien nunca fue suspendida, quien ya cumplió una de un día,
-- y la misma de un día pero por FALTAS — que se rige por otra escala.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000002a1', 'TopePrimera', 'Laboratorio', '00000000-0000-0000-0000-0000000002e0', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-0000000002a2', 'TopeSegunda', 'Laboratorio', '00000000-0000-0000-0000-0000000002e0', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-0000000002a3', 'TopeFalta', 'Laboratorio', '00000000-0000-0000-0000-0000000002e0', 'test-hash', 'planilla');

-- Horario de los siete días para las dos: sin él no hay días laborables que
-- fijar y `fn_dias_suspension` aborta antes de llegar a lo que se prueba.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select p, '2020-01-01', '09:00', '18:00', 60, 60, array[0,1,2,3,4,5,6], 45
from (values ('00000000-0000-0000-0000-0000000002a1'::uuid),
             ('00000000-0000-0000-0000-0000000002a2'::uuid),
             ('00000000-0000-0000-0000-0000000002a3'::uuid)) as v(p);

-- La suspensión previa de un día, ENTREGADA y vigente (art. 56).
insert into expediente_disciplinario
  (correlativo, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   suspension_dias, suspension_desde, suspension_hasta, firmante_id, firmado_at,
   medio_entrega, entregado_at, creado_por)
values
  ('T-ZZTOP/0001', '00000000-0000-0000-0000-0000000002a2', 'tardanza', 'suspension', 'entregado',
   fn_hoy_lima() - 40, fn_hoy_lima() - 35, 1, fn_hoy_lima() - 34, fn_hoy_lima() - 34,
   '00000000-0000-0000-0000-0000000002e1', now() - interval '1 month',
   'fisico', now() - interval '1 month',
   '00000000-0000-0000-0000-0000000002e1'),
  -- La misma forma, pero por FALTAS: su escala tiene un solo peldaño de
  -- suspensión y el generador la emite siempre de un día.
  ('F-ZZTOP/0001', '00000000-0000-0000-0000-0000000002a3', 'falta', 'suspension', 'entregado',
   fn_hoy_lima() - 40, fn_hoy_lima() - 35, 1, fn_hoy_lima() - 34, fn_hoy_lima() - 34,
   '00000000-0000-0000-0000-0000000002e1', now() - interval '1 month',
   'fisico', now() - interval '1 month',
   '00000000-0000-0000-0000-0000000002e1');

-- Los dos borradores que se van a editar.
insert into expediente_disciplinario
  (id, persona_id, tipo_causal, nivel, estado, periodo_desde, periodo_hasta,
   suspension_dias, suspension_desde, suspension_hasta, creado_por)
values
  ('00000000-0000-0000-0000-0000000002b1', '00000000-0000-0000-0000-0000000002a1',
   'tardanza', 'suspension', 'borrador', fn_hoy_lima() - 2, fn_hoy_lima(),
   1, fn_hoy_lima() + 1, fn_hoy_lima() + 1, '00000000-0000-0000-0000-0000000002e1'),
  ('00000000-0000-0000-0000-0000000002b2', '00000000-0000-0000-0000-0000000002a2',
   'tardanza', 'suspension', 'borrador', fn_hoy_lima() - 2, fn_hoy_lima(),
   2, fn_hoy_lima() + 1, fn_hoy_lima() + 2, '00000000-0000-0000-0000-0000000002e1'),
  ('00000000-0000-0000-0000-0000000002b3', '00000000-0000-0000-0000-0000000002a3',
   'falta', 'suspension', 'borrador', fn_hoy_lima() - 2, fn_hoy_lima(),
   1, fn_hoy_lima() + 1, fn_hoy_lima() + 1, '00000000-0000-0000-0000-0000000002e1');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000002e9', true);

-- ── 1-2 · El techo absoluto del numeral 54.5 ────────────────────────────────
-- Es el caso real: 10 días escritos sobre un borrador de segunda suspensión.
select throws_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b2'::uuid, 10, fn_hoy_lima() + 1) $$,
  'P0001',
  null,
  'Diez días se rechazan: el numeral 54.5 topa toda suspensión en tres');

select throws_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b1'::uuid, 4, fn_hoy_lima() + 1) $$,
  'P0001',
  null,
  'Cuatro días tampoco, ni siquiera en una primera suspensión');

-- ── 3-4 · Numeral 19.2 c): la primera es de uno a dos días ──────────────────
select throws_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b1'::uuid, 3, fn_hoy_lima() + 1) $$,
  'P0001',
  null,
  'Tres días en una PRIMERA suspensión se rechazan (19.2 c la topa en dos)');

select lives_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b1'::uuid, 2, fn_hoy_lima() + 1) $$,
  'Dos días en una primera suspensión sí se aceptan');

-- ── 5-6 · Numeral 19.2 d): la segunda, de mayor duración que la primera ─────
select throws_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b2'::uuid, 1, fn_hoy_lima() + 1) $$,
  'P0001',
  null,
  'Igualar la suspensión previa se rechaza: una escalera que no sube no agrava');

select lives_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b2'::uuid, 3, fn_hoy_lima() + 1) $$,
  'Tres días en una SEGUNDA suspensión sí se aceptan: mayor que la primera y dentro del techo');

-- ── 7 · Y lo aceptado se escribe de verdad ──────────────────────────────────
-- Un candado que rechaza pero no guarda sería peor que no tenerlo: el borrador
-- se quedaría con el número viejo mientras la pantalla dice que se fijó.
select is(
  (select suspension_dias from expediente_disciplinario
    where id = '00000000-0000-0000-0000-0000000002b2'),
  3,
  'Los tres días quedaron escritos en el borrador');

-- ── 8-9 · La escalera del 19.2 es la de TARDANZAS, y solo esa ──────────────
-- La escala de faltas tiene un único peldaño de suspensión (amonestación →
-- suspensión → imputación) y su generador la emite siempre de un día. Exigirle
-- «mayor que la anterior» rechazaría un borrador legítimo al mover su fecha,
-- porque cambiar la fecha reenvía los mismos días.
select lives_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b3'::uuid, 1, fn_hoy_lima() + 1) $$,
  'Una suspensión por FALTAS repite el día de la anterior: su escala no gradúa como el 19.2');

-- Pero el techo del 54.5 sí es de toda suspensión, sea cual sea la causal.
select throws_ok(
  $$ select * from fn_expediente_set_suspension(
       '00000000-0000-0000-0000-0000000002b3'::uuid, 4, fn_hoy_lima() + 1) $$,
  'P0001',
  null,
  'Cuatro días por faltas también se rechazan: el 54.5 topa toda suspensión');

select * from finish();
rollback;
