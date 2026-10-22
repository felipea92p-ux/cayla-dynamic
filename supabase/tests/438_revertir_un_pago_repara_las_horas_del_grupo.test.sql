-- ============================================================================
-- 438_revertir_un_pago_repara_las_horas_del_grupo.test.sql
-- ============================================================================
-- LO QUE DEFIENDE (migración 0546):
--
--   `fn_revertir_pago` reabre UN grupo. Hasta la 0546 solo recalculaba las
--   jornadas si el periodo ENTERO estaba pagado antes de reabrir (0323: era
--   cuando el candado de horas era uno solo). Desde la 0327 el candado es por
--   grupo, así que un grupo pagado SOLO —con el periodo todavía 'abierto'—
--   bloquea las horas de su gente y, al reabrirlo, nada las recalculaba. Es el
--   incidente del 2026-10-21 (planilla marcada pagada a mitad de periodo): las
--   jornadas se quedaban «abierta», sin salida y sin horas, y las marcas
--   selladas seguían selladas.
--
--   Esta prueba monta ese escenario y comprueba que, SIN llamar a ninguna otra
--   herramienta, reabrir el grupo deja:
--
--     · la jornada de quien marcó su salida con el grupo pagado → cerrada, con
--       su salida real y sus horas, y su marca ya sin sello;
--     · la jornada de quien quedó atrasada SIN sello → recalculada igual;
--     · un día realmente roto → SIGUE sellado (no se encubre);
--     · otro grupo → intacto.
--
--   La 437 defiende la herramienta (`fn_reparar_dias_tras_reabrir`) por sí sola;
--   esta defiende que `fn_revertir_pago` la use.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000043800', 'ZZ438', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000043801', 'CuatroTresOchoAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000043800', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000043809', '2024-01-01');
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000004380e', '00000000-0000-0000-0000-000000043800',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000004380a');
set session_replication_role = origin;

-- Planilla A (marca con sello), B (día roto), C (atrasada sin sello).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000043802', 'OchoA', 'Laboratorio', '00000000-0000-0000-0000-000000043800', 'test-hash', '2024-01-01'),
       ('00000000-0000-0000-0000-000000043803', 'OchoB', 'Laboratorio', '00000000-0000-0000-0000-000000043800', 'test-hash', '2024-01-01'),
       ('00000000-0000-0000-0000-000000043805', 'OchoC', 'Laboratorio', '00000000-0000-0000-0000-000000043800', 'test-hash', '2024-01-01');
-- RxH: mantiene el periodo entero 'abierto' y comprueba que no se toca.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000043804', 'OchoRxh', 'Laboratorio', '00000000-0000-0000-0000-000000043800', 'test-hash', '2024-01-01', 'rxh');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
select id, date '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6,7], 45
  from personas where id in ('00000000-0000-0000-0000-000000043802', '00000000-0000-0000-0000-000000043803', '00000000-0000-0000-0000-000000043805');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000438aa', '2026-09-28', '2026-10-28', 'abierto');

