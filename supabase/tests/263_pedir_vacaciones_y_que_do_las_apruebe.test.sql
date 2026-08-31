-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 263_pedir_vacaciones_y_que_do_las_apruebe.test.sql — la 0330 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) nadie vea u opere la solicitud de otra persona que no sea DO, (b) que la
-- ENCARGADA DE SEDE —que sí opera ausencias del día a día— NO pueda aprobar
-- una que paga (misma regla que ya rige fn_aprobar_ausencia), (c) que aprobar
-- cree la ausencia real por la vía de siempre (fn_registrar_ausencia) y nunca
-- por un camino paralelo, y (d) que las carreras de fechas —contra otra
-- solicitud pendiente, y contra una ausencia ya aprobada— se corten solas.
-- ============================================================================
begin;
select plan(19);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000e9701', 'ZZV01', 'Sede vacaciones', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000ea001', 'VacAdmin', 'Lab',
   '00000000-0000-0000-0000-0000000e9701', 'admin', 'x',
   '00000000-0000-0000-0000-0000000eb001', '2023-01-01'),
  ('00000000-0000-0000-0000-0000000ea002', 'VacEncargada', 'Lab',
   '00000000-0000-0000-0000-0000000e9701', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000eb002', '2023-01-01'),
  -- Con más de dos años de antigüedad: le sobra saldo para las pruebas felices.
  ('00000000-0000-0000-0000-0000000ea003', 'VacSolicitante', 'Lab',
   '00000000-0000-0000-0000-0000000e9701', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000eb003', '2023-01-01'),
  -- Otra integrante, solo para probar que no ve ni opera lo ajeno.
  ('00000000-0000-0000-0000-0000000ea004', 'VacAjena', 'Lab',
   '00000000-0000-0000-0000-0000000e9701', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000eb004', '2023-01-01'),
  -- Recién ingresada HOY: cero días ganados todavía, para el caso de saldo insuficiente.
  ('00000000-0000-0000-0000-0000000ea005', 'VacNueva', 'Lab',
   '00000000-0000-0000-0000-0000000e9701', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000eb005', fn_hoy_lima());
set session_replication_role = origin;

-- ── Validaciones de forma, antes de tocar nada de fondo ─────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb003', true);

select throws_ok(
  $$ select fn_solicitar_vacaciones(fn_hoy_lima() + 10, fn_hoy_lima() + 5, null) $$,
  'La fecha de fin no puede ser anterior a la de inicio.',
  'la fecha de fin no puede ser anterior al inicio'
);

select throws_ok(
  $$ select fn_solicitar_vacaciones(fn_hoy_lima() - 1, fn_hoy_lima(), null) $$,
  'No se pueden solicitar vacaciones para una fecha que ya pasó.',
  'no se puede pedir un rango que ya empezó a pasar'
);

-- ── Saldo insuficiente: quien acaba de ingresar hoy no tiene nada ganado ────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb005', true);

select throws_ok(
  $$ select fn_solicitar_vacaciones(fn_hoy_lima() + 30, fn_hoy_lima() + 30, null) $$,
  'Pides 1 día(s) y tienes 0 pendiente(s). Ajusta el rango.',
  'quien ingresó hoy no tiene saldo para pedir ni un día'
);

-- ── La solicitud feliz ───────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb003', true);

select lives_ok(
  $$ select fn_solicitar_vacaciones(fn_hoy_lima() + 10, fn_hoy_lima() + 14, 'Viaje familiar ya coordinado.') $$,
  'con saldo de sobra, puede pedir cinco días'
);

select is(
  (select count(*)::int from solicitudes_vacaciones
   where persona_id = '00000000-0000-0000-0000-0000000ea003' and estado = 'pendiente'),
  1,
  'y queda una fila pendiente, a su nombre'
);

-- No crea nada en `ausencias` todavía: pendiente no es real.
select is(
  (select count(*)::int from ausencias where persona_id = '00000000-0000-0000-0000-0000000ea003'),
  0,
  'pedirla no crea todavía ninguna ausencia'
);

-- Dos solicitudes que se cruzan: la exclusion constraint la corta.
select throws_ok(
  $$ select fn_solicitar_vacaciones(fn_hoy_lima() + 12, fn_hoy_lima() + 20, null) $$,
  'Ya tienes otra solicitud pendiente que se cruza con esas fechas.',
  'no se puede pedir un rango que se cruza con una solicitud propia ya pendiente'
);

-- ── Nadie ve ni opera la solicitud de otra ───────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb004', true);

-- ⚠ pgTAP corre como `postgres` (superusuario, se salta la RLS): sin este
-- cambio de rol la consulta vería la fila ajena y la prueba pasaría por el
-- motivo equivocado.
set local role authenticated;
select is(
  (select count(*)::int from solicitudes_vacaciones),
  0,
  'otra integrante no ve la solicitud de su compañera'
);
reset role;

select is(
  (select count(*)::int from fn_solicitudes_vacaciones(true)),
  0,
  'ni a través de la función que lee el panel'
);

-- ── La encargada de sede NO puede resolverla: solo DO ───────────────────────
-- Misma regla que ya rige fn_aprobar_ausencia: aprobar convierte días en
-- plata, y por eso no lo puede dar quien opera el día a día de la sede.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb002', true);

select throws_ok(
  format($$ select fn_resolver_solicitud_vacaciones(%L, true, null) $$,
         (select id from solicitudes_vacaciones where persona_id = '00000000-0000-0000-0000-0000000ea003')),
  'Solo un administrador o líder de Desarrollo Organizacional puede resolver una solicitud de vacaciones.',
  'la encargada de sede no puede aprobar una solicitud de vacaciones'
);

-- ── DO sí puede verla y resolverla ───────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb001', true);

select is(
  (select count(*)::int from fn_solicitudes_vacaciones(true)),
  1,
  'DO sí ve la solicitud pendiente'
);

-- Rechazar sin motivo no vale: hay que decir por qué.
select throws_ok(
  format($$ select fn_resolver_solicitud_vacaciones(%L, false, null) $$,
         (select id from solicitudes_vacaciones where persona_id = '00000000-0000-0000-0000-0000000ea003')),
  'Para rechazar hace falta decir por qué, aunque sea en una línea.',
  'rechazar exige motivo'
);

select lives_ok(
  format($$ select fn_resolver_solicitud_vacaciones(%L, true, 'Aprobado, buen viaje.') $$,
         (select id from solicitudes_vacaciones where persona_id = '00000000-0000-0000-0000-0000000ea003')),
  'DO aprueba la solicitud'
);

-- Aprobar creó la ausencia real, por la vía de siempre.
select is(
  (select count(*)::int from ausencias
   where persona_id = '00000000-0000-0000-0000-0000000ea003' and tipo = 'vacaciones' and aprobada_at is not null),
  1,
  'aprobar crea la ausencia real ya aprobada, via fn_registrar_ausencia'
);

-- Resolver dos veces la misma solicitud no vale.
select throws_ok(
  format($$ select fn_resolver_solicitud_vacaciones(%L, true, null) $$,
         (select id from solicitudes_vacaciones where persona_id = '00000000-0000-0000-0000-0000000ea003')),
  'Esa solicitud ya fue aprobada — no se puede resolver dos veces.',
  'no se puede resolver dos veces la misma solicitud'
);

-- ── Pedir un rango que ya es una ausencia real: se corta antes de la exclusion ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eb003', true);

select throws_ok(
  $$ select fn_solicitar_vacaciones(fn_hoy_lima() + 11, fn_hoy_lima() + 11, null) $$,
  'Ya tienes una ausencia registrada que se cruza con esas fechas.',
  'no se puede pedir un rango que ya es una ausencia aprobada'
);

-- ── Retirar la propia, mientras siga pendiente ──────────────────────────────
select lives_ok(
  $$ select fn_solicitar_vacaciones(fn_hoy_lima() + 40, fn_hoy_lima() + 41, null) $$,
  'pide un segundo rango, sin cruce con lo anterior'
);

select lives_ok(
  format($$ select fn_cancelar_solicitud_vacaciones(%L) $$,
         (select id from solicitudes_vacaciones
          where persona_id = '00000000-0000-0000-0000-0000000ea003' and estado = 'pendiente')),
  'puede retirar su propia solicitud mientras está pendiente'
);

select throws_ok(
  format($$ select fn_cancelar_solicitud_vacaciones(%L) $$,
         (select id from solicitudes_vacaciones
          where persona_id = '00000000-0000-0000-0000-0000000ea003' and estado = 'cancelada')),
  'Esa solicitud no existe, no es tuya, o ya fue resuelta.',
  'no se puede retirar una solicitud que ya quedó resuelta'
);

select * from finish();
rollback;
