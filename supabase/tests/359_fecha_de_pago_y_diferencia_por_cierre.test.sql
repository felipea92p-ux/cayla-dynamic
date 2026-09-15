-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 359_fecha_de_pago_y_diferencia_por_cierre.test.sql — 0454
-- ============================================================================
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   (A) `fn_liquidacion_pagar` valida la fecha de pago: nunca antes del cese,
--       nunca en el futuro, y HOY si no se manda ninguna — igual en la
--       segunda llamada («volver a marcar») que en la primera.
--
--   (B) `fn_liquidacion_diferencias` distingue una diferencia que YA EXPLICA
--       el descuento que el cierre de Planilla obligó a registrar (0244) de
--       una diferencia real. El montaje reproduce las dos, con dos personas
--       en periodos que no se solapan (mismo criterio que la 194):
--
--       ·358001 CierreA  — el caso normal: liquidación pagada, el freno del
--                cierre obliga a descontar, se descuenta, se cierra el mes.
--                Eso NO es una avería: origen = 'esperada_por_cierre'.
--       ·358002 FeriadoB — un feriado se registra DESPUÉS de pagar, dentro
--                del periodo pero sin que nadie cierre nada. El periodo del
--                cierre no interviene (`ya_pagado_en_planilla` = 0), así que
--                la diferencia que deja no la explica ningún descuento:
--                origen = 'real'.
--
--   (C) `descuadra_real` de `fn_liquidaciones_pendientes` solo se enciende con
--       (B); `descuadra` —la columna que ya existía— se sigue encendiendo con
--       cualquiera de las dos, sin cambiar su comportamiento de antes.
--
--   (D) La firma vieja de dos argumentos de `fn_liquidacion_pagar` no queda
--       viva al lado de la nueva de tres: si quedaran las dos, una llamada
--       con argumentos con nombre («p_persona_id», «p_nota») dejaría de saber
--       cuál usar — el defecto que la 0297/0299 dejó documentado para otra
--       función.
-- ============================================================================
begin;
select plan(16);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000358000', 'ZZ358', 'Sede de laboratorio 358', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000358099', 'Admin358', 'Laboratorio',
        '00000000-0000-0000-0000-000000358000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000358098', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000358098', true);

-- Sin feriados de fábrica de por medio: FeriadoB agrega el suyo a mano, y no
-- puede competir con uno que ya estuviera ahí.
delete from feriados where fecha between '2020-05-01' and '2020-08-31';

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000358001', 'CierreA',  'Laboratorio', '00000000-0000-0000-0000-000000358000', 'test-hash', '2018-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000358002', 'FeriadoB', 'Laboratorio', '00000000-0000-0000-0000-000000358000', 'test-hash', '2018-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values
  ('00000000-0000-0000-0000-000000358001', 'cayla', 1500.00, '2018-01-02'),
  ('00000000-0000-0000-0000-000000358002', 'cayla', 1500.00, '2018-01-02');

-- Periodos separados, sin solape — mismo motivo que en la 194: el freno del
-- cierre mira el periodo entero, y dos casos en el mismo mes se taparían.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000358101', '2020-08-01', '2020-08-30', 'abierto'),
  ('00000000-0000-0000-0000-000000358102', '2020-07-01', '2020-07-30', 'abierto');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000358001', d::date, 6.5, 'cerrada'
from generate_series('2020-08-01'::date, '2020-08-10'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000358002', d::date, 6.5, 'cerrada'
from generate_series('2020-07-01'::date, '2020-07-10'::date, interval '1 day') d;

update personas set estado='inactivo', fecha_cese='2020-08-10' where id='00000000-0000-0000-0000-000000358001';
update personas set estado='inactivo', fecha_cese='2020-07-10' where id='00000000-0000-0000-0000-000000358002';


-- ── § 1 · La fecha de pago se valida, y por defecto es HOY ──────────────────
select throws_like(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000358001', 'prueba', '2020-08-09'::date) $$,
  '%no puede ser anterior al cese%',
  '1 · una fecha de pago anterior al cese se rechaza');

select throws_like(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000358001', 'prueba', (fn_hoy_lima() + 1)) $$,
  '%no puede ser futura%',
  '2 · una fecha de pago futura se rechaza');

select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000358001', 'primer pago', '2020-08-11'::date) $$,
  '3 · con una fecha válida, se congela (v1)');

