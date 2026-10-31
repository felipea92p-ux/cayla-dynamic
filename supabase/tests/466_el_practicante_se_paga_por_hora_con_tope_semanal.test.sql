-- ============================================================================
-- 466_el_practicante_se_paga_por_hora_con_tope_semanal.test.sql
-- ============================================================================
-- Migración 0576. Un practicante se paga por hora sobre el sueldo mínimo —base
-- 30 h el preprofesional, 45 h el egresado— y lo que marque por encima de su tope
-- SEMANAL (30 h / 48 h, de lunes a domingo) no se paga. Las horas de un convenio
-- ya no cambian la base.
--
-- Periodo de laboratorio: lunes 2030-03-04 → domingo 2030-03-31 (28 días, cuatro
-- semanas calendario completas), subvención S/ 1 230.
--   1. preprofesional: 17 h/sem → 697.00 · 30 h/sem exactas → 1 230.00 sin nada
--      sobre el tope · 36 h/sem → 1 230.00 con 24 h sobre el tope;
--   2. el tope es POR SEMANA: 40 h una semana y 20 h las otras tres (100 h, que
--      no pasan las 120 del periodo) → se pagan 90 h: 922.50;
--   3. egresado: 45 h/sem → 1 230.00 · 48 h/sem → 1 312.00 (su tope es 48) ·
--      50 h/sem → 1 312.00 con 8 h sobre el tope;
--   4. un convenio firmado de 17 h no cambia la base: sigue siendo 30;
--   5. la planilla, igual (714.29).
-- ============================================================================
begin;
select plan(13);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000466000', 'ZZ466', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000004660ad', 'Admin',  'Lab466', '00000000-0000-0000-0000-000000466000', 'admin', 'activo', 'x', '00000000-0000-0000-0000-0000004660ff', '2020-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-000000466001', 'Pre17',  'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000466002', 'Pre30',  'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000466003', 'Pre36',  'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000466004', 'PreDesigual', 'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000466005', 'Egr45',  'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-000000466006', 'Egr48',  'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-000000466007', 'Egr50',  'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-000000466008', 'PreConv17', 'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000466009', 'Planilla', 'Lab466', '00000000-0000-0000-0000-000000466000', 'integrante', 'activo', 'x', null, '2029-01-01', 'planilla', null);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', case when nombres = 'Planilla' then 1300 else 1230 end, '2029-01-01'
  from personas where apellidos = 'Lab466' and nombres <> 'Admin';

insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin,
                                 horas_semanales, documento_html, generado_por, fecha_firma, registrado_por)
values ('00000000-0000-0000-0000-000000466008', 'convenio_practicas', 'Practicante', '00000000-0000-0000-0000-000000466000',
        1230, '2030-01-01', '2030-12-31', 17, 'x', '00000000-0000-0000-0000-0000004660ad', '2030-01-01', '00000000-0000-0000-0000-0000004660ad');

-- Horas: cada fila es (persona, días de cada semana desde el lunes, horas por día).
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, date '2030-03-04' + s * 7 + d, h, 'cerrada'
  from (values
    ('00000000-0000-0000-0000-000000466001'::uuid, array[0,1], 8.5),          -- 17 h/sem
    ('00000000-0000-0000-0000-000000466002'::uuid, array[0,1,2,3,4], 6),      -- 30 h/sem
    ('00000000-0000-0000-0000-000000466003'::uuid, array[0,1,2,3], 9),        -- 36 h/sem
    ('00000000-0000-0000-0000-000000466005'::uuid, array[0,1,2,3,4], 9),      -- 45 h/sem
    ('00000000-0000-0000-0000-000000466006'::uuid, array[0,1,2,3,4,5], 8),    -- 48 h/sem
    ('00000000-0000-0000-0000-000000466007'::uuid, array[0,1,2,3,4], 10),     -- 50 h/sem
    ('00000000-0000-0000-0000-000000466008'::uuid, array[0,1], 8.5),          -- 17 h/sem, con convenio de 17 h
    ('00000000-0000-0000-0000-000000466009'::uuid, array[0,1], 12.5)          -- planilla: 25 h/sem = 100 h
  ) v(p, dias, h),
  generate_series(0, 3) s,
  unnest(dias) d;
-- PreDesigual: 40 h la primera semana (4 × 10) y 20 h cada una de las otras tres (2 × 10).
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000466004', f, 10, 'cerrada'
  from unnest(array[date '2030-03-04', date '2030-03-05', date '2030-03-06', date '2030-03-07',
                    date '2030-03-11', date '2030-03-12', date '2030-03-18', date '2030-03-19',
                    date '2030-03-25', date '2030-03-26']) f;
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004660ff', true);

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2030-03-04', '2030-03-31') -> 'filas') x
   where x->>'nombre' = p_nombre || ' Lab466';
$f$;

-- 1 · Preprofesional: base 30, tope 30 por semana
select is((pg_temp.fila('Pre17')->>'pago_base')::numeric, 697.00::numeric, '17 h a la semana → 1 230 × 68 ÷ 120 = 697.00');
select is((pg_temp.fila('Pre30')->>'pago_base')::numeric, 1230.00::numeric, '30 h exactas cada semana → la subvención entera');
select is((pg_temp.fila('Pre30')->>'horas_sobre_tope')::numeric, 0.00::numeric, 'Y quien cumple su jornada no toca el tope');
select is((pg_temp.fila('Pre36')->>'pago_base')::numeric, 1230.00::numeric, '36 h a la semana → se pagan 30 de cada semana');
select is((pg_temp.fila('Pre36')->>'horas_sobre_tope')::numeric, 24.00::numeric, 'Y se informan las 24 h que pasaron el tope');

-- 2 · El tope es por semana, no por periodo
select is((pg_temp.fila('PreDesigual')->>'pago_base')::numeric, 922.50::numeric,
  '40 h una semana y 20 h las otras: se pagan 30 + 20 + 20 + 20 = 90 h, aunque las 100 h no pasen las 120 del periodo');

-- 3 · Egresado: base 45, tope 48
select is((pg_temp.fila('Egr45')->>'pago_base')::numeric, 1230.00::numeric, 'Egresado de 45 h a la semana → la subvención entera');
select is((pg_temp.fila('Egr48')->>'pago_base')::numeric, 1312.00::numeric, 'Egresado de 48 h → su tope es 48: 1 230 × 192 ÷ 180');
select is((pg_temp.fila('Egr50')->>'pago_base')::numeric, 1312.00::numeric, 'Egresado de 50 h → se pagan 48 de cada semana');
select is((pg_temp.fila('Egr50')->>'horas_sobre_tope')::numeric, 8.00::numeric, 'Y se informan las 8 h que pasaron el tope');

-- 4 · El convenio no cambia la base
select is((pg_temp.fila('PreConv17')->>'base_horas_semana')::numeric, 30::numeric, 'Un convenio firmado de 17 h no cambia la base: 30');
select is((pg_temp.fila('PreConv17')->>'pago_base')::numeric, 697.00::numeric, 'Y con 17 h marcadas cobra 697.00, igual que sin convenio');

-- 5 · Planilla
select is((pg_temp.fila('Planilla')->>'pago_base')::numeric, 714.29::numeric, 'Planilla: 1 300 × 100 ÷ (6.5 × 28), igual que siempre');

select * from finish();
rollback;
