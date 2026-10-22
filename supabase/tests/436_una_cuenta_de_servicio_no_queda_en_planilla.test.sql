-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 436_una_cuenta_de_servicio_no_queda_en_planilla.test.sql — 0544
-- ============================================================================
-- Defiende la 0544. Hasta ella una estación de retail nacía con los defaults de
-- la tabla —vínculo `planilla`, en planilla— y solo después se marcaba como
-- cuenta de servicio; la marca no tocaba el vínculo. El 2026-10-21 «ESTACIÓN —
-- Producción» apareció como una persona a asegurar en el Seguro de Vida Ley
-- (21 «a cubrir» cuando eran 20 personas).
--
--   1 · EL ALTA de una estación (fn_crear_persona con p_es_estacion) nace
--       `no_trabajador`, y una persona normal NO cambia.
--   2 · LA FICHA: marcar a alguien que ya existe también le deja el vínculo en
--       `no_trabajador` —las dos entradas pasan por la misma puerta—.
--   3 · LOS BORDES: una practicante pierde su modalidad (la regla de
--       fn_set_tipo_vinculo), quien ya es `no_trabajador` no ensucia el rastro,
--       una ficha cesada con otro vínculo se niega, y una negativa de las de
--       siempre no deja el vínculo a medio cambiar.
--   4 · DESMARCAR NO devuelve el vínculo: se decide en Equipo.
--
-- Todos los nombres son inventados.
-- ============================================================================
begin;
select plan(23);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000054400', 'ZZ544', 'Sede de laboratorio 544', true);

set session_replication_role = replica;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000005441a', 'admin-544@local');
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, auth_user_id, fecha_ingreso,
                      tipo_vinculo, practicante_modalidad) values
  -- quien marca
  ('00000000-0000-0000-0000-000000054411', 'Admin', 'Cincocuatrocuatro', '00000000-0000-0000-0000-000000054400',
   'admin', 'activo', 'x', '00000000-0000-0000-0000-00000005441a', '2024-01-01', 'planilla', null),
  -- P1 · una ficha de planilla que se marca desde la ficha
  ('00000000-0000-0000-0000-000000054412', 'Ficha', 'DePlanilla', '00000000-0000-0000-0000-000000054400',
   'integrante', 'activo', 'x', null, '2026-09-01', 'planilla', null),
  -- P2 · una practicante (la modalidad cuelga del vínculo)
  ('00000000-0000-0000-0000-000000054413', 'Practica', 'Marcada', '00000000-0000-0000-0000-000000054400',
   'integrante', 'activo', 'x', null, '2026-09-01', 'practicante', 'profesional'),
  -- P3 · ya es no_trabajador, como las seis estaciones que se corrigieron a mano
  ('00000000-0000-0000-0000-000000054414', 'ESTACIÓN —', 'Vieja Lab (no es persona)', '00000000-0000-0000-0000-000000054400',
   'integrante', 'activo', 'x', null, '2026-06-01', 'no_trabajador', null),
  -- P6 · trabaja de verdad: tiene una jornada
  ('00000000-0000-0000-0000-000000054416', 'Marcela', 'Trabaja', '00000000-0000-0000-0000-000000054400',
   'integrante', 'activo', 'x', null, '2026-01-01', 'planilla', null);
insert into personas (id, nombres, apellidos, sede_base_id, rol, estado, pin_hash, fecha_ingreso, fecha_cese,
                      motivo_cese, tipo_vinculo) values
  -- P4 · cesada con vínculo de planilla: su liquidación se calculó con él
  ('00000000-0000-0000-0000-000000054417', 'Ya', 'SalioPlanilla', '00000000-0000-0000-0000-000000054400',
   'integrante', 'inactivo', 'x', '2025-01-01', '2026-03-31', 'renuncia', 'planilla'),
  -- P5 · cesada pero ya no_trabajador: una estación retirada
  ('00000000-0000-0000-0000-000000054418', 'ESTACIÓN —', 'Retirada Lab (no es persona)', '00000000-0000-0000-0000-000000054400',
   'integrante', 'inactivo', 'x', '2025-01-01', '2026-03-31', 'renuncia', 'no_trabajador');
