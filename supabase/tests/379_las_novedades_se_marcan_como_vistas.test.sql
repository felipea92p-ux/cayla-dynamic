-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 379_las_novedades_se_marcan_como_vistas.test.sql — la 0480 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) cada persona solo ve y solo escribe SUS marcas —una integrante no lee lo
-- que entendió otra—, (b) marcar dos veces no falla ni CORRE la fecha de la
-- primera vez, (c) un id sin forma de id no entra ni por la función ni por un
-- insert directo, y (d) nada se escribe sin pasar por la función.
-- ============================================================================
begin;
select plan(19);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000ec901', 'ZZN01', 'Sede novedades uno', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000eca01', 'NovUno', 'Lab',
   '00000000-0000-0000-0000-0000000ec901', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000ecb01', '2023-01-01'),
  ('00000000-0000-0000-0000-0000000eca02', 'NovDos', 'Lab',
   '00000000-0000-0000-0000-0000000ec901', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000ecb02', '2023-01-01');
set session_replication_role = origin;

-- ── Marcar, y que quede una sola vez ─────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ecb01', true);

select lives_ok(
  $$ select fn_marcar_novedad_vista('2026-09-19-anuncios-cuenta-que-mejora') $$,
  'una integrante puede marcar como entendida una novedad'
);

select is(
  (select count(*)::int from novedades_vistas
    where persona_id = '00000000-0000-0000-0000-0000000eca01'),
  1,
  'la marca quedó, una sola'
);

-- La fecha de la PRIMERA vez se conserva. Dentro de una transacción `now()` no
-- cambia, así que sin envejecer la marca a mano esta prueba pasaría aunque la
-- función hiciera `do update set visto_at = now()`.
update novedades_vistas set visto_at = '2020-01-01 00:00:00+00'
 where persona_id = '00000000-0000-0000-0000-0000000eca01';

select lives_ok(
  $$ select fn_marcar_novedad_vista('2026-09-19-anuncios-cuenta-que-mejora') $$,
  'marcar la misma novedad otra vez no falla'
);

select is(
  (select visto_at from novedades_vistas
    where persona_id = '00000000-0000-0000-0000-0000000eca01'),
  '2020-01-01 00:00:00+00'::timestamptz,
  'y no corre la fecha de la primera vez'
);

select is(
  (select count(*)::int from novedades_vistas
    where persona_id = '00000000-0000-0000-0000-0000000eca01'),
  1,
  'marcarla dos veces sigue siendo una sola fila'
);

-- ── Cada quien ve lo suyo, y nada más ────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ecb02', true);
set local role authenticated;

select is(
  (select count(*)::int from novedades_vistas),
  0,
  'otra integrante no ve las marcas de la primera (RLS, no solo la función)'
);

select throws_ok(
  $$ insert into novedades_vistas (persona_id, novedad_id)
     values ('00000000-0000-0000-0000-0000000eca02', '2026-09-19-anuncios-cuenta-que-mejora') $$,
  '42501',
  null,
  'no se escribe por insert directo: solo por la función'
);

reset role;

-- ── Ni siquiera la dueña de la marca escribe a mano ──────────────────────
-- Supabase le concede a `authenticated` escritura sobre toda tabla nueva de
-- `public`; la migración la revoca. Sin ese `revoke`, un update o un delete no
-- dan error: RLS los deja en cero filas y la prueba lo tomaría por bueno. Y
-- `truncate` no pasa por RLS, así que solo el permiso lo detiene.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ecb01', true);
set local role authenticated;

select throws_ok(
  $$ update novedades_vistas set visto_at = now() $$,
  '42501',
  null,
  'la dueña no actualiza su marca a mano'
);

select throws_ok(
  $$ delete from novedades_vistas $$,
  '42501',
  null,
  'la dueña no borra su marca a mano'
);

select throws_ok(
  $$ truncate novedades_vistas $$,
  '42501',
  null,
  'nadie vacía la tabla: truncate no pasa por RLS, solo lo detiene el permiso'
);

reset role;

select is(
  (select count(*)::int from novedades_vistas
    where persona_id = '00000000-0000-0000-0000-0000000eca01'),
  1,
  'y la marca sigue ahí'
);

-- ── Un id sin forma de id no entra ───────────────────────────────────────
select throws_ok(
  $$ select fn_marcar_novedad_vista('Sin-Fecha-Ni-Minusculas') $$,
  '23514',
  null,
  'un id sin fecha y con mayúsculas no entra'
);

select throws_ok(
  $$ select fn_marcar_novedad_vista('') $$,
  '23514',
  null,
  'un id vacío no entra'
);

select throws_ok(
  $$ select fn_marcar_novedad_vista('2026-09-19-' || repeat('a', 100)) $$,
  '23514',
  null,
  'un id de más de 100 caracteres no entra'
);

select throws_ok(
  $$ select fn_marcar_novedad_vista('2026-09-19-con espacios') $$,
  '23514',
  null,
  'un id con espacios no entra'
);

-- ── Sin ficha y sin sesión ───────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ecb99', true);

select throws_ok(
  $$ select fn_marcar_novedad_vista('2026-09-19-anuncios-cuenta-que-mejora') $$,
  'Tu cuenta todavía no está enlazada con tu ficha.',
  'una cuenta sin ficha no marca nada, y el mensaje dice por qué'
);

set local role anon;
select throws_ok(
  $$ select fn_marcar_novedad_vista('2026-09-19-anuncios-cuenta-que-mejora') $$,
  '42501',
  null,
  'sin sesión (anon) no se puede ni ejecutar la función'
);
reset role;

-- ── La tabla no queda abierta ────────────────────────────────────────────
select is(
  (select relrowsecurity from pg_class where oid = 'novedades_vistas'::regclass),
  true,
  'la tabla tiene RLS encendida'
);

select throws_ok(
  $$ insert into novedades_vistas (persona_id, novedad_id)
     values ('00000000-0000-0000-0000-0000000ecfff', '2026-09-19-anuncios-cuenta-que-mejora') $$,
  '23503',
  null,
  'una marca sin persona real no existe (llave foránea)'
);

select * from finish();
rollback;
