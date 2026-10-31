-- ============================================================================
-- 463_el_practicante_se_paga_sobre_una_base_de_30_horas.test.sql
-- ============================================================================
-- Migración 0573. La hora de un practicante vale su subvención pactada entre
-- 30 h semanales (o las horas de su convenio FIRMADO, si pactó menos); lo que
-- marca por encima no se paga. Todos los demás cobran igual que antes.
--
-- LO QUE DEFIENDE, en un periodo de laboratorio de 28 días (cuatro semanas):
--   1. base 30: 17 h/sem → 697.00 · 25.5 h/sem → 1 045.50;
--   2. el tope: 36 h/sem → 1 230.00, con 24 h informadas «sobre el tope»;
--   3. el convenio firmado de 17 h con S/ 697: cumplirlo paga 697.00 (no la
--      proporción dos veces); faltar una semana paga 522.75; marcar de más, 697;
--   4. un BORRADOR de convenio no cambia nada: se paga con base 30;
--   5. el egresado (modalidad profesional) cobra la subvención entera con 45 h
--      (desde la 0575 su base es 45 h; la 465 lo prueba en detalle);
--   6. quien entró a mitad de periodo cobra sus horas (desde la 0575, el tope
--      es el del periodo entero);
--   7. la planilla no se mueve ni un céntimo y no informa base de practicante;
--   8. el total de un practicante sigue cuadrando con sus líneas;
--   9. fn_practicante_horas_pactadas no la ejecuta un cliente.
-- Los «antes» de la migración, medidos sin ella sobre este mismo fixture, están
-- en su encabezado.
-- ============================================================================
begin;
select plan(19);

-- Fixture de la prueba 463 (sin pgTAP), para medir antes y después.
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000463000', 'ZZ463', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000004630ad', 'Admin', 'Lab463', '00000000-0000-0000-0000-000000463000', 'admin', 'activo', 'x', '00000000-0000-0000-0000-0000004630ff', '2020-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-00000046300a', 'A17h', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046300b', 'B25h', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046300c', 'C36h', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046300d', 'DConv17', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046300e', 'EConv17Falta', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046300f', 'FConv17Extra', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000463010', 'GBorrador17', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000463011', 'HProfesional', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-000000463012', 'IPlanilla', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2029-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-000000463013', 'JMitad', 'Lab463', '00000000-0000-0000-0000-000000463000', 'integrante', 'activo', 'x', null, '2030-03-15', 'practicante', 'preprofesional');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000046300a', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046300b', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046300c', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046300d', 'colibri',  697, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046300e', 'colibri',  697, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046300f', 'colibri',  697, '2029-01-01'),
  ('00000000-0000-0000-0000-000000463010', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000463011', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000463012', 'colibri', 1300, '2029-01-01'),
  ('00000000-0000-0000-0000-000000463013', 'colibri', 1230, '2030-03-15');

-- Convenios: tres FIRMADOS de 17 h (D, E, F) y un BORRADOR de 17 h (G).
insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin,
                                 horas_semanales, documento_html, generado_por, fecha_firma, registrado_por)
select p, 'convenio_practicas', 'Practicante', '00000000-0000-0000-0000-000000463000', r, '2030-01-01', '2030-12-31',
       17, 'x', '00000000-0000-0000-0000-0000004630ad', f, case when f is null then null else '00000000-0000-0000-0000-0000004630ad'::uuid end
  from (values
    ('00000000-0000-0000-0000-00000046300d'::uuid,  697, date '2030-01-01'),
    ('00000000-0000-0000-0000-00000046300e'::uuid,  697, date '2030-01-01'),
    ('00000000-0000-0000-0000-00000046300f'::uuid,  697, date '2030-01-01'),
    ('00000000-0000-0000-0000-000000463010'::uuid, 1230, null::date)) v(p, r, f);

-- Las horas del periodo de laboratorio 2030-03-01 → 2030-03-28 (28 días, cuatro semanas).
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, date '2030-03-01' + d, h, 'cerrada'
  from (values
    -- A, D, G: 17 h a la semana = 2 días de 8.5 h × 4 semanas = 68 h
    ('00000000-0000-0000-0000-00000046300a'::uuid, array[0,1,7,8,14,15,21,22], 8.5),
    ('00000000-0000-0000-0000-00000046300d'::uuid, array[0,1,7,8,14,15,21,22], 8.5),
    ('00000000-0000-0000-0000-000000463010'::uuid, array[0,1,7,8,14,15,21,22], 8.5),
    -- B: 25.5 h a la semana = 3 días de 8.5 h × 4 = 102 h
    ('00000000-0000-0000-0000-00000046300b'::uuid, array[0,1,2,7,8,9,14,15,16,21,22,23], 8.5),
    -- C: 36 h a la semana = 4 días de 9 h × 4 = 144 h
    ('00000000-0000-0000-0000-00000046300c'::uuid, array[0,1,2,3,7,8,9,10,14,15,16,17,21,22,23,24], 9),
    -- E: faltó una semana entera = 6 días de 8.5 h = 51 h
    ('00000000-0000-0000-0000-00000046300e'::uuid, array[0,1,7,8,14,15], 8.5),
    -- F: marcó de más = 8 días de 10 h = 80 h
    ('00000000-0000-0000-0000-00000046300f'::uuid, array[0,1,7,8,14,15,21,22], 10),
    -- H: profesional, 45 h a la semana = 5 días de 9 h × 4 = 180 h
    ('00000000-0000-0000-0000-000000463011'::uuid, array[0,1,2,3,4,7,8,9,10,11,14,15,16,17,18,21,22,23,24,25], 9),
    -- I: planilla, 100 h = 10 días de 10 h
    ('00000000-0000-0000-0000-000000463012'::uuid, array[0,1,2,7,8,9,14,15,16,21], 10),
    -- J: entró el 15: 7 días de 10 h = 70 h en sus 14 días
    ('00000000-0000-0000-0000-000000463013'::uuid, array[14,15,16,17,21,22,23], 10)
  ) v(p, dias, h),
  unnest(dias) d;
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004630ff', true);

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2030-03-01', '2030-03-28') -> 'filas') x
   where x->>'nombre' = p_nombre || ' Lab463';
