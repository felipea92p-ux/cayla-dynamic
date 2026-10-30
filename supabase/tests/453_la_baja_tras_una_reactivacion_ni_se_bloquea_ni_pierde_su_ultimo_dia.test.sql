-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 453_la_baja_tras_una_reactivacion_ni_se_bloquea_ni_pierde_su_ultimo_dia.test.sql — la 0563
-- ============================================================================
-- Los dos casos REALES del 2026-10-29 (Robert Cabrera y Emily Rico) y lo que no
-- puede moverse:
--   · ROBERT: ingreso 19/10, trabajó hasta el 28/10. Lo dieron de baja con un
--     cese del 19/10, lo reactivaron y repitieron la baja: el cierre de la prueba
--     (que ya no veía sus jornadas, porque la prueba se reabrió HOY) volvió a
--     poner el 19/10, y además la baja se negaba por el horario que dejó la
--     reactivación. Ahora: último día 28/10, sin bloqueo, y su sueldo y su horario
--     llegan hasta el 28/10 (no se quedan cerrados el 19).
--   · EMILY: baja correcta el 29/10, reactivada, baja otra vez. El cierre ya
--     acertaba (marcó el 29), pero la baja se negaba por los tramos que dejó la
--     reactivación.
--   · LO QUE NO SE RETIRA: un salario futuro cargado a propósito (sin constancia de
--     reactivación) sigue frenando la baja; y un tramo de reactivación sobre el que
--     ya se trabajó también.
--   · Lo retirado deja su rastro, y repegar la migración no cambia nada.
-- ============================================================================
begin;
select plan(26);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000453a01', 'ZZ453', 'Sede de laboratorio 453', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000453b01', 'Admin', 'Lab453', '00000000-0000-0000-0000-000000453a01', 'admin', 'x',
   '00000000-0000-0000-0000-000000453c01', '2024-01-01', 'activo', 'planilla');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000453c01', true);

-- Robert (d01), Emily (d02), un salario futuro a propósito (d03) y un tramo con trabajo encima (d04).
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000453d01', 'Robert', 'Lab453', '00000000-0000-0000-0000-000000453a01', 'integrante', 'x', '2026-10-19', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000453d02', 'Emily',  'Lab453', '00000000-0000-0000-0000-000000453a01', 'integrante', 'x', '2026-10-21', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000453d03', 'Futuro', 'Lab453', '00000000-0000-0000-0000-000000453a01', 'integrante', 'x', '2026-10-10', 'activo', 'prueba'),
  ('00000000-0000-0000-0000-000000453d04', 'Trabajo','Lab453', '00000000-0000-0000-0000-000000453a01', 'integrante', 'x', '2026-10-19', 'activo', 'prueba');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000453d01', 'cayla', 1230, '2026-09-28'),
  ('00000000-0000-0000-0000-000000453d02', 'cayla', 1230, '2026-09-28'),
  ('00000000-0000-0000-0000-000000453d04', 'cayla', 1230, '2026-09-28');
-- El de d03 tiene un aumento futuro cargado A MANO: nadie lo creó una reactivación.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta, nota) values
  ('00000000-0000-0000-0000-000000453d03', 'cayla', 1230, '2026-09-28', '2026-10-20', null);
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, nota) values
  ('00000000-0000-0000-0000-000000453d03', 'cayla', 1300, '2026-10-21', 'Aumento pactado');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida) values
  ('00000000-0000-0000-0000-000000453d01', '2026-10-19', '09:00', '17:30'),
  ('00000000-0000-0000-0000-000000453d02', '2026-10-21', '09:00', '17:30'),
  ('00000000-0000-0000-0000-000000453d04', '2026-10-19', '09:00', '17:30');

create function pg_temp.jornada(p_persona uuid, p_fecha date) returns void language sql as $$
  insert into jornadas (persona_id, fecha, sede_id, entrada_ts, salida_final_ts, horas_trabajadas, estado)
  values (p_persona, p_fecha, '00000000-0000-0000-0000-000000453a01',
          (p_fecha || ' 09:00-05')::timestamptz, (p_fecha || ' 15:00-05')::timestamptz, 6, 'cerrada');
$$;
-- Robert trabajó del 19 al 28; Emily del 21 al 29.
select pg_temp.jornada('00000000-0000-0000-0000-000000453d01', d::date)
  from generate_series(date '2026-10-19', date '2026-10-28', interval '1 day') d;
select pg_temp.jornada('00000000-0000-0000-0000-000000453d02', d::date)
  from generate_series(date '2026-10-21', date '2026-10-29', interval '1 day') d;
select pg_temp.jornada('00000000-0000-0000-0000-000000453d04', d::date)
  from generate_series(date '2026-10-19', date '2026-10-28', interval '1 day') d;

-- ── 1 · ROBERT: la baja equivocada, la reactivación y la baja repetida ──────
select lives_ok($$ select fn_cesar_persona('00000000-0000-0000-0000-000000453d01', '2026-10-19', 'fin_periodo_prueba') $$,
  'ROBERT · primero se le da de baja con un último día equivocado (19/10), como pasó');
select lives_ok($$ select fn_reactivar_persona('00000000-0000-0000-0000-000000453d01') $$,
  'ROBERT · se lo reactiva para rehacerla');
