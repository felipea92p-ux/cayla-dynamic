-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 305 — Quién trabaja sin horario vigente, y a quién NO hay que acusar (0385)
-- ============================================================================
-- Lo que más se defiende aquí no es a quién encuentra, sino a quién NO señala.
--
-- El 2026-09-06 se midió producción: 16 personas con jornadas sin horario
-- vigente. Dos de ellas —las dos de Central, con 47 y 44 días— lo tienen así A
-- PROPÓSITO: una es locadora de servicios (RxH, no tiene jornada que cumplir) y
-- la otra es personal de dirección (art. 5 del D.S. 007-2002-TR, excluido de la
-- jornada máxima). Sin excluirlas, este aviso nacería señalándolas todos los
-- días por algo correcto — y un aviso que chilla siempre se aprende a ignorar
-- antes de que llegue el caso que sí importa.
--
-- Es exactamente el defecto que la 0384 arregló en la lista de días por
-- revisar. Se escribe la prueba de la exclusión ANTES de que el aviso llegue a
-- producción, en vez de después.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000005fc', 'ZZ385', 'Sede de laboratorio 385', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000005d0', 'Admin385', 'Laboratorio', '00000000-0000-0000-0000-0000000005fc', 'admin', 'test-hash', '00000000-0000-0000-0000-0000000005e0');
set session_replication_role = origin;

-- Cuatro personas que trabajan los mismos días sin horario vigente. Solo dos
-- deben aparecer: las otras dos no llevan horario porque no les toca.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo, personal_direccion) values
  ('00000000-0000-0000-0000-0000000005d1', 'Ahueco',   'Laboratorio', '00000000-0000-0000-0000-0000000005fc', 'test-hash', 'planilla',  false),
  ('00000000-0000-0000-0000-0000000005d2', 'Bnunca',   'Laboratorio', '00000000-0000-0000-0000-0000000005fc', 'test-hash', 'planilla',  false),
  ('00000000-0000-0000-0000-0000000005d3', 'Clocador', 'Laboratorio', '00000000-0000-0000-0000-0000000005fc', 'test-hash', 'rxh',       false),
  ('00000000-0000-0000-0000-0000000005d4', 'Dgerente', 'Laboratorio', '00000000-0000-0000-0000-0000000005fc', 'test-hash', 'planilla',  true);

-- A · tiene horario, pero con un HUECO: el tramo viejo cerró el 20 y el nuevo
--     abre el 25. Los días 21 y 22 quedan al aire.
insert into horarios_asignados (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-0000000005d1', fn_hoy_lima() - 40, fn_hoy_lima() - 20, '09:00', '18:00', '{1,2,3,4,5}'),
       ('00000000-0000-0000-0000-0000000005d1', fn_hoy_lima() - 15, null,               '10:00', '19:00', '{1,2,3,4,5}');

-- Los cuatro tienen jornada en los mismos dos días del hueco.
insert into jornadas (persona_id, fecha, estado, horas_trabajadas) values
  ('00000000-0000-0000-0000-0000000005d1', fn_hoy_lima() - 18, 'cerrada', 8.0),
  ('00000000-0000-0000-0000-0000000005d1', fn_hoy_lima() - 17, 'cerrada', 8.0),
  ('00000000-0000-0000-0000-0000000005d2', fn_hoy_lima() - 18, 'cerrada', 8.0),
  ('00000000-0000-0000-0000-0000000005d2', fn_hoy_lima() - 17, 'cerrada', 8.0),
  ('00000000-0000-0000-0000-0000000005d3', fn_hoy_lima() - 18, 'cerrada', 8.0),
  ('00000000-0000-0000-0000-0000000005d3', fn_hoy_lima() - 17, 'cerrada', 8.0),
  ('00000000-0000-0000-0000-0000000005d4', fn_hoy_lima() - 18, 'cerrada', 8.0),
  ('00000000-0000-0000-0000-0000000005d4', fn_hoy_lima() - 17, 'cerrada', 8.0);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000005e0', true);


-- ── Lo que NO hay que acusar. Va primero porque es lo que más importa ────────

select is((select count(*)::int from fn_personas_sin_horario_vigente(60)
            where persona_id = '00000000-0000-0000-0000-0000000005d3'),
          0,
          'RxH · un locador no tiene jornada que cumplir: no se le señala nunca');

select is((select count(*)::int from fn_personas_sin_horario_vigente(60)
            where persona_id = '00000000-0000-0000-0000-0000000005d4'),
          0,
          'DIRECCIÓN · art. 5 del D.S. 007-2002-TR: excluido de la jornada, no es un descuido');

select is((select count(*)::int from fn_personas_sin_horario_vigente(60) where sede = 'ZZ385'),
          2,
          'SOLO DOS · de cuatro personas con los mismos días al aire, solo dos son un problema');


-- ── Y lo que sí ─────────────────────────────────────────────────────────────

select is((select dias from fn_personas_sin_horario_vigente(60)
            where persona_id = '00000000-0000-0000-0000-0000000005d1'),
          2,
          'HUECO · los dos días entre el tramo que cerró y el que abrió se cuentan');

select is((select nunca_tuvo_horario from fn_personas_sin_horario_vigente(60)
            where persona_id = '00000000-0000-0000-0000-0000000005d1'),
          false,
          'HUECO · y se distingue de quien nunca tuvo: esta persona sí tiene tramos');

select is((select nunca_tuvo_horario from fn_personas_sin_horario_vigente(60)
            where persona_id = '00000000-0000-0000-0000-0000000005d2'),
          true,
          'NUNCA · a quien no se le cargó ninguno se le dice así, porque se arregla distinto');

-- Los días que el tramo SÍ cubre no entran: si entraran, el aviso contaría como
-- hueco toda la vida laboral de la persona.
insert into jornadas (persona_id, fecha, estado, horas_trabajadas)
values ('00000000-0000-0000-0000-0000000005d1', fn_hoy_lima() - 10, 'cerrada', 8.0);

select is((select dias from fn_personas_sin_horario_vigente(60)
            where persona_id = '00000000-0000-0000-0000-0000000005d1'),
          2,
          'CUBIERTO · un día que su horario sí cubre no suma al hueco');

select * from finish();
rollback;
