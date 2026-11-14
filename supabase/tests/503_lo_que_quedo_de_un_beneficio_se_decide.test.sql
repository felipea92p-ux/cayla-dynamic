-- 503 · La decisión sobre un beneficio vencido (0618)
--
-- Lo que tiene que ser cierto: solo la dirección decide, siempre con motivo,
-- nunca antes de que la ventana venza, nunca editando lo ya escrito, y vale la
-- decisión más nueva aunque dos se escriban en la misma transacción (empate de
-- created_at: por eso se ordena por secuencia).
begin;
select plan(11);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000503a01', 'ZZ503', 'Sede de laboratorio 503', true);
set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000503a1d', 'admin-503@local'),
  ('00000000-0000-0000-0000-000000503a2d', 'lider-503@local'),
  ('00000000-0000-0000-0000-000000503a3d', 'integrante-503@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000503b14', 'Direccion', 'Admin', '00000000-0000-0000-0000-000000503a01',
   'admin', 'activo', 'x', '00000000-0000-0000-0000-000000503a1d', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000503b24', 'Lider', 'DO', '00000000-0000-0000-0000-000000503a01',
   'lider_do', 'activo', 'x', '00000000-0000-0000-0000-000000503a2d', '2024-01-01', 'planilla'),
  ('00000000-0000-0000-0000-000000503b34', 'Ana', 'Integrante', '00000000-0000-0000-0000-000000503a01',
   'integrante', 'activo', 'x', '00000000-0000-0000-0000-000000503a3d', '2024-01-01', 'planilla');
set session_replication_role = origin;

create function pg_temp.entrar(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

-- ── La líder de DO lee, pero no decide ───────────────────────────────────────
select pg_temp.entrar('00000000-0000-0000-0000-000000503a2d');
set local role authenticated;
select throws_ok(
  $$select fn_beneficio_decidir('00000000-0000-0000-0000-000000503b34', 'cts_may', 2025, 306.04, 'Se regulariza sobre lo declarado')$$,
  '42501', 'Solo la dirección puede decidir sobre un beneficio vencido.',
  'Una líder de DO no puede decidir');
reset role;

-- ── La dirección decide ──────────────────────────────────────────────────────
select pg_temp.entrar('00000000-0000-0000-0000-000000503a1d');
set local role authenticated;

select throws_ok(
  $$select fn_beneficio_decidir('00000000-0000-0000-0000-000000503b34', 'cts_may', 2025, 306.04, 'corto')$$,
  'P0001', 'Falta el motivo de la decisión (al menos 10 caracteres).',
  'Sin motivo no hay decisión');

select throws_ok(
  $$select fn_beneficio_decidir('00000000-0000-0000-0000-000000503b34', 'cts_may', 2025, -1, 'Se regulariza sobre lo declarado')$$,
  'P0001', 'El monto reconocido no puede ser negativo.',
  'Un monto negativo se rechaza');

select throws_like(
  $$select fn_beneficio_decidir('00000000-0000-0000-0000-000000503b34', 'grati_s2', 2099, 100, 'Se regulariza sobre lo declarado')$$,
  'Esa ventana todavía no vence%',
  'Una ventana que todavía no vence no se decide');

select throws_ok(
  $$select fn_beneficio_decidir('00000000-0000-0000-0000-000000503b34', 'vacaciones', 2025, 100, 'Se regulariza sobre lo declarado')$$,
  'P0001', 'Ventana desconocida: vacaciones.',
  'Vacaciones no tiene fecha común: no entra');

select lives_ok(
  $$select fn_beneficio_decidir('00000000-0000-0000-0000-000000503b34', 'cts_may', 2025, 306.04, 'Se regulariza sobre lo declarado')$$,
  'La dirección registra la decisión');
select lives_ok(
  $$select fn_beneficio_decidir('00000000-0000-0000-0000-000000503b34', 'cts_may', 2025, 0, 'Corrección: no corresponde nada en esta ventana')$$,
  'Y puede cambiarla con otra fila, incluso a cero');

-- Las dos filas nacieron en la misma transacción: created_at empata. Vale la última.
select is(
  (select monto_reconocido from fn_beneficio_decision_vigente(2025)
    where persona_id = '00000000-0000-0000-0000-000000503b34' and ventana = 'cts_may'),
  0.00::numeric, 'Vale la decisión más nueva, aunque el instante empate');

select throws_ok(
  $$insert into beneficios_decisiones (persona_id, ventana, anio, monto_reconocido, motivo)
    values ('00000000-0000-0000-0000-000000503b34', 'cts_may', 2025, 999, 'Escritura directa desde el navegador')$$,
  '42501', null, 'Nadie escribe la tabla por fuera de la función');
reset role;

-- ── La historia no se corrige, ni siquiera desde la base ─────────────────────
select throws_ok(
  $$update beneficios_decisiones set monto_reconocido = 1 where anio = 2025$$,
  'P0001', 'Una decisión sobre un beneficio no se edita ni se borra: se registra otra con su motivo.',
  'Ni la base edita una decisión ya escrita');

-- ── Una integrante no ve decisiones de nadie ─────────────────────────────────
select pg_temp.entrar('00000000-0000-0000-0000-000000503a3d');
set local role authenticated;
select is(
  (select count(*)::int from fn_beneficio_decision_vigente(2025)), 0,
  'Una integrante no ve ninguna decisión');
reset role;

select * from finish();
rollback;
