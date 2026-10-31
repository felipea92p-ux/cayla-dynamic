-- ============================================================================
-- 462_los_parametros_de_plata_tienen_vigencia_y_vista_previa.test.sql
-- ============================================================================
-- Migración 0572. Un parámetro de clase plata rige POR FECHAS: cambiarlo no
-- reescribe lo ya pagado, y antes de confirmar se ve a quién le toca.
--
-- LO QUE DEFIENDE, EN ESTE ORDEN:
--   1. plata solo puede vivir con fechas (CHECK), y lo que tiene fechas dice a
--      quién toca;
--   2. el valor de una fecha: antes de la primera versión, el de partida;
--   3. quién puede (roles_cambia) y que la versión se encadena: la anterior se
--      cierra el día antes;
--   4. la fecha nueva tiene que ser posterior a la última versión;
--   5. NO se reescribe un periodo pagado: ni el pagado de ese grupo ni uno
--      pagado entero; el pagado de OTRO grupo no estorba;
--   6. la puerta de siempre (fn_parametro_cambiar) se niega a tocar uno con fechas;
--   7. las versiones no se escriben ni se borran ni se editan por fuera;
--   8. el historial dice desde cuándo rige;
--   9. la vista previa lista a quien está en el alcance y solo a él;
--  10. la lista entrega el valor de hoy y el próximo cambio programado.
-- Las fechas son de 2030 a propósito: ningún periodo real las toca.
-- ============================================================================
begin;
select plan(21);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000462001', 'ZZ462', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000046201c', 'do-462@local'),
  ('00000000-0000-0000-0000-00000046201d', 'admin-462@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, fecha_cese, tipo_vinculo, practicante_modalidad) values
  ('00000000-0000-0000-0000-000000462013', 'Lider', 'DO',    '00000000-0000-0000-0000-000000462001', 'lider_do', 'activo', 'x', '00000000-0000-0000-0000-00000046201c', '2024-01-01', null, 'planilla', null),
  ('00000000-0000-0000-0000-000000462014', 'Direccion', 'Admin', '00000000-0000-0000-0000-000000462001', 'admin', 'activo', 'x', '00000000-0000-0000-0000-00000046201d', '2024-01-01', null, 'planilla', null),
  ('00000000-0000-0000-0000-000000462015', 'Preprofesional', 'Lab', '00000000-0000-0000-0000-000000462001', 'integrante', 'activo', 'x', null, '2029-06-01', null, 'practicante', 'preprofesional'),
  ('00000000-0000-0000-0000-000000462016', 'Profesional', 'Lab', '00000000-0000-0000-0000-000000462001', 'integrante', 'activo', 'x', null, '2029-06-01', null, 'practicante', 'profesional');
set session_replication_role = origin;

-- Dos periodos de laboratorio: el primero ya pagado para practicantes; el segundo, abierto.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000462a01', '2030-01-01', '2030-01-28', 'abierto'),
  ('00000000-0000-0000-0000-000000462a02', '2030-01-29', '2030-02-28', 'abierto');
insert into periodo_grupo_pago (periodo_id, grupo, estado) values
  ('00000000-0000-0000-0000-000000462a01', 'practicante', 'pagado');

-- ── 1 · Plata solo con fechas ───────────────────────────────────────────────
select throws_ok(
  $$ insert into parametros_catalogo (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto, almacen_clave, editable)
     values ('zz_plata_sin_fechas', 'X', 'x', 'horas', 'plata', 'entero', 1, 40, 30, 'zz_plata_sin_fechas', true) $$,
  '23514', null, 'Un parámetro de plata guardado en configuracion (sin fechas) se rechaza');
select throws_ok(
  $$ insert into parametros_catalogo (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto, almacen, almacen_clave, editable)
     values ('zz_plata_sin_alcance', 'X', 'x', 'horas', 'plata', 'entero', 1, 40, 30, 'vigencias', 'zz_plata_sin_alcance', true) $$,
  '23514', null, 'Uno con fechas pero sin decir a quién toca se rechaza');

insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto, almacen, almacen_clave, alcance, editable)
values ('zz_base_462', 'Base de laboratorio', 'Solo para esta prueba.', 'horas', 'plata', 'entero', 20, 40, 30,
        'vigencias', 'zz_base_462', 'practicante_preprofesional', true);

-- ── 2 · El valor de una fecha ───────────────────────────────────────────────
select is(fn_parametro_valor_en('zz_base_462', date '2030-02-01'), 30::numeric,
  'Antes de su primera versión rige el valor de partida del catálogo');

-- ── 3 · Quién puede, y el encadenado ────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046201c', true);
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar_vigencia('zz_base_462', 24, date '2030-02-01', 'DO intenta, y es solo de la dirección') $$,
  'Tu rol no puede cambiar «Base de laboratorio». Pueden: admin.',
  'DO no cambia un parámetro que es solo de la dirección');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046201d', true);
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar_vigencia('zz_base_462', 24, date '2030-02-01', 'La dirección baja la base a 24') $$,
  'La dirección cambia el valor desde una fecha dentro de un periodo sin pagar');
reset role;
select is(fn_parametro_valor_en('zz_base_462', date '2030-01-31'), 30::numeric, 'El día anterior rige todavía el valor viejo');
select is(fn_parametro_valor_en('zz_base_462', date '2030-02-01'), 24::numeric, 'Desde la fecha rige el nuevo');