select is(
  (select fecha_pago from liquidacion_pagada
    where persona_id='00000000-0000-0000-0000-000000358001' order by version desc limit 1),
  '2020-08-11'::date,
  '4 · la fecha de pago guardada es la que se mandó, no la de hoy');

select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000358001', 'vuelvo a marcarla') $$,
  '5 · volver a marcar sin fecha no revienta (v2)');

select is(
  (select fecha_pago from liquidacion_pagada
    where persona_id='00000000-0000-0000-0000-000000358001' order by version desc limit 1),
  fn_hoy_lima(),
  '6 · sin fecha, la versión nueva asume HOY');


-- ── § 2 · CierreA: el freno obliga a descontar, y el cierre lo explica ──────
select lives_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-000000358101',
       '00000000-0000-0000-0000-000000358001', 'descuento', 'Ya le pague aparte (liquidacion)',
       (select monto_periodo from liquidacion_pagada
         where persona_id='00000000-0000-0000-0000-000000358001' order by version desc limit 1)) $$,
  '7 · se registra el descuento que el freno del cierre exige');

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000358101', true) $$,
  '8 · con el descuento puesto, el mes se cierra');

select is(
  (select origen from fn_liquidacion_diferencias('00000000-0000-0000-0000-000000358001')
    where concepto = 'Sueldo del periodo'),
  'esperada_por_cierre',
  '9 · la diferencia del sueldo del periodo la explica el cierre, no es una avería');

select is(
  (select descuadra_real from fn_liquidaciones_pendientes()
    where persona_id='00000000-0000-0000-0000-000000358001'),
  false,
  '10 · descuadra_real NO se enciende: nada que revisar de verdad');

select is(
  (select descuadra from fn_liquidaciones_pendientes()
    where persona_id='00000000-0000-0000-0000-000000358001'),
  true,
  '11 · descuadra (la columna vieja) se sigue encendiendo igual que siempre — no se le cambió el sentido');


-- ── § 3 · FeriadoB: un cambio real, sin que el cierre tenga nada que ver ────
-- El nombre quedó de un primer intento con un feriado posterior al cese, que
-- no sirvió: `fn_liquidacion` recalcula con `fn_planilla_calcular(fecha_ini,
-- v_cese, periodo_id)`, restringido HASTA el cese, así que un feriado
-- posterior a esa fecha no entra en ese cálculo — sí entraría en el cierre
-- del mes completo (0244), pero esa es otra función. La causa real que sí se
-- ve por acá, y que el propio 0167 nombra como la más frecuente de todas, es
-- un marcaje corregido DENTRO del rango que ya se pagó.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000358002', 'pago normal') $$,
  '12 · FeriadoB se paga primero, sin ningún descuento de por medio');

select lives_ok(
  $$ update jornadas set horas_trabajadas = 8.0
      where persona_id='00000000-0000-0000-0000-000000358002' and fecha='2020-07-05' $$,
  '13 · después se corrige un marcaje de un día ya pagado, dentro del rango');

select is(
  (select origen from fn_liquidacion_diferencias('00000000-0000-0000-0000-000000358002')
    where concepto = 'Sueldo del periodo'),
  'real',
  '14 · esa diferencia no la explica ningún cierre: es real, y así se marca');

select is(
  (select descuadra_real from fn_liquidaciones_pendientes()
    where persona_id='00000000-0000-0000-0000-000000358002'),
  true,
  '15 · descuadra_real SÍ se enciende: esto hay que revisarlo');


-- ── § 4 · No quedó una sobrecarga fantasma de 2 argumentos ──────────────────
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_liquidacion_pagar'),
  1,
  '16 · fn_liquidacion_pagar tiene una sola definición — nada de sobrecarga por nombre');

select * from finish();
rollback;
