-- ============================================================================
-- 262_el_estimado_de_planilla_se_consulta_por_persona.test.sql
-- ============================================================================
-- LO QUE DEFIENDE (migración 0329, y actualizado por la 0337):
--
--   1. El número que devuelve para una persona es IDÉNTICO al que produce
--      fn_planilla_calcular para esa misma persona — se compara directo
--      contra la función oficial, no contra un valor esperado a mano, porque
--      la promesa central de esta función es que nunca reimplementa una
--      regla de negocio.
--   2. Acceso: admin/líder ve a cualquiera; una persona ve SOLO la suya —
--      desde la 0337, cuando el camino "en vivo" pasa a llamar a
--      fn_planilla_calcular_nucleo (sin el guard de admin/líder que
--      fn_planilla_calcular seguiría aplicando). Antes de la 0337 esto
--      estaba bloqueado a propósito para CUALQUIER identidad, incluida la
--      propia — ver el historial de este archivo si hace falta ese contexto.
--   3. El guard es null-safe frente al caso de la 0078: una identidad con
--      sesión pero SIN fila en `personas` (una terminal) tampoco cuela — ni
--      "es admin" ni "es la propia" pueden colarse con un null.
--   4. Una vez que el grupo de esa persona se paga, la respuesta cambia de
--      'calculo' a 'foto' y coincide exactamente con lo que quedó congelado
--      en `planilla_pagada_detalle` — nunca se recalcula lo ya pagado. Esta
--      rama no la tocó la 0337.
--   5. Self-service nunca antes del periodo actual (0337, corte pedido por
--      Felipe el 2026-08-31): una persona que consulta LA SUYA en un periodo
--      pasado se rechaza, aunque sea admitida por las reglas 2 y 3 — el
--      periodo del fixture principal (pruebas 1-12) se construye siempre
--      alrededor de `fn_hoy_lima()`, nunca con fechas fijas, precisamente
--      para poder afirmar "es el periodo actual" sin que la prueba caduque.
--      Admin/líder no lleva este límite.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000262', 'ZZ262', 'Sede de laboratorio', true);

set session_replication_role = replica;

insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000271', 'DosSeisDosAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000000262', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000000371', '2024-01-01');

-- Bea: integrante normal (tipo_vinculo por defecto = 'planilla'), con cuenta propia.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000272', 'DosSeisDosBea', 'Laboratorio',
        '00000000-0000-0000-0000-000000000262', 'test-hash',
        '00000000-0000-0000-0000-000000000372', '2024-01-01');

-- Cati: otra integrante normal, con cuenta propia.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000273', 'DosSeisDosCati', 'Laboratorio',
        '00000000-0000-0000-0000-000000000262', 'test-hash',
        '00000000-0000-0000-0000-000000000373', '2024-01-01');

set session_replication_role = origin;

-- El periodo abarca hoy con holgura (20-46 días exige periodos_planilla_check)
-- a propósito: las pruebas 1-12 necesitan que este sea "el periodo actual"
-- de verdad, para la prueba 5 de arriba (el corte por fecha). Fechas fijas
-- habrían caducado la prueba 5 el día que dejaran de contener hoy.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000262aa', fn_hoy_lima() - 10, fn_hoy_lima() + 15, 'abierto');

-- Bea marca un día completo, dentro del periodo de arriba.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-000000000262', 'entrada',      (fn_hoy_lima()::text || 'T09:00:00-05:00')::timestamptz),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-000000000262', 'salida_final', (fn_hoy_lima()::text || 'T18:00:00-05:00')::timestamptz);


-- ── 1-3 · Admin consulta a Bea: en vivo, e idéntico al cálculo oficial ─────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000371', true);

select lives_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') $$,
  'Admin puede pedir el estimado de cualquier persona');

select is(
  (fn_planilla_calcular_persona('00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') ->> 'fuente'),
  'calculo',
  'Periodo abierto y grupo sin pagar: la fuente es el cálculo en vivo, no una foto');