set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar_vigencia('zz_base_462', 22, date '2030-02-10', 'Otro ajuste, más adelante') $$,
  'Un segundo cambio con fecha posterior entra');
reset role;
select is((select vigente_hasta from parametros_vigencias where parametro = 'zz_base_462' and valor = 24),
          date '2030-02-09', 'La versión anterior se cerró el día antes del cambio');

-- ── 4 · La fecha tiene que ser posterior a la última versión ────────────────
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar_vigencia('zz_base_462', 25, date '2030-02-05', 'Con fecha atrasada') $$,
  'Ya hay una versión de «Base de laboratorio» que rige desde el 2030-02-10. La fecha nueva tiene que ser posterior.',
  'Una fecha igual o anterior a la última versión se rechaza');

-- ── 5 · Lo ya pagado no se reescribe ────────────────────────────────────────
select throws_ok(
  $$ select fn_parametro_cambiar_vigencia('zz_base_462', 25, date '2030-01-20', 'Dentro de un periodo ya pagado') $$,
  'El periodo que termina el 2030-01-28 ya está pagado para este grupo: un valor que rige desde el 2030-01-20 reescribiría lo ya pagado. Elige una fecha dentro de un periodo sin pagar.',
  'Una fecha dentro de un periodo ya pagado para el grupo se rechaza');
reset role;

-- El segundo periodo, pagado SOLO para planilla: no estorba a los practicantes.
insert into periodo_grupo_pago (periodo_id, grupo, estado) values
  ('00000000-0000-0000-0000-000000462a02', 'planilla', 'pagado');
set role authenticated;
select lives_ok(
  $$ select fn_parametro_cambiar_vigencia('zz_base_462', 21, date '2030-02-20', 'El periodo pagado es de otro grupo') $$,
  'Un periodo pagado para OTRO grupo no estorba');
reset role;

-- Ahora ese periodo se paga entero: ya no.
update periodos_planilla set estado = 'pagado' where id = '00000000-0000-0000-0000-000000462a02';
set role authenticated;
select throws_ok(
  $$ select fn_parametro_cambiar_vigencia('zz_base_462', 23, date '2030-02-25', 'El periodo ya se pagó entero') $$,
  'El periodo que termina el 2030-02-28 ya está pagado para este grupo: un valor que rige desde el 2030-02-25 reescribiría lo ya pagado. Elige una fecha dentro de un periodo sin pagar.',
  'Un periodo pagado entero también frena el cambio');

-- ── 6 · La puerta de siempre se niega ───────────────────────────────────────
select throws_ok(
  $$ select fn_parametro_cambiar('zz_base_462', 25, 'Por la puerta sin fecha') $$,
  '«Base de laboratorio» rige por fechas: se cambia con su fecha de vigencia (fn_parametro_cambiar_vigencia), no con esta puerta.',
  'fn_parametro_cambiar se niega a tocar un parámetro que rige por fechas');

-- ── 7 · Las versiones no se tocan por fuera ─────────────────────────────────
select throws_ok(
  $$ insert into parametros_vigencias (parametro, valor, vigente_desde, motivo, creado_por)
     values ('zz_base_462', 40, date '2031-01-01', 'Escritura directa', '00000000-0000-0000-0000-000000462014') $$,
  '42501', null, 'Un cliente no escribe en parametros_vigencias');
reset role;
select throws_ok(
  $$ update parametros_vigencias set valor = 99 where parametro = 'zz_base_462' $$,
  'Una versión de un parámetro no se edita: solo se le cierra el vigente_hasta una vez.',
  'Ni quien escribe a mano en la base edita una versión');
select throws_ok(
  $$ delete from parametros_vigencias where parametro = 'zz_base_462' $$,
  'Las versiones de un parámetro no se borran: volver atrás es un cambio nuevo con otra fecha.',
  'Ni borra una versión');

-- ── 8 · El historial dice desde cuándo rige ─────────────────────────────────
select is((select count(*)::int from parametros_historial
            where parametro = 'zz_base_462' and motivo like 'Rige desde 2030-02-01. %'
              and valor_anterior = 30 and valor_nuevo = 24),
          1, 'El historial guarda de qué a qué y «Rige desde» la fecha');

-- ── 9 · La vista previa: a quién le toca ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000046201d', true);
set role authenticated;
select is((select array_agg(persona) from fn_parametro_vista_previa('zz_base_462', 25, date '2030-03-05')
            where persona like 'Lab,%'),
          array['Lab, Preprofesional']::text[], 'La vista previa lista al preprofesional y no al profesional');
select throws_ok(
  $$ select * from fn_parametro_vista_previa('zz_base_462', 25, date '2030-01-20') $$,
  'El periodo que termina el 2030-01-28 ya está pagado para este grupo: un valor que rige desde el 2030-01-20 reescribiría lo ya pagado. Elige una fecha dentro de un periodo sin pagar.',
  'La vista previa avisa del periodo pagado ANTES de confirmar');

-- ── 10 · La lista ───────────────────────────────────────────────────────────
select is((select proximo_desde from fn_parametros_listar() where parametro = 'zz_base_462'),
          date '2030-02-01', 'La lista dice cuál es el próximo cambio programado');
reset role;

select * from finish();
rollback;
