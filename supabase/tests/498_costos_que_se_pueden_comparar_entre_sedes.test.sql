-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 498_costos_que_se_pueden_comparar_entre_sedes.test.sql  (migración 0612)
-- ============================================================================
-- Dos tiendas con el mismo costo y la misma cantidad de plazas: dos plazas,
-- dos periodos, S/ 1 000 por plaza y por periodo. En la «Estable» las ocupan las
-- mismas dos personas; en la de «Rotación», una de las dos plazas la ocupó una
-- persona distinta cada periodo.
--
-- Lo que cuesta una persona al mes es lo mismo en las dos: S/ 1 000. El costo
-- por persona de siempre decía otra cosa —S/ 2 000 contra S/ 1 333.33— porque
-- dividía el año entre personas distintas, y la rotación agrandaba el divisor.
-- Medido en producción el 2026-11-10: con esa cifra Central costaba 2.25 veces
-- lo que Tienda TRU por persona; por persona y por periodo, 1.31 veces.
--
-- Y una oficina donde una persona marca (100 h, S/ 1 000) y otra no marca
-- (S/ 2 000). La hora de quien marcó cuesta S/ 10; la cifra de siempre decía
-- S/ 30, porque sumaba el sueldo de quien no marca sin sus horas. En producción
-- eso ponía la hora de Central a 1.67 veces la de TRU; contando a quien marcó,
-- 1.01.
--
-- Las fotos del pago se escriben a mano (como en la 184) para que el escenario
-- dependa solo de lo que esta migración cuenta, no del cálculo de la planilla.
-- Todo el pago va como sueldo base: la foto exige que el total cuadre con sus
-- conceptos (chk_foto_cuadra).
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-0000000498e0'::uuid, 'ZZ498E', 'Tienda estable 498',  true, 'tienda'),
  ('00000000-0000-0000-0000-0000000498f0'::uuid, 'ZZ498R', 'Tienda que rota 498', true, 'tienda'),
  ('00000000-0000-0000-0000-0000000498a0'::uuid, 'ZZ498G', 'Taller 498',          true, 'taller'),
  ('00000000-0000-0000-0000-0000000498c0'::uuid, 'ZZ498C', 'Oficina 498',         true, 'central');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000049899'::uuid, 'Adm498', 'Laboratorio',
        '00000000-0000-0000-0000-0000000498e0'::uuid, 'admin', 'x',
        '00000000-0000-0000-0000-000000049898'::uuid, '2024-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049898', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso) values
  -- Estable: las mismas dos los dos periodos.
  ('00000000-0000-0000-0000-000000049801'::uuid, 'Estable', 'Uno',  '00000000-0000-0000-0000-0000000498e0'::uuid, 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000049802'::uuid, 'Estable', 'Dos',  '00000000-0000-0000-0000-0000000498e0'::uuid, 'x', '2024-01-01'),
  -- Rotación: una se queda; la otra plaza la ocupa una persona distinta cada periodo.
  ('00000000-0000-0000-0000-000000049803'::uuid, 'Rota',    'Fija', '00000000-0000-0000-0000-0000000498f0'::uuid, 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000049804'::uuid, 'Rota',    'Feb',  '00000000-0000-0000-0000-0000000498f0'::uuid, 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000049805'::uuid, 'Rota',    'Mar',  '00000000-0000-0000-0000-0000000498f0'::uuid, 'x', '2024-01-01'),
  -- Dos grupos: entra en preselección y pasa a planilla en el mismo periodo.
  ('00000000-0000-0000-0000-000000049806'::uuid, 'Pasa',    'APlanilla', '00000000-0000-0000-0000-0000000498a0'::uuid, 'x', '2024-01-01'),
  -- Oficina: una marca, la otra no.
  ('00000000-0000-0000-0000-000000049807'::uuid, 'Oficina', 'Marca',   '00000000-0000-0000-0000-0000000498c0'::uuid, 'x', '2024-01-01'),
  ('00000000-0000-0000-0000-000000049808'::uuid, 'Oficina', 'NoMarca', '00000000-0000-0000-0000-0000000498c0'::uuid, 'x', '2024-01-01');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000498b1', '2030-02-01', '2030-02-28', 'abierto'),
  ('00000000-0000-0000-0000-0000000498b2', '2030-03-01', '2030-03-31', 'abierto');

insert into planilla_pagada_detalle
  (periodo_id, persona_id, version, origen, nombre, sede_codigo, grupo, horas_mes, pago_base, total, fila)
values
  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049801', 1, 'pago', 'Estable Uno', 'ZZ498E', 'planilla', 100, 1000, 1000, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049802', 1, 'pago', 'Estable Dos', 'ZZ498E', 'planilla', 100, 1000, 1000, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b2', '00000000-0000-0000-0000-000000049801', 1, 'pago', 'Estable Uno', 'ZZ498E', 'planilla', 100, 1000, 1000, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b2', '00000000-0000-0000-0000-000000049802', 1, 'pago', 'Estable Dos', 'ZZ498E', 'planilla', 100, 1000, 1000, '{}'::jsonb),

  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049803', 1, 'pago', 'Rota Fija',   'ZZ498R', 'planilla', 100, 1000, 1000, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049804', 1, 'pago', 'Rota Feb',    'ZZ498R', 'planilla', 100, 1000, 1000, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b2', '00000000-0000-0000-0000-000000049803', 1, 'pago', 'Rota Fija',   'ZZ498R', 'planilla', 100, 1000, 1000, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b2', '00000000-0000-0000-0000-000000049805', 1, 'pago', 'Rota Mar',    'ZZ498R', 'planilla', 100, 1000, 1000, '{}'::jsonb),

  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049806', 1, 'pago', 'Pasa APlanilla', 'ZZ498G', 'prueba', 30, 300, 300, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049806', 1, 'pago', 'Pasa APlanilla', 'ZZ498G', 'planilla', 70, 700, 700, '{}'::jsonb),

  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049807', 1, 'pago', 'Oficina Marca',   'ZZ498C', 'planilla', 100, 1000, 1000, '{}'::jsonb),
  ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-000000049808', 1, 'pago', 'Oficina NoMarca', 'ZZ498C', 'planilla',   0, 2000, 2000, '{}'::jsonb);

