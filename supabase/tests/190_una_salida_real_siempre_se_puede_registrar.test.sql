-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 190_una_salida_real_siempre_se_puede_registrar.test.sql
-- ============================================================================
-- Un día con las pausas descuadradas —basta una corrección con la hora mal
-- tecleada— hacía que la resta (salida − entrada) − ausencia diera negativo.
-- `chk_horas_no_negativas` lo rechazaba, y como el insert de la jornada cuelga
-- del trigger de `marcajes`, la excepción se llevaba por delante EL MARCAJE.
-- Efecto real: esa persona NO PODÍA MARCAR SU SALIDA. El terminal se la seguía
-- ofreciendo toda la noche y cada intento acababa apartado en la cola.
--
-- Esto fija las cuatro mitades del arreglo de la 0249: que la marca entra, que
-- las horas quedan en null y no en cero, que el día se sella para revisión en
-- vez de pagarse callado, y que un día normal no se entera de nada.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000001a1', 'ZZNEG', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-0000000001a9', 'terminal-neg@local');
set session_replication_role = origin;

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-0000000001a2', '00000000-0000-0000-0000-0000000001a1',
        'Terminal de laboratorio', true, '00000000-0000-0000-0000-0000000001a9');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000001a3', 'DiaImposible', 'Lab',
        '00000000-0000-0000-0000-0000000001a1', 'x', '2024-01-01'),
       ('00000000-0000-0000-0000-0000000001a4', 'DiaNormal', 'Lab',
        '00000000-0000-0000-0000-0000000001a1', 'x', '2024-01-01');

-- ── El día imposible ────────────────────────────────────────────────────────
-- El retorno del almuerzo quedó a las 23:30 en vez de las 13:30: la ausencia
-- (14 h) pasa a ser mayor que el tramo entrado–salido (11 h).
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen) values
  ('00000000-0000-0000-0000-0000000001b1', '00000000-0000-0000-0000-0000000001a3',
   '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000001a2',
   'entrada',          timestamptz '2026-08-10 09:00-05:00', 'terminal'),
  ('00000000-0000-0000-0000-0000000001b2', '00000000-0000-0000-0000-0000000001a3',
   '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000001a2',
   'salida_almuerzo',  timestamptz '2026-08-10 09:30-05:00', 'terminal'),
  ('00000000-0000-0000-0000-0000000001b3', '00000000-0000-0000-0000-0000000001a3',
   '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000001a2',
   'retorno_almuerzo', timestamptz '2026-08-10 23:30-05:00', 'admin_correccion');

-- 1 · La salida entra. Antes de la 0249 esto lanzaba
--     «new row for relation "jornadas" violates check constraint».
select lives_ok(
  $$select fn_registrar_marcaje(
      '00000000-0000-0000-0000-0000000001a3', 'salida_final',
      timestamptz '2026-08-10 20:00-05:00',
      '00000000-0000-0000-0000-0000000001b4', 'terminal',
      '00000000-0000-0000-0000-0000000001a2')$$,
  'la salida de un día imposible SE REGISTRA en vez de rebotar');

-- 2 · Y queda de verdad guardada, no solo «sin error».
select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-0000000001a3' and tipo = 'salida_final'),
  1,
  'la marca de salida existe en marcajes');

-- 3 · Las horas quedan en NULL: «no se sabe cuánto», no «trabajó cero».
select is(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-0000000001a3' and fecha = '2026-08-10'),
  null::numeric,
  'un día imposible guarda null, nunca un negativo ni un cero inventado');

-- 4 · Y no se queda callado: la planilla lee coalesce(horas, 0), así que sin
--     este sello el día se pagaría como cero sin que nadie lo mirara.
select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-0000000001a3'
      and estado_revision = 'pendiente_revision'),
  4,
  'las cuatro marcas del día imposible quedan selladas para revisión');

-- ── Un día normal, que no debe enterarse de nada ────────────────────────────
insert into marcajes (client_uuid, persona_id, sede_id, terminal_id, tipo, timestamp_marca, origen) values
  ('00000000-0000-0000-0000-0000000001c1', '00000000-0000-0000-0000-0000000001a4',
   '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000001a2',
   'entrada',          timestamptz '2026-08-10 09:00-05:00', 'terminal'),
  ('00000000-0000-0000-0000-0000000001c2', '00000000-0000-0000-0000-0000000001a4',
   '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000001a2',
   'salida_almuerzo',  timestamptz '2026-08-10 13:00-05:00', 'terminal'),
  ('00000000-0000-0000-0000-0000000001c3', '00000000-0000-0000-0000-0000000001a4',
   '00000000-0000-0000-0000-0000000001a1', '00000000-0000-0000-0000-0000000001a2',
   'retorno_almuerzo', timestamptz '2026-08-10 14:00-05:00', 'terminal');

select fn_registrar_marcaje(
  '00000000-0000-0000-0000-0000000001a4', 'salida_final',
  timestamptz '2026-08-10 19:00-05:00',
  '00000000-0000-0000-0000-0000000001c4', 'terminal',
  '00000000-0000-0000-0000-0000000001a2');

-- 5 · 10 h de tramo menos 1 h de almuerzo = 9 h. El número de siempre.
select is(
  (select horas_trabajadas from jornadas
    where persona_id = '00000000-0000-0000-0000-0000000001a4' and fecha = '2026-08-10'),
  9.00::numeric,
  'un día normal sigue dando exactamente las mismas horas');

-- 6 · Y ninguna de sus marcas se sella por contagio.
select is(
  (select count(*)::int from marcajes
    where persona_id = '00000000-0000-0000-0000-0000000001a4'
      and estado_revision <> 'normal'),
  0,
  'un día normal no queda sellado');

-- 7 · El candado de la 0095 sigue puesto. La 0249 no lo levanta: sigue siendo
--     imposible guardar un día con horas negativas; lo que cambia es que ahora
--     nadie intenta guardarlo.
select ok(
  exists (select 1 from pg_constraint
           where conname = 'chk_horas_no_negativas'
             and conrelid = 'jornadas'::regclass),
  'chk_horas_no_negativas sigue existiendo');

select * from finish();
rollback;
