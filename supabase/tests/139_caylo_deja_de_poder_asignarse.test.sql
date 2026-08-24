-- ============================================================================
-- 139_caylo_deja_de_poder_asignarse.test.sql
-- ============================================================================
-- La 0140 retiró el rango «caylo» del catálogo, pero solo por un lado: le borró
-- el techo de educación y lo dejó fuera de `categorias_laborales`, mientras los
-- CHECK de dos tablas lo seguían aceptando. Un rango asignable sin techo cargado
-- es lo peor de los dos mundos: `fn_educacion_respeta_el_tope` «falla abierto a
-- propósito» cuando no encuentra techo, así que en vez de bloquear, pagaba.
--
-- Medido antes de la 0178, con el comprobante real de S/ 727:
--     cayla → S/ 180.00      caylo → S/ 545.25
--
-- Este archivo fija las dos cosas: que el rango retirado ya no entra, y —lo que
-- de verdad importa a tres años— que NINGÚN rango pueda volver a quedar en ese
-- limbo. Las aserciones 4 y 5 no hablan de «caylo»: comparan el candado contra
-- el catálogo. Son las que van a cazar al próximo.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000ca00', 'ZZCAY', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ca01', 'AdminCay', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ca00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000ca09', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ca09', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000000ca02', 'PersonaCay', 'Laboratorio',
        '00000000-0000-0000-0000-00000000ca00', 'test-hash', '2024-01-01', 'planilla');


-- ── 1 · El rango retirado ya no entra ──────────────────────────────────────
select throws_ok(
  $$insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
    values ('00000000-0000-0000-0000-00000000ca02', 'caylo', 1185.00, '2024-01-01')$$,
  '23514',
  null,
  'RETIRADO · «caylo» ya no se puede asignar: la base lo rechaza, no depende de que la pantalla no lo ofrezca');

-- ── 2 · Y el que lo reemplaza sí ───────────────────────────────────────────
select lives_ok(
  $$insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
    values ('00000000-0000-0000-0000-00000000ca02', 'cayla', 1185.00, '2024-01-01')$$,
  'REEMPLAZO · «cayla» entra sin problema: es el mismo nivel y la misma base declarada');

-- ── 3 · Tampoco se le puede cargar un techo por la puerta de atrás ─────────
-- Si esto se pudiera, alguien «arreglaría» el agujero cargándole techo a caylo
-- en vez de dejar de usarlo, y volveríamos a tener dos nombres para un nivel.
select throws_ok(
  $$insert into topes_educacion_rango (rango, tope_mensual) values ('caylo', 180.00)$$,
  '23514',
  null,
  'SIN PUERTA TRASERA · tampoco se le puede cargar techo a un rango retirado');


-- ── 4 · El candado dice exactamente lo que dice el catálogo ────────────────
-- Esta es la que caza al próximo. No compara contra una lista escrita a mano:
-- compara el CHECK contra `categorias_laborales`, que es de donde sale el cuadro
-- de categorías que se le publica al equipo. Si alguien agrega una categoría y
-- se olvida del CHECK —o al revés— esto se pone rojo.
select is(
  (select array_agg(m[1] order by m[1])
     from pg_constraint c
     join pg_class t on t.oid = c.conrelid,
          lateral regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') m
    where t.relname = 'asignaciones_salario'
      and c.conname = 'asignaciones_salario_rango_check'),
  (select array_agg(rango order by rango) from categorias_laborales),
  'UN SOLO CATÁLOGO · los rangos que el CHECK acepta son exactamente los del cuadro de categorías');


-- ── 5 · Y ninguna categoría vigente se queda sin techo ─────────────────────
-- El agujero original no fue que caylo existiera: fue que existiera SIN techo,
-- porque sin techo el candado paga en vez de bloquear. Mientras esta aserción
-- esté verde, ese estado no puede volver a existir.
select is(
  (select count(*)::int
     from categorias_laborales c
    where not exists (select 1 from topes_educacion_rango t where t.rango = c.rango)),
  0,
  'SIN LIMBO · toda categoría del catálogo tiene su techo de educación cargado — sin techo, el candado paga sin límite');


-- ── 6 · Nadie quedó en el rango retirado ───────────────────────────────────
select is(
  (select count(*)::int from asignaciones_salario where rango = 'caylo'),
  0,
  'MIGRADOS · no queda ninguna asignación en el rango retirado, ni vigente ni histórica');


-- ── 7 · Y el techo sigue mordiendo donde tiene que morder ──────────────────
-- La reasignación no debe cambiar lo que nadie cobra, pero sí debe devolver el
-- techo que caylo no tenía. Con el comprobante de S/ 727 que motivó todo esto:
-- el 75% daría S/ 545.25 y el techo de cayla lo baja a S/ 180.
-- ⇩ CAMBIO 0281 ⇩ con las fechas del tramo, que es lo que la función pide desde
-- que el techo se reparte. Esta persona no tiene ninguna asignación cargada, así
-- que el saldo es el techo entero y la cifra es la misma de siempre.
select is(
  fn_educacion_monto('00000000-0000-0000-0000-00000000ca02', 727.00,
                     '2027-01-01'::date, '2027-12-31'::date),
  180.00::numeric,
  'TECHO · con el comprobante de S/727 el monto queda en S/180 — antes, en caylo, salían S/545.25');

select * from finish();
rollback;
