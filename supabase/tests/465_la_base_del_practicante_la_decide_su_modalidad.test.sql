-- ============================================================================
-- 465_la_base_del_practicante_la_decide_su_modalidad.test.sql
-- ============================================================================
-- Migración 0575. Para un practicante, la MODALIDAD decide la base: el
-- preprofesional se paga sobre 30 h semanales y el egresado (modalidad
-- `profesional`) sobre 45 h; lo marcado por encima no se paga, con el tope del
-- PERIODO entero. Sin modalidad, o sin vínculo practicante, todo como antes.
--
-- LO QUE DEFIENDE, en un periodo de laboratorio de 28 días con S/ 1 230:
--   1. egresado: 45 h/sem → 1 230.00 · 24.5 h/sem → 669.67 · 48 h/sem → 1 230.00
--      con 12 h sobre el tope (antes de la 0573: 1 216.48 · 662.31 · 1 297.58);
--   2. preprofesional: igual que en la 0573 (17 h/sem → 697.00);
--   3. el tope ya no corta a quien tuvo un solo día activo: 7.45 h → 76.36
--      (la 0573 le pagaba 4.29 h: 43.93), ni a quien entró a mitad (717.50);
--   4. un practicante SIN modalidad cobra exactamente como antes (675.82) y no
--      informa base;
--   5. la planilla no se mueve ni un céntimo (714.29);
--   6. rige DESDE el periodo 2026-10-29 → 2026-11-28: el periodo anterior se
--      sigue pagando con la fórmula de antes.
-- ============================================================================
begin;
select plan(16);

-- Fixture de laboratorio (sin pgTAP), para medir antes y después.
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000465000', 'ZZ465', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000004650ad', 'Admin', 'Lab465', '00000000-0000-0000-0000-000000465000', 'admin', 'activo', 'x', '00000000-0000-0000-0000-0000004650ff', '2020-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-00000046500a', 'A17h', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046500b', 'B25h', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046500c', 'C36h', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046500d', 'DConv17', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046500e', 'EConv17Falta', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-00000046500f', 'FConv17Extra', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000465010', 'GBorrador17', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000465011', 'HProfesional', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-000000465012', 'IPlanilla', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-000000465013', 'JMitad', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2030-03-15', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000465014', 'KEgresado24', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-000000465015', 'LEgresado48', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional'),
  ('00000000-0000-0000-0000-000000465016', 'MUnDia', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000465017', 'NSinModalidad', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', null);
