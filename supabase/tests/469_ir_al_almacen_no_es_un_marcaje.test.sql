-- ============================================================================
-- 469_ir_al_almacen_no_es_un_marcaje.test.sql
-- ============================================================================
-- Lo que defiende (migración 0580):
--
--   · «Voy a almacén» / «Vuelvo a tienda» entra por UNA puerta, con las mismas
--     comprobaciones de identidad que un marcaje (terminal activo, sesión = ese
--     terminal, persona de su lista) y la misma idempotencia por client_uuid.
--   · La tabla es append-only: no se borra, no se edita; se anula con motivo y
--     deja rastro en correcciones_auditoria.
--   · `fn_ubicaciones_del_dia` —el contrato con la sesión de Turnos— arma los
--     tramos como se decidió: cierra con «Vuelvo a tienda», con la salida final
--     NO anulada, o con la vuelta prevista ya vencida; junta un doble toque;
--     ignora lo anulado; y solo la ven admin, lider_do y la líder de esa sede.
--
-- Los escenarios de lectura van en una fecha fija pasada (2026-10-15), donde
-- toda vuelta prevista ya venció. El tramo «en vivo» usa now().
-- ============================================================================
begin;
select plan(30);

-- ── Semilla ────────────────────────────────────────────────────────────────
insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-0000000a1a00', 'ZZALA', 'Sede de laboratorio A', true),
  ('00000000-0000-0000-0000-0000000a1b00', 'ZZALB', 'Sede de laboratorio B', true);

set session_replication_role = replica;
insert into terminales (id, sede_id, nombre_dispositivo, auth_user_id, activo) values
  ('00000000-0000-0000-0000-0000000a1a0e', '00000000-0000-0000-0000-0000000a1a00', 'Mac mini A',
   '00000000-0000-0000-0000-0000000a1a09', true),
  ('00000000-0000-0000-0000-0000000a1b0e', '00000000-0000-0000-0000-0000000a1b00', 'Mac mini B',
   '00000000-0000-0000-0000-0000000a1b09', true);
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000a1aa1', 'LiderA', 'Lab', '00000000-0000-0000-0000-0000000a1a00', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000a1aa9'),
  ('00000000-0000-0000-0000-0000000a1bb1', 'LiderB', 'Lab', '00000000-0000-0000-0000-0000000a1b00', 'supervisor_sede', 'x', '00000000-0000-0000-0000-0000000a1bb9'),
  ('00000000-0000-0000-0000-0000000a1dd1', 'AdminLab', 'Lab', '00000000-0000-0000-0000-0000000a1a00', 'admin', 'x', '00000000-0000-0000-0000-0000000a1dd9');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000a1001', 'Viva',     'Lab', '00000000-0000-0000-0000-0000000a1a00', 'x'),
  ('00000000-0000-0000-0000-0000000a1002', 'Vuelve',   'Lab', '00000000-0000-0000-0000-0000000a1a00', 'x'),
  ('00000000-0000-0000-0000-0000000a1003', 'Vence',    'Lab', '00000000-0000-0000-0000-0000000a1a00', 'x'),
  ('00000000-0000-0000-0000-0000000a1004', 'SeVa',     'Lab', '00000000-0000-0000-0000-0000000a1a00', 'x'),
  ('00000000-0000-0000-0000-0000000a1005', 'Doble',    'Lab', '00000000-0000-0000-0000-0000000a1a00', 'x'),
  ('00000000-0000-0000-0000-0000000a1006', 'DosVeces', 'Lab', '00000000-0000-0000-0000-0000000a1a00', 'x'),
  ('00000000-0000-0000-0000-0000000a1007', 'Reabre',   'Lab', '00000000-0000-0000-0000-0000000a1a00', 'x'),
  ('00000000-0000-0000-0000-0000000a1008', 'OtraSede', 'Lab', '00000000-0000-0000-0000-0000000a1b00', 'x');