insert into jornadas (persona_id, fecha) values ('00000000-0000-0000-0000-000000054416', '2026-09-10');
set session_replication_role = origin;

-- ── 1 · EL ALTA ────────────────────────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000005441a', true);
set role authenticated;
select lives_ok(
  $$ select fn_crear_persona('ESTACIÓN — Caja 544', '(no es persona)', '00000000-0000-0000-0000-000000054400',
                             'integrante', 'calidad_servicio', null, 'x', true, null, null, true) $$,
  'ALTA · la estación entra (confirma que no es la «Vieja Lab» del fixture: el alta avisa de nombres parecidos)');
select lives_ok(
  $$ select fn_crear_persona('Persona', 'Normal544', '00000000-0000-0000-0000-000000054400',
                             'integrante', 'calidad_servicio', null, 'x', false, 'dni', '54400001') $$,
  'ALTA · y una persona normal también');
reset role;

select is(
  (select p.tipo_vinculo || ' · ' || p.en_planilla::text || ' · ' || p.cuenta_de_servicio::text
     from personas p where p.nombres = 'ESTACIÓN — Caja 544'),
  'no_trabajador · false · true',
  'ALTA · la estación nace no_trabajador, fuera de planilla y marcada: ya no hace falta que alguien la cambie a mano');
select is(
  (select count(*)::int from correcciones_auditoria a join personas p on p.id = a.persona_id
    where p.nombres = 'ESTACIÓN — Caja 544' and a.campo_modificado = 'personas.tipo_vinculo'
      and a.valor_anterior = 'planilla' and a.valor_nuevo = 'no_trabajador'
      and a.corregido_por = '00000000-0000-0000-0000-000000054411'),
  1,
  'RASTRO · el cambio de vínculo quedó, firmado por quien dio el alta, por la puerta del vínculo');
select is(
  (select p.tipo_vinculo || ' · ' || p.en_planilla::text || ' · ' || p.cuenta_de_servicio::text
     from personas p where p.apellidos = 'Normal544'),
  'planilla · true · false',
  'CONTROL · una persona normal sigue naciendo en planilla: lo nuevo solo toca a las estaciones');

-- ── 2 · LA FICHA: marcar a alguien que ya existe ───────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000005441a', true);
set role authenticated;
select lives_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000054412', true) $$,
  'FICHA · se marca a una ficha de planilla que ya existía');
reset role;
select is(
  (select tipo_vinculo || ' · ' || en_planilla::text || ' · ' || cuenta_de_servicio::text
     from personas where id = '00000000-0000-0000-0000-000000054412'),
  'no_trabajador · false · true',
  'FICHA · el vínculo pasó a no_trabajador en la misma operación: la otra entrada tenía el mismo defecto');
select is(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000054412'
      and campo_modificado = 'personas.cuenta_de_servicio' and valor_nuevo = 'true'),
  'Marcada como cuenta de servicio: su vínculo pasa a «Sin vínculo laboral» y sale de la planilla y de las listas del equipo.',
  'RASTRO · el texto del marcado dice que el vínculo también cambió');

-- ── 3 · LOS BORDES ─────────────────────────────────────────────────────────
set role authenticated;
select lives_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000054413', true) $$,
  'PRACTICANTE · se marca');
reset role;
select is(
  (select tipo_vinculo || ' · ' || coalesce(practicante_modalidad, 'sin modalidad')
     from personas where id = '00000000-0000-0000-0000-000000054413'),
  'no_trabajador · sin modalidad',
  'PRACTICANTE · pierde la modalidad, porque el vínculo cambió por fn_set_tipo_vinculo y no por un update suelto (si no, el CHECK de coherencia la rechazaría)');

