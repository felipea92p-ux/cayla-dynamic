-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 287_copiar_objetivos_no_duplica_con_doble_clic.test.sql
-- ============================================================================
-- La 0361 arregla el hallazgo 15 de la auditoría del 2026-09-03/04: dos
-- llamadas simultáneas a fn_objetivos_copiar_mes_anterior duplicaban el
-- checklist, porque las dos preguntaban «¿el mes está vacío?» antes de que
-- ninguna insertara. La carrera en sí no se puede reproducir dentro de una
-- transacción pgTAP (hace falta una segunda sesión; esa medición se hizo a
-- mano y sus cifras están en el encabezado de la 0361, bajo «MEDIDO»). Lo
-- que esta prueba SÍ fija:
--
--   · que el cuerpo vigente lleva el candado (`pg_advisory_xact_lock`) y el
--     marcador `CAMBIO 0361` — si alguien reescribe la función desde una
--     versión más vieja, esto lo delata antes de que llegue a producción;
--   · que sigue habiendo UNA sola función con ese nombre (la lección de la
--     0297/0299: dos sobrecargas conviviendo en silencio);
--   · que la copia normal sigue funcionando igual que en la 276: N ítems,
--     todos sin marcar, y el sync en objetivos_mensuales;
--   · que una segunda copia inmediata se niega con «ya tiene objetivos»;
--   · que copiar hacia un mes con UN ítem propio se niega, aunque ese ítem
--     no coincida con nada del mes anterior;
--   · y el `not exists` de defensa en profundidad, probado por la puerta que
--     lo justifica: con el `if exists` neutralizado (un ítem que ya existe
--     en el destino, insertado directo sin pasar por la RPC) el insert no
--     lo repite. Como la RPC se niega antes de llegar al insert, ese caso se
--     prueba llamando al insert equivalente a mano, no a la función.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa) values
  ('00000000-0000-0000-0000-000000287e01', 'ZZ287', 'Sede de laboratorio 287', true);

-- Admin (necesita auth_user_id contra auth.users, que no existe en esta
-- prueba: replica salta esa FK igual que el trigger de escalafón).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-000000287e03', 'DcAdmin', 'Lab', '00000000-0000-0000-0000-000000287e01', 'admin', 'x', '00000000-0000-0000-0000-000000287ee3');
set session_replication_role = origin;

-- Integrantes: A recibe la copia normal; B tiene un ítem propio en el destino.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-000000287e05', 'DcIntegranteA', 'Lab', '00000000-0000-0000-0000-000000287e01', 'x'),
  ('00000000-0000-0000-0000-000000287e06', 'DcIntegranteB', 'Lab', '00000000-0000-0000-0000-000000287e01', 'x');

-- A: ocho objetivos en agosto 2026 (el checklist típico del hallazgo), tres cumplidos.
insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden, cumplido)
select '00000000-0000-0000-0000-000000287e05', 2026, 8,
       'Objetivo ' || n, case when n % 2 = 0 then 'Indicación ' || n end, n, n <= 3
from generate_series(1, 8) as n;

-- B: dos objetivos en agosto, y UNO propio ya escrito en septiembre.
insert into objetivos_items (persona_id, anio, mes, descripcion, orden) values
  ('00000000-0000-0000-0000-000000287e06', 2026, 8, 'Ordenar el almacén', 1),
  ('00000000-0000-0000-0000-000000287e06', 2026, 8, 'Cero tardanzas', 2),
  ('00000000-0000-0000-0000-000000287e06', 2026, 9, 'Inventario de fin de temporada', 1);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000287ee3', true); -- admin

-- ── 1 · El cuerpo vigente es el de la 0361, no el de la 0348 ────────────────
select ok(
  position('pg_advisory_xact_lock' in (select prosrc from pg_proc where proname = 'fn_objetivos_copiar_mes_anterior')) > 0,
  'CUERPO · fn_objetivos_copiar_mes_anterior toma pg_advisory_xact_lock (0361)');

select ok(
  position('CAMBIO 0361' in (select prosrc from pg_proc where proname = 'fn_objetivos_copiar_mes_anterior')) > 0,
  'CUERPO · lleva el marcador CAMBIO 0361');

