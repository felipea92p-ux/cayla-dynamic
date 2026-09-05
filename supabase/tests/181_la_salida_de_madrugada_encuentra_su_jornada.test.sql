-- ============================================================================
-- 181_la_salida_de_madrugada_encuentra_su_jornada.test.sql
-- ============================================================================
-- Defiende la 0240 (C4). Reproducido contra el Postgres local antes de escribir
-- nada: quien entra a las 15:00 y cierra tienda a las 00:30 NO PODÍA marcar su
-- salida — «tipo salida_final no válido en el estado actual (se esperaba
-- entrada)»— porque el sistema miraba el día nuevo del calendario.
--
-- De ahí salían dos errores de signo contrario en la misma noche, medidos con
-- salario S/1500:
--
--     lo que pasó          15:00 → 00:30      9.50 h
--     martes registrado    15:00 → 23:00*     8.00 h   (*la inventó el cron)
--     miércoles fantasma   00:30 → 23:00*    22.50 h
--                                            ───────
--                                            30.50 h  donde hubo 9.50
--
-- LAS DOS MITADES. Que la salida de madrugada encuentre su jornada, Y que nada
-- cambie para quien no cruza la medianoche — que son casi todos. Un cambio en
-- fn_registrar_marcaje toca la puerta por la que pasa TODO el marcaje del
-- sistema: la mitad de abajo es la que dice que no rompimos el 99 % de los días.
--
-- Y LOS BORDES, que es donde esto se puede volver en contra:
--   · una jornada olvidada hace tres días NO puede tragarse la salida de hoy;
--   · una `entrada` de madrugada sigue abriendo un día nuevo, porque puede ser
--     alguien empezando su turno.
-- ============================================================================
begin;
select plan(9);

set session_replication_role = replica;
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000018100', 'ZZ181', 'Sede de laboratorio', true);
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000018102', 'NocheLab', 'Laboratorio',
        '00000000-0000-0000-0000-000000018100', 'x', '2024-01-01');
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000001810e', '00000000-0000-0000-0000-000000018100',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000001810f');
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-000000018102', '2024-01-01', '15:00', '23:00', 0, 0,
        array[1,2,3,4,5,6], 45,
        '{"1":{"e":"15:00","s":"23:00","r":0},"2":{"e":"15:00","s":"23:00","r":0},
          "3":{"e":"15:00","s":"23:00","r":0},"4":{"e":"15:00","s":"23:00","r":0},
          "5":{"e":"15:00","s":"23:00","r":0},"6":{"e":"15:00","s":"23:00","r":0}}'::jsonb);
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000001810f', true);


-- ── 1-4 · La noche que cruza la medianoche ──────────────────────────────────
select lives_ok(
  $$ select fn_registrar_marcaje('00000000-0000-0000-0000-000000018102'::uuid,
       'entrada'::tipo_marca, '2026-08-04T15:00:00-05:00'::timestamptz,
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000001810e'::uuid) $$,
  'Entra el martes a las 15:00');

select lives_ok(
  $$ select fn_registrar_marcaje('00000000-0000-0000-0000-000000018102'::uuid,
       'salida_final'::tipo_marca, '2026-08-05T00:30:00-05:00'::timestamptz,
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000001810e'::uuid) $$,
  'MEDIANOCHE · ahora SÍ puede marcar su salida a las 00:30 (antes se rechazaba)');

select is(
  (select count(*)::int from jornadas where persona_id = '00000000-0000-0000-0000-000000018102'),
  1,
  'MEDIANOCHE · una sola jornada: el día fantasma no nace');

select results_eq(
  $$ select fecha, estado::text, horas_trabajadas
       from jornadas where persona_id = '00000000-0000-0000-0000-000000018102' $$,
  $$ values ('2026-08-04'::date, 'cerrada', 9.50::numeric) $$,
  'MEDIANOCHE · el martes queda cerrado con sus 9.50 h reales, no con 8.00 inventadas');


-- ── 5 · La marca dice a qué jornada pertenece, y solo cuando hace falta ─────
-- La columna lleva valor SOLO en la excepción. Si se llenara siempre, repetiría
-- lo que el timestamp ya sabe y dejaría de señalar nada.
select results_eq(
  $$ select tipo::text, (fecha_jornada is not null)
       from marcajes where persona_id = '00000000-0000-0000-0000-000000018102'
      order by timestamp_marca $$,
  $$ values ('entrada', false), ('salida_final', true) $$,
  'La entrada normal no guarda fecha_jornada; solo la de madrugada la necesita');


-- ── 6-7 · La otra mitad: un día normal no cambia en nada ────────────────────
select lives_ok(
  $$ select fn_registrar_marcaje('00000000-0000-0000-0000-000000018102'::uuid,
       'entrada'::tipo_marca, '2026-08-06T15:00:00-05:00'::timestamptz,
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000001810e'::uuid) $$,
  'NORMAL · entra el jueves');

select lives_ok(
  $$ select fn_registrar_marcaje('00000000-0000-0000-0000-000000018102'::uuid,
       'salida_final'::tipo_marca, '2026-08-06T22:00:00-05:00'::timestamptz,
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000001810e'::uuid) $$,
  'NORMAL · y sale a las 22:00 del mismo día, como siempre');


-- ── 8 · El tope: una jornada olvidada no se traga el día siguiente ──────────
-- Se deja abierto el sábado 8 y se marca una salida el LUNES 10. Han pasado más
-- de 16 h desde su entrada, así que esa salida NO es de aquella jornada — si lo
-- fuera, un descuido de una tarde se convertiría en una jornada de dos días.
select lives_ok(
  $$ select fn_registrar_marcaje('00000000-0000-0000-0000-000000018102'::uuid,
       'entrada'::tipo_marca, '2026-08-08T15:00:00-05:00'::timestamptz,
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000001810e'::uuid) $$,
  'TOPE · entra el sábado y nadie cierra ese día');

select throws_ok(
  $$ select fn_registrar_marcaje('00000000-0000-0000-0000-000000018102'::uuid,
       'salida_final'::tipo_marca, '2026-08-10T09:00:00-05:00'::timestamptz,
       gen_random_uuid(), 'terminal'::origen_marca,
       '00000000-0000-0000-0000-00000001810e'::uuid) $$,
  'P0001', null,
  'TOPE · una salida dos días después NO se adopta: pasado el tope manda el calendario');

select * from finish();
rollback;