-- ── Antes del pago ──────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004380a', true);
select fn_registrar_marcaje('00000000-0000-0000-0000-000000043802', 'entrada'::tipo_marca, timestamptz '2026-10-21 09:00-05',
  '00000000-0000-0000-0000-000000043a01', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004380e');
select fn_registrar_marcaje('00000000-0000-0000-0000-000000043805', 'entrada'::tipo_marca, timestamptz '2026-10-21 09:00-05',
  '00000000-0000-0000-0000-000000043a02', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004380e');
select fn_registrar_marcaje('00000000-0000-0000-0000-000000043804', 'entrada'::tipo_marca, timestamptz '2026-10-21 09:00-05',
  '00000000-0000-0000-0000-000000043a03', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004380e');
select fn_registrar_marcaje('00000000-0000-0000-0000-000000043804', 'salida_final'::tipo_marca, timestamptz '2026-10-21 18:00-05',
  '00000000-0000-0000-0000-000000043a04', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004380e');

-- ── Se paga SOLO planilla, a mitad del periodo ──────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000043809', true);
select fn_periodo_pagado('00000000-0000-0000-0000-0000000438aa', true, 'planilla');

-- ── Con el grupo pagado: A marca su salida (entra sellada) ──────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000004380a', true);
select fn_registrar_marcaje('00000000-0000-0000-0000-000000043802', 'salida_final'::tipo_marca, timestamptz '2026-10-21 18:00-05',
  '00000000-0000-0000-0000-000000043a05', 'terminal'::origen_marca, '00000000-0000-0000-0000-00000004380e');

-- C: su salida entra por una vía que no sella; el candado frena el recálculo y
-- queda una jornada atrasada SIN sello que la delate.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen)
values ('00000000-0000-0000-0000-000000043a06', '00000000-0000-0000-0000-000000043805',
        '00000000-0000-0000-0000-000000043800', '00000000-0000-0000-0000-00000004380e',
        'salida_final', timestamptz '2026-10-21 18:00-05', 'terminal');

-- B: un día realmente roto (una salida sin entrada), sellado como lo dejaría 0068.
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen, estado_revision)
values ('00000000-0000-0000-0000-000000043a07', '00000000-0000-0000-0000-000000043803',
        '00000000-0000-0000-0000-000000043800', '00000000-0000-0000-0000-00000004380e',
        'salida_final', timestamptz '2026-10-21 18:05-05', 'terminal', 'pendiente_revision');


-- ── 1-4 · El escenario del incidente ────────────────────────────────────────
select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-0000000438aa'),
  'abierto',
  'ESCENARIO · el periodo entero sigue abierto (a rxh le falta pagar)');

select is(
  (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a05'),
  'pendiente_revision',
  'ESCENARIO · la salida real de A entró sellada');

select ok(
  (select estado = 'abierta' and salida_final_ts is null from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043802' and fecha = date '2026-10-21'),
  'ESCENARIO · la jornada de A sigue abierta aunque ya marcó su salida');

select ok(
  (select estado = 'abierta' and salida_final_ts is null from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043805' and fecha = date '2026-10-21'),
  'ESCENARIO · la jornada de C está atrasada y NO tiene ningún sello que la delate');


-- ── 5 · Se reabre el grupo, y SOLO eso: ninguna otra herramienta ────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000043809', true);
select lives_ok(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-0000000438aa', 'Pago de planilla marcado por error', 'planilla') $$,
  'Se puede reabrir el grupo planilla');


-- ── 6-10 · Reabrir YA deja las horas al día ────────────────────────────────
select ok(
  (select estado = 'cerrada' and salida_final_ts = timestamptz '2026-10-21 18:00-05' and horas_trabajadas > 0
     from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043802' and fecha = date '2026-10-21'),
  'REABRIR REPARA · la jornada de A quedó cerrada, con su salida real y sus horas');

select is(
  (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a05'),
  'normal',
  'REABRIR REPARA · el sello de A se quitó: su día cuadra y nunca debió ponerse');

select ok(
  (select estado = 'cerrada' and salida_final_ts = timestamptz '2026-10-21 18:00-05' and horas_trabajadas > 0
     from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043805' and fecha = date '2026-10-21'),
  'REABRIR REPARA · la jornada de C, que no tenía sello, también se recalculó');

select is(
  (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a07'),
  'pendiente_revision',
  'NO ENCUBRE · el día de B está realmente roto y SIGUE sellado');

select ok(
  (select estado = 'cerrada' from jornadas
    where persona_id = '00000000-0000-0000-0000-000000043804' and fecha = date '2026-10-21')
  and (select estado_revision::text from marcajes where client_uuid = '00000000-0000-0000-0000-000000043a04') = 'normal',
  'OTRO GRUPO · rxh quedó intacto');


-- ── 11 · La reversa sigue dejando su rastro ────────────────────────────────
select ok(
  (select count(*) = 1 from reversas_pago
    where periodo_id = '00000000-0000-0000-0000-0000000438aa' and grupo = 'planilla'
      and motivo = 'Pago de planilla marcado por error'),
  'RASTRO · la reversa quedó registrada con su motivo y su grupo');

select * from finish();
rollback;
