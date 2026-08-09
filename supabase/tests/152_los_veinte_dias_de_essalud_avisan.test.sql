-- ============================================================================
-- 152_los_veinte_dias_de_essalud_avisan.test.sql
-- ============================================================================
-- Los primeros 20 días de incapacidad del año los paga el empleador; desde el 21
-- los subsidia EsSalud, y ese reembolso se reclama con el CITT. Hasta la 0197 el
-- sistema no distinguía un descanso corto de uno largo: nadie avisaba, y la plata
-- que EsSalud debe devolver no se reclamaba porque no aparecía en ningún reporte.
--
-- Este archivo fija las tres cosas que hacen que el aviso sirva, y cada una
-- corresponde a una manera distinta de romperlo:
--
--   · que CUENTE bien — días calendario, sumando varios descansos del mismo año;
--   · que NO cuente la maternidad, que tiene subsidio propio desde el primer día
--     y no consume este cupo. Sumarla haría saltar el aviso por una licencia que
--     EsSalud ya está pagando;
--   · que el certificado sea dato de salud: solo admin y líder de DO.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000ce000', 'ZZSUB', 'Lab', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000ce00a', 'AdminSub', 'Lab',
        '00000000-0000-0000-0000-0000000ce000', 'admin', 'h',
        '00000000-0000-0000-0000-0000000ce00b', '2020-01-01');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000ce001', 'Corto',      'Lab',
   '00000000-0000-0000-0000-0000000ce000', 'h', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ce002', 'Largo',      'Lab',
   '00000000-0000-0000-0000-0000000ce000', 'h', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ce003', 'Maternidad', 'Lab',
   '00000000-0000-0000-0000-0000000ce000', 'h', '2020-01-01', 'planilla'),
  ('00000000-0000-0000-0000-0000000ce004', 'CruzaAnio',  'Lab',
   '00000000-0000-0000-0000-0000000ce000', 'h', '2020-01-01', 'planilla');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ce00b', true);

insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por,
                       doc_profesional, doc_colegiatura, doc_fecha) values
  ('00000000-0000-0000-0000-0000000ce001','descanso_medico','2026-03-02','2026-03-06','a',
   '00000000-0000-0000-0000-0000000ce00a','Dra. X','CMP 1','2026-03-02'),
  -- Dos descansos separados que SUMAN 17: el caso que nadie ve mirando uno solo.
  ('00000000-0000-0000-0000-0000000ce002','descanso_medico','2026-02-01','2026-02-08','b',
   '00000000-0000-0000-0000-0000000ce00a','Dra. X','CMP 1','2026-02-01'),
  ('00000000-0000-0000-0000-0000000ce002','descanso_medico','2026-05-01','2026-05-09','c',
   '00000000-0000-0000-0000-0000000ce00a','Dra. X','CMP 1','2026-05-01'),
  ('00000000-0000-0000-0000-0000000ce003','maternidad','2026-03-01','2026-06-06','d',
   '00000000-0000-0000-0000-0000000ce00a','Dra. X','CMP 1','2026-03-01'),
  -- Del 28/12/2025 al 05/01/2026: 4 días caen en 2025 y 5 en 2026.
  ('00000000-0000-0000-0000-0000000ce004','descanso_medico','2025-12-28','2026-01-05','e',
   '00000000-0000-0000-0000-0000000ce00a','Dra. X','CMP 1','2025-12-28');


-- ── Que cuente bien ────────────────────────────────────────────────────────
select is(
  (select dias_calendario from fn_ausencias_subsidio(2026)
    where persona_id = '00000000-0000-0000-0000-0000000ce002'),
  17,
  'SUMA · dos descansos del mismo año se suman: 8 + 9 = 17 días');

select ok(
  (select hay_que_avisar from fn_ausencias_subsidio(2026)
    where persona_id = '00000000-0000-0000-0000-0000000ce002'),
  'AVISA · a los 17 ya avisa, antes de cruzar los 20 — con margen para reunir el CITT');

select is(
  (select dias_para_el_umbral from fn_ausencias_subsidio(2026)
    where persona_id = '00000000-0000-0000-0000-0000000ce002'),
  3,
  'CUÁNTO FALTA · dice 3, para que el aviso sea accionable y no solo alarmante');

-- Días CALENDARIO, no laborables: el 02 al 06 de marzo de 2026 incluye un
-- domingo. Si esto diera 4, alguien lo cambió a días trabajados y el número
-- dejaría de coincidir con el que lleva EsSalud.
select is(
  (select dias_calendario from fn_ausencias_subsidio(2026)
    where persona_id = '00000000-0000-0000-0000-0000000ce001'),
  5,
  'CALENDARIO · cuenta días corridos, domingos incluidos, como el CITT');

select ok(
  not (select hay_que_avisar from fn_ausencias_subsidio(2026)
        where persona_id = '00000000-0000-0000-0000-0000000ce001'),
  'SIN RUIDO · con 5 días no avisa: un aviso que salta siempre se deja de leer');


-- ── Que NO cuente la maternidad ────────────────────────────────────────────
-- 98 días, subsidiados por EsSalud desde el primer día. Si apareciera acá, el
-- aviso saltaría por una licencia que ya está pagada.
select is(
  (select count(*)::int from fn_ausencias_subsidio(2026)
    where persona_id = '00000000-0000-0000-0000-0000000ce003'),
  0,
  'MATERNIDAD · no consume el cupo de los 20: tiene subsidio propio');


-- ── El año calendario, y su borde ──────────────────────────────────────────
select is(
  (select dias_calendario from fn_ausencias_subsidio(2026)
    where persona_id = '00000000-0000-0000-0000-0000000ce004'),
  5,
  'BORDE · un descanso del 28/12 al 05/01 aporta solo sus 5 días de enero a 2026');

select is(
  (select dias_calendario from fn_ausencias_subsidio(2025)
    where persona_id = '00000000-0000-0000-0000-0000000ce004'),
  4,
  'BORDE · y sus 4 días de diciembre a 2025 — el cupo se reinicia con el año');


-- ── Y el certificado es dato de salud ──────────────────────────────────────
-- Las cuatro políticas, porque Storage escribe con INSERT … ON CONFLICT DO
-- UPDATE … RETURNING: faltando una, subir falla con un error que no dice cuál.
select is(
  (select count(*)::int from pg_policies
    where tablename = 'objects' and policyname like 'certificados_%'),
  4,
  'ALMACÉN · las cuatro políticas puestas: sin las cuatro, subir un archivo falla');

select * from finish();
rollback;
