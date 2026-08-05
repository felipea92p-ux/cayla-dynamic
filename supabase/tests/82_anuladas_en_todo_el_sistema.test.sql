-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 82_anuladas_en_todo_el_sistema.test.sql — Que nadie cuente una marca anulada
-- ============================================================================
-- La 0081 enseñó a fn_recalcular_jornada a ignorar las marcas anuladas, pero
-- otras seis funciones seguían contándolas. Esto prueba que ya no.
--
-- El fallo que evita cada una, en la vida real de una tienda:
--   · Se anula por error la entrada de alguien → si el terminal no se entera,
--     esa persona no puede volver a marcar su entrada en toda la mañana.
--   · Se arregla un día anulando las marcas que sobraban → si el detector de
--     secuencias no se entera, el día sigue en rojo para siempre.
--   · Se anula la primera marca histórica de alguien → su fecha de ingreso
--     cambia, y de ahí cuelgan sus vacaciones y su CTS.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000fc', 'ZZSIS', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id) values
  ('00000000-0000-0000-0000-0000000000d0', 'PruebaAdminS', 'Laboratorio', '00000000-0000-0000-0000-0000000000fc', 'admin', 'test-hash', '00000000-0000-0000-0000-0000000000e0');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash) values
  ('00000000-0000-0000-0000-0000000000d1', 'PruebaTerm', 'Laboratorio', '00000000-0000-0000-0000-0000000000fc', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000d2', 'PruebaSello', 'Laboratorio', '00000000-0000-0000-0000-0000000000fc', 'test-hash'),
  ('00000000-0000-0000-0000-0000000000d3', 'PruebaIngr', 'Laboratorio', '00000000-0000-0000-0000-0000000000fc', 'test-hash');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e0', true);

-- ── El terminal: con la entrada anulada, vuelve a tocar marcar entrada ───────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0003-000000000001', gen_random_uuid(), '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000fc', 'entrada', '2026-07-22T09:00:00-05:00');

select isnt((select fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000d1', '2026-07-22')::text),
            'entrada', 'TERM · con su entrada puesta, el terminal ya no espera otra entrada');

select fn_anular_marcaje('00000000-0000-0000-0003-000000000001', 'Se marcó a la persona equivocada');

select is((select fn_siguiente_tipo_esperado('00000000-0000-0000-0000-0000000000d1', '2026-07-22')::text),
          'entrada', 'TERM · anulada la entrada, el terminal vuelve a esperar una entrada — la persona puede marcar');

select is((select count(*)::int from jornadas where persona_id='00000000-0000-0000-0000-0000000000d1' and fecha='2026-07-22'),
          0, 'TERM · sin marcas vivas, el día no deja jornada');

-- ── El sello de día imposible se levanta al anular lo que sobraba ────────────
-- Dos "salida a almuerzo" seguidas sin retorno entre medio: secuencia imposible.
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0003-000000000011', gen_random_uuid(), '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000fc', 'entrada',         '2026-07-23T09:00:00-05:00'),
  ('00000000-0000-0000-0003-000000000012', gen_random_uuid(), '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000fc', 'salida_almuerzo', '2026-07-23T13:00:00-05:00'),
  ('00000000-0000-0000-0003-000000000013', gen_random_uuid(), '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000fc', 'salida_almuerzo', '2026-07-23T17:00:00-05:00');

select is((select fn_dia_incoherente('00000000-0000-0000-0000-0000000000d2', '2026-07-23')),
          true, 'SELLO · dos salidas seguidas sin retorno: el día está sellado, como debe');

select fn_anular_marcaje('00000000-0000-0000-0003-000000000013', 'Marca duplicada que llegó tarde de la cola sin conexión');

select is((select fn_dia_incoherente('00000000-0000-0000-0000-0000000000d2', '2026-07-23')),
          false, 'SELLO · anulada la marca que sobraba, el sello se levanta: el día quedó resuelto');

-- ── La fecha de ingreso no la fija una marca anulada ─────────────────────────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  ('00000000-0000-0000-0003-000000000021', gen_random_uuid(), '00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000fc', 'entrada', '2026-03-02T09:00:00-05:00'),
  ('00000000-0000-0000-0003-000000000022', gen_random_uuid(), '00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000fc', 'entrada', '2026-05-10T09:00:00-05:00');

select is((select (e ->> 'primera_entrada')::date
             from jsonb_array_elements(fn_ingresos()) e
            where e ->> 'persona_id' = '00000000-0000-0000-0000-0000000000d3'),
          '2026-03-02'::date, 'INGRESO · de partida, su primera marca es la del 2 de marzo');

select fn_anular_marcaje('00000000-0000-0000-0003-000000000021', 'Se registró en la persona equivocada');

select is((select (e ->> 'primera_entrada')::date
             from jsonb_array_elements(fn_ingresos()) e
            where e ->> 'persona_id' = '00000000-0000-0000-0000-0000000000d3'),
          '2026-05-10'::date, 'INGRESO · anulada esa marca, su ingreso pasa a ser el 10 de mayo — no una fecha que ya no existe');

-- ── Los días por revisar no incluyen marcas anuladas ─────────────────────────
insert into marcajes (id, client_uuid, persona_id, sede_id, tipo, timestamp_marca, origen, estado_revision) values
  ('00000000-0000-0000-0003-000000000031', gen_random_uuid(), '00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000fc', 'salida_final', '2026-07-23T18:00:00-05:00', 'auto_cierre', 'pendiente_revision');

select is((select count(*)::int from fn_dias_por_revisar(100)
           where persona_id='00000000-0000-0000-0000-0000000000d2' and fecha='2026-07-23'),
          1, 'REVISAR · un auto-cierre pendiente aparece en la lista de días por revisar');

select fn_anular_marcaje('00000000-0000-0000-0003-000000000031', 'Ya se registró su salida real');

select is((select count(*)::int from fn_dias_por_revisar(100)
           where persona_id='00000000-0000-0000-0000-0000000000d2' and fecha='2026-07-23'),
          0, 'REVISAR · anulado, deja de pedir revisión: la lista no se llena de días ya resueltos');

select * from finish();
rollback;
