-- ============================================================================
-- 186_la_retencion_de_cuarta_se_calcula_sola.test.sql — migración 0245
-- ============================================================================
-- A quien cobra por recibo por honorarios se le retiene el 8 % de renta de
-- cuarta categoría. Hasta la 0245 no se le retenía nada: había que escribirlo a
-- mano como un movimiento de tipo 'descuento', mes por mes.
--
-- POR QUÉ DIEZ PERSONAS Y NO UNA. La regla tiene cuatro entradas —el modo, la
-- constancia, el monto y el vínculo— y cada una se equivoca por su cuenta:
--
--   · el MODO en NULL no puede retener nada, o pegar la migración le habría
--     cambiado el neto a tres locadores el mismo día;
--   · el TOPE es «excede», no «alcanza»: justo en S/1,500 no se retiene, y un
--     céntimo más arriba sí. Es la frontera que un `>=` mal puesto se lleva;
--   · la CONSTANCIA manda sobre el modo mientras esté vigente, y devuelve el
--     mando cuando vence;
--   · el VÍNCULO es el guarda final: un trabajador de planilla no emite recibo
--     por honorarios, y si alguien le escribe el modo a mano no debe pasar nada.
--
-- Y LO QUE NO DEBE MOVERSE, que es la mitad del valor de esta prueba: la persona
-- de planilla al lado, que tiene que cobrar el mismo céntimo que antes de la
-- 0245. Un cálculo nuevo que le toque el sueldo a las treinta personas que sí
-- están en planilla sería mucho peor que el trabajo manual que vino a ahorrar.
--
-- Abril 2026 del 1 al 28, 24 días de 8 h = 192 h. Con el factor de la 0239 el
-- pago queda en salario × 192 / (6.5 × 28): S/1,800 → 1898.90 (sobre el tope) y
-- S/1,000 → 1054.95 (por debajo). Los bonos ajustan la base al céntimo para
-- poder pararse justo encima de la frontera.
-- ============================================================================
begin;
select plan(18);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000c4', 'ZZ4TA', 'Sede de laboratorio 4ta', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id)
values ('00000000-0000-0000-0000-00000000c499', 'Adm4ta', 'Laboratorio',
        '00000000-0000-0000-0000-0000000000c4', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000c498');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c498', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso,
                      tipo_vinculo, retencion_4ta, constancia_4ta_hasta) values
  -- Sobre el tope (1898.90)
  ('00000000-0000-0000-0000-00000000c401', 'Alto', 'SinConfigurar',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', null,         null),
  ('00000000-0000-0000-0000-00000000c402', 'Alto', 'Automatica',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'automatica', null),
  ('00000000-0000-0000-0000-00000000c403', 'Alto', 'ConstanciaVigente',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'automatica', '2026-12-31'),
  ('00000000-0000-0000-0000-00000000c404', 'Alto', 'ConstanciaVencida',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'automatica', '2025-12-31'),
  ('00000000-0000-0000-0000-00000000c405', 'Alto', 'ConDescuento',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'automatica', null),
  -- Por debajo del tope (1054.95), y los dos que se paran en la frontera
  ('00000000-0000-0000-0000-00000000c406', 'Bajo', 'Automatica',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'automatica', null),
  ('00000000-0000-0000-0000-00000000c407', 'Bajo', 'Siempre',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'siempre',    null),
  ('00000000-0000-0000-0000-00000000c408', 'Justo', 'EnElTope',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'automatica', null),
  ('00000000-0000-0000-0000-00000000c409', 'Justo', 'UnCentimoArriba',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'rxh', 'automatica', null),
  -- El testigo: de planilla, y con el modo escrito a mano para probar el guarda
  ('00000000-0000-0000-0000-00000000c410', 'Testigo', 'DePlanilla',
   '00000000-0000-0000-0000-0000000000c4', 'th', '2025-01-01', 'planilla', 'siempre', null);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla',
       case when nombres in ('Alto', 'Testigo') then 1800 else 1000 end,
       '2025-01-01'
from personas
where sede_base_id = '00000000-0000-0000-0000-0000000000c4'
  and id <> '00000000-0000-0000-0000-00000000c499';

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 8, 'cerrada'
from generate_series('2026-04-01'::date, '2026-04-28'::date, interval '1 day') d
cross join (select id from personas
             where sede_base_id = '00000000-0000-0000-0000-0000000000c4'
               and id <> '00000000-0000-0000-0000-00000000c499') p
where extract(dow from d) <> 0;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-0000000000c7', '2026-04-01', '2026-04-28', 'abierto');

-- Los bonos que paran a alguien JUSTO en el tope, y el descuento que no debe
-- bajar la base: 1054.95 + 445.05 = 1500.00 exacto, y + 445.06 = 1500.01.
insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por) values
  ('00000000-0000-0000-0000-0000000000c7', '00000000-0000-0000-0000-00000000c408',
   'bono', 'Ajuste para parar en el tope', 445.05, '00000000-0000-0000-0000-00000000c499'),
  ('00000000-0000-0000-0000-0000000000c7', '00000000-0000-0000-0000-00000000c409',
   'bono', 'Ajuste para pasar el tope por un centimo', 445.06, '00000000-0000-0000-0000-00000000c499'),
  ('00000000-0000-0000-0000-0000000000c7', '00000000-0000-0000-0000-00000000c405',
   'descuento', 'Ya pagado por fuera', 500.00, '00000000-0000-0000-0000-00000000c499');

