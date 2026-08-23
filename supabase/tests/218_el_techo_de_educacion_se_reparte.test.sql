-- ============================================================================
-- 218_el_techo_de_educacion_se_reparte.test.sql
-- ============================================================================
-- Lo que la 0281 promete, con el caso que la motivó:
--
--   Ana es rango cayla, techo S/180. Ella estudia (pensión S/200 → el 75 % son
--   S/150) y su hija va al colegio (S/200 → S/150 más). Antes de la 0281 la
--   segunda fila rebotaba entera y, como el monto no se teclea desde la 0149,
--   no había forma de registrar ese comprobante ni por los S/30 que quedaban
--   libres bajo el techo. Ahora entra por S/30.
--
--   Después la bajan a colibrí (techo S/90) y el reparto se rehace solo: la
--   primera se queda con 90, la segunda con 0. Y cuando la suben a archicaylo
--   (S/480), las dos vuelven a su 75 %.
--
-- Todo en begin/rollback y en fechas de 2027-2028, lejos de cualquier dato real.
-- ============================================================================
begin;
select plan(27);

-- ── Semilla ─────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ec00', 'ZZTEC', 'Sede de laboratorio 281', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ec01', 'TecDO', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ec00', 'lider_do', 'test-hash',
        '00000000-0000-0000-0000-00000000ec09', '2020-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ec02', 'TecAna', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ec00', 'test-hash', '2025-01-02');

-- Rango cayla: techo S/180 según la escala de la 0132.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000ec02', 'cayla', 1130, '2025-01-02');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ec09', true);


-- ── 1 · El saldo, que es el dato que faltaba ────────────────────────────────
select is(
  fn_educacion_saldo('00000000-0000-0000-0000-00000000ec02', '2027-03-01', '2027-12-31'),
  180.00::numeric,
  'SALDO · sin nada cargado, queda el techo entero del rango');

select is(
  fn_educacion_monto('00000000-0000-0000-0000-00000000ec02', 200::numeric, '2027-03-01', '2027-12-31'),
  150.00::numeric,
  'MONTO · con techo libre manda el 75 % del comprobante');


-- ── 2 · El estudio de ella ──────────────────────────────────────────────────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ec02'::uuid, 'Instituto de laboratorio', 200::numeric,
    'trabajador', '2027-03-01'::date, '2027-12-31'::date,
    null, 'educacion/x/ella.pdf', null, null, null) $$,
  'ALTA · la primera asignación entra por el 75 %');

select is(
  (select monto from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02' and beneficiario = 'trabajador'),
  150.00::numeric,
  'ALTA · guardó S/150, que es el 75 % de S/200');

select is(
  fn_educacion_saldo('00000000-0000-0000-0000-00000000ec02', '2027-03-01', '2027-12-31'),
  30.00::numeric,
  'SALDO · después de la primera quedan S/30 de techo');


-- ── 3 · El colegio de la hija: EL CASO QUE MOTIVÓ LA MIGRACIÓN ──────────────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ec02'::uuid, 'Colegio de laboratorio', 200::numeric,
    'hijo', '2027-03-01'::date, '2027-12-31'::date,
    'Lucia de Laboratorio', 'educacion/x/hija.pdf', null, null, null) $$,
  'REPARTO · el segundo comprobante ya no rebota: entra por el saldo');

