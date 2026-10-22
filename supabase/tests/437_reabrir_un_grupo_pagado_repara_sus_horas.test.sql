-- ============================================================================
-- 437_reabrir_un_grupo_pagado_repara_sus_horas.test.sql
-- ============================================================================
-- LO QUE DEFIENDE (migración 0545) — y reproduce el incidente del 2026-10-21:
--
--   Un grupo («planilla») se marca pagado a mitad de un periodo que no ha
--   terminado. Los demás grupos con gente (aquí rxh) no se pagan, así que
--   `periodos_planilla.estado` se queda 'abierto'. Después de eso:
--
--     1. cada marca nueva de planilla entra SELLADA, una por una (0207);
--     2. su jornada no se recalcula: se queda «abierta», sin salida y sin horas,
--        aunque la persona ya marcó su salida (el candado de fn_recalcular_jornada).
--
--   Reabrir el grupo con `fn_revertir_pago` NO lo repara, porque esa función
--   solo recalcula si el periodo ENTERO estaba pagado antes (0323). Las
--   aserciones 6 y 7 lo fijan tal cual es HOY — si alguna vez cambian, es que
--   `fn_revertir_pago` se arregló: actualiza esta prueba, no la fuerces.
--
--   Lo que la 0545 agrega es la herramienta de reparación:
--
--     · se NIEGA si algún día sigue pagado (recalcular ahí no haría nada y lo
--       haría en silencio);
--     · recalcula la jornada y quita el sello de los días que SÍ cuadran;
--     · un día realmente roto SIGUE sellado — no se «arregla» a ciegas;
--     · no toca a otro grupo, y repetirla deja lo mismo.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000043700', 'ZZ437', 'Sede de laboratorio', true);

set session_replication_role = replica;
-- Quien paga y reabre (admin, con su cuenta).
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000043701', 'CuatroTresAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000043700', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000043709', '2024-01-01');
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000004370e', '00000000-0000-0000-0000-000000043700',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000004370a');
set session_replication_role = origin;

-- Planilla A: su día se reparará.  Planilla B: su día está realmente roto.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000043702', 'CuatroTresA', 'Laboratorio',
        '00000000-0000-0000-0000-000000043700', 'test-hash', '2024-01-01'),
       ('00000000-0000-0000-0000-000000043703', 'CuatroTresB', 'Laboratorio',
        '00000000-0000-0000-0000-000000043700', 'test-hash', '2024-01-01');
-- Planilla C: una jornada atrasada SIN ningún sello que quitar (ver más abajo).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000043705', 'CuatroTresC', 'Laboratorio',
        '00000000-0000-0000-0000-000000043700', 'test-hash', '2024-01-01');
-- RxH: otro grupo con gente, para que el periodo entero siga 'abierto' y para
-- comprobar que la reparación de planilla no lo toca.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000043704', 'CuatroTresRxh', 'Laboratorio',
        '00000000-0000-0000-0000-000000043700', 'test-hash', '2024-01-01', 'rxh');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, date '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6,7], 45
  from personas where id in ('00000000-0000-0000-0000-000000043702', '00000000-0000-0000-0000-000000043703', '00000000-0000-0000-0000-000000043705');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000437aa', '2026-09-28', '2026-10-28', 'abierto');

-- Quien llama cambia según la puerta: el terminal marca, el admin paga y reabre.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004370a', true);

-- ── Antes del pago: A entra a las 09:00 y RxH marca su día completo ─────────
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000043702', 'entrada'::tipo_marca, timestamptz '2026-10-21 09:00-05',
  '00000000-0000-0000-0000-000000043a01', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004370e');
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000043705', 'entrada'::tipo_marca, timestamptz '2026-10-21 09:00-05',
  '00000000-0000-0000-0000-000000043a07', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004370e');
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000043704', 'entrada'::tipo_marca, timestamptz '2026-10-21 09:00-05',
  '00000000-0000-0000-0000-000000043a02', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004370e');
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000043704', 'salida_final'::tipo_marca, timestamptz '2026-10-21 18:00-05',
  '00000000-0000-0000-0000-000000043a03', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004370e');

-- ── Se paga SOLO planilla, a mitad del periodo ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000043709', true);
select fn_periodo_pagado('00000000-0000-0000-0000-0000000437aa', true, 'planilla');

-- ── Después del pago: A marca su salida ─────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004370a', true);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000043702', 'salida_final'::tipo_marca, timestamptz '2026-10-21 18:00-05',
  '00000000-0000-0000-0000-000000043a04', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004370e');


-- C: su salida entra por una vía que no sella (aquí, un insert directo con estado
-- 'normal'). El candado igual frena el recálculo: queda una jornada atrasada SIN
-- sello. Es el caso que obliga a que la herramienta recalcule por sí misma y no
-- dependa de que al quitar un sello el trigger de marcajes recalcule de rebote.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen)
values ('00000000-0000-0000-0000-000000043a06', '00000000-0000-0000-0000-000000043705',
        '00000000-0000-0000-0000-000000043700', '00000000-0000-0000-0000-00000004370e',
        'salida_final', timestamptz '2026-10-21 18:00-05', 'terminal');


-- ── 1-5 · El incidente, reproducido ─────────────────────────────────────────
select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-0000000437aa'),
  'abierto',
  'ESCENARIO · el periodo entero sigue abierto: a rxh le falta pagar');