create temp table _r on commit drop as
select (e->>'persona_id')::uuid                       as pid,
       (e->>'retencion_4ta')::numeric                 as ret,
       (e->>'retencion_4ta_base')::numeric            as base,
       (e->>'retencion_4ta_sin_configurar')::boolean  as avisa,
       (e->>'pago_base')::numeric                     as pago_base,
       (e->>'total')::numeric                         as total
from jsonb_array_elements(
       fn_planilla_calcular('2026-04-01', '2026-04-28',
                            '00000000-0000-0000-0000-0000000000c7') -> 'filas') e;

-- ── 1 · Sin configurar no se retiene NADA ──────────────────────────────────
-- Es la propiedad que hace que la 0245 se pueda pegar en producción sin que
-- nadie cobre distinto: las dos columnas nacen en NULL.
select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c401'),
  0::numeric,
  'A un locador sin modo configurado no se le retiene un centimo');

select is(
  (select total from _r where pid = '00000000-0000-0000-0000-00000000c401'),
  (select pago_base from _r where pid = '00000000-0000-0000-0000-00000000c401'),
  'Y su total sigue siendo exactamente su pago por horas');

-- ── 2 · Pero se AVISA, que es la otra mitad del trabajo ────────────────────
select ok(
  (select avisa from _r where pid = '00000000-0000-0000-0000-00000000c401'),
  'Un locador sin configurar cuyo recibo pasa el tope queda marcado en pantalla');

select ok(
  not (select avisa from _r where pid = '00000000-0000-0000-0000-00000000c406'),
  'Pero uno por debajo del tope no molesta: no hay nada que configurar');

-- ── 3 · La regla legal: 8 % del recibo, art. 74 de la Ley del IR ───────────
select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c402'),
  151.91::numeric,
  'Sobre el tope y en automatica: 8% de 1898.90 = 151.91');

select is(
  (select total from _r where pid = '00000000-0000-0000-0000-00000000c402'),
  1746.99::numeric,
  'Y el total lo resta UNA vez: 1898.90 - 151.91');

select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c406'),
  0::numeric,
  'Por debajo del tope, en automatica, no se retiene');

-- ── 4 · LA FRONTERA. «No excede» no es «no alcanza» ───────────────────────
-- R.S. 013-2007/SUNAT: no procede la retencion cuando el recibo NO EXCEDE los
-- S/1,500. Justo en 1500.00 no se retiene; con un centimo mas, si. Es el error
-- que un `>=` mal puesto comete sin que ninguna pantalla lo muestre.
select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c408'),
  0::numeric,
  'Justo en S/1,500.00 no se retiene: el tope es EXCEDER, no alcanzar');

select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c409'),
  120.00::numeric,
  'Un centimo por encima si se retiene: 8% de 1500.01 = 120.00');

-- ── 5 · «Siempre» retiene aunque el recibo sea chico ──────────────────────
-- Es el caso real que pidio la migracion: el prestador que factura a muchas
-- empresas y prefiere adelantar el 8% antes que pagarlo entero en marzo.
select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c407'),
  84.40::numeric,
  'En modo siempre se retiene aunque el recibo este por debajo del tope');

-- ── 6 · La constancia del 1609 manda sobre el modo — mientras esté vigente ─
select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c403'),
  0::numeric,
  'Con constancia de suspension vigente no se retiene, diga lo que diga el modo');

select is(
  (select ret from _r where pid = '00000000-0000-0000-0000-00000000c404'),
  151.91::numeric,
  'Y cuando la constancia vence, el modo vuelve a mandar');

-- ── 7 · Un descuento NO baja la base ──────────────────────────────────────
-- Un descuento de planilla es casi siempre «esto ya se te transfirio por
-- fuera». El recibo se emitio por el monto completo, asi que restarlo de la
-- base retendria de menos.
select is(
  (select base from _r where pid = '00000000-0000-0000-0000-00000000c405'),
  1898.90::numeric,
  'Un descuento de S/500 no baja la base de la retencion');

-- ── 8 · EL TESTIGO NO SE MUEVE ────────────────────────────────────────────
-- De planilla, con el modo escrito a mano, y cobrando lo mismo que antes de la
-- 0245: los S/2,213.64 estan medidos contra la funcion de la 0242.
select is(
  (select total from _r where pid = '00000000-0000-0000-0000-00000000c410'),
  2213.64::numeric,
  'Quien esta en planilla cobra el mismo centimo que antes: el vinculo es el guarda');

-- ── 9 · La puerta por la que se escribe ───────────────────────────────────
-- No se configura con un `update` desde el cliente: decide cuánto neto recibe
-- una persona, así que pasa por una RPC que valida y deja rastro.
select throws_ok(
  $$ select fn_set_retencion_4ta('00000000-0000-0000-0000-00000000c410', 'siempre') $$,
  null,
  null,
  'A quien esta en planilla no se le puede configurar retencion de cuarta');

select throws_ok(
  $$ select fn_set_retencion_4ta('00000000-0000-0000-0000-00000000c401', 'a_veces') $$,
  null,
  null,
  'Un modo inventado se rechaza en la puerta, no al calcular la planilla');

select lives_ok(
  $$ select fn_set_retencion_4ta('00000000-0000-0000-0000-00000000c401', 'automatica', '2026-12-31') $$,
  'A un locador si se le puede configurar');

select isnt_empty(
  $$ select 1 from correcciones_auditoria
      where persona_id = '00000000-0000-0000-0000-00000000c401'
        and campo_modificado = 'personas.retencion_4ta' $$,
  'Y el cambio deja su rastro en correcciones_auditoria');

select * from finish();
rollback;
