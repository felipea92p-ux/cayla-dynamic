-- ============================================================================
-- 147_una_tardanza_de_tres_horas_no_desaparece.test.sql
-- ============================================================================
-- El defecto que cierra, vivo desde el 2026-07-11 (migración 0013):
--
--   `fn_recalcular_jornada` ponía `minutos_tarde := null` cuando pasaba de 180,
--   con el comentario «implausible: turno distinto, no medible». Y los tres
--   consumidores filtran `is not null`, así que leían ese null como «no hubo
--   tardanza». Medido antes de la 0189 sobre este mismo escenario: quien llegó
--   3 h 45 min tarde NO aparecía en Disciplina en absoluto — ni una fila.
--
-- LAS DOS MITADES QUE DEFIENDE, Y QUE SE CONTRADICEN SI UNA SE ROMPE
--
--   · El número REAL se guarda siempre. Destruirlo es la causa raíz.
--   · Y ese número NO sanciona solo. Una tardanza de más de tres horas casi
--     siempre significa que el turno cargado era otro; imputar sobre eso es el
--     falso positivo que este proyecto define como su peor error.
--
--   Quien «arregle» esto haciendo que los 225 minutos cuenten para el umbral
--   legal rompe la segunda mitad, y la prueba de abajo se cae.
--
-- POR QUÉ EL CASO USA 225 MINUTOS Y NO 200
--   Para que el número sea reconocible al leer un fallo: 225 = 3 h 45 min, la
--   hora de entrada 12:45 contra un horario de 09:00. Si algún día esta prueba
--   se cae, el número dice solo de dónde salió.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000e100', 'ZZTAR', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000e101', 'TarAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000e100', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000e109');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000e102', 'TarPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000e100', 'test-hash', 'planilla');

-- El terminal necesita dueño desde la 0202: `terminal_activo_con_dueno` prohíbe
-- que uno ACTIVO tenga `auth_user_id` nulo, y este montaje se escribió cuando esa
-- regla no existía. El replica_role salta la FK contra auth.users, que en las
-- pruebas no existe; los CHECK no son triggers y siguen aplicando.
set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-00000000e10e', '00000000-0000-0000-0000-00000000e100',
        'Mac mini de laboratorio', true, '00000000-0000-0000-0000-00000000e10f');
set session_replication_role = origin;

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
values ('00000000-0000-0000-0000-00000000e102', '2026-01-01', '09:00', '18:00', 60, 60,
        array[1,2,3,4,5,6], 45,
        '{"1":{"e":"09:00","s":"18:00","r":60},"2":{"e":"09:00","s":"18:00","r":60},
          "3":{"e":"09:00","s":"18:00","r":60},"4":{"e":"09:00","s":"18:00","r":60},
          "5":{"e":"09:00","s":"18:00","r":60},"6":{"e":"09:00","s":"18:00","r":60}}'::jsonb);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e109', true);

-- ── El escenario: un día tardísimo y otro tarde normal ──────────────────────
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen) values
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000e102', '00000000-0000-0000-0000-00000000e100', 'entrada',      '2026-08-04T12:45:00-05:00', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000e102', '00000000-0000-0000-0000-00000000e100', 'salida_final', '2026-08-04T18:00:00-05:00', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000e102', '00000000-0000-0000-0000-00000000e100', 'entrada',      '2026-08-05T09:30:00-05:00', 'terminal'),
  (gen_random_uuid(), '00000000-0000-0000-0000-00000000e102', '00000000-0000-0000-0000-00000000e100', 'salida_final', '2026-08-05T18:00:00-05:00', 'terminal');

-- ── 1 · El número real se guarda, no se destruye ────────────────────────────
select is(
  (select minutos_tarde from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000e102' and fecha = '2026-08-04'),
  225,
  'SE GUARDA · 3 h 45 min tarde quedan como 225 minutos, no como NULL');

select is(
  (select minutos_tarde from jornadas
    where persona_id = '00000000-0000-0000-0000-00000000e102' and fecha = '2026-08-05'),
  30,
  'DE CONTROL · la tardanza normal sigue midiéndose igual que siempre');

-- ── 2 · El umbral vive en un solo sitio y dice lo que tiene que decir ───────
select is(fn_tardanza_es_medible(30),   true,  'MEDIBLE · 30 minutos sirven para decidir');
select is(fn_tardanza_es_medible(180),  true,  'MEDIBLE · el borde exacto, 180, todavía cuenta');
select is(fn_tardanza_es_medible(225),  false, 'DUDOSA  · 225 minutos no sirven para sancionar');
select is(fn_tardanza_es_medible(null), false, 'SIN DATO · un día sin horario tampoco sirve');

-- ── 3 · La persona aparece, y con las dos cifras separadas ──────────────────
-- Antes de la 0189 esta consulta devolvía CERO filas: con una sola tardanza
-- medible no llegaba al mínimo de dos, y la de tres horas no existía para nadie.
select is(
  (select tardanzas_mes from fn_tardanzas_resumen('2026-08-31')
    where persona_id = '00000000-0000-0000-0000-00000000e102'),
  1,
  'NO SANCIONA · el día dudoso NO suma al umbral del D.S. 003-97-TR');

select is(
  (select sin_medir from fn_tardanzas_resumen('2026-08-31')
    where persona_id = '00000000-0000-0000-0000-00000000e102'),
  1,
  'PERO AVISA · sale contado aparte, para que una persona lo mire');

select * from finish();
rollback;
