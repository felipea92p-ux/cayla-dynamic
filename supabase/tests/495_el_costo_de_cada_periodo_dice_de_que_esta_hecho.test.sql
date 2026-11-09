-- ============================================================================
-- 495_el_costo_de_cada_periodo_dice_de_que_esta_hecho.test.sql — migración 0609
-- ============================================================================
-- Cada periodo de `fn_costos_planilla` trae ahora sus conceptos. Lo que esta
-- prueba vigila es que CUADREN: el gráfico «En qué se va la planilla» se pone
-- al lado del «Costo de planilla», y si los dos no dicen el mismo total al
-- centavo, hay dos costos.
--
-- Y que nada más se mueva: la 0609 reescribe la función entera.
--
-- El montaje es el de la 201: un periodo cerrado con una locadora con
-- retención de 4ta y una trabajadora de planilla con pensión, para que los
-- tres descuentos tengan algo que restar.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000000495', 'ZZ495', 'Sede de laboratorio 495', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000049599', 'Adm495', 'Laboratorio',
        '00000000-0000-0000-0000-000000000495', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000049598', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000049598', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      tipo_vinculo, sueldo_fijo, retencion_4ta, regimen_pension) values
  ('00000000-0000-0000-0000-000000049501', 'Loc', 'ConRetencion',
   '00000000-0000-0000-0000-000000000495', 'th', '2025-01-01', 'rxh', true, 'siempre', null),
  ('00000000-0000-0000-0000-000000049502', 'Test', 'DePlanilla',
   '00000000-0000-0000-0000-000000000495', 'th', '2025-01-01', 'planilla', false, null, 'integra');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 1250.37, '2025-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-000000000495'
  and id <> '00000000-0000-0000-0000-000000049599';

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000049502', d::date, 8, 'cerrada'
from generate_series('2026-07-29'::date, '2026-08-28'::date, interval '1 day') d
where extract(dow from d) <> 0;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000000497', '2026-07-29', '2026-08-28', 'abierto');
select fn_planilla_congelar('00000000-0000-0000-0000-000000000497', 'pago',
                            '00000000-0000-0000-0000-000000049599');
update periodos_planilla set estado = 'pagado', pagado_at = now()
 where id = '00000000-0000-0000-0000-000000000497';

create temp table _p on commit drop as
select x as p, x->'conceptos' as c
from jsonb_array_elements((select fn_costos_planilla('2026-07-01', '2026-09-30'))->'por_periodo') x
where x->>'periodo_id' = '00000000-0000-0000-0000-000000000497';

create temp table _f on commit drop as
select * from planilla_pagada_detalle where periodo_id = '00000000-0000-0000-0000-000000000497';

-- ── 1 · Cada periodo trae sus conceptos ────────────────────────────────────
select isnt((select c from _p), null, 'El periodo pagado trae sus conceptos');

-- ── 2 · Los conceptos menos los descuentos son el neto, al centavo ─────────
select is(
  (select (c->>'pago_base')::numeric + (c->>'descanso_semanal')::numeric + (c->>'sobretiempo')::numeric
          + (c->>'feriados')::numeric + (c->>'plus')::numeric + (c->>'bonos')::numeric
          + (c->>'asignacion_familiar')::numeric + (c->>'movilidad')::numeric + (c->>'educacion')::numeric
          - (c->>'descuentos')::numeric - (c->>'pension')::numeric - (c->>'retencion_4ta')::numeric from _p),
  (select (p->>'neto')::numeric from _p),
  'Conceptos menos descuentos = neto, al centavo');

-- ── 3 · Y con las provisiones del periodo, son el costo ────────────────────
select is(
  (select (p->>'neto')::numeric + (p->>'provisiones')::numeric from _p),
  (select (p->>'costo')::numeric from _p),
  'Neto + provisiones = costo: el desglose cuadra con «Costo de planilla»');

-- ── 4 · Los descuentos son los de la foto, no un número aparte ─────────────
select is(
  (select (c->>'pension')::numeric + (c->>'retencion_4ta')::numeric from _p),
  (select round(sum(coalesce(descuento_pension, 0) + coalesce(retencion_4ta, 0)), 2) from _f),
  'La pensión y la retención de 4ta son las de la foto del pago');

-- ── 5 · Las cuatro provisiones detallan la cifra, a lo sumo un centavo por fila ──
-- Cada una se redondea por su lado: no suman `provision_total` al centavo. Por
-- eso el cuadre usa `provisiones`, y esto solo vigila que el detalle no se aleje.
select cmp_ok(
  (select abs((c->>'provision_gratificacion')::numeric + (c->>'provision_cts')::numeric
              + (c->>'provision_vacaciones')::numeric + (c->>'provision_bonif_extraordinaria')::numeric
              - (p->>'provisiones')::numeric) from _p),
  '<=',
  (select count(*) * 0.01 from _f),
  'Las cuatro provisiones no se alejan de la cifra en más de un centavo por fila');

-- ── 6 · Lo demás del periodo no se movió ──────────────────────────────────
select is(
  (select (p->>'costo')::numeric from _p),
  (select round(sum(costo_total), 2) from _f),
  'El costo del periodo sigue siendo la suma de la foto');

select * from finish();
rollback;