update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id in ('00000000-0000-0000-0000-0000000498b1', '00000000-0000-0000-0000-0000000498b2');

create temp table _c on commit drop as
select fn_costos_planilla('2030-01-01', '2030-12-31') as j;

create temp table _sede on commit drop as
select x->>'sede' as sede, x from _c, jsonb_array_elements(j->'por_sede') x;

-- ── 1 · La plaza que rotó cuenta por periodo, no por persona ────────────────
select is((select (x->>'personas_periodo')::int from _sede where sede = 'ZZ498R'),
          4, 'ROTACIÓN · tres personas en dos periodos son cuatro personas-periodo, como en la estable');

select is((select (x->>'costo_por_persona_periodo')::numeric from _sede where sede = 'ZZ498R'),
          1000.00::numeric, 'ROTACIÓN · una persona al mes cuesta lo que costó cada plaza: S/ 1 000');

-- `coalesce(…, false)`: sin la cifra, las dos serían null, y null contra null
-- pasaría como «iguales» sin que haya nada que comparar.
select ok(coalesce((select (x->>'costo_por_persona_periodo')::numeric from _sede where sede = 'ZZ498R')
                 = (select (x->>'costo_por_persona_periodo')::numeric from _sede where sede = 'ZZ498E'), false),
          'ROTACIÓN · la tienda que rota ya no parece más barata que la estable');

-- La cifra de siempre NO cambia de significado: la pantalla publicada la lee
-- mientras la 0612 se pega antes de fusionar, y la 100 fija qué es.
select is((select array[(x->>'costo_por_persona')::numeric] from _sede where sede = 'ZZ498R')
          || (select (x->>'costo_por_persona')::numeric from _sede where sede = 'ZZ498E'),
          array[1333.33, 2000.00]::numeric[],
          'ANTES · el costo por persona de siempre sigue igual: con él, la que rota parecía 33 % más barata');

-- ── 2 · Dos filas de la misma persona en el mismo periodo son una ───────────
select is((select (x->>'personas_periodo')::int from _sede where sede = 'ZZ498G'),
          1, 'DOS GRUPOS · pasar de preselección a planilla a mitad de periodo es una persona ese periodo');

select is((select (x->>'costo_por_persona_periodo')::numeric from _sede where sede = 'ZZ498G'),
          1000.00::numeric, 'DOS GRUPOS · y su costo es lo de los dos grupos juntos');

-- ── 3 · El corte por tipo suma igual ────────────────────────────────────────
select is((select (x->>'personas_periodo')::int
             from _c, jsonb_array_elements(j->'por_tipo') x where x->>'tipo' = 'tienda'),
          8, 'TIPO · las dos tiendas suman ocho personas-periodo');

select is((select (x->>'costo_por_persona_periodo')::numeric
             from _c, jsonb_array_elements(j->'por_tipo') x where x->>'tipo' = 'tienda'),
          1000.00::numeric, 'TIPO · y una persona de tienda al mes cuesta S/ 1 000');

-- ── 4 · La hora es de quien marcó ───────────────────────────────────────────
select is((select (x->>'costo_por_hora')::numeric from _sede where sede = 'ZZ498C'),
          10.00::numeric, 'POR HORA · el sueldo de quien no marca ya no infla la hora: S/ 1 000 entre 100 h, no S/ 3 000');

select is((select (x->>'costo_sin_horas')::numeric from _sede where sede = 'ZZ498C'),
          2000.00::numeric, 'POR HORA · y lo que costó quien no marca sale aparte, no desaparece');

select is((select array[(x->>'costo_por_hora')::numeric, (x->>'costo_sin_horas')::numeric] from _sede where sede = 'ZZ498E'),
          array[10.00, 0.00]::numeric[], 'POR HORA · donde todos marcan, la hora no cambia y no hay nada sin horas');

select is((select array[(x->>'costo_por_hora')::numeric, (x->>'costo_sin_horas')::numeric]
             from _c, jsonb_array_elements(j->'por_tipo') x where x->>'tipo' = 'central'),
          array[10.00, 2000.00]::numeric[], 'TIPO · el corte por tipo calcula la hora igual');

select * from finish();
rollback;