update personas set estado = 'inactivo', fecha_cese = '2030-03-01' where id = '00000000-0000-0000-0000-000000465016';

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000046500a', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046500b', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046500c', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046500d', 'colibri',  697, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046500e', 'colibri',  697, '2029-01-01'),
  ('00000000-0000-0000-0000-00000046500f', 'colibri',  697, '2029-01-01'),
  ('00000000-0000-0000-0000-000000465010', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000465011', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000465012', 'colibri', 1300, '2029-01-01'),
  ('00000000-0000-0000-0000-000000465013', 'colibri', 1230, '2030-03-15'),
  ('00000000-0000-0000-0000-000000465014', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000465015', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000465016', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000465017', 'colibri', 1230, '2029-01-01');

-- Convenios: tres FIRMADOS de 17 h (D, E, F) y un BORRADOR de 17 h (G).
insert into contratos_generados (persona_id, tipo, cargo, sede_id, remuneracion_mensual, fecha_inicio, fecha_fin,
                                 horas_semanales, documento_html, generado_por, fecha_firma, registrado_por)
select p, 'convenio_practicas', 'Practicante', '00000000-0000-0000-0000-000000465000', r, '2030-01-01', '2030-12-31',
       17, 'x', '00000000-0000-0000-0000-0000004650ad', f, case when f is null then null else '00000000-0000-0000-0000-0000004650ad'::uuid end
  from (values
    ('00000000-0000-0000-0000-00000046500d'::uuid,  697, date '2030-01-01'),
    ('00000000-0000-0000-0000-00000046500e'::uuid,  697, date '2030-01-01'),
    ('00000000-0000-0000-0000-00000046500f'::uuid,  697, date '2030-01-01'),
    ('00000000-0000-0000-0000-000000465010'::uuid, 1230, null::date)) v(p, r, f);

-- Las horas del periodo de laboratorio 2030-03-01 → 2030-03-28 (28 días, cuatro semanas).
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, date '2030-03-01' + d, h, 'cerrada'
  from (values
    -- A, D, G: 17 h a la semana = 2 días de 8.5 h × 4 semanas = 68 h
    ('00000000-0000-0000-0000-00000046500a'::uuid, array[0,1,7,8,14,15,21,22], 8.5),
    ('00000000-0000-0000-0000-00000046500d'::uuid, array[0,1,7,8,14,15,21,22], 8.5),
    ('00000000-0000-0000-0000-000000465010'::uuid, array[0,1,7,8,14,15,21,22], 8.5),
    -- B: 25.5 h a la semana = 3 días de 8.5 h × 4 = 102 h
    ('00000000-0000-0000-0000-00000046500b'::uuid, array[0,1,2,7,8,9,14,15,16,21,22,23], 8.5),
    -- C: 36 h a la semana = 4 días de 9 h × 4 = 144 h
    ('00000000-0000-0000-0000-00000046500c'::uuid, array[0,1,2,3,7,8,9,10,14,15,16,17,21,22,23,24], 9),
    -- E: faltó una semana entera = 6 días de 8.5 h = 51 h
    ('00000000-0000-0000-0000-00000046500e'::uuid, array[0,1,7,8,14,15], 8.5),
    -- F: marcó de más = 8 días de 10 h = 80 h
    ('00000000-0000-0000-0000-00000046500f'::uuid, array[0,1,7,8,14,15,21,22], 10),
    -- H: profesional, 45 h a la semana = 5 días de 9 h × 4 = 180 h
    ('00000000-0000-0000-0000-000000465011'::uuid, array[0,1,2,3,4,7,8,9,10,11,14,15,16,17,18,21,22,23,24,25], 9),
    -- I: planilla, 100 h = 10 días de 10 h
    ('00000000-0000-0000-0000-000000465012'::uuid, array[0,1,2,7,8,9,14,15,16,21], 10),
    -- J: entró el 15: 7 días de 10 h = 70 h en sus 14 días
    ('00000000-0000-0000-0000-000000465013'::uuid, array[14,15,16,17,21,22,23], 10),
    -- K: egresado, 24.5 h a la semana = 14 días de 7 h = 98 h
    ('00000000-0000-0000-0000-000000465014'::uuid, array[0,1,2,3,7,8,9,14,15,16,17,21,22,23], 7),
    -- L: egresado, 48 h a la semana = 6 días de 8 h × 4 = 192 h
    ('00000000-0000-0000-0000-000000465015'::uuid, array[0,1,2,3,4,5,7,8,9,10,11,12,14,15,16,17,18,19,21,22,23,24,25,26], 8),
    -- M: un solo día activo (cesó el 1), 7.45 h ese día
    ('00000000-0000-0000-0000-000000465016'::uuid, array[0], 7.45),
    -- N: practicante sin modalidad, 100 h
    ('00000000-0000-0000-0000-000000465017'::uuid, array[0,1,2,7,8,9,14,15,16,21], 10)
  ) v(p, dias, h),
  unnest(dias) d;
set session_replication_role = origin;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004650ff', true);


-- P: preprofesional con horas en el periodo ANTERIOR a la regla y en el primero de ella.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-000000465019', 'PFrontera', 'Lab465', '00000000-0000-0000-0000-000000465000', 'integrante', 'activo', 'x', null, '2026-01-01', 'practicante', 'preprofesional');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000465019', 'colibri', 1230, '2026-01-01');
-- 40 h en cada periodo: 4 días de 10 h.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000465019', d, 10, 'cerrada'
  from unnest(array[date '2026-10-05', date '2026-10-06', date '2026-10-12', date '2026-10-13',
                    date '2026-11-02', date '2026-11-03', date '2026-11-09', date '2026-11-10']) d;