$f$;

-- 1 · Base 30
select is((pg_temp.fila('A17h')->>'pago_base')::numeric, 697.00::numeric,
  '17 h a la semana con S/ 1 230 → S/ 697.00 (1 230 × 17 ÷ 30)');
select is((pg_temp.fila('B25h')->>'pago_base')::numeric, 1045.50::numeric,
  '25.5 h a la semana → S/ 1 045.50');
select is((pg_temp.fila('A17h')->>'base_horas_semana')::numeric, 30::numeric,
  'Sin convenio firmado con horas, la base es 30 h');

-- 2 · El tope
-- CAMBIO 0576 · el tope es por semana calendario (lunes a domingo) y el convenio ya no cambia la base;
--   este fixture arranca un viernes, así que sus «semanas» de 7 días no coinciden con las calendario.
select is((pg_temp.fila('C36h')->>'pago_base')::numeric, 1291.50::numeric,
  '36 h por bloque de 7 días: por semana calendario se pagan 126 h (tope 30 en cada semana)');
select is((pg_temp.fila('C36h')->>'horas_sobre_tope')::numeric, 18.00::numeric,
  'Y se informan las 18 h que pasaron el tope semanal');
select is((pg_temp.fila('C36h')->>'horas_mes')::numeric, 144.00::numeric,
  'Las horas marcadas se siguen informando tal cual');

-- 3 · Convenio firmado de 17 h con S/ 697
select is((pg_temp.fila('DConv17')->>'pago_base')::numeric, 394.97::numeric,
  'CAMBIO 0576 · el convenio ya no cambia la base: con S/ 697 cargados se paga 697 × 68 ÷ 120 (por eso la 0576 exige la subvención completa)');
select is((pg_temp.fila('DConv17')->>'base_horas_semana')::numeric, 30::numeric,
  'CAMBIO 0576 · su base es 30 aunque su convenio diga 17 h');
select is((pg_temp.fila('EConv17Falta')->>'pago_base')::numeric, 296.22::numeric,
  'Faltar una semana descuenta en proporción: 697 × 51 ÷ 120');
select is((pg_temp.fila('FConv17Extra')->>'pago_base')::numeric, 464.67::numeric,
  'CAMBIO 0576 · 20 h por semana no pasan el tope de 30: se pagan todas');
select is((pg_temp.fila('FConv17Extra')->>'horas_sobre_tope')::numeric, 0.00::numeric,
  'Y no hay horas sobre el tope');

-- 4 · Un borrador no cuenta
select is((pg_temp.fila('GBorrador17')->>'base_horas_semana')::numeric, 30::numeric,
  'Un convenio SIN FIRMAR no cambia la base');
select is((pg_temp.fila('GBorrador17')->>'pago_base')::numeric, 697.00::numeric,
  'Y se paga con base 30');

-- 5 · El profesional (egresado). CAMBIO 0575: su base pasó a 45 h; con 45 h a la
--     semana sigue cobrando la subvención entera (la 465 prueba la base 45).
select is((pg_temp.fila('HProfesional')->>'pago_base')::numeric, 1230.00::numeric,
  'Un egresado de 45 h a la semana cobra la subvención entera');

-- 6 · A mitad de periodo. CAMBIO 0575: el tope es el del periodo entero (120 h),
--     así que sus 70 h se pagan todas (la 0573 lo cortaba a 60 h: 615.00).
select is((pg_temp.fila('JMitad')->>'pago_base')::numeric, 615.00::numeric,
  'CAMBIO 0576 · quien entró el 15 marcó 40 h en la semana del 18 al 24: se pagan 30 de esa semana');

-- 7 · La planilla no se mueve
select is((pg_temp.fila('IPlanilla')->>'pago_base')::numeric, 714.29::numeric,
  'Planilla: 1 300 × 100 ÷ (6.5 × 28), igual que antes');
select ok(pg_temp.fila('IPlanilla')->'base_horas_semana' = 'null'::jsonb,
  'Y no informa base de practicante');

-- 8 · El total cuadra
select is((pg_temp.fila('C36h')->>'total')::numeric, (pg_temp.fila('C36h')->>'pago_base')::numeric,
  'El total de un practicante sin otros conceptos es su pago, sin restos del tope');

-- 9 · La función auxiliar no la ejecuta un cliente
select ok(not has_function_privilege('authenticated', 'fn_practicante_horas_pactadas(uuid, date, date)', 'execute'),
  'fn_practicante_horas_pactadas no la ejecuta un cliente: solo la planilla');

select * from finish();
rollback;
