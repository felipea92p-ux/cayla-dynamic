-- ============================================================================
-- 91_la_planilla_no_la_lee_cualquiera.test.sql
-- ============================================================================
-- La 0076 cerró la ejecución anónima con un barrido de grants sin excepciones, y
-- de paso deshizo el `revoke ... from authenticated` con que las migraciones
-- 0025/0026/0027 y 0032 protegían a mano dos funciones. Durante unas horas, una
-- sesión de integrante —que por RLS no puede leer ni una fila de
-- asignaciones_salario— podía pedir la planilla entera con todos los sueldos.
-- Y la del terminal de tienda, que no es siquiera una persona, también.
--
-- Esta prueba existe para que no vuelva a pasar en silencio: comprueba el
-- resultado (quién puede y quién no), no el permiso. Un permiso se puede volver
-- a conceder por accidente; que una integrante lea los sueldos, no.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000000d5', 'ZZPLA', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000000d6', 'PlanillaAdmin',   'Lab', '00000000-0000-0000-0000-0000000000d5', 'admin',           'x', '00000000-0000-0000-0000-00000000dd06', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000000d7', 'PlanillaEncarg',  'Lab', '00000000-0000-0000-0000-0000000000d5', 'supervisor_sede', 'x', '00000000-0000-0000-0000-00000000dd07', '2024-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000000d8', 'PlanillaIntegra', 'Lab', '00000000-0000-0000-0000-0000000000d5', 'integrante',      'x', '00000000-0000-0000-0000-00000000dd08', '2024-01-15', 'planilla');
insert into terminales (id, sede_id, nombre_dispositivo, auth_user_id, activo) values
  ('00000000-0000-0000-0000-0000000000d9', '00000000-0000-0000-0000-0000000000d5', 'Mac mini lab', '00000000-0000-0000-0000-00000000dd09', true);
set session_replication_role = origin;

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-0000000000d6', 'archicaylo', 5000, '2024-01-15'),
  ('00000000-0000-0000-0000-0000000000d7', 'cayla',      2500, '2024-01-15'),
  ('00000000-0000-0000-0000-0000000000d8', 'colibri',    1200, '2024-01-15');

-- ── La integrante: por RLS no ve ni un salario, y tampoco por la puerta de atrás
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dd08', true);

-- La RLS de tabla solo actúa si además se cambia de ROL: set_config sola no
-- basta (eso mueve auth.uid(), que es lo que miran las funciones definer).
set role authenticated;
create temp table _rls_salarios as select count(*)::int as n from asignaciones_salario;
reset role;
select is((select n from _rls_salarios),
          0, 'INTEGRANTE · la RLS no le deja leer ni una fila de salarios (esto ya funcionaba)');

select throws_ok($$ select fn_planilla_calcular('2026-07-01','2026-07-31') $$,
                 null, null, 'INTEGRANTE · y tampoco puede pedir la planilla, que es la misma información por otra puerta');

select throws_ok($$ select fn_provisiones('2026-07-31') $$,
                 null, null, 'INTEGRANTE · ni las provisiones (esto ya lo hacía bien)');

-- ── La encargada de sede: gestiona su tienda, pero la planilla no es suya
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dd07', true);
select throws_ok($$ select fn_planilla_calcular('2026-07-01','2026-07-31') $$,
                 null, null, 'ENCARGADA · tampoco: la planilla es de administración, no de la sede');

-- ── El terminal de tienda: está autenticado pero no es ni una persona
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dd09', true);
select throws_ok($$ select fn_planilla_calcular('2026-07-01','2026-07-31') $$,
                 null, null, 'TERMINAL · la Mac mini de la tienda no puede pedir la planilla del equipo');

-- ── Y quien sí debe, sigue pudiendo
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000dd06', true);
select lives_ok($$ select fn_planilla_calcular('2026-07-01','2026-07-31') $$,
                 'ADMIN · quien sí debe calcularla la calcula igual que siempre');

select is((select jsonb_array_length(fn_planilla_calcular('2026-07-01','2026-07-31')->'filas') > 0),
          true, 'ADMIN · y le devuelve filas de verdad, no una lista vacía');

select * from finish();
rollback;
