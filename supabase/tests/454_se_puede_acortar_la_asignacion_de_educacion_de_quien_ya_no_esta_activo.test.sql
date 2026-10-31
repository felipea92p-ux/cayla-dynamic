-- ============================================================================
-- 454_se_puede_acortar_la_asignacion_de_educacion_de_quien_ya_no_esta_activo.test.sql
-- ============================================================================
-- La regla de la 0564: a una persona inactiva no se le abre dinero nuevo, pero
-- su asignación SÍ se puede acortar. Hasta la 0523 corregir cualquier cosa de
-- alguien que cesó daba «Esa persona no existe o no está activa.» (2026-10-30,
-- «hasta» 29/10 que debía ser 28/10). Fechas de 2028, lejos de datos reales.
-- Todo en begin/rollback.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000ed560', 'ZZE56', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000ed561', 'AdminEdu56', 'Laboratorio',
        '00000000-0000-0000-0000-0000000ed560', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000ed569', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000ed562', 'EduActiva56', 'Laboratorio', '00000000-0000-0000-0000-0000000ed560', 'test-hash', '2025-01-02'),
  ('00000000-0000-0000-0000-0000000ed563', 'EduCesada56', 'Laboratorio', '00000000-0000-0000-0000-0000000ed560', 'test-hash', '2025-01-02');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-0000000ed562', 'aurora', 1500, '2025-01-02'),
  ('00000000-0000-0000-0000-0000000ed563', 'aurora', 1500, '2025-01-02');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ed569', true);

-- Ella tiene su asignación estando activa, y después cesa (con fecha POSTERIOR al
-- fin de la vigencia, para que el cese no la recorte por su cuenta).
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000ed563'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2028-03-01'::date, '2028-06-30'::date,
    null, 'educacion/x/y.pdf', null, null, null) $$,
  'PARTIDA · se registra mientras está activa');

update personas set estado = 'inactivo', fecha_cese = '2028-12-31'
 where id = '00000000-0000-0000-0000-0000000ed563';

select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000ed563'::uuid, 'Otra asignación', 200::numeric,
    'trabajador', '2028-07-01'::date, '2028-09-30'::date,
    null, null, null, null, null) $$,
  '%no existe o no está activa%',
  'ALTA · a una persona inactiva no se le registra una asignación nueva');

select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000ed563'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2028-03-01'::date, '2028-08-31'::date, null, null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000ed563'),
    'intento alargar') $$,
  '%solo se puede acortar%',
  'ALARGAR · a una persona inactiva no se le extiende el hasta');

select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000ed563'::uuid, 'Instituto de laboratorio', 300::numeric,
    'trabajador', '2028-03-01'::date, '2028-06-30'::date, null, null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000ed563'),
    'intento subir el costo') $$,
  '%solo se puede acortar%',
  'COSTO · a una persona inactiva no se le cambia el costo');

select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000ed563'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2028-03-01'::date, '2028-06-29'::date, null, null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000ed563'),
    'el último día era el 29, no el 30') $$,
  'ACORTAR · una persona inactiva sí puede acortar el hasta');

select is((select max(vigente_hasta) from asignaciones_educacion
            where persona_id = '00000000-0000-0000-0000-0000000ed563'),
  '2028-06-29'::date, 'ACORTAR · el hasta quedó en la fecha nueva');

select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-0000000ed562'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2028-03-01'::date, '2028-06-29'::date, null, null, null,
    (select id from asignaciones_educacion where persona_id = '00000000-0000-0000-0000-0000000ed563' limit 1),
    'a nombre de otra persona') $$,
  '%no es de esa persona%',
  'OTRA PERSONA · corregir una asignación indicando a otra persona se rechaza');

select * from finish();
rollback;
