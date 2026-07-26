-- ============================================================================
-- 80_recalcular_jornada.test.sql — Red de seguridad del número que paga
-- ============================================================================
-- fn_recalcular_jornada produce `horas_trabajadas`, y de ese número sale el
-- sueldo de una persona real: pago = salario × horas / (6.5 × días). Hasta hoy
-- (26/07/2026) no tenía ni una sola prueba, y es la función más reescrita del
-- repo — seis migraciones la han tocado (0002, 0009, 0013, 0014, 0016, 0017).
--
-- ESTAS PRUEBAS FIJAN LO QUE HACE HOY, no lo que debería hacer. Dos de los casos
-- documentan defectos conocidos y están marcados como tales: el objetivo es que
-- cualquier cambio futuro los mueva A PROPÓSITO y no por accidente. Cuando se
-- corrija un defecto, se actualiza aquí en el mismo commit.
--
-- Los casos vienen de días reales de producción, no de la imaginación:
--   JB → Estefany (17 jul) y Carlos (25 jul): salieron y no marcaron el retorno.
--   JC → Ytamar (25 jul): le marcaron "salida a almuerzo" cuando en realidad se
--        iba a casa, alguien marcó un "regreso" intentando arreglarlo, y el
--        auto-cierre cerró el día copiando la hora de la última marca.
--   JD → Felipe (25 jul): entrada y auto-cierre a la misma hora → cero horas.
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000fe', 'ZZJOR', 'Sede de laboratorio', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000a1', 'PruebaJA', 'Laboratorio', '00000000-0000-0000-0000-0000000000fe', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000a2', 'PruebaJB', 'Laboratorio', '00000000-0000-0000-0000-0000000000fe', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000a3', 'PruebaJC', 'Laboratorio', '00000000-0000-0000-0000-0000000000fe', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000a4', 'PruebaJD', 'Laboratorio', '00000000-0000-0000-0000-0000000000fe', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000a5', 'PruebaJE', 'Laboratorio', '00000000-0000-0000-0000-0000000000fe', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000a6', 'PruebaJF', 'Laboratorio', '00000000-0000-0000-0000-0000000000fe', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000a7', 'PruebaJG', 'Laboratorio', '00000000-0000-0000-0000-0000000000fe', 'test-hash');

-- Horario 09:00–18:00 con 60 min de refrigerio ⇒ 8 h programadas al día.
-- JC va aparte: turno de tarde, 13:00–20:00 con 60 min ⇒ 6 h programadas.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo,
   horario_por_dia)
select p, '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 48,
       '{"0":{"e":"09:00","s":"18:00","r":60},"1":{"e":"09:00","s":"18:00","r":60},
         "2":{"e":"09:00","s":"18:00","r":60},"3":{"e":"09:00","s":"18:00","r":60},
         "4":{"e":"09:00","s":"18:00","r":60},"5":{"e":"09:00","s":"18:00","r":60},
         "6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array[
  '00000000-0000-0000-0000-0000000000a1'::uuid, '00000000-0000-0000-0000-0000000000a2'::uuid,
  '00000000-0000-0000-0000-0000000000a4'::uuid, '00000000-0000-0000-0000-0000000000a5'::uuid,
  '00000000-0000-0000-0000-0000000000a6'::uuid, '00000000-0000-0000-0000-0000000000a7'::uuid]) p;

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo,
   horario_por_dia)
values ('00000000-0000-0000-0000-0000000000a3', '2026-01-01', '13:00', '20:00', 60, 60,
        array[1,2,3,4,5,6], 42,
        '{"0":{"e":"13:00","s":"20:00","r":60},"1":{"e":"13:00","s":"20:00","r":60},
          "2":{"e":"13:00","s":"20:00","r":60},"3":{"e":"13:00","s":"20:00","r":60},
          "4":{"e":"13:00","s":"20:00","r":60},"5":{"e":"13:00","s":"20:00","r":60},
          "6":{"e":"13:00","s":"20:00","r":60}}'::jsonb);

-- ── JA · el día que sale bien: entra, almuerza una hora, vuelve, se va ───────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000fe', 'entrada',          '2026-07-22T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000fe', 'salida_almuerzo',  '2026-07-22T13:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000fe', 'retorno_almuerzo', '2026-07-22T14:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000fe', 'salida_final',     '2026-07-22T18:00:00-05:00');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000a1' and fecha='2026-07-22'),
          8.00::numeric, 'JA · día normal: 9 h de presencia menos 1 h de refrigerio = 8 h pagadas');
select is((select tiene_salida_no_retornada from jornadas where persona_id='00000000-0000-0000-0000-0000000000a1' and fecha='2026-07-22'),
          false, 'JA · día normal: no queda ninguna pausa abierta');
select is((select estado::text from jornadas where persona_id='00000000-0000-0000-0000-0000000000a1' and fecha='2026-07-22'),
          'cerrada', 'JA · día normal: el día queda cerrado');

-- ── JB · DEFECTO CONOCIDO: sale al almuerzo y no marca el retorno ────────────
-- Caso real de Estefany (17 jul) y Carlos (25 jul). El contador de ausencia solo
-- suma cuando aparece el retorno, así que sin él la resta no descuenta nada y se
-- paga el tramo entero. Lo real es indeterminado: pudo irse (4 h), pudo volver
-- sin marcar (8 h), o pudo no tomar refrigerio y seguir trabajando (9 h).
-- Se fija en 9.00 para que cualquier cambio del cálculo salte aquí.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000fe', 'entrada',         '2026-07-22T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000fe', 'salida_almuerzo', '2026-07-22T13:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000fe', 'salida_final',    '2026-07-22T18:00:00-05:00');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000a2' and fecha='2026-07-22'),
          9.00::numeric, 'JB · DEFECTO: sin marca de retorno se paga el tramo entero (9 h) en vez de descontar la ausencia');
