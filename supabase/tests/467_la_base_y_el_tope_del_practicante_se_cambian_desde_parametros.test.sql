-- ============================================================================
-- 467_la_base_y_el_tope_del_practicante_se_cambian_desde_parametros.test.sql
-- ============================================================================
-- Migración 0577. La base y el tope del practicante salen de Parámetros, con la
-- fecha de vigencia de cada cambio:
--   1. los cuatro parámetros existen, son de plata, solo los cambia la dirección
--      y valen 30 · 30 · 45 · 48;
--   2. cambiar la base del preprofesional a 25 h desde el 2030-02-04 cambia el
--      pago de ese periodo (17 h/sem → 1 230 × 68 ÷ 100 = 836.40) y NO el del
--      periodo anterior (sigue en base 30: 697.00);
--   3. bajar el tope a 15 h corta las semanas de 17 h a 15.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000467000', 'ZZ467', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000004670ff', 'admin-467@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000004670ad', 'Admin', 'Lab467', '00000000-0000-0000-0000-000000467000', 'admin', 'activo', 'x', '00000000-0000-0000-0000-0000004670ff', '2020-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-000000467001', 'Pre17', 'Lab467', '00000000-0000-0000-0000-000000467000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000467001', 'colibri', 1230, '2029-01-01');
-- 17 h por semana (lunes y martes, 8.5 h) en dos periodos de cuatro semanas.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000467001', date '2030-01-07' + s * 7 + d, 8.5, 'cerrada'
  from generate_series(0, 7) s, unnest(array[0, 1]) d;
set session_replication_role = origin;
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000467a01', '2030-01-07', '2030-02-03', 'abierto'),
  ('00000000-0000-0000-0000-000000467a02', '2030-02-04', '2030-03-03', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004670ff', true);

create or replace function pg_temp.pago(p_ini date, p_fin date) returns numeric
language sql as $f$
  select (x->>'pago_base')::numeric
    from jsonb_array_elements(fn_planilla_calcular(p_ini, p_fin) -> 'filas') x
   where x->>'nombre' = 'Pre17 Lab467';
$f$;

-- 1 · Los parámetros
select is((select count(*)::int from parametros_catalogo
            where parametro in ('practicante_base_preprofesional', 'practicante_tope_preprofesional',
                                'practicante_base_egresado', 'practicante_tope_egresado')
              and clase = 'plata' and almacen = 'vigencias' and roles_cambia = array['admin']),
          4, 'Los cuatro parámetros existen, de plata, con fechas y solo para la dirección');
select is(array[fn_parametro_valor_en('practicante_base_preprofesional', date '2030-02-04'),
                fn_parametro_valor_en('practicante_tope_preprofesional', date '2030-02-04'),
                fn_parametro_valor_en('practicante_base_egresado', date '2030-02-04'),
                fn_parametro_valor_en('practicante_tope_egresado', date '2030-02-04')],
          array[30, 30, 45, 48]::numeric[], 'Sus valores de partida son 30 · 30 · 45 · 48');
select is(pg_temp.pago('2030-02-04', '2030-03-03'), 697.00::numeric, 'Con los valores de partida, 17 h/sem → 697.00 (igual que la 0576)');

-- 2 · Cambiar la base desde una fecha
set role authenticated;
select lives_ok($$ select fn_parametro_cambiar_vigencia('practicante_base_preprofesional', 25, date '2030-02-04', 'Prueba: base 25 desde febrero') $$,
  'La dirección cambia la base del preprofesional a 25 desde el 2030-02-04');
reset role;
select is(pg_temp.pago('2030-02-04', '2030-03-03'), 836.40::numeric, 'Desde esa fecha: 1 230 × 68 ÷ (25 × 4) = 836.40');
select is(pg_temp.pago('2030-01-07', '2030-02-03'), 697.00::numeric, 'El periodo anterior sigue en base 30: 697.00');

-- 3 · Bajar el tope
set role authenticated;
select fn_parametro_cambiar_vigencia('practicante_tope_preprofesional', 15, date '2030-02-04', 'Prueba: tope 15');
reset role;
select is(pg_temp.pago('2030-02-04', '2030-03-03'), 738.00::numeric, 'Con tope 15, cada semana de 17 h paga 15: 1 230 × 60 ÷ 100 = 738.00');

select * from finish();
rollback;
