-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 327_a_un_practicante_ya_se_le_mide_la_tardanza.test.sql
-- ============================================================================
-- La 0413 separó "medir" de "disciplinar" para un practicante: gana su
-- tardanza (fn_recalcular_jornada, informativo) pero no puede ser sancionado
-- con ella (fn_expediente_generar_tardanza, candado propio). Un RxH sigue
-- exactamente igual que antes de la 0413: no tiene jornada que medir.
--
-- Estas pruebas fijan las dos mitades por separado, para que un cambio futuro
-- que reabra cualquiera de las dos no pase inadvertido.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000e3271', 'ZZ71M', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000e3272', 'AdminTardePractica', 'Lab',
        '00000000-0000-0000-0000-0000000e3271', 'admin', 'x',
        '00000000-0000-0000-0000-00000e327202', '2020-01-01', 'activo', 'planilla');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, estado, tipo_vinculo)
values
  ('00000000-0000-0000-0000-0000000e3273', 'LlegaPractica', 'Lab',
   '00000000-0000-0000-0000-0000000e3271', 'x', '2020-01-01', 'activo', 'practicante'),
  ('00000000-0000-0000-0000-0000000e3274', 'LlegaRxh', 'Lab',
   '00000000-0000-0000-0000-0000000e3271', 'x', '2020-01-01', 'activo', 'rxh'),
  ('00000000-0000-0000-0000-0000000e3275', 'LlegaPlanilla', 'Lab',
   '00000000-0000-0000-0000-0000000e3271', 'x', '2020-01-01', 'activo', 'planilla');

-- Mismo horario para los tres: 09:00-18:00, los siete días, para que el
-- resultado no dependa del día de la semana en que se corra la prueba.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values
  ('00000000-0000-0000-0000-0000000e3273', '2020-01-01', '09:00', '18:00', 60, 60, array[0,1,2,3,4,5,6], 45),
  ('00000000-0000-0000-0000-0000000e3274', '2020-01-01', '09:00', '18:00', 60, 60, array[0,1,2,3,4,5,6], 45),
  ('00000000-0000-0000-0000-0000000e3275', '2020-01-01', '09:00', '18:00', 60, 60, array[0,1,2,3,4,5,6], 45);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000e327202', true);

-- ── Un día cualquiera, los tres entran 16 minutos tarde ──────────────────────
-- La fecha es fija y arbitraria: el horario cubre los siete días, así que no
-- importa en qué día de la semana caiga.
create function pg_temp.marca_entrada(p_persona uuid, p_client uuid) returns void language sql as $$
  insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
  values (p_client, p_persona, '00000000-0000-0000-0000-0000000e3271', 'entrada',
          '2026-01-15 09:16:00-05'::timestamptz);
$$;
create function pg_temp.marca_salida(p_persona uuid, p_client uuid) returns void language sql as $$
  insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
  values (p_client, p_persona, '00000000-0000-0000-0000-0000000e3271', 'salida_final',
          '2026-01-15 18:00:00-05'::timestamptz);
$$;

select pg_temp.marca_entrada('00000000-0000-0000-0000-0000000e3273', '00000000-0000-0000-0000-0000000f3273');
select pg_temp.marca_salida ('00000000-0000-0000-0000-0000000e3273', '00000000-0000-0000-0000-0000000f3274');
select pg_temp.marca_entrada('00000000-0000-0000-0000-0000000e3274', '00000000-0000-0000-0000-0000000f3275');
select pg_temp.marca_salida ('00000000-0000-0000-0000-0000000e3274', '00000000-0000-0000-0000-0000000f3276');
select pg_temp.marca_entrada('00000000-0000-0000-0000-0000000e3275', '00000000-0000-0000-0000-0000000f3277');
select pg_temp.marca_salida ('00000000-0000-0000-0000-0000000e3275', '00000000-0000-0000-0000-0000000f3278');

-- ════════════════════════════════════════════════════════════════════════════
-- MITAD 1 · fn_recalcular_jornada — medir sí, para practicante y planilla
-- ════════════════════════════════════════════════════════════════════════════
select is(
  (select minutos_tarde from jornadas where persona_id = '00000000-0000-0000-0000-0000000e3273' and fecha = '2026-01-15'),
  16,
  '0413 · un practicante SÍ acumula minutos_tarde, igual que planilla');

select is(
  (select minutos_tarde from jornadas where persona_id = '00000000-0000-0000-0000-0000000e3274' and fecha = '2026-01-15'),
  null,
  '0191 · un RxH sigue sin medirse: la 0413 no le cambia nada');

select is(
  (select minutos_tarde from jornadas where persona_id = '00000000-0000-0000-0000-0000000e3275' and fecha = '2026-01-15'),
  16,
  'control · planilla sigue midiéndose exactamente igual que antes de la 0413');

-- ════════════════════════════════════════════════════════════════════════════
-- MITAD 2 · fn_expediente_generar_tardanza — disciplinar no, ni para
-- practicante ni para RxH, aunque ya tengan minutos_tarde en la base
-- ════════════════════════════════════════════════════════════════════════════
select throws_ok(
  $$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e3273') $$,
  null,
  '0413 · un practicante no puede recibir un memo de tardanza aunque ya tenga minutos_tarde medido');

select throws_like(
  $$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e3273') $$,
  '%no está sujeta a disciplina%',
  '0413 · y el motivo es el candado nuevo, no otro paso previo de la función');

select throws_ok(
  $$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e3274') $$,
  null,
  '0413 · el candado nuevo también alcanza a un RxH, por las dudas de que alguien lo llame directo');

-- Control: a alguien de planilla el candado nuevo NO lo detiene — sigue
-- fallando por falta de tardanzas suficientes (el paso de más adelante en la
-- misma función, con solo 1 tardanza medida y mínimo 3 sin antecedente), no
-- por el candado de esta migración. pgTAP no trae un "throws_unlike"; se
-- prueba en positivo, con el mensaje real que sí debe salir.
select throws_like(
  $$ select fn_expediente_generar_tardanza('00000000-0000-0000-0000-0000000e3275') $$,
  '%Aún no corresponde%',
  'control · a planilla el candado nuevo no le aplica; sigue fallando por falta de tardanzas, no por el candado');

select finish();
rollback;