select ok(
  (select min(vigente_desde) from horarios_asignados where persona_id = '00000000-0000-0000-0000-000000453d01' and vigente_desde > '2026-10-28') is not null,
  'ROBERT · y la reactivación le dejó un horario que empieza DESPUÉS del 28/10 (lo que bloqueaba la baja)');
select lives_ok($$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000453d01', 'no_apto', 'No pasó la prueba') $$,
  'ROBERT · cerrar la prueba ya no se bloquea');
select is((select fecha_cese from personas where id = '00000000-0000-0000-0000-000000453d01'), '2026-10-28'::date,
  'ROBERT · el último día es el 28/10, el de su última jornada, no el de ingreso (el defecto de la 0536)');
select is((select cerrada_fecha from pruebas where persona_id = '00000000-0000-0000-0000-000000453d01' and resultado = 'no_apto'), '2026-10-28'::date,
  'ROBERT · y la prueba queda cerrada con esa misma fecha');
select is((select count(*)::int from horarios_asignados where persona_id = '00000000-0000-0000-0000-000000453d01' and vigente_desde > '2026-10-28'), 0,
  'ROBERT · el horario de la reactivación se retiró');
select is((select count(*)::int from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000453d01' and vigente_desde > '2026-10-28'), 0,
  'ROBERT · y el salario de la reactivación también');
select is((select max(vigente_hasta) from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000453d01'), '2026-10-28'::date,
  'ROBERT · su sueldo llega hasta el 28/10, no se queda cerrado el día de la baja equivocada (la liquidación pagaba un día)');
select is((select max(vigente_hasta) from horarios_asignados where persona_id = '00000000-0000-0000-0000-000000453d01'), '2026-10-28'::date,
  'ROBERT · y su horario también');
select is((select count(*)::int from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000453d01' and vigente_hasta is null), 0,
  'ROBERT · no queda ningún salario abierto en alguien que ya se fue');

-- ── 2 · EMILY: la baja correcta, reactivada, y otra vez ─────────────────────
select lives_ok($$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000453d02', 'no_apto', 'Primera baja') $$,
  'EMILY · la primera baja sale con su último día real');
select is((select fecha_cese from personas where id = '00000000-0000-0000-0000-000000453d02'), '2026-10-29'::date,
  'EMILY · el 29/10');
select lives_ok($$ select fn_reactivar_persona('00000000-0000-0000-0000-000000453d02') $$,
  'EMILY · se la reactiva');
select lives_ok($$ select fn_prueba_cerrar('00000000-0000-0000-0000-000000453d02', 'no_apto', 'Segunda baja') $$,
  'EMILY · y la segunda baja ya no se bloquea por los tramos que dejó la reactivación');
select is((select fecha_cese from personas where id = '00000000-0000-0000-0000-000000453d02'), '2026-10-29'::date,
  'EMILY · con el mismo último día');
select is((select max(vigente_hasta) from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000453d02'), '2026-10-29'::date,
  'EMILY · su sueldo llega hasta el 29/10');

-- ── 3 · Lo retirado deja su rastro ──────────────────────────────────────────
select is((select count(*)::int from correcciones_auditoria where persona_id = '00000000-0000-0000-0000-000000453d01'
            and campo_modificado = 'salario_de_reactivacion_retirado'), 1,
  'RASTRO · el salario retirado de Robert queda escrito');
select ok((select valor_anterior like 'S/ 1230.00 vigente desde %' from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-000000453d01' and campo_modificado = 'salario_de_reactivacion_retirado'),
  'RASTRO · con su monto y su fecha, para poder restituirlo');
select is((select count(*)::int from correcciones_auditoria where persona_id = '00000000-0000-0000-0000-000000453d01'
            and campo_modificado = 'horario_de_reactivacion_retirado'), 1,
  'RASTRO · y su horario');

-- ── 4 · Lo que NO se retira ─────────────────────────────────────────────────
select throws_ok($$ select fn_cesar_persona('00000000-0000-0000-0000-000000453d03', '2026-10-15', 'fin_periodo_prueba') $$,
  'P0001', null,
  'NO SE RETIRA · un salario futuro cargado a propósito sigue frenando la baja');
select is((select count(*)::int from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000453d03' and vigente_desde = '2026-10-21'), 1,
  'NO SE RETIRA · y ese salario sigue ahí');

select lives_ok($$ select fn_cesar_persona('00000000-0000-0000-0000-000000453d04', '2026-10-19', 'fin_periodo_prueba') $$,
  'TRABAJO · baja equivocada de alguien que SÍ trabajó después');
select lives_ok($$ select fn_reactivar_persona('00000000-0000-0000-0000-000000453d04') $$,
  'TRABAJO · reactivada');
select pg_temp.jornada('00000000-0000-0000-0000-000000453d04', fn_hoy_lima());
select throws_ok($$ select fn_cesar_persona('00000000-0000-0000-0000-000000453d04', '2026-10-28', 'fin_periodo_prueba') $$,
  'P0001', null,
  'TRABAJO · si ya marcó desde que empieza el tramo de la reactivación, ese tramo NO se retira y la baja sigue frenada');
select is((select count(*)::int from correcciones_auditoria where persona_id = '00000000-0000-0000-0000-000000453d04'
            and campo_modificado like '%de_reactivacion_retirado'), 0,
  'TRABAJO · y no se retiró nada');

select * from finish();
rollback;
