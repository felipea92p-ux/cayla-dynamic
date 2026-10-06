-- ============================================================================
-- 317_los_papeles_de_cese_traen_la_identidad_correcta.test.sql
-- ============================================================================
-- Cubre `fn_papeles_cese` (0400): el certificado de trabajo y la constancia de
-- cese comparten esta única función de identidad, de solo lectura.
--
-- Lo que tiene que quedar probado, en este orden de consecuencia:
--   1. Solo admin/líder puede llamarla — es el mismo dato sensible (DNI) que
--      ya protege fn_liquidacion, y el guard es el mismo guard.
--   2. A quien no tiene fecha de cese no se le puede pedir estos papeles: son
--      papeles de cese, no de cualquiera.
--   3. El tiempo de servicio se calcula bien contra fechas conocidas.
--   4. El género sale de `datos_personales.genero` — la misma fuente que ya
--      usa el convenio de prácticas — y no de un criterio nuevo.
--   5. `authenticated` puede ejecutarla, o la pantalla se queda en blanco.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000f300', 'ZZCES', 'Sede de laboratorio', true);

-- El admin que consulta los papeles.
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000f301', 'CeseAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000f300', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000f309');

-- Una encargada de sede: ve su sede, no los papeles de cese de nadie.
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000f302', 'CeseEncargada', 'Laboratorio',
        '00000000-0000-0000-0000-00000000f300', 'supervisor_sede', 'test-hash',
        '00000000-0000-0000-0000-00000000f308');
set session_replication_role = origin;

-- La persona que cesó. Fechas elegidas para que el tiempo de servicio sea
-- exacto y fácil de verificar a ojo: 6 años y 5 días, sin meses sueltos.
insert into personas
  (id, nombres, apellidos, documento, tipo_documento, cargo, funcion, tipo_vinculo, sede_base_id,
   pin_hash, estado, fecha_ingreso, fecha_cese, motivo_cese)
values
  ('00000000-0000-0000-0000-00000000f303', 'Melany', 'Cesada Prueba', '87654321', 'dni',
   'Vendedora', 'experiencia_marca', 'planilla', '00000000-0000-0000-0000-00000000f300',
   'test-hash', 'inactivo', '2020-01-15', '2026-01-20', 'renuncia');

insert into datos_personales (persona_id, genero)
values ('00000000-0000-0000-0000-00000000f303', 'masculino');

-- Alguien activo, sin fecha de cese: no se le puede pedir estos papeles.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000f304', 'Sigue', 'Activa Prueba',
        '00000000-0000-0000-0000-00000000f300', 'test-hash', 'planilla');

-- ── Como admin ───────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f309', true);

select is(
  (fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'nombre_completo'),
  'Melany Cesada Prueba',
  'nombre_completo junta nombres y apellidos'
);
select is(
  (fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'documento'),
  '87654321',
  'documento es el DNI de la persona'
);
select is(
  (fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'cargo'),
  'Vendedora',
  'cargo es "la naturaleza de las labores" que exige el certificado'
);
select is(
  (fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'sede'),
  'Sede de laboratorio',
  'sede se resuelve por sede_base_id, no se deja en el id crudo'
);
select is(
  (fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'genero'),
  'masculino',
  'genero sale de datos_personales, la misma fuente que ya usa el convenio de prácticas'
);
select is(
  ((fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'tiempo_servicio_anios')::int),
  6, 'tiempo de servicio: 6 años exactos entre 2020-01-15 y 2026-01-20'
);
select is(
  ((fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'tiempo_servicio_meses')::int),
  0, 'tiempo de servicio: cero meses sueltos'
);
select is(
  ((fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'tiempo_servicio_dias')::int),
  5, 'tiempo de servicio: cinco días sueltos'
);
select is(
  (fn_papeles_cese('00000000-0000-0000-0000-00000000f303') ->> 'motivo_cese'),
  'renuncia',
  'motivo_cese viaja en el jsonb — le sirve a quien genera el papel en pantalla, aunque ningún documento impreso lo muestre'
);

-- Sin fecha de cese: no hay papeles de cese que pedir, aunque quien pregunta
-- tenga todo el permiso del mundo.
select throws_ok(
  $$ select fn_papeles_cese('00000000-0000-0000-0000-00000000f304') $$,
  'Esa persona no tiene fecha de cese. Estos papeles son de cese.',
  'una persona activa no tiene papeles de cese que generar'
);

-- ── Como encargada de sede: mismo guard que fn_liquidacion ──────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f308', true);
select throws_ok(
  $$ select fn_papeles_cese('00000000-0000-0000-0000-00000000f303') $$,
  'Solo un administrador o líder puede ver los papeles de cese de una persona.',
  'una encargada de sede no puede pedir los papeles de cese de nadie'
);

select ok(
  has_function_privilege('authenticated', 'fn_papeles_cese(uuid)', 'execute'),
  'authenticated puede ejecutar fn_papeles_cese, o la pantalla de Liquidaciones se queda en blanco'
);

select finish();
rollback;
