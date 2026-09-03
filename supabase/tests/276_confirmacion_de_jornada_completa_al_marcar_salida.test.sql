-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 276_confirmacion_de_jornada_completa_al_marcar_salida.test.sql
-- ============================================================================
-- Cubre la 0350: el nuevo parámetro `p_confirmo_sin_refrigerio` de
-- fn_registrar_marcaje se guarda tal cual en la columna nueva, y —lo que de
-- verdad importa de agregar un parámetro a una función con 7 versiones
-- anteriores— un llamador que NO lo manda (Correcciones, cualquier código que
-- siga con la firma vieja) sigue funcionando exactamente igual que antes.
-- ============================================================================
begin;
select plan(4);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000027601', 'ZZREF', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into auth.users (id, email)
values ('00000000-0000-0000-0000-000000027602', 'terminal-ref@local');
set session_replication_role = origin;

insert into terminales (id, sede_id, nombre_dispositivo, activo, auth_user_id)
values ('00000000-0000-0000-0000-000000027603', '00000000-0000-0000-0000-000000027601',
        'Terminal de laboratorio', true, '00000000-0000-0000-0000-000000027602');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  ('00000000-0000-0000-0000-000000027604', 'RefCorrido', 'Lab', '00000000-0000-0000-0000-000000027601', 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000027605', 'RefSinPreguntar', 'Lab', '00000000-0000-0000-0000-000000027601', 'x', '2024-01-01');

-- ── 1 · Un llamador viejo (8 argumentos, sin el nuevo) sigue funcionando ────
-- Esto es lo que hace hoy Correcciones, y lo que hacían las 7 versiones
-- anteriores de esta función. Si el `drop function` + `create` de la 0350 se
-- hubiera equivocado de firma, esta llamada fallaría con "function ... does
-- not exist" o "is not unique".
select lives_ok(
  $$select fn_registrar_marcaje(
      '00000000-0000-0000-0000-000000027605', 'entrada',
      timestamptz '2026-08-10 09:00-05:00', gen_random_uuid(),
      'terminal', '00000000-0000-0000-0000-000000027603',
      '00000000-0000-0000-0000-000000027601', null)
  $$,
  'un llamador con la firma de 8 argumentos (Correcciones, versiones previas) sigue funcionando'
);

-- Y sin que nadie le pida la confirmación, la columna nueva queda en null —no
-- en false—: null significa "nunca se le preguntó", no "dijo que no".
select is(
  (select confirmo_sin_refrigerio from marcajes
    where persona_id = '00000000-0000-0000-0000-000000027605' and tipo = 'entrada'),
  null,
  'sin el parámetro nuevo, la columna queda en null (nunca se preguntó), no en false'
);

-- ── 2 · El terminal SÍ pregunta, y la respuesta queda en el propio marcaje ──
-- Entrada y directo a salida_final, SIN pasar por salida_almuerzo: es la
-- única ambigüedad alcanzable en vivo (ver encabezado — el candado ya obliga
-- a marcar retorno_almuerzo antes de nada más, así que "salida sin retorno"
-- nunca llega a esta función viniendo del terminal).
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000027604', 'entrada',
  timestamptz '2026-08-10 09:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000027603',
  '00000000-0000-0000-0000-000000027601', null);
select fn_registrar_marcaje(
  '00000000-0000-0000-0000-000000027604', 'salida_final',
  timestamptz '2026-08-10 20:00-05:00', gen_random_uuid(),
  'terminal', '00000000-0000-0000-0000-000000027603',
  '00000000-0000-0000-0000-000000027601', null, true);

select is(
  (select confirmo_sin_refrigerio from marcajes
    where persona_id = '00000000-0000-0000-0000-000000027604' and tipo = 'salida_final'),
  true,
  'cuando el terminal pregunta y la persona confirma, la respuesta queda en su propio marcaje de salida_final'
);

-- La respuesta no se sale de su fila: la entrada del mismo día sigue en null.
select is(
  (select confirmo_sin_refrigerio from marcajes
    where persona_id = '00000000-0000-0000-0000-000000027604' and tipo = 'entrada'),
  null,
  'la confirmación es del marcaje de salida_final, no se filtra a los demás marcajes del día'
);

select * from finish();
rollback;