-- Escenarios del 2026-10-15 (hora de Lima), cargados directo: la puerta se
-- prueba aparte, aquí se prueba la lectura.
insert into cambios_ubicacion (client_uuid, persona_id, sede_id, terminal_id, ubicacion, timestamp_cambio, vuelve_previsto)
select gen_random_uuid(), p::uuid, coalesce(s, '00000000-0000-0000-0000-0000000a1a00')::uuid,
       coalesce(t, '00000000-0000-0000-0000-0000000a1a0e')::uuid, u,
       ('2026-10-15T' || h || '-05:00')::timestamptz,
       case when v is null then null else ('2026-10-15T' || v || '-05:00')::timestamptz end
from (values
  -- Vuelve: 10:00 a almacén «hasta que vuelva», 11:00 marca la vuelta.
  ('00000000-0000-0000-0000-0000000a1002', 'almacen', '10:00:00', null::text, null::text, null::text),
  ('00000000-0000-0000-0000-0000000a1002', 'tienda',  '11:00:00', null, null, null),
  -- Vence: 12:00 por 30 min y no marca la vuelta → cierra 12:30.
  ('00000000-0000-0000-0000-0000000a1003', 'almacen', '12:00:00', '12:30:00', null, null),
  -- SeVa: 14:00 a almacén, salida final 15:00 → cierra 15:00.
  ('00000000-0000-0000-0000-0000000a1004', 'almacen', '14:00:00', null, null, null),
  -- Doble: doble toque 09:00 (30 min) y 09:05 (hasta que vuelva), vuelve 10:00 → un tramo.
  ('00000000-0000-0000-0000-0000000a1005', 'almacen', '09:00:00', '09:30:00', null, null),
  ('00000000-0000-0000-0000-0000000a1005', 'almacen', '09:05:00', null, null, null),
  ('00000000-0000-0000-0000-0000000a1005', 'tienda',  '10:00:00', null, null, null),
  -- DosVeces: dos idas que vencen, con piso en medio → dos tramos.
  ('00000000-0000-0000-0000-0000000a1006', 'almacen', '16:00:00', '16:30:00', null, null),
  ('00000000-0000-0000-0000-0000000a1006', 'almacen', '17:00:00', '17:30:00', null, null),
  -- Reabre: 15:00 a almacén; su salida final está anulada → sigue allí.
  ('00000000-0000-0000-0000-0000000a1007', 'almacen', '15:00:00', null, null, null),
  -- OtraSede: no debe aparecer en la sede A.
  ('00000000-0000-0000-0000-0000000a1008', 'almacen', '10:00:00', null,
   '00000000-0000-0000-0000-0000000a1b00', '00000000-0000-0000-0000-0000000a1b0e')
) as x(p, u, h, v, s, t);

-- Una ida anulada de Vuelve (13:00) que no debe contar.
insert into cambios_ubicacion (client_uuid, persona_id, sede_id, terminal_id, ubicacion, timestamp_cambio,
                               anulado_at, anulado_por, anulado_motivo)
values (gen_random_uuid(), '00000000-0000-0000-0000-0000000a1002', '00000000-0000-0000-0000-0000000a1a00',
        '00000000-0000-0000-0000-0000000a1a0e', 'almacen', '2026-10-15T13:00:00-05:00',
        now(), '00000000-0000-0000-0000-0000000a1aa1', 'se marcó por error');

insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen,
                      anulada_at, anulada_por, anulada_motivo)
values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000a1004', '00000000-0000-0000-0000-0000000a1a00',
   'entrada', '2026-10-15T09:00:00-05:00', 'terminal', null, null, null),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000a1004', '00000000-0000-0000-0000-0000000a1a00',
   'salida_final', '2026-10-15T15:00:00-05:00', 'terminal', null, null, null),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000a1007', '00000000-0000-0000-0000-0000000a1a00',
   'entrada', '2026-10-15T09:00:00-05:00', 'terminal', null, null, null),
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000a1007', '00000000-0000-0000-0000-0000000a1a00',
   'salida_final', '2026-10-15T16:00:00-05:00', 'terminal',
   now(), '00000000-0000-0000-0000-0000000a1aa1', 'reabrió su día');

-- ── CATÁLOGO ───────────────────────────────────────────────────────────────
select has_table('public', 'cambios_ubicacion', 'existe cambios_ubicacion');
select ok(not has_function_privilege('anon',
  'public.fn_registrar_cambio_ubicacion(uuid, text, timestamptz, uuid, text, uuid, timestamptz, uuid)', 'execute'),
  'anon no puede registrar ubicaciones');
