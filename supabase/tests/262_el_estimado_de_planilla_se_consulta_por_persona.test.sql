-- ============================================================================
-- 262_el_estimado_de_planilla_se_consulta_por_persona.test.sql
-- ============================================================================
-- LO QUE DEFIENDE (migración 0329, fn_planilla_calcular_persona):
--
--   1. El número que devuelve para una persona es IDÉNTICO al que produce
--      fn_planilla_calcular para esa misma persona — se compara directo
--      contra la función oficial, no contra un valor esperado a mano, porque
--      la promesa central de esta función es que nunca reimplementa una
--      regla de negocio.
--   2. Acceso: SOLO admin/líder. Ninguna otra identidad puede consultar NADA
--      por esta función — ni la de otra persona, ni la propia. El
--      self-service quedó fuera a propósito: probado más abajo, porque el
--      camino "en vivo" reenvía a fn_planilla_calcular, que trae desde la
--      0090 su propio guard "solo admin/líder" que esta función no puede
--      sortear sin tocarlo (y ese guard no se toca — ver la migración).
--   3. El guard es null-safe frente al caso de la 0078: una identidad con
--      sesión pero SIN fila en `personas` (una terminal) tampoco cuela.
--   4. Una vez que el grupo de esa persona se paga, la respuesta cambia de
--      'calculo' a 'foto' y coincide exactamente con lo que quedó congelado
--      en `planilla_pagada_detalle` — nunca se recalcula lo ya pagado.
-- ============================================================================
begin;
select plan(12);

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

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000262aa', '2026-06-01', '2026-06-30', 'abierto');

-- Bea marca un día completo.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-000000000262', 'entrada',      '2026-06-10T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-000000000262', 'salida_final', '2026-06-10T18:00:00-05:00');


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
     (select fn_planilla_calcular('2026-06-01'::date, '2026-06-30'::date, '00000000-0000-0000-0000-0000000262aa'::uuid)) -> 'filas'
   ) f where (f ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000000272'),
  'IDÉNTICO · quitando "fuente", la fila es exactamente la misma que produce fn_planilla_calcular para Bea — no hay una segunda lógica');


-- ── 4 · Bea NO puede pedir la suya — ni siquiera la propia ─────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000372', true);

select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') $$,
  'P0001', 'Sin permiso para consultar esta planilla',
  'SIN SELF-SERVICE (por ahora) · Bea no es admin/líder, así que ni siquiera puede pedir su propio estimado — bloqueada por el guard de fn_planilla_calcular (0090), no por esta función');


-- ── 5-6 · Cati tampoco puede ver la de Bea, ni la suya propia ──────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000373', true);

select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000272', '00000000-0000-0000-0000-0000000262aa') $$,
  'P0001', 'Sin permiso para consultar esta planilla',
  'Cati (integrante, no admin) NO puede consultar el estimado de Bea');

select throws_ok(
  $$ select fn_planilla_calcular_persona(
       '00000000-0000-0000-0000-000000000273', '00000000-0000-0000-0000-0000000262aa') $$,
  'P0001', 'Sin permiso para consultar esta planilla',
  'y tampoco el suyo propio — el candado es "solo admin/líder", no "cualquiera menos otra persona"');


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

select * from finish();
rollback;
