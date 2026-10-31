-- ============================================================================
-- 468_el_sueldo_se_cambia_por_grupo_y_avisa_a_quien_toca.test.sql
-- ============================================================================
-- Migración 0578. El sueldo de un grupo (preprofesionales, egresados, honorarios)
-- se cambia de una vez para las personas marcadas, por la puerta de siempre; y el
-- comunicado queda en BORRADOR solo para ellas.
--   1. la vista previa lista al grupo y marca quién tiene el sueldo por defecto;
--   2. solo la dirección cambia; un practicante no baja de la RMV; la persona
--      tiene que ser del grupo; un periodo pagado no se reescribe;
--   3. cambia a las marcadas (y no a las demás) desde la fecha;
--   4. el comunicado nace en borrador: nadie lo ve hasta publicarlo, y publicado
--      lo ve solo quien está en su audiencia.
-- ============================================================================
begin;
select plan(14);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000468000', 'ZZ468', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000004680ff', 'admin-468@local'),
  ('00000000-0000-0000-0000-0000004680fe', 'do-468@local'),
  ('00000000-0000-0000-0000-0000004680f1', 'pre1-468@local'),
  ('00000000-0000-0000-0000-0000004680f3', 'egr-468@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-0000004680ad', 'Admin', 'Lab468', '00000000-0000-0000-0000-000000468000', 'admin', 'activo', 'x', '00000000-0000-0000-0000-0000004680ff', '2020-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-0000004680d0', 'Do', 'Lab468', '00000000-0000-0000-0000-000000468000', 'lider_do', 'activo', 'x', '00000000-0000-0000-0000-0000004680fe', '2020-01-01', 'planilla', null),
  ('00000000-0000-0000-0000-000000468001', 'Pre1', 'Lab468', '00000000-0000-0000-0000-000000468000', 'integrante', 'activo', 'x', '00000000-0000-0000-0000-0000004680f1', '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000468002', 'Pre2', 'Lab468', '00000000-0000-0000-0000-000000468000', 'integrante', 'activo', 'x', null, '2029-01-01', 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000468003', 'Egr1', 'Lab468', '00000000-0000-0000-0000-000000468000', 'integrante', 'activo', 'x', '00000000-0000-0000-0000-0000004680f3', '2029-01-01', 'practicante', 'profesional');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-000000468001', 'colibri', 1230, '2029-01-01'),
  ('00000000-0000-0000-0000-000000468002', 'colibri', 1400, '2029-01-01'),
  ('00000000-0000-0000-0000-000000468003', 'colibri', 1230, '2029-01-01');
set session_replication_role = origin;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000468a01', '2030-01-01', '2030-01-28', 'abierto');
insert into periodo_grupo_pago (periodo_id, grupo, estado) values
  ('00000000-0000-0000-0000-000000468a01', 'practicante', 'pagado');

-- 1 · Vista previa (como la dirección)
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004680ff', true);
set role authenticated;
select is((select array_agg(nombre || ':' || es_por_defecto order by nombre)
             from fn_sueldo_grupo_vista_previa('practicante_preprofesional') where nombre like 'Lab468%'),
          array['Lab468, Pre1:true', 'Lab468, Pre2:false'],
          'La vista previa lista a los preprofesionales y marca quién tiene el sueldo por defecto');

-- 2 · Las barreras
select throws_ok($$ select fn_sueldo_grupo_cambiar('practicante_preprofesional', array['00000000-0000-0000-0000-000000468001'::uuid], 1000, date '2030-02-01', 'Prueba') $$,
  'P0001', null, 'Un practicante no baja de la RMV');
select throws_ok($$ select fn_sueldo_grupo_cambiar('practicante_preprofesional', array['00000000-0000-0000-0000-000000468003'::uuid], 1300, date '2030-02-01', 'Prueba') $$,
  'Una de las personas marcadas no pertenece a este grupo.', 'Una persona de otro grupo no se cuela');
select throws_ok($$ select fn_sueldo_grupo_cambiar('practicante_preprofesional', array['00000000-0000-0000-0000-000000468001'::uuid], 1300, date '2030-01-15', 'Prueba') $$,
  'P0001', null, 'Una fecha dentro de un periodo pagado se rechaza');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004680fe', true);
set role authenticated;
select throws_ok($$ select fn_sueldo_grupo_cambiar('practicante_preprofesional', array['00000000-0000-0000-0000-000000468001'::uuid], 1300, date '2030-02-01', 'Prueba') $$,
  'Solo la dirección puede cambiar el sueldo de un grupo.', 'DO no cambia sueldos por grupo: solo la dirección');
reset role;

-- 3 · El cambio
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004680ff', true);
set role authenticated;
select is((fn_sueldo_grupo_cambiar('practicante_preprofesional', array['00000000-0000-0000-0000-000000468001'::uuid], 1300, date '2030-02-01', 'Ajuste de prueba') ->> 'cambiados')::int,
          1, 'Cambia a la persona marcada');
reset role;
select is((select salario_mensual_soles from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000468001' and vigente_hasta is null),
          1300::numeric, 'La marcada tiene el sueldo nuevo');
select is((select vigente_desde from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000468001' and vigente_hasta is null),
          date '2030-02-01', 'Desde la fecha elegida');
select is((select salario_mensual_soles from asignaciones_salario where persona_id = '00000000-0000-0000-0000-000000468002' and vigente_hasta is null),
          1400::numeric, 'La no marcada no cambia');

-- 4 · El comunicado
select is((select count(*)::int from anuncios where estado = 'borrador' and audiencia -> 'personas' ? '00000000-0000-0000-0000-000000468001'),
          1, 'Queda un comunicado en borrador para la marcada');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004680f1', true);
set role authenticated;
select is((select count(*)::int from fn_anuncios_vigentes(false) where audiencia_descripcion like 'Practicantes preprofesionales%'),
          0, 'Mientras es borrador, ni la propia persona lo ve');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004680ff', true);
set role authenticated;
select lives_ok($$ select fn_anuncio_publicar_borrador((select id from anuncios where estado = 'borrador' and audiencia -> 'personas' ? '00000000-0000-0000-0000-000000468001')) $$,
  'La dirección lo publica');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004680f1', true);
set role authenticated;
select is((select count(*)::int from fn_anuncios_vigentes(false) where audiencia_descripcion like 'Practicantes preprofesionales%'),
          1, 'Publicado, lo ve la persona a la que va');
reset role;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000004680f3', true);
set role authenticated;
select is((select count(*)::int from fn_anuncios_vigentes(false) where audiencia_descripcion like 'Practicantes preprofesionales%'),
          0, 'Y no lo ve quien no está en su audiencia');
reset role;

select * from finish();
rollback;