set session_replication_role = origin;

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2030-03-01', '2030-03-28') -> 'filas') x
   where x->>'nombre' = p_nombre || ' Lab465';
$f$;

-- 1 · Egresado: base 45
select is((pg_temp.fila('HProfesional')->>'pago_base')::numeric, 1230.00::numeric,
  'Egresado de 45 h a la semana → la subvención entera');
select is((pg_temp.fila('HProfesional')->>'base_horas_semana')::numeric, 45::numeric,
  'Su base es 45 h, no 30');
select is((pg_temp.fila('KEgresado24')->>'pago_base')::numeric, 669.67::numeric,
  'Egresado de 24.5 h a la semana → 1 230 × 98 ÷ 180');
-- CAMBIO 0576 · el tope es por semana calendario (lunes a domingo) y el convenio ya no cambia la base;
--   este fixture arranca un viernes, así que sus «semanas» de 7 días no coinciden con las calendario.
select is((pg_temp.fila('LEgresado48')->>'pago_base')::numeric, 1312.00::numeric,
  'CAMBIO 0576 · egresado de 48 h a la semana: su tope es 48, se pagan todas (1 230 × 192 ÷ 180)');
select is((pg_temp.fila('LEgresado48')->>'horas_sobre_tope')::numeric, 0.00::numeric,
  'Y no hay horas sobre el tope de 48');

-- 2 · Preprofesional: sin cambio respecto de la 0573
select is((pg_temp.fila('A17h')->>'pago_base')::numeric, 697.00::numeric,
  'Preprofesional de 17 h a la semana → 697.00, como en la 0573');
select is((pg_temp.fila('A17h')->>'base_horas_semana')::numeric, 30::numeric,
  'Su base sigue siendo 30 h');

-- 3 · El tope del periodo entero
select is((pg_temp.fila('MUnDia')->>'horas_pagadas')::numeric, 7.45::numeric,
  'Un solo día activo con 7.45 h: se pagan las 7.45 h (la 0573 lo cortaba a 4.29)');
select is((pg_temp.fila('MUnDia')->>'pago_base')::numeric, 76.36::numeric,
  'Y vale 7.45 × 1 230 ÷ 120');
select is((pg_temp.fila('JMitad')->>'pago_base')::numeric, 615.00::numeric,
  'CAMBIO 0576 · quien entró a mitad: la semana con 40 h se topa en 30');

-- 4 · Sin modalidad: como antes
select is((pg_temp.fila('NSinModalidad')->>'pago_base')::numeric, 675.82::numeric,
  'Un practicante sin modalidad cobra exactamente como antes: 1 230 × 100 ÷ (6.5 × 28)');
select ok(pg_temp.fila('NSinModalidad')->'base_horas_semana' = 'null'::jsonb,
  'Y no informa base propia');

-- 5 · La planilla no se mueve (y no puede tener modalidad: personas_practicante_modalidad_coherente)
select is((pg_temp.fila('IPlanilla')->>'pago_base')::numeric, 714.29::numeric,
  'Planilla: 1 300 × 100 ÷ (6.5 × 28), igual que siempre');
select ok(pg_temp.fila('IPlanilla')->'base_horas_semana' = 'null'::jsonb,
  'Y no informa base de practicante');

-- 6 · Desde este periodo
select is((select (x->>'pago_base')::numeric
             from jsonb_array_elements(fn_planilla_calcular('2026-09-29', '2026-10-28') -> 'filas') x
            where x->>'nombre' = 'PFrontera Lab465'),
          252.31::numeric,
  'El periodo ANTERIOR (29-sep → 28-oct) se paga como antes: 1 230 × 40 ÷ (6.5 × 30)');
select is((select (x->>'pago_base')::numeric
             from jsonb_array_elements(fn_planilla_calcular('2026-10-29', '2026-11-28') -> 'filas') x
            where x->>'nombre' = 'PFrontera Lab465'),
          370.32::numeric,
  'Desde el periodo 29-oct → 28-nov, base 30: 1 230 × 40 ÷ (30 × 31 ÷ 7)');

select * from finish();
rollback;