select ok(not has_table_privilege('authenticated', 'public.cambios_ubicacion', 'insert'),
  'nadie inserta en la tabla directamente: solo por la función');

-- ── LA PUERTA, desde el terminal A ─────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1a09', true);

select lives_ok($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1001', 'almacen',
    now() - interval '1 minute', '00000000-0000-0000-0000-0000000a1c01', 'terminal',
    '00000000-0000-0000-0000-0000000a1a0e', now() + interval '59 minutes')
$$, 'el terminal registra «Voy a almacén» por una hora');

select is((select sede_id from cambios_ubicacion where client_uuid = '00000000-0000-0000-0000-0000000a1c01'),
  '00000000-0000-0000-0000-0000000a1a00'::uuid, 'la sede sale del terminal, no del cliente');

select lives_ok($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1001', 'almacen',
    now() - interval '1 minute', '00000000-0000-0000-0000-0000000a1c01', 'terminal',
    '00000000-0000-0000-0000-0000000a1a0e', now() + interval '59 minutes')
$$, 'un reintento de la cola con el mismo client_uuid no falla');
select is((select count(*)::int from cambios_ubicacion where client_uuid = '00000000-0000-0000-0000-0000000a1c01'),
  1, '…y no duplica');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1008', 'almacen',
    now(), gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a1a0e')
$$, '%lista de este terminal%', 'el terminal A no registra a alguien de la sede B');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1008', 'almacen',
    now(), gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a1b0e')
$$, '%no coincide con p_terminal_id%', 'la sesión del terminal A no firma como el terminal B');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1001', 'tienda',
    now(), gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a1a0e', now() + interval '1 hour')
$$, '%solo va con almacen%', 'volver a tienda no lleva hora prevista');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1001', 'tienda',
    now() + interval '1 hour', gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a1a0e')
$$, '%en el futuro%', 'un reloj adelantado no escribe el futuro');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1001', 'sotano',
    now(), gen_random_uuid(), 'terminal', '00000000-0000-0000-0000-0000000a1a0e')
$$, '%no válida%', 'solo tienda o almacen');

-- ── APPEND-ONLY ────────────────────────────────────────────────────────────
set local role authenticated;
select throws_like($$
  insert into cambios_ubicacion (client_uuid, persona_id, sede_id, terminal_id, ubicacion, timestamp_cambio)
  values (gen_random_uuid(), '00000000-0000-0000-0000-0000000a1001', '00000000-0000-0000-0000-0000000a1a00',
          '00000000-0000-0000-0000-0000000a1a0e', 'almacen', now())
$$, '%permission denied%', 'un cliente no inserta saltándose la puerta');
reset role;

select throws_like($$
  delete from cambios_ubicacion where client_uuid = '00000000-0000-0000-0000-0000000a1c01'
$$, '%no se borra%', 'ni siquiera desde el SQL Editor se borra');

select throws_like($$
  update cambios_ubicacion set ubicacion = 'tienda' where client_uuid = '00000000-0000-0000-0000-0000000a1c01'
$$, '%no se edita%', 'tampoco se edita');

-- ── LA LECTURA DEL CONTRATO, como la líder de equipo de A ──────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1aa9', true);

select results_eq($$
  select persona_id, to_char(desde at time zone 'America/Lima', 'HH24:MI'),
         to_char(hasta at time zone 'America/Lima', 'HH24:MI')
    from fn_ubicaciones_del_dia('00000000-0000-0000-0000-0000000a1a00', date '2026-10-15')
$$, $$ values
  ('00000000-0000-0000-0000-0000000a1002'::uuid, '10:00', '11:00'),
  ('00000000-0000-0000-0000-0000000a1003'::uuid, '12:00', '12:30'),
  ('00000000-0000-0000-0000-0000000a1004'::uuid, '14:00', '15:00'),
  ('00000000-0000-0000-0000-0000000a1005'::uuid, '09:00', '10:00'),
  ('00000000-0000-0000-0000-0000000a1006'::uuid, '16:00', '16:30'),
  ('00000000-0000-0000-0000-0000000a1006'::uuid, '17:00', '17:30'),
  ('00000000-0000-0000-0000-0000000a1007'::uuid, '15:00', null)
$$, 'los tramos del día: vuelta marcada, vuelta vencida, salida final, doble toque, dos idas, salida anulada; sin la otra sede ni lo anulado');