select is(
  (select monto from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02' and beneficiario = 'hijo'),
  30.00::numeric,
  'REPARTO · y entra por S/30, que es lo que quedaba del techo');

select is(
  (select sum(monto) from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02'),
  180.00::numeric,
  'REPARTO · las dos juntas suman exactamente el techo, ni un céntimo más');


-- ── 4 · Cuando ya no queda nada, se dice por qué ────────────────────────────
select throws_like($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ec02'::uuid, 'Otro instituto', 400::numeric,
    'trabajador', '2027-03-01'::date, '2027-12-31'::date,
    null, 'educacion/x/otro.pdf', null, null, null) $$,
  '%No queda techo libre%',
  'SIN SALDO · una tercera en las mismas fechas se rechaza diciendo el motivo');


-- ── 5 · Meses distintos no compiten por el mismo techo ──────────────────────
select lives_ok($$
  select fn_educacion_registrar(
    '00000000-0000-0000-0000-00000000ec02'::uuid, 'Instituto del año siguiente', 200::numeric,
    'trabajador', '2028-01-01'::date, '2028-06-30'::date,
    null, 'educacion/x/2028.pdf', null, null, null) $$,
  'SOLAPE · un curso en fechas que no se solapan entra sin pelear por el techo');

select is(
  (select monto from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02' and vigente_desde = '2028-01-01'),
  150.00::numeric,
  'SOLAPE · y cobra su 75 % entero, no el saldo de 2027');


-- ── 6 · La bajan de rango: el techo deja de ser una foto ────────────────────
select lives_ok($$
  select fn_set_salario('00000000-0000-0000-0000-00000000ec02'::uuid, 'colibri',
                        1130::numeric, '2027-06-01'::date, 'Prueba 281') $$,
  'RANGO · el cambio de rango se aplica');

select is(
  (select coalesce(sum(monto), 0) from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02'
      and vigente_desde <= '2027-07-01' and vigente_hasta >= '2027-07-01'),
  90.00::numeric,
  'RANGO · con el techo de colibrí, lo vigente en julio suma S/90 y no S/180');

select is(
  (select count(*)::int from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02' and vigente_hasta = '2027-05-31'),
  2,
  'RANGO · las vigencias viejas se CIERRAN el día anterior, no se reescriben');

select is(
  (select monto from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02' and vigente_desde = '2028-01-01'),
  90.00::numeric,
  'RANGO · el techo nuevo también alcanza a la que empieza el año siguiente');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-00000000ec02'
      and campo_modificado = 'educacion_realineada'),
  3,
  'RASTRO · cada fila movida dejó su renglón en correcciones_auditoria');


-- ── 7 · La suben de rango: el monto vuelve a lo que el papel sostiene ───────
select lives_ok($$
  select fn_set_salario('00000000-0000-0000-0000-00000000ec02'::uuid, 'archicaylo',
                        3000::numeric, '2027-09-01'::date, 'Prueba 281 · ascenso') $$,
  'ASCENSO · el cambio de rango se aplica');

select is(
  (select coalesce(sum(monto), 0) from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02'
      and vigente_desde <= '2027-10-01' and vigente_hasta >= '2027-10-01'),
  300.00::numeric,
  'ASCENSO · con techo de S/480 las dos vuelven a su 75 %: 150 + 150');

select is(
  (select monto from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02' and vigente_desde = '2028-01-01'),
  150.00::numeric,
  'ASCENSO · y la de 2028 también vuelve a su 75 %');


-- ── 8 · Un cambio de sueldo sin cambio de techo no mueve nada ──────────────
select is(
  fn_educacion_realinear('00000000-0000-0000-0000-00000000ec02'::uuid, '2027-10-01'::date),
  0,
  'IDEMPOTENTE · realinear contra el mismo techo no mueve ninguna fila');


-- ── 9 · El candado impide subir, pero ya no impide arreglar ────────────────
-- Se baja el techo POR DEBAJO de lo vigente sin tocar el rango, que es el estado
-- heredado que dejó la 0132: filas por encima de su techo. Antes de la 0281, ahí
-- el candado rechazaba también el intento de corregirlas hacia abajo.
update topes_educacion_rango set tope_mensual = 100 where rango = 'archicaylo';

select throws_like($$
  update asignaciones_educacion set monto = monto + 10
   where persona_id = '00000000-0000-0000-0000-00000000ec02'
     and vigente_desde = '2027-09-01' and beneficiario = 'trabajador' $$,
  '%supera el tope%',
  'CANDADO · subir un monto por encima del techo se sigue rechazando');

select lives_ok($$
  update asignaciones_educacion set monto = 120
   where persona_id = '00000000-0000-0000-0000-00000000ec02'
     and vigente_desde = '2027-09-01' and beneficiario = 'trabajador' $$,
  'CANDADO · bajarlo, en cambio, ahora se puede: el techo no puede impedir el arreglo');

update topes_educacion_rango set tope_mensual = 480 where rango = 'archicaylo';


-- ── 10 · Lo que ya se pagó no se reescribe ────────────────────────────────
select is(
  (select sum(monto) from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02' and vigente_hasta = '2027-05-31'),
  180.00::numeric,
  'PASADO · las cerradas conservan sus S/150 y S/30, no los S/90 y S/0 del recorte');


-- ── 11 · La fila que continúa hereda su lugar en la cola del techo ─────────
-- `created_at` decide quién se reparte primero el techo. Si la fila que nace de
-- un recorte estrenara fecha, cada realineación cambiaría el orden de prioridad
-- y el reparto dejaría de ser estable. Se marca la de la trabajadora con una
-- fecha vieja —dentro de una transacción todas las filas comparten `now()`— y se
-- fuerza otro recorte para ver si la hereda.
update asignaciones_educacion set created_at = '2020-01-01'
 where persona_id = '00000000-0000-0000-0000-00000000ec02'
   and beneficiario = 'trabajador' and vigente_desde = '2027-09-01';

select lives_ok($$
  select fn_set_salario('00000000-0000-0000-0000-00000000ec02'::uuid, 'cayla',
                        1130::numeric, '2027-11-01'::date, 'Prueba 281 · vuelta a cayla') $$,
  'ORDEN · el rango vuelve a cayla');

select is(
  (select created_at from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02'
      and beneficiario = 'trabajador' and vigente_desde = '2027-11-01'),
  '2020-01-01'::timestamptz,
  'ORDEN · la vigencia nueva hereda el created_at de la que reemplaza');

select is(
  (select monto from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02'
      and beneficiario = 'trabajador' and vigente_desde = '2027-11-01'),
  150.00::numeric,
  'ORDEN · y por ser la primera de la cola se queda con su 75 % entero');

select is(
  (select monto from asignaciones_educacion
    where persona_id = '00000000-0000-0000-0000-00000000ec02'
      and beneficiario = 'hijo' and vigente_desde = '2027-11-01'),
  30.00::numeric,
  'ORDEN · y la segunda, con los S/30 que quedan bajo el techo de cayla');

select * from finish();
rollback;