set role authenticated;
select lives_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000054414', true) $$,
  'YA NO TRABAJADOR · se marca igual (las seis estaciones que se corrigieron a mano)');
reset role;
select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000054414' and campo_modificado = 'personas.tipo_vinculo'),
  0,
  'YA NO TRABAJADOR · no se escribe un rastro de vínculo para un cambio que no ocurrió');

set role authenticated;
select throws_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000054417', true) $$,
  'Esta ficha ya está cesada y su vínculo no es «Sin vínculo laboral»: su liquidación se calculó con ese vínculo, así que no se puede marcar como cuenta de servicio.',
  'CESADA · con vínculo de planilla se niega, y con palabras de esta pantalla');
reset role;
select is(
  (select tipo_vinculo || ' · ' || cuenta_de_servicio::text
     from personas where id = '00000000-0000-0000-0000-000000054417'),
  'planilla · false',
  'CESADA · la negativa no dejó nada a medias: ni marca ni vínculo cambiado');

set role authenticated;
select lives_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000054418', true) $$,
  'CESADA · una estación retirada que ya era no_trabajador sí se marca');
select throws_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000054416', true) $$,
  'Esta ficha tiene marcajes: alguien trabajó con ella. Una cuenta de servicio no marca asistencia, y marcarla así la sacaría de la planilla.',
  'MARCAJES · a quien trabaja se le sigue negando');
reset role;
select is(
  (select tipo_vinculo || ' · ' || cuenta_de_servicio::text
     from personas where id = '00000000-0000-0000-0000-000000054416'),
  'planilla · false',
  'MARCAJES · y sigue cobrando: la negativa llega ANTES de tocar el vínculo');

select is(
  (select count(*)::int from personas
    where sede_base_id = '00000000-0000-0000-0000-000000054400' and cuenta_de_servicio and en_planilla),
  0,
  'LA CONSULTA DE VIDA LEY · ninguna cuenta de servicio de esta sede figura en planilla: el 21 contra 20 no se repite');

-- ── 4 · DESMARCAR NO DEVUELVE EL VÍNCULO ───────────────────────────────────
set role authenticated;
select lives_ok(
  $$ select fn_set_cuenta_de_servicio('00000000-0000-0000-0000-000000054412', false) $$,
  'DESMARCAR · se puede, como siempre');
reset role;
select is(
  (select tipo_vinculo || ' · ' || en_planilla::text || ' · ' || cuenta_de_servicio::text
     from personas where id = '00000000-0000-0000-0000-000000054412'),
  'no_trabajador · false · false',
  'DESMARCAR · deja de ser cuenta de servicio pero el vínculo NO vuelve solo: no hay de dónde saber si era planilla, prueba u honorarios');
select is(
  (select motivo from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000054412'
      and campo_modificado = 'personas.cuenta_de_servicio' and valor_nuevo = 'false'),
  'Deja de ser cuenta de servicio: vuelve a las listas del equipo. Su vínculo no cambia: se decide en Equipo.',
  'RASTRO · el texto de desmarcar ya no promete «vuelve a la planilla»');

-- ── 5 · LA FORMA DE LA FUNCIÓN ─────────────────────────────────────────────
select ok(
  (select count(*) = 1 and bool_and(prosrc like '%CAMBIO 0544%') from pg_proc
    where proname = 'fn_set_cuenta_de_servicio' and pronamespace = 'public'::regnamespace)
  and not has_function_privilege('anon', 'fn_set_cuenta_de_servicio(uuid,boolean,text)', 'execute')
  and has_function_privilege('authenticated', 'fn_set_cuenta_de_servicio(uuid,boolean,text)', 'execute'),
  'FIRMA · una sola versión, la nueva; anon no la ejecuta y authenticated sí');
select is(
  (select nombre from migraciones_aplicadas where numero = 544),
  'una_cuenta_de_servicio_no_queda_en_planilla',
  'REGISTRO · la 544 es esta migración');

select * from finish();
rollback;