select is((select count(*)::int
             from fn_ubicaciones_del_dia('00000000-0000-0000-0000-0000000a1a00',
                                         ((now() - interval '1 minute') at time zone 'America/Lima')::date)
            where persona_id = '00000000-0000-0000-0000-0000000a1001' and hasta is null),
  1, 'quien acaba de irse y aún no vence su hora sigue en almacén (hasta = null)');

select lives_ok($$
  select * from fn_ubicaciones_del_dia('00000000-0000-0000-0000-0000000a1a00', date '2026-10-15')
$$, 'la líder de su sede la lee');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1dd9', true);
select lives_ok($$
  select * from fn_ubicaciones_del_dia('00000000-0000-0000-0000-0000000a1b00', date '2026-10-15')
$$, 'admin lee cualquier sede');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1bb9', true);
select throws_like($$
  select * from fn_ubicaciones_del_dia('00000000-0000-0000-0000-0000000a1a00', date '2026-10-15')
$$, '%Sin permiso%', 'la líder de B no lee la sede A');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1a09', true);
select throws_like($$
  select * from fn_ubicaciones_del_dia('00000000-0000-0000-0000-0000000a1a00', date '2026-10-15')
$$, '%Sin permiso%', 'el terminal no usa la lectura del panel');

-- ── RLS de la tabla ────────────────────────────────────────────────────────
set local role authenticated;
select is((select count(*)::int from cambios_ubicacion where persona_id = '00000000-0000-0000-0000-0000000a1002'),
  3, 'el terminal A ve los cambios de su gente (también el anulado: el cliente lo filtra)');
select is((select count(*)::int from cambios_ubicacion where persona_id = '00000000-0000-0000-0000-0000000a1008'),
  0, 'el terminal A no ve los de la sede B');
reset role;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1bb9', true);
set local role authenticated;
select is((select count(*)::int from cambios_ubicacion where sede_id = '00000000-0000-0000-0000-0000000a1a00'),
  0, 'la líder de B no ve la tabla de A');
reset role;

-- ── ANULAR ─────────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1a09', true);
select throws_like($$
  select fn_anular_cambio_ubicacion((select id from cambios_ubicacion
    where client_uuid = '00000000-0000-0000-0000-0000000a1c01'), 'no fue')
$$, '%Sin permiso%', 'el terminal no anula');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000a1aa9', true);
select lives_ok($$
  select fn_anular_cambio_ubicacion((select id from cambios_ubicacion
    where client_uuid = '00000000-0000-0000-0000-0000000a1c01'), 'solo fue a traer una caja')
$$, 'la líder de su sede anula con motivo');

select is((select count(*)::int from correcciones_auditoria
            where persona_id = '00000000-0000-0000-0000-0000000a1001'
              and campo_modificado = 'cambio_ubicacion' and motivo = 'solo fue a traer una caja'),
  1, 'la anulación deja rastro en auditoría');

select throws_like($$
  select fn_anular_cambio_ubicacion((select id from cambios_ubicacion
    where client_uuid = '00000000-0000-0000-0000-0000000a1c01'), 'otra vez')
$$, '%ya está anulado%', 'no se anula dos veces');

-- ── DESDE EL PANEL ─────────────────────────────────────────────────────────
select is((select registrado_por from fn_registrar_cambio_ubicacion(
    '00000000-0000-0000-0000-0000000a1002', 'almacen', now() - interval '2 minutes', gen_random_uuid(),
    'panel', null, null, '00000000-0000-0000-0000-0000000a1a00')),
  '00000000-0000-0000-0000-0000000a1aa1'::uuid, 'la líder lo registra desde el panel y queda quién fue');

select throws_like($$
  select fn_registrar_cambio_ubicacion('00000000-0000-0000-0000-0000000a1008', 'almacen', now(),
    gen_random_uuid(), 'panel', null, null, '00000000-0000-0000-0000-0000000a1b00')
$$, '%Sin permiso%', 'la líder de A no registra en la sede B');

select * from finish();
rollback;