select is(
  (select estado from periodo_grupo_pago
    where periodo_id = '00000000-0000-0000-0000-0000000437aa' and grupo = 'planilla'),
  'pagado',
  'ESCENARIO · pero el grupo planilla sí quedó pagado');

select is(
  (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a04'),
  'pendiente_revision',
  'SÍNTOMA 1 · la salida real de A entró SELLADA, aunque su día cuadra');

select is(
  (select estado from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043702' and fecha = date '2026-10-21'),
  'abierta',
  'SÍNTOMA 2 · la jornada de A sigue «abierta» aunque ya marcó su salida');

select ok(
  (select salida_final_ts is null and horas_trabajadas is null from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043702' and fecha = date '2026-10-21'),
  'SÍNTOMA 2 · sin salida y sin horas: es lo que la planilla pagaría como cero');


select ok(
  (select estado = 'abierta' and salida_final_ts is null from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043705' and fecha = date '2026-10-21')
  and (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a06') = 'normal',
  'SÍNTOMA 3 · la jornada de C está atrasada y NO hay ningún sello que delate el problema');

-- ── 6 · Mientras el grupo SIGA pagado la herramienta se NIEGA ───────────────
select throws_like(
  $$ select fn_reparar_dias_tras_reabrir('planilla', date '2026-10-21', date '2026-10-21') $$,
  '%sigue pagado%',
  'GUARDIA · si el grupo sigue pagado la herramienta se niega, en vez de «funcionar» sin cambiar nada');

-- ── 7-8 · Reabrir el grupo NO lo repara (lo que hace hoy fn_revertir_pago) ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000043709', true);
select lives_ok(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-0000000437aa', 'Pago de planilla marcado por error', 'planilla') $$,
  'Se puede reabrir el grupo planilla');

select is(
  (select estado from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043702' and fecha = date '2026-10-21'),
  'abierta',
  'LÍMITE ACTUAL · reabrir el grupo NO recalcula (el periodo entero estaba abierto). Si esto cambia, fn_revertir_pago se arregló: actualiza la prueba');

-- B tiene un día REALMENTE roto: una salida sin entrada, sellada. En vivo el
-- terminal no deja marcar eso (el candado anti-doble-marcado); llega cuando una
-- marca atrasada se cuela fuera de orden, y entonces 0068 sella el día. Se
-- inserta tal cual quedaría, para comprobar que la reparación NO lo encubre.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen, estado_revision)
values ('00000000-0000-0000-0000-000000043a05', '00000000-0000-0000-0000-000000043703',
        '00000000-0000-0000-0000-000000043700', '00000000-0000-0000-0000-00000004370e',
        'salida_final', timestamptz '2026-10-21 18:05-05', 'terminal', 'pendiente_revision');


-- ── 9-13 · La reparación ───────────────────────────────────────────────────
select is(
  fn_reparar_dias_tras_reabrir('planilla', date '2026-10-21', date '2026-10-21'),
  3,
  'REPARA · recalculó exactamente los 3 días de planilla (A, B y C), y ninguno de rxh');

select ok(
  (select estado = 'cerrada' and salida_final_ts = timestamptz '2026-10-21 18:00-05' and horas_trabajadas > 0
     from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043702' and fecha = date '2026-10-21'),
  'REPARA · la jornada de A quedó cerrada, con su salida real y con horas');

select ok(
  (select estado = 'cerrada' and salida_final_ts = timestamptz '2026-10-21 18:00-05' and horas_trabajadas > 0
     from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043705' and fecha = date '2026-10-21'),
  'REPARA · la jornada de C, que NO tenía sello, también se recalculó: la herramienta no depende de un sello para actuar');

select is(
  (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a04'),
  'normal',
  'REPARA · el sello de A se quitó: su día cuadra y nunca debió ponerse');

select is(
  (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a05'),
  'pendiente_revision',
  'NO ENCUBRE · el día de B está realmente roto (salida sin entrada) y SIGUE sellado');

select ok(
  (select estado = 'cerrada' from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043704' and fecha = date '2026-10-21')
  and (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a03') = 'normal',
  'OTRO GRUPO · la reparación de planilla no cambió nada de rxh');


-- ── 14-16 · Repetirla deja lo mismo, y las marcas no se tocaron ────────────
create temp table horas_antes_437 on commit drop as
  select horas_trabajadas, minutos_tarde, estado
    from jornadas
   where persona_id = '00000000-0000-0000-0000-000000043702' and fecha = date '2026-10-21';

select is(
  fn_reparar_dias_tras_reabrir('planilla', date '2026-10-21', date '2026-10-21'),
  3,
  'IDEMPOTENTE · repetirla recalcula los mismos días');

select ok(
  (select (j.horas_trabajadas, j.minutos_tarde, j.estado) is not distinct from (h.horas_trabajadas, h.minutos_tarde, h.estado)
     from jornadas j, horas_antes_437 h
    where j.persona_id = '00000000-0000-0000-0000-000000043702' and j.fecha = date '2026-10-21'),
  'IDEMPOTENTE · y las horas, la tardanza y el estado de A no cambian entre una corrida y otra');

select is(
  (select count(*)::int from marcajes
    where persona_id in ('00000000-0000-0000-0000-000000043702', '00000000-0000-0000-0000-000000043703')),
  3,
  'NO TOCA MARCAS · A y B siguen con exactamente las que marcaron, ni una más ni una menos (2 + 1)');

select * from finish();
rollback;
