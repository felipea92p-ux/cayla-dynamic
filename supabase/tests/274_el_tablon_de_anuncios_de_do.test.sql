-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 274_el_tablon_de_anuncios_de_do.test.sql — la 0348 de punta a punta
-- ============================================================================
-- Lo que hay que proteger acá no es que se pueda insertar una fila: es que
-- (a) solo DO publica y anula — ni la encargada de sede ni una integrante
-- pueden hablar en nombre de la empresa a las cuatro sedes, (b) un anuncio
-- dirigido a una sede no se filtra a otra, (c) anular no es un DELETE —el
-- anuncio sigue existiendo, solo deja de ser vigente— y no se puede anular
-- dos veces, y (d) marcar como leído es idempotente y cuenta bien.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000ea901', 'ZZA01', 'Sede anuncios uno', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000ea902', 'ZZA02', 'Sede anuncios dos', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso) values
  ('00000000-0000-0000-0000-0000000eaa01', 'AnuAdmin', 'Lab',
   '00000000-0000-0000-0000-0000000ea901', 'admin', 'x',
   '00000000-0000-0000-0000-0000000eab01', '2023-01-01'),
  ('00000000-0000-0000-0000-0000000eaa02', 'AnuEncargada', 'Lab',
   '00000000-0000-0000-0000-0000000ea901', 'supervisor_sede', 'x',
   '00000000-0000-0000-0000-0000000eab02', '2023-01-01'),
  -- En la sede uno: debe ver los anuncios generales y los dirigidos a su sede.
  ('00000000-0000-0000-0000-0000000eaa03', 'AnuUno', 'Lab',
   '00000000-0000-0000-0000-0000000ea901', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000eab03', '2023-01-01'),
  -- En la sede dos: no debe ver un anuncio dirigido solo a la sede uno.
  ('00000000-0000-0000-0000-0000000eaa04', 'AnuDos', 'Lab',
   '00000000-0000-0000-0000-0000000ea902', 'integrante', 'x',
   '00000000-0000-0000-0000-0000000eab04', '2023-01-01');
set session_replication_role = origin;

-- ── Solo DO publica ──────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab02', true);

select throws_ok(
  $$ select fn_publicar_anuncio('Feriado el lunes', 'Recuerden que el lunes no hay atención.', null) $$,
  'Solo un administrador o líder de Desarrollo Organizacional puede publicar un anuncio.',
  'la encargada de sede no puede publicar un anuncio'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab03', true);

select throws_ok(
  $$ select fn_publicar_anuncio('Feriado el lunes', 'Recuerden que el lunes no hay atención.', null) $$,
  'Solo un administrador o líder de Desarrollo Organizacional puede publicar un anuncio.',
  'una integrante no puede publicar un anuncio'
);

-- ── Validaciones de forma ────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab01', true);

select throws_ok(
  $$ select fn_publicar_anuncio('   ', 'algo', null) $$,
  'El anuncio necesita un título.',
  'no se puede publicar sin título'
);

select throws_ok(
  $$ select fn_publicar_anuncio('Título', '  ', null) $$,
  'El anuncio necesita un cuerpo.',
  'no se puede publicar sin cuerpo'
);

-- ── DO publica uno general y uno dirigido a la sede uno ─────────────────
select lives_ok(
  $$ select fn_publicar_anuncio('Cierre de planilla', 'La planilla de este mes cierra el 28.', null) $$,
  'DO publica un anuncio para las cuatro sedes'
);

select lives_ok(
  format($$ select fn_publicar_anuncio('Horario especial', 'Solo para esta sede.', %L) $$,
         '00000000-0000-0000-0000-0000000ea901'),
  'DO publica un anuncio dirigido solo a la sede uno'
);

-- ── Quien está en la sede uno ve los dos ─────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab03', true);

select is(
  (select count(*)::int from fn_anuncios_vigentes(false)),
  2,
  'alguien de la sede uno ve el anuncio general y el dirigido a su sede'
);

-- ── Quien está en la sede dos solo ve el general ─────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab04', true);

select is(
  (select count(*)::int from fn_anuncios_vigentes(false)),
  1,
  'alguien de la sede dos NO ve el anuncio dirigido a la sede uno'
);

select is(
  (select titulo from fn_anuncios_vigentes(false) limit 1),
  'Cierre de planilla',
  'y lo único que ve es el anuncio general'
);

-- Y tampoco por la vía directa a la tabla — la RLS corta igual, no solo la RPC.
set local role authenticated;
select is(
  (select count(*)::int from anuncios where sede_id = '00000000-0000-0000-0000-0000000ea901'),
  0,
  'la RLS de la tabla, no solo la función, también lo filtra'
);
reset role;

-- ── Marcar como leído: idempotente ───────────────────────────────────────
select lives_ok(
  format($$ select fn_marcar_anuncio_leido(%L) $$,
         (select id from anuncios where titulo = 'Cierre de planilla')),
  'AnuDos marca el anuncio general como leído'
);
select lives_ok(
  format($$ select fn_marcar_anuncio_leido(%L) $$,
         (select id from anuncios where titulo = 'Cierre de planilla')),
  'marcarlo leído dos veces no falla'
);
select is(
  (select count(*)::int from anuncios_leidos where anuncio_id = (select id from anuncios where titulo = 'Cierre de planilla')),
  1,
  'y no queda duplicado: sigue siendo una sola fila'
);

select is(
  (select mi_leido_at is not null from fn_anuncios_vigentes(false) where titulo = 'Cierre de planilla'),
  true,
  'y la propia lista ya lo refleja como leído'
);

-- ── Anular: solo DO, y no dos veces ──────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab02', true);

select throws_ok(
  format($$ select fn_anular_anuncio(%L) $$,
         (select id from anuncios where titulo = 'Cierre de planilla')),
  'Solo un administrador o líder de Desarrollo Organizacional puede anular un anuncio.',
  'la encargada de sede no puede anular un anuncio'
);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab01', true);

select lives_ok(
  format($$ select fn_anular_anuncio(%L) $$,
         (select id from anuncios where titulo = 'Cierre de planilla')),
  'DO anula el anuncio general'
);

select throws_ok(
  format($$ select fn_anular_anuncio(%L) $$,
         (select id from anuncios where titulo = 'Cierre de planilla')),
  'Ese anuncio no existe o ya estaba anulado.',
  'no se puede anular dos veces el mismo anuncio'
);

-- Anular no borra: sigue existiendo, solo deja de ser vigente para quien no es DO.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000eab04', true);
select is(
  (select count(*)::int from fn_anuncios_vigentes(false)),
  0,
  'una vez anulado, deja de contar como vigente para el equipo'
);

select * from finish();
rollback;