select is((select tiene_salida_no_retornada from jornadas where persona_id='00000000-0000-0000-0000-0000000000a2' and fecha='2026-07-22'),
          true, 'JB · el sistema SÍ detecta y marca el día: la señal existe');
select is((select estado::text from jornadas where persona_id='00000000-0000-0000-0000-0000000000a2' and fecha='2026-07-22'),
          'cerrada', 'JB · DEFECTO: el estado queda "cerrada", como un día cualquiera — no entra en ninguna lista de pendientes');
select is((select horas_extra_detectadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000a2' and fecha='2026-07-22'),
          1.00::numeric, 'JB · DEFECTO agravado: además le anota 1 h de tiempo adicional sobre unas horas que no trabajó');

-- ── JC · caso Ytamar (25 jul): tipo de marca equivocado + auto-cierre ────────
-- Se fue a casa a las 19:36 pero marcó "salida a almuerzo"; alguien marcó un
-- "regreso" a las 19:53 intentando arreglarlo; el auto-cierre cerró copiando esa
-- misma hora. Presencia 13:18→19:53 = 6 h 35 min, menos 17 min de "almuerzo".
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000fe', 'entrada',          '2026-07-25T13:18:00-05:00', 'terminal',    'normal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000fe', 'salida_almuerzo',  '2026-07-25T19:36:00-05:00', 'terminal',    'normal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000fe', 'retorno_almuerzo', '2026-07-25T19:53:00-05:00', 'terminal',    'normal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000fe', 'salida_final',     '2026-07-25T19:53:00-05:00', 'auto_cierre', 'pendiente_revision');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000a3' and fecha='2026-07-25'),
          6.30::numeric, 'JC · Ytamar: 6 h 35 min de presencia menos 17 min de "almuerzo" = 6.30 h');
select is((select estado::text from jornadas where persona_id='00000000-0000-0000-0000-0000000000a3' and fecha='2026-07-25'),
          'auto_cerrada_pendiente', 'JC · Ytamar: el día queda pendiente de revisión, como debe');
select is((select minutos_salida_temprana from jornadas where persona_id='00000000-0000-0000-0000-0000000000a3' and fecha='2026-07-25'),
          null::int, 'JC · en un auto-cierre NO se mide la salida anticipada: la hora la inventó el sistema, medirla sería acusar con un dato falso');
select is((select horas_extra_detectadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000a3' and fecha='2026-07-25'),
          0.00::numeric, 'JC · en un auto-cierre tampoco se cuenta tiempo adicional, por la misma razón');

-- ── JD · caso Felipe (25 jul): el auto-cierre copia la hora de la entrada ────
-- Marcó su entrada y nada más. El auto-cierre cerró el día con esa misma hora,
-- así que el sistema le cuenta CERO horas de un día que sí trabajó.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000fe', 'entrada',      '2026-07-25T14:35:00-05:00', 'terminal',    'normal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000fe', 'salida_final', '2026-07-25T14:35:00-05:00', 'auto_cierre', 'pendiente_revision');

select is((select horas_trabajadas from jornadas where persona_id='00000000-0000-0000-0000-0000000000a4' and fecha='2026-07-25'),
          0.00::numeric, 'JD · Felipe: el auto-cierre copia la hora de entrada y el día queda en 0 h — se paga de MENOS');
select is((select estado::text from jornadas where persona_id='00000000-0000-0000-0000-0000000000a4' and fecha='2026-07-25'),
          'auto_cerrada_pendiente', 'JD · Felipe: queda pendiente de revisión, que es lo único que evita que se pague así');

-- ── JE · tardanza y salida anticipada, con sus tolerancias ──────────────────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000fe', 'entrada',      '2026-07-22T09:15:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000fe', 'salida_final', '2026-07-22T17:00:00-05:00');

select is((select minutos_tarde from jornadas where persona_id='00000000-0000-0000-0000-0000000000a5' and fecha='2026-07-22'),
          15, 'JE · tardanza: entró 09:15 con hora de entrada 09:00 → 15 minutos, sin tolerancia');
select is((select minutos_salida_temprana from jornadas where persona_id='00000000-0000-0000-0000-0000000000a5' and fecha='2026-07-22'),
          60, 'JE · salida anticipada: se fue a las 17:00 con salida a las 18:00 → 60 minutos');

-- ── JF · salida anticipada DENTRO de la tolerancia de 15 min ────────────────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000000fe', 'entrada',      '2026-07-22T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000000fe', 'salida_final', '2026-07-22T17:50:00-05:00');

select is((select minutos_salida_temprana from jornadas where persona_id='00000000-0000-0000-0000-0000000000a6' and fecha='2026-07-22'),
          0, 'JF · irse 10 minutos antes queda en 0: la tolerancia de 15 min no se marca como incidencia');

-- ── JG · un día sin marcas no deja jornada fantasma ─────────────────────────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-0000000000fe', 'entrada', '2026-07-22T09:00:00-05:00');
delete from marcajes where persona_id = '00000000-0000-0000-0000-0000000000a7';

select is((select count(*) from jornadas where persona_id='00000000-0000-0000-0000-0000000000a7' and fecha='2026-07-22'),
          0::bigint, 'JG · al quedarse el día sin marcas, la jornada se borra: no queda un resumen huérfano');

select * from finish();
rollback;
