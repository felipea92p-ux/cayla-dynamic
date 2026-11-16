-- ============================================================================
-- 505_lo_que_pasa_del_maximo_legal_se_puede_pagar_al_practicante.test.sql
-- ============================================================================
-- Migración 0620. El tope semanal del practicante puede subir hasta 168 h (las
-- de una semana), y con eso se paga todo lo marcado, como antes del 29-oct-2026:
--   1. el catálogo deja los dos topes ir hasta 168 y los dos de la base siguen
--      con su máximo legal (30 y 48); 169 se rechaza;
--   2. con los valores de partida, nada cambia: preprofesional 36 h/sem →
--      1 230.00 (tope 30) y egresado 50 h/sem → 1 312.00 (tope 48);
--   3. con el tope en 168 desde el segundo periodo, ese periodo paga todo lo
--      marcado: 1 230 × 144 ÷ 120 = 1 476.00 y 1 230 × 200 ÷ 180 = 1 366.67,
--      sin horas sobre el tope;
--   4. el periodo anterior al cambio sigue con su tope: 1 230.00 y 1 312.00.
-- ============================================================================
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000505000', 'ZZ505', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000005050ff', 'admin-505@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000005050ad', 'Admin', 'Lab505', '00000000-0000-0000-0000-000000505000', 'admin', 'activo', 'x', '00000000-0000-0000-0000-0000005050ff', '2020-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-000000505001', 'Pre36', 'Lab505', '00000000-0000-0000-0000-000000505000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000505002', 'Egr50', 'Lab505', '00000000-0000-0000-0000-000000505000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'profesional');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000505001', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000505002', 'colibri', 1230, '2029-01-01');
-- Dos periodos de cuatro semanas, de lunes a domingo.
-- Pre36: 6 h de lunes a sábado = 36 h por semana.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000505001', date '2030-01-07' + s * 7 + d, 6, 'cerrada'
  from generate_series(0, 7) s, generate_series(0, 5) d;
-- Egr50: 10 h de lunes a viernes = 50 h por semana.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000505002', date '2030-01-07' + s * 7 + d, 10, 'cerrada'
  from generate_series(0, 7) s, generate_series(0, 4) d;
set session_replication_role = origin;
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000505a01', '2030-01-07', '2030-02-03', 'abierto'),
  ('00000000-0000-0000-0000-000000505a02', '2030-02-04', '2030-03-03', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000005050ff', true);

create or replace function pg_temp.fila(p_ini date, p_fin date, p_nombre text) returns jsonb
language sql as $f$
  select x
    from jsonb_array_elements(fn_planilla_calcular(p_ini, p_fin) -> 'filas') x
   where x->>'nombre' = p_nombre;
$f$;
create or replace function pg_temp.pago(p_ini date, p_fin date, p_nombre text) returns numeric
language sql as $f$ select (pg_temp.fila(p_ini, p_fin, p_nombre)->>'pago_base')::numeric $f$;

-- 1 · El catálogo
select is((select array_agg(valor_max order by parametro) from parametros_catalogo
            where parametro in ('practicante_tope_egresado', 'practicante_tope_preprofesional')),
          array[168, 168]::numeric[], 'Los dos topes pueden ir hasta 168 h, las horas de una semana');
select is((select array_agg(valor_max order by parametro) from parametros_catalogo
            where parametro in ('practicante_base_egresado', 'practicante_base_preprofesional')),
          array[48, 30]::numeric[], 'Las dos bases siguen con su máximo legal (48 y 30)');
set role authenticated;
select throws_ok($$ select fn_parametro_cambiar_vigencia('practicante_tope_preprofesional', 169, date '2030-02-04', 'Prueba: más que una semana') $$,
  'P0001', null, 'Un tope de 169 h se rechaza: ninguna semana las tiene');
reset role;

-- 2 · Con los valores de partida, nada cambia
select is(pg_temp.pago('2030-02-04', '2030-03-03', 'Pre36 Lab505'), 1230.00::numeric,
  'Con el tope de partida (30), 36 h/sem pagan 30: 1 230.00');
select is(pg_temp.pago('2030-02-04', '2030-03-03', 'Egr50 Lab505'), 1312.00::numeric,
  'Con el tope de partida (48), 50 h/sem pagan 48: 1 312.00');

-- 3 · Tope en 168 desde el segundo periodo
set role authenticated;
select lives_ok($$ select fn_parametro_cambiar_vigencia('practicante_tope_preprofesional', 168, date '2030-02-04', 'Prueba: se paga lo que pasa del máximo legal') $$,
  'La dirección abre el tope del preprofesional desde el 2030-02-04');
select fn_parametro_cambiar_vigencia('practicante_tope_egresado', 168, date '2030-02-04', 'Prueba: se paga lo que pasa del máximo legal');
reset role;
select is(pg_temp.pago('2030-02-04', '2030-03-03', 'Pre36 Lab505'), 1476.00::numeric,
  'Preprofesional, 36 h/sem sin tope: 1 230 × 144 ÷ 120 = 1 476.00');
select is(pg_temp.pago('2030-02-04', '2030-03-03', 'Egr50 Lab505'), 1366.67::numeric,
  'Egresado, 50 h/sem sin tope: 1 230 × 200 ÷ 180 = 1 366.67');
select is(array[(pg_temp.fila('2030-02-04', '2030-03-03', 'Pre36 Lab505')->>'horas_sobre_tope')::numeric,
                (pg_temp.fila('2030-02-04', '2030-03-03', 'Egr50 Lab505')->>'horas_sobre_tope')::numeric],
          array[0, 0]::numeric[], 'Sin tope no queda ninguna hora sobre el tope');

-- 4 · El periodo anterior al cambio sigue con su tope
select is(pg_temp.pago('2030-01-07', '2030-02-03', 'Pre36 Lab505'), 1230.00::numeric,
  'El periodo anterior sigue con tope 30: 1 230.00');
select is(pg_temp.pago('2030-01-07', '2030-02-03', 'Egr50 Lab505'), 1312.00::numeric,
  'El periodo anterior sigue con tope 48: 1 312.00');

select * from finish();
rollback;
