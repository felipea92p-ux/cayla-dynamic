-- ============================================================================
-- 149_a_un_locador_no_se_le_mide_la_hora.test.sql
-- ============================================================================
-- El caso real, del 2026-08-08: revisando por qué a Claudia Solórzano (AQP) le
-- salían tardanzas de más de tres horas, Felipe respondió lo que ningún dato
-- decía — «era RXH, ellos no están sujetos a horarios, solo lo puse como
-- referencia».
--
-- El sistema le estaba midiendo la hora de entrada a alguien que por ley no
-- tiene hora de entrada. Y no es un número inexacto de más: un registro de
-- tardanzas es CONTROL DE JORNADA, el indicio más directo de subordinación que
-- existe. Convierte una locación de servicios en un contrato de trabajo, con
-- CTS, gratificaciones y vacaciones retroactivas — y la prueba la fabricaba el
-- propio sistema de CAYLA.
--
-- POR QUÉ EL ESCENARIO TIENE DOS PERSONAS Y NO UNA
--   Porque lo que hay que demostrar no es «al locador no se le mide»: eso lo
--   cumpliría también una función rota que no midiera a nadie. Las dos llegan
--   EL MISMO DÍA, a LA MISMA HORA, con EL MISMO horario cargado. Lo único que
--   las distingue es el tipo de vínculo, y por eso el resultado distinto solo
--   puede venir de ahí.
--
-- LAS DOS MITADES, que se rompen por separado:
--   · a quien cumple una jornada se le sigue midiendo, exactamente igual;
--   · a quien presta un servicio no se le mide nada, ni entrada ni salida.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000f100', 'ZZLOC', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000f101', 'LocAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000f100', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000f109');
set session_replication_role = origin;

-- Las dos idénticas salvo en una cosa.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo) values
  ('00000000-0000-0000-0000-00000000f102', 'EnPlanilla',    'Laboratorio', '00000000-0000-0000-0000-00000000f100', 'test-hash', 'planilla'),
  ('00000000-0000-0000-0000-00000000f103', 'PorHonorarios', 'Laboratorio', '00000000-0000-0000-0000-00000000f100', 'test-hash', 'rxh');

-- El terminal necesita dueño desde la 0202: `terminal_activo_con_dueno` prohíbe
-- que uno ACTIVO tenga `auth_user_id` nulo, y este montaje se escribió cuando esa
-- regla no existía. El replica_role salta la FK contra auth.users, que en las
-- pruebas no existe; los CHECK no son triggers y siguen aplicando.
set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000000f10e', '00000000-0000-0000-0000-00000000f100',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000000f10f');
set session_replication_role = origin;

-- Mismo horario para las dos: el del locador está cargado «solo como
-- referencia», que es exactamente el caso que motivó la 0191.
insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2026-01-01', '09:00', '18:00', 60, 60, array[1,2,3,4,5,6], 45,
       '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
         "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
         "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb
from unnest(array['00000000-0000-0000-0000-00000000f102'::uuid,
                  '00000000-0000-0000-0000-00000000f103'::uuid]) p;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f109', true);

-- Las dos entran 40 min tarde y se van 30 min antes. El mismo miércoles.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen)
select gen_random_uuid(), p, '00000000-0000-0000-0000-00000000f100', x.t::tipo_marca, x.ts, 'terminal'
from unnest(array['00000000-0000-0000-0000-00000000f102'::uuid,
                  '00000000-0000-0000-0000-00000000f103'::uuid]) p,
     unnest(array['entrada', 'salida_final'],
            array['2026-08-05T09:40:00-05:00'::timestamptz,
                  '2026-08-05T17:30:00-05:00'::timestamptz]) as x(t, ts);

-- ── 1 · A quien cumple una jornada se le sigue midiendo igual ───────────────
select is(
  (select minutos_tarde from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f102' and fecha = '2026-08-05'),
  40,
  'PLANILLA · los 40 minutos de tardanza se miden como siempre');

select is(
  (select minutos_salida_temprana from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f102' and fecha = '2026-08-05'),
  30,
  'PLANILLA · y los 30 de salida anticipada también');

-- ── 2 · A quien presta un servicio, nada ────────────────────────────────────
select is(
  (select minutos_tarde from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f103' and fecha = '2026-08-05'),
  null,
  'LOCADOR · misma hora, mismo horario, y NO se le mide tardanza');

select is(
  (select minutos_salida_temprana from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f103' and fecha = '2026-08-05'),
  null,
  'LOCADOR · tampoco salida anticipada: no tiene jornada que cumplir');

-- ── 3 · Pero sus horas SÍ se calculan ───────────────────────────────────────
-- Es la mitad que se olvida. Un locador no tiene hora de entrada, pero sí presta
-- horas, y de esas horas depende lo que se le paga. Si alguien «arregla» esto
-- dejando de calcular su jornada entera, deja de cobrar.
select cmp_ok(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f103' and fecha = '2026-08-05'),
  '>', 0::numeric,
  'LOCADOR · sus horas trabajadas se calculan igual: de eso depende su pago');

select is(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f103' and fecha = '2026-08-05'),
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000f102' and fecha = '2026-08-05'),
  'LOCADOR · y son exactamente las mismas que las de su compañera');

select * from finish();
rollback;