select is(
  (select count(*)::int from pg_proc where proname = 'fn_objetivos_copiar_mes_anterior'),
  1,
  'UNA SOLA · no hay sobrecargas de fn_objetivos_copiar_mes_anterior en pg_proc');

-- ── 2 · Copia normal: 8 ítems, todos sin marcar, sync hecho ─────────────────
select is(
  (fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-000000287e05', 2026, 9)->>'copiados')::int,
  8,
  'COPIA · agosto → septiembre de A copia los 8 objetivos');

select is(
  (select count(*)::int from objetivos_items
   where persona_id = '00000000-0000-0000-0000-000000287e05' and anio = 2026 and mes = 9),
  8,
  'COPIA · septiembre de A queda con exactamente 8 ítems, ni uno más');

select is(
  (select count(*)::int from objetivos_items
   where persona_id = '00000000-0000-0000-0000-000000287e05' and anio = 2026 and mes = 9 and cumplido),
  0,
  'COPIA · ninguno llega marcado, aunque tres de agosto lo estaban');

select is(
  (select count(*)::int from objetivos_mensuales
   where persona_id = '00000000-0000-0000-0000-000000287e05' and anio = 2026 and mes = 9),
  1,
  'SYNC · objetivos_mensuales tiene la fila de septiembre de A tras la copia');

-- ── 3 · Segunda copia inmediata: el mes ya no está vacío ────────────────────
select throws_ok(
  $$ select fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-000000287e05', 2026, 9) $$,
  'P0001',
  'Este mes ya tiene objetivos: solo se puede copiar hacia un mes vacío.',
  'DOBLE CLIC · la segunda copia se niega con el mensaje de la 0348');

select is(
  (select count(*)::int from objetivos_items
   where persona_id = '00000000-0000-0000-0000-000000287e05' and anio = 2026 and mes = 9),
  8,
  'DOBLE CLIC · y septiembre de A sigue con 8, no con 16');

-- ── 4 · Un ítem propio en el destino basta para negarse ─────────────────────
select throws_ok(
  $$ select fn_objetivos_copiar_mes_anterior('00000000-0000-0000-0000-000000287e06', 2026, 9) $$,
  'P0001',
  'Este mes ya tiene objetivos: solo se puede copiar hacia un mes vacío.',
  'NO VACÍO · B ya tiene un ítem propio en septiembre: no se copia encima');

-- ── 5 · Defensa en profundidad: el insert con `not exists` no repite lo que ya está
-- Se reproduce el insert de la 0361 a mano para B, con «Ordenar el almacén»
-- ya escrito en septiembre por otra puerta: de los dos de agosto solo debe
-- entrar «Cero tardanzas».
insert into objetivos_items (persona_id, anio, mes, descripcion, orden) values
  ('00000000-0000-0000-0000-000000287e06', 2026, 9, 'Ordenar el almacén', 7);

insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden)
select '00000000-0000-0000-0000-000000287e06', 2026, 9, src.descripcion, src.indicaciones, src.orden
from objetivos_items src
where src.persona_id = '00000000-0000-0000-0000-000000287e06' and src.anio = 2026 and src.mes = 8
  and not exists (
    select 1 from objetivos_items d
    where d.persona_id = '00000000-0000-0000-0000-000000287e06' and d.anio = 2026 and d.mes = 9
      and d.descripcion = src.descripcion
  )
order by src.orden, src.created_at
limit 20;

select is(
  (select count(*)::int from objetivos_items
   where persona_id = '00000000-0000-0000-0000-000000287e06' and anio = 2026 and mes = 9
     and descripcion = 'Ordenar el almacén'),
  1,
  'DEFENSA · «Ordenar el almacén» ya estaba en septiembre de B y el not exists no lo repite');

-- Y por la otra punta: el `not exists` no puede filtrar de más. Si estuviera
-- mal escrito (comparando contra el mes origen, por ejemplo) dejaría fuera
-- también «Cero tardanzas» y el aserto de arriba seguiría en verde.
select is(
  (select count(*)::int from objetivos_items
   where persona_id = '00000000-0000-0000-0000-000000287e06' and anio = 2026 and mes = 9),
  3,
  'DEFENSA · y «Cero tardanzas» SÍ entró: septiembre de B queda con 3 (propio + repetido + copiado)');

select * from finish();
rollback;