select is(
  fn_planilla_calcular_persona('00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') - 'fuente',
  (select f from jsonb_array_elements(
     (select fn_planilla_calcular((fn_hoy_lima() - 10)::date, (fn_hoy_lima() + 15)::date, '00000000-0000-0000-0000-0000000262aa'::uuid)) -> 'filas'
   ) f where (f ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000000272'),
  'IDÉNTICO · quitando "fuente", la fila es exactamente la misma que produce fn_planilla_calcular para Bea — no hay una segunda lógica');


-- ── 4-5 · Bea SÍ puede pedir la suya, desde la 0337 ────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000372', true);

select lives_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') $$,
  'SELF-SERVICE (0337) · Bea no es admin/líder, pero puede pedir SU PROPIO estimado');

select is(
  fn_planilla_calcular_persona('00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') - 'fuente',
  (select f from jsonb_array_elements(
     (select fn_planilla_calcular_nucleo((fn_hoy_lima() - 10)::date, (fn_hoy_lima() + 15)::date, '00000000-0000-0000-0000-0000000262aa'::uuid)) -> 'filas'
   ) f where (f ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000000272'),
  'y es exactamente la misma fila que produce el núcleo — su propio self-service no reimplementa nada');


-- ── 6-8 · Cati puede ver la suya, pero ni ella ni Bea ven la de la otra ────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000373', true);

select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') $$,
  'P0001', 'Sin permiso para consultar esta planilla',
  'Cati (integrante, no admin) NO puede consultar el estimado de Bea — el self-service es "la propia", no "cualquiera"');

select lives_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000273', '00000000-0000-0000-0000-0000000262aa') $$,
  'pero el suyo propio sí — el candado es "admin/líder, o la propia", no "solo admin/líder"');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000372', true);
select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000273', '00000000-0000-0000-0000-0000000262aa') $$,
  'P0001', 'Sin permiso para consultar esta planilla',
  'y en el otro sentido: Bea tampoco ve la de Cati — el self-service no es transitivo entre compañeras');


-- ── 7 · Una sesión SIN fila en personas (como una terminal) tampoco cuela ──
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000999', true);

select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') $$,
  'P0001', 'Sin permiso para consultar esta planilla',
  'NULL-SAFE (0078) · una sesión sin fila en personas (fn_es_admin_o_lider() = false, nunca null) no pasa por accidente');


-- ── 8-10 · Se paga el grupo de Bea: la respuesta pasa a ser la foto ────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000371', true);

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-0000000262aa', true, 'planilla') $$,
  'Se paga el grupo planilla del periodo (Bea es tipo_vinculo = planilla por defecto)');

select is(
  (fn_planilla_calcular_persona('00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') ->> 'fuente'),
  'foto',
  'Con su grupo pagado, la fuente pasa a ser la foto congelada — no se recalcula');

select is(
  fn_planilla_calcular_persona('00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') - 'fuente',
  (select d.fila from planilla_pagada_detalle d
    where d.periodo_id = '00000000-0000-0000-0000-0000000262aa'
      and d.grupo = 'planilla' and d.persona_id = '00000000-0000-0000-0000-000000000272'
    order by d.version desc limit 1),
  'y coincide exactamente con lo que quedó congelado en planilla_pagada_detalle');


-- ── 11-12 · Periodo y persona inexistentes se rechazan con mensaje claro ──
select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-000000000000') $$,
  'P0001', 'El periodo no existe',
  'Un periodo_id que no existe se rechaza con mensaje claro, no con un error genérico');

select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000262aa') $$,
  'P0001', 'La persona no existe',
  'Un persona_id que no existe se rechaza con mensaje claro');


-- ── 13-14 · El corte por fecha (0337): self-service no llega a un periodo pasado
-- Un periodo claramente anterior al de arriba — mismo holgado 20-46 días,
-- pero sin tocar el rango que contiene hoy.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000262bb', fn_hoy_lima() - 100, fn_hoy_lima() - 70, 'pagado');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000372', true);
select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262bb') $$,
  'P0001', 'Tu planilla solo se puede consultar desde el periodo actual en adelante',
  'CORTE POR FECHA (0337) · Bea no puede pedir SU PROPIO estimado de un periodo ya pasado — así haya tenido derecho a verlo si fuera el actual');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000371', true);
select lives_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262bb') $$,
  'pero admin SÍ puede seguir consultando ese mismo periodo pasado para Bea — el corte es solo para el autoservicio');

select * from finish();
rollback;
