-- ============================================================================
-- 260_el_candado_de_horas_es_por_grupo.test.sql
-- ============================================================================
-- LO QUE DEFIENDE (Entrega 2, migración 0327):
--
--   Antes de la 0327, "periodo pagado" bloqueaba editar marcajes/jornadas
--   como un interruptor único para el periodo ENTERO — aunque la 0323 ya
--   pagaba planilla y RxH por separado. Resultado: mientras quedara un solo
--   grupo sin pagar, las horas de TODOS —incluida la gente de un grupo YA
--   pagado, con su foto YA congelada— seguían editables sin ningún candado.
--
--   Este archivo monta exactamente ese escenario: un periodo donde planilla
--   se paga y RxH todavía no, y comprueba que:
--
--     1. Anular un marcaje de la persona de PLANILLA (ya pagada) SE BLOQUEA
--        — aunque `periodos_planilla.estado` siga en 'abierto', porque RxH
--        no ha pagado.
--     2. Anular un marcaje de la persona de RXH (todavía abierta) SIGUE
--        FUNCIONANDO — su grupo no está pagado, aunque el de planilla sí.
--     3. En cuanto RxH TAMBIÉN se paga, sus marcajes quedan bloqueados igual
--        que los de planilla — y ahí, y solo ahí, `periodos_planilla.estado`
--        pasa a 'pagado' (el agregado de los 5 grupos, sin cambios desde la
--        0323).
--
--   No se prueban las otras ~30 funciones retocadas por la 0327 una por
--   una — cada una se verificó por separado, adversarialmente, contra su
--   cuerpo vigente exacto antes de escribir esta migración. Lo que este
--   archivo defiende es el COMPORTAMIENTO END-TO-END que todas comparten:
--   la pieza central, `fn_fecha_en_periodo_pagado(fecha, persona_id)`.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000260', 'ZZ260', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000261', 'DosSeisAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000000260', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000000269', '2024-01-01');
set session_replication_role = origin;

-- Planilla (tipo_vinculo por defecto).
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000000262', 'DosSeisPlanilla', 'Laboratorio',
        '00000000-0000-0000-0000-000000000260', 'test-hash', '2024-01-01');

-- RxH — locadora por honorarios.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000000263', 'DosSeisRxh', 'Laboratorio',
        '00000000-0000-0000-0000-000000000260', 'test-hash', '2024-01-01', 'rxh');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000269', true);

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-0000000026aa', '2026-05-01', '2026-05-31', 'abierto');

-- Planilla: un día completo, el 10 de mayo.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000262', '00000000-0000-0000-0000-000000000260', 'entrada',       '2026-05-10T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000262', '00000000-0000-0000-0000-000000000260', 'salida_final',  '2026-05-10T18:00:00-05:00');

-- RxH: DOS días completos — uno para probar mientras sigue abierta, otro
-- para probar después de que también se le pague.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000263', '00000000-0000-0000-0000-000000000260', 'entrada',       '2026-05-11T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000263', '00000000-0000-0000-0000-000000000260', 'salida_final',  '2026-05-11T18:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000263', '00000000-0000-0000-0000-000000000260', 'entrada',       '2026-05-12T09:00:00-05:00'),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000263', '00000000-0000-0000-0000-000000000260', 'salida_final',  '2026-05-12T18:00:00-05:00');


-- ── 1-2 · Se paga SOLO planilla ──────────────────────────────────────────────
select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-0000000026aa', true, 'planilla') $$,
  'Se puede pagar el grupo planilla por sí solo');

select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-0000000026aa'),
  'abierto',
  'AGREGADO · el periodo entero sigue "abierto": a RxH todavía le falta pagar');

select is(
  (select estado from periodo_grupo_pago
    where periodo_id = '00000000-0000-0000-0000-0000000026aa' and grupo = 'planilla'),
  'pagado',
  'periodo_grupo_pago · planilla sí quedó pagado, por su cuenta');


-- ── 3-5 · Planilla (pagada) queda bloqueada; RxH (abierta) sigue editable ───
select throws_ok(
  $$ select fn_anular_marcaje(
       (select id from marcajes where persona_id = '00000000-0000-0000-0000-000000000262'
          and tipo = 'salida_final' and timestamp_marca::date = '2026-05-10'),
       'intento de anular tras pagar planilla') $$,
  'P0001',
  'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.',
  'CANDADO POR GRUPO · a planilla (ya pagada) SÍ se le bloquea anular su marca, aunque el periodo siga "abierto"');

select lives_ok(
  $$ select fn_anular_marcaje(
       (select id from marcajes where persona_id = '00000000-0000-0000-0000-000000000263'
          and tipo = 'salida_final' and timestamp_marca::date = '2026-05-11'),
       'RxH sigue abierta, esto debe funcionar') $$,
  'CANDADO POR GRUPO · a RxH (todavía sin pagar) NO se le bloquea, aunque planilla ya esté pagada');

select ok(
  (select anulada_at is not null from marcajes
    where persona_id = '00000000-0000-0000-0000-000000000263'
      and tipo = 'salida_final' and timestamp_marca::date = '2026-05-11'),
  'y de verdad quedó anulada — no fue un lives_ok sobre una excepción silenciada');


-- ── 6-8 · Se paga RxH también: ahí sí se completa el periodo ───────────────
select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-0000000026aa', true, 'rxh') $$,
  'Se puede pagar el grupo rxh, aparte y después');

select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-0000000026aa'),
  'pagado',
  'AGREGADO · con los dos grupos pagados, RECIÉN AHÍ el periodo entero pasa a "pagado"');

select throws_ok(
  $$ select fn_anular_marcaje(
       (select id from marcajes where persona_id = '00000000-0000-0000-0000-000000000263'
          and tipo = 'salida_final' and timestamp_marca::date = '2026-05-12'),
       'intento de anular tras pagar rxh también') $$,
  'P0001',
  'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.',
  'CANDADO POR GRUPO · a RxH, en cuanto SU grupo también se paga, se le bloquea igual que a planilla');


-- ── 9-11 · fn_fecha_en_periodo_pagado responde lo mismo directamente ───────
select ok(
  fn_fecha_en_periodo_pagado('2026-05-10'::date, '00000000-0000-0000-0000-000000000262'::uuid),
  'HELPER · directo: la fecha de planilla, para la persona de planilla, da pagado');

select is(
  fn_fecha_en_periodo_pagado('2026-05-10'::date, '00000000-0000-0000-0000-000000000263'::uuid),
  fn_fecha_en_periodo_pagado('2026-05-10'::date, '00000000-0000-0000-0000-000000000262'::uuid),
  'HELPER · con los dos grupos ya pagados, da lo mismo para cualquiera de las dos personas');

select ok(
  (select count(*) = 2 from periodo_grupo_pago where periodo_id = '00000000-0000-0000-0000-0000000026aa' and estado = 'pagado'),
  'Quedaron exactamente los 2 grupos con gente (planilla y rxh) marcados pagado — ninguno de más');

select * from finish();
rollback;
