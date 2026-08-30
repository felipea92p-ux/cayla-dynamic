-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 185_la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre.test.sql — 0244
-- ============================================================================
-- La 0243 ya está en producción y su prueba es la 184, que sigue existiendo y
-- sigue midiendo lo que aquella prometió. Esta mide otra cosa: los SEIS bordes
-- que la 0243 dejó abiertos y que cierra la 0244.
--
-- Corrida contra la 0243 tal como está pegada en producción, este archivo se
-- pone rojo en DOCE aserciones —29, 30, 31, 33, 34, 35, 37, 38, 43, 44, 45 y 51—;
-- con la 0244 puesta, verde. Esas doce son la medida de qué añade la 0244, y
-- están comprobadas por mutación: quitando una pieza cada vez, mueren exactamente
-- las del grupo que esa pieza sostiene y ninguna otra.
--
--   pieza                                   | aserciones que mueren sin ella
--   ----------------------------------------+-------------------------------
--   el gate `v_per.estado = 'pagado'`        | 29, 30, 33
--   el suelo `greatest(v_foto, 0)`           | 34, 35
--   la excepción del `retroactivo`           | 37, 38
--   la condición `< lq.monto_periodo`        | 43, 44
--   la rama del aviso «periodo reabierto»    | 31
--   la rama del aviso «ya se pagó»           | 45, 51
--   la rama del aviso de la 0243             | 49
--   el filtro por periodo del `v_liq`        | 50
--   el orden de versiones del `v_liq`        | 51
--
-- Nueve piezas y catorce aserciones, pero contra la 0243 caen doce y no catorce:
-- la 49 pasa porque esa rama del aviso YA existía en la 0243 —lo que no existía
-- era una prueba que la mirara—, y la 50 pasa en vacío porque la 0243 no lee
-- `liquidacion_pagada` en ningún sitio, así que no puede citarla mal. Las dos
-- vigilan que la 0244 no rompa lo que hereda, no lo que arregla.
--
-- Esa tabla cita aserciones POR NÚMERO, así que las que se agreguen van al final
-- (§ 14) y nunca en medio: insertar una arriba correría todas las demás y
-- dejaría mintiendo a esta tabla y a la gemela de la 0244.
--
-- Y § 14 existe porque la misma mutación encontró tres piezas SIN vigilancia: la
-- rama del aviso que puso la 0243 —la que explica una resta de dinero—, el filtro
-- por periodo del `v_liq` y su orden de versiones. Rompiendo cualquiera de las
-- tres, la 184 y la 185 se quedaban enteras en verde. Quedan en 49, 50 y 51.
--
-- LO QUE SIGUE SIN VIGILAR, dicho para que no se confunda con un descuido: el
-- `raise warning` del caso retroactivo (0244) puede enmudecerse sin que ninguna
-- aserción caiga, porque la 37 es un `lives_ok` y pgTAP no captura warnings. Se
-- deja así a sabiendas: lo que importa de ese caso —que la función NO aborte y
-- que la foto histórica quede tomada— sí está medido, en la 37 y la 38.
--
-- POR QUÉ REPITE EL MONTAJE DE LA 184 EN VEZ DE COMPARTIRLO. Son dos archivos
-- que miden dos versiones distintas de las mismas dos funciones, y los dos
-- tienen que poder correr. Todo lo que este crea vive en su propio espacio de
-- nombres —sede `ZZ185`, UUIDs `…185NNN`— así que ni un dato se cruza con la
-- 184, corran en el orden que corran.
--
-- LO QUE YA MEDÍA LA 184 Y ACÁ SE VUELVE A MEDIR, porque es el suelo que la 0244
-- no puede romper: que DONDE NO HAY FOTO no se reste nada —la regresión
-- principal, invisible para las ~30 personas que no están en esta situación—, y
-- que donde SÍ hay foto se reste exactamente lo transferido, con sus tres
-- trampas: la `version` es del PERIODO y no de la persona (0201), la vista
-- `v_planilla_pagada` resuelve con el máximo GLOBAL y dejaría fuera justo a la
-- cesada que hay que cazar, y el suelo en cero con las truncas enteras.
--
-- LOS SEIS BORDES QUE MIDE ESTE ARCHIVO, todos medidos antes de escribirlos:
--
--   1. UNA FOTO NO ACREDITA QUE EL DINERO SALIERA. `fn_revertir_pago` (0203)
--      devuelve el periodo a 'abierto' y NO borra la foto —el trigger de
--      inmutabilidad bloquea el delete—, así que un mes cerrado por error y
--      revertido antes de transferir deja una foto viva de un pago que no
--      ocurrió. Con la 0243 eso le quita el mes entero a quien no cobró un
--      céntimo: su liquidación sale en S/1,393.27 en vez de S/2,143.27, y la
--      hoja lo afirma por escrito. Es el borde que PAGA DE MENOS.  (§ 8)
--   2. UNA FOTO PUEDE SER NEGATIVA. `total` es numeric(12,2) sin check de
--      no-negativo y `chk_foto_cuadra` la admite en cuanto los descuentos
--      superan lo devengado. Restar un negativo SUMA: S/2,817.65 en vez de
--      S/2,567.65, S/250.00 de más y sin una línea que lo explique.  (§ 9)
--   3. LA FOTO RETROACTIVA NO SE FRENA. `fn_planilla_congelar_pendientes` (0096)
--      documenta meses transferidos hace tiempo; ahí «el dinero todavía no
--      salió» es falso por construcción y con la 0243 el freno aborta la función
--      entera, dejando esos periodos sin foto para siempre.  (§ 10)
--   4. EL FRENO SE LEVANTA CON EL DESCUENTO, NO CON LA FILA EN CERO. Con
--      `total > 0` como única salida, quien hace EXACTAMENTE lo que el mensaje
--      manda sigue sin poder cerrar el mes si le queda un saldo ganado de
--      verdad, y las dos escapatorias son quitarle ese saldo o falsear un
--      registro inmutable.  (§ 11)
--   5. Y ese caso no es raro: el art. 4 del D.S. 001-97-TR obliga a liquidar en
--      48 horas y el periodo cierra el 28, así que liquidar antes de congelar es
--      el orden NORMAL. Por eso § 11 monta el flujo legal limpio —cesa el 10, se
--      liquida el 12— y no un caso de laboratorio.
--   6. EL CERO NO SE DEJA EN SILENCIO. Tras el descuento que el freno OBLIGA a
--      registrar, el devengado baja solo y la hoja quedaba en S/0.00 sin decir
--      por qué.  (§ 12)
--
-- El montaje: S/1,500, jornadas de 6.5 h del 1 al 15, cese el 15. Periodos que
-- no se solapan y no se estorban —lo exige el EXCLUDE `periodos_sin_solape`, y
-- es lo que hace fiable deducir el periodo por la fecha de cese—: junio SIN
-- congelar (la regresión), abril CONGELADO (la resta), mayo para el freno, julio
-- REABIERTO, marzo histórico y agosto para el saldo.
-- ============================================================================
begin;
select plan(51);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000185000', 'ZZ185', 'Sede de laboratorio 185', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000185099', 'Admin185', 'Laboratorio',
        '00000000-0000-0000-0000-000000185000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000185098', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000185098', true);

-- Sin feriados de por medio: acá lo que se compara son dos llamadas a la misma
-- función, y un feriado dentro de un rango y fuera del otro sería ruido. La
-- excepción es agosto, donde el feriado POSTERIOR AL CESE es justamente lo que
-- monta el saldo legítimo de la trampa 7 — ahí se pone uno a mano.
delete from feriados where fecha between '2026-03-01' and '2026-08-31';

-- Nueve personas iguales entre sí. Lo único que las distingue es qué le pasa a
-- su periodo, que es justamente lo que esta prueba mide.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000185001', 'SinFoto',    'Junio',  '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185002', 'ConFoto',    'Abril',  '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185003', 'DosVersiones', 'Abril','00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185004', 'FotoDeMas',  'Abril',  '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185005', 'FrenoFlor',  'Mayo',   '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185006', 'Reabierta',  'Julio',  '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185007', 'FotoNegativa','Abril', '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185008', 'Historica',  'Marzo',  '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000185009', 'SaldoSuyo',  'Agosto', '00000000-0000-0000-0000-000000185000', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 1500.00, '2024-01-02'
from personas
where sede_base_id = '00000000-0000-0000-0000-000000185000'
  and id <> '00000000-0000-0000-0000-000000185099';

-- Tres periodos que no se solapan (lo exige el EXCLUDE `periodos_sin_solape`, y
-- es lo que hace fiable deducir el periodo por la fecha de cese).
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000185101', '2026-06-01', '2026-06-30', 'abierto'),  -- nunca se congela
  ('00000000-0000-0000-0000-000000185102', '2026-04-01', '2026-04-30', 'abierto'),  -- se congela
  ('00000000-0000-0000-0000-000000185103', '2026-05-01', '2026-05-30', 'abierto'),  -- el freno
  ('00000000-0000-0000-0000-000000185104', '2026-07-01', '2026-07-30', 'abierto'),  -- se cierra y se REVIERTE
  ('00000000-0000-0000-0000-000000185105', '2026-03-01', '2026-03-30', 'abierto'),  -- historico, foto retroactiva
  ('00000000-0000-0000-0000-000000185106', '2026-08-01', '2026-08-30', 'abierto');  -- el saldo que si gano

-- Cada una trabaja del 1 al 15 de SU mes y cesa el 15.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000185001', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 6.5, 'cerrada'
from generate_series('2026-04-01'::date, '2026-04-15'::date, interval '1 day') d
cross join (values ('00000000-0000-0000-0000-000000185002'::uuid),
                   ('00000000-0000-0000-0000-000000185003'::uuid),
                   ('00000000-0000-0000-0000-000000185004'::uuid),
                   ('00000000-0000-0000-0000-000000185007'::uuid)) p(id);

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000185005', d::date, 6.5, 'cerrada'
from generate_series('2026-05-01'::date, '2026-05-15'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000185006', d::date, 6.5, 'cerrada'
from generate_series('2026-07-01'::date, '2026-07-15'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000185008', d::date, 6.5, 'cerrada'
from generate_series('2026-03-02'::date, '2026-03-15'::date, interval '1 day') d;

-- Agosto: trabaja del 1 al 10 y cesa el 10, pero el periodo llega al 30 y trae
-- un FERIADO el 20. Así el total del periodo (que va del 1 al 30) es mayor que
-- el sueldo que su liquidación cobró (que va del 1 al 10): ese sobrante es el
-- saldo legítimo que el freno le estaba quitando.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000185009', d::date, 6.5, 'cerrada'
from generate_series('2026-08-01'::date, '2026-08-10'::date, interval '1 day') d;
insert into feriados (fecha, nombre) values ('2026-08-20', 'Feriado de laboratorio 185');

-- El cese se pone a mano, como en la 130 y la 133: `fn_cesar_persona` se niega a
-- cesar dentro de un periodo ya pagado (0176:285-291) y acá hace falta cesar
-- antes y después del congelamiento.
update personas set estado = 'inactivo', fecha_cese = '2026-06-15' where id = '00000000-0000-0000-0000-000000185001';
update personas set estado = 'inactivo', fecha_cese = '2026-04-15' where id in (
  '00000000-0000-0000-0000-000000185002',
  '00000000-0000-0000-0000-000000185003',
  '00000000-0000-0000-0000-000000185004',
  '00000000-0000-0000-0000-000000185007');
update personas set estado = 'inactivo', fecha_cese = '2026-05-15' where id = '00000000-0000-0000-0000-000000185005';
update personas set estado = 'inactivo', fecha_cese = '2026-07-15' where id = '00000000-0000-0000-0000-000000185006';
update personas set estado = 'inactivo', fecha_cese = '2026-03-15' where id = '00000000-0000-0000-0000-000000185008';
update personas set estado = 'inactivo', fecha_cese = '2026-08-10' where id = '00000000-0000-0000-0000-000000185009';

-- Lo que la liquidación decía ANTES de que existiera ninguna foto. Es contra
-- esto contra lo que se mide la resta: sin este «antes», la prueba solo podría
-- decir que el número es distinto, no que bajó en lo que se transfirió.
create temp table _antes as
select p.id                                                  as pid,
       (fn_liquidacion(p.id, p.fecha_cese)->'periodo'->>'monto')::numeric as monto,
       (fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric            as total
from personas p
where p.sede_base_id = '00000000-0000-0000-0000-000000185000'
  and p.id <> '00000000-0000-0000-0000-000000185099';


-- ── 1 · SIN FOTO NO SE RESTA NADA — la regresión principal ──────────────────
-- El periodo de junio no se congela en ningún momento de este archivo. Aunque
-- la base se llene de fotos de abril, esta persona tiene que cobrar lo mismo que
-- cobraba antes de la 0243.
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185001', '2026-06-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  0::numeric,
  'SIN FOTO · no hay nada que restar, y se dice con un cero, no con un nulo');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185001', '2026-06-15')->'periodo'->>'monto')::numeric,
  (select round((value->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-06-01', '2026-06-15',
              '00000000-0000-0000-0000-000000185101') -> 'filas') as t(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-000000185001'),
  'SIN FOTO · el sueldo sigue siendo EXACTAMENTE lo que calcula la planilla');

select ok(
  (fn_liquidacion('00000000-0000-0000-0000-000000185001', '2026-06-15')->>'aviso_periodo') is null,
  'SIN FOTO · y no se avisa de un descuento que no existe');


-- ── 2 · Congelar abril no frena, porque nadie cobró su liquidación ──────────
-- Control negativo. Si el freno se escribiera demasiado ancho —mirando
-- `liquidacion_pagada` sin acotar al periodo, o sin exigir monto_periodo > 0—
-- esta línea sola tumbaría el cierre de un mes normal.
select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185102', true) $$,
  'CIERRE · un periodo con gente cesada pero sin liquidaciones pagadas se cierra igual');

-- Una versión 2 SOLO para dos de las tres. La tercera (ConFoto) se queda en la
-- v1 mientras el periodo va por la v2: es el caso de la cesada que ya no sale en
-- el recálculo, y el que la vista v_planilla_pagada no sabría resolver.
insert into planilla_pagada_detalle
  (periodo_id, persona_id, version, origen, nombre, sede_codigo, pago_base, total, fila)
values
  ('00000000-0000-0000-0000-000000185102', '00000000-0000-0000-0000-000000185003', 2,
   'pago', 'DosVersiones Abril', 'ZZ185', 10.00, 10.00, '{}'::jsonb),
  ('00000000-0000-0000-0000-000000185102', '00000000-0000-0000-0000-000000185004', 2,
   'pago', 'FotoDeMas Abril', 'ZZ185', 9999.00, 9999.00, '{}'::jsonb);


-- ── 3 · CON FOTO se resta exactamente lo transferido ───────────────────────
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  (select total from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000185102'
      and persona_id = '00000000-0000-0000-0000-000000185002'
      and version = 1),
  'CON FOTO · lo que se resta es exactamente lo que dice la foto del pago');

select is(
  (select a.total from _antes a where a.pid = '00000000-0000-0000-0000-000000185002')
  - (fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-04-15')->>'total')::numeric,
  (fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  'CON FOTO · el total baja exactamente en lo transferido, ni un centimo mas');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-04-15')->'periodo'->>'devengado')::numeric,
  (select a.monto from _antes a where a.pid = '00000000-0000-0000-0000-000000185002'),
  'CON FOTO · el devengado sigue diciendo lo que tocaba por el mes, sin descontar');

-- LA TRAMPA DEL MÁXIMO GLOBAL. El periodo va por la version 2, pero ConFoto solo
-- existe en la 1. `v_planilla_pagada` le devolvería cero filas y la resta seria
-- 0 — justo para quien la 0243 viene a cazar.
select is(
  (select max(version) from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000185102'),
  2,
  'VERSION · el periodo va por la v2 (montaje de la trampa siguiente)');

select cmp_ok(
  (fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  '>', 0::numeric,
  'VERSION · a quien solo existe en la v1 se le sigue restando: no se usa el max del PERIODO');


-- ── 4 · Dos versiones no duplican la resta ─────────────────────────────────
-- La v1 vale ~750 y la v2 vale 10. Sumarlas restaria ~760; la respuesta es 10.
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185003', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  10.00::numeric,
  'VERSION · manda la ULTIMA version de esa persona, no la suma de todas');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185003', '2026-04-15')->'periodo'->>'foto_version')::int,
  2,
  'VERSION · y lo dice, para que la hoja pueda citar de que foto salio');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185003', '2026-04-15')->'periodo'->>'monto')::numeric,
  round((select a.monto from _antes a where a.pid = '00000000-0000-0000-0000-000000185003') - 10.00, 2),
  'VERSION · el neto descuenta 10.00 y no 760.00: la resta no se duplica');


-- ── 5 · Nunca negativo, y las truncas se pagan enteras ─────────────────────
-- La foto vigente dice 9999.00 sobre un mes de ~750. La respuesta no es -9249.
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185004', '2026-04-15')->'periodo'->>'monto')::numeric,
  0::numeric,
  'SUELO · si lo ya transferido supera lo calculado, el sueldo del periodo va a 0');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185004', '2026-04-15')->>'total')::numeric,
  round((fn_vacaciones_truncas('00000000-0000-0000-0000-000000185004', '2026-04-15')->>'monto')::numeric
      + (fn_grati_trunca('00000000-0000-0000-0000-000000185004', '2026-04-15')->>'monto')::numeric
      + (fn_cts_trunca('00000000-0000-0000-0000-000000185004', '2026-04-15')->>'monto')::numeric, 2),
  'SUELO · y las tres truncas se pagan ENTERAS: no estan en la planilla del mes');

select cmp_ok(
  (fn_liquidacion('00000000-0000-0000-0000-000000185004', '2026-04-15')->>'total')::numeric,
  '>', 0::numeric,
  'SUELO · el total sigue siendo positivo: nadie cobra de menos por este arreglo');


-- ── 6 · El freno del orden inverso ─────────────────────────────────────────
-- Mayo sigue abierto, asi que la liquidacion cobra el mes entero: es el orden
-- que produjo los seis casos de julio.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000185005', 'pago de laboratorio') $$,
  'FRENO · con el periodo abierto la liquidacion se paga y se lleva el mes entero');

select cmp_ok(
  (select monto_periodo from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000185005' order by version desc limit 1),
  '>', 0::numeric,
  'FRENO · esa liquidacion guarda el sueldo del mes: es lo que se solaparia');

-- Y ahora cerrar mayo pagaria el mismo mes por segunda vez. Un «no se puede»
-- sin nombre obligaria a revisar a las 30 personas del periodo una por una.
select throws_like(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185103', true) $$,
  '%FrenoFlor Mayo%',
  'FRENO · el cierre se niega y NOMBRA a la persona, no dice solo que no se puede');

select throws_like(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185103', true) $$,
  '%Ya le pagué aparte%',
  'FRENO · y dice el paso exacto que lo levanta, que en este estado si esta disponible');

select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-000000185103'),
  'abierto',
  'FRENO · el periodo sigue ABIERTO: no se congelo nada a medias');

select is(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000185103'),
  0,
  'FRENO · y no queda ni una fila de foto: el insert es uno solo y se revirtio entero');

-- LA SEGUNDA MITAD, que es la que evita que esto acabe en `--no-verify`: el
-- freno se levanta solo en cuanto el descuento esta registrado. El boton
-- «Ya le pague aparte» hace exactamente esto (planilla/page.tsx:1357-1363).
select lives_ok(
  $$ select fn_agregar_movimiento(
       '00000000-0000-0000-0000-000000185103',
       '00000000-0000-0000-0000-000000185005',
       'descuento',
       'Ya pagado el 15/05/2026 — fuera de planilla',
       (select round((value->>'total')::numeric, 2)
          from jsonb_array_elements(
                 fn_planilla_calcular('2026-05-01', '2026-05-30',
                   '00000000-0000-0000-0000-000000185103') -> 'filas') as t(value)
         where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-000000185005')) $$,
  'FRENO · con el periodo abierto el descuento SI se puede registrar');

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185103', true) $$,
  'FRENO · y entonces el cierre pasa: el freno se levanta solo, no hay que desactivarlo');


-- ── 7 · El repago tampoco vuelve a registrar el mes ────────────────────────
-- El caso de julio, que es el que ya está en producción: la liquidación se pagó
-- ANTES de que existiera la 0243, así que guardó el mes ENTERO, y el periodo ya
-- está cerrado. Se monta a mano —como hace la 164 con esta misma tabla— porque
-- desde la 0243 ninguna liquidación nueva puede quedar así.
--
-- Si el freno se apagara con el periodo pagado, `fn_repagar_periodo` escribiría
-- una versión nueva con el total completo y el doble pago volvería a entrar por
-- la otra puerta.
insert into liquidacion_pagada
  (persona_id, version, congelada_por, persona, fecha_ingreso, fecha_cese,
   monto_periodo, total, detalle)
select '00000000-0000-0000-0000-000000185002', 1,
       '00000000-0000-0000-0000-000000185099', 'ConFoto Abril', '2024-01-02', '2026-04-15',
       d.total, d.total, '{}'::jsonb
from planilla_pagada_detalle d
where d.periodo_id = '00000000-0000-0000-0000-000000185102'
  and d.persona_id = '00000000-0000-0000-0000-000000185002'
  and d.version = 1;

select throws_like(
  $$ select fn_repagar_periodo('00000000-0000-0000-0000-000000185102', 'recalculo de laboratorio') $$,
  '%ConFoto Abril%',
  'REPAGO · volver a congelar un periodo pagado tambien frena, y nombra a la persona');

select throws_like(
  $$ select fn_repagar_periodo('00000000-0000-0000-0000-000000185102', 'recalculo de laboratorio') $$,
  '%Revertir pago%',
  'REPAGO · y manda al rodeo que SI existe en ese estado, no al boton que esta bloqueado');


-- ── 8 · UNA FOTO NO ACREDITA QUE EL DINERO SALIERA ─────────────────────────
-- Julio se cierra POR ERROR y se revierte ANTES de transferir nada. La foto
-- sobrevive a la reapertura porque el trigger de inmutabilidad bloquea el
-- delete (0203 solo cambia el estado). Si la resta se fiara de que la fila
-- existe, a esta persona se le quitaria el mes entero sin que nadie le haya
-- pagado un centimo — y la hoja lo afirmaria por escrito.
select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185104', true) $$,
  'REABIERTO · julio se cierra (por error, en este montaje)');

select lives_ok(
  $$ select fn_revertir_pago('00000000-0000-0000-0000-000000185104',
       'cerrado por error: NO se transfirio nada al banco') $$,
  'REABIERTO · y se revierte antes de transferir');

select cmp_ok(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000185104'),
  '>', 0,
  'REABIERTO · la foto SIGUE VIVA: revertir no la borra (montaje de la trampa)');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185006', '2026-07-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  0::numeric,
  'REABIERTO · y aun asi no se acredita nada: el periodo ya no esta pagado');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185006', '2026-07-15')->'periodo'->>'monto')::numeric,
  (fn_liquidacion('00000000-0000-0000-0000-000000185006', '2026-07-15')->'periodo'->>'devengado')::numeric,
  'REABIERTO · cobra el mes ENTERO: nadie pierde un sueldo por una foto huerfana');

-- Y no se calla, porque el caso simetrico —reversion de un pago que SI salio—
-- no lo puede resolver la base: lo decide quien firma.
select alike(
  (fn_liquidacion('00000000-0000-0000-0000-000000185006', '2026-07-15')->>'aviso_periodo'),
  '%COMPRU%',
  'REABIERTO · pero lo DICE y manda comprobarlo a mano, en vez de callarse');

-- La segunda red: al volver a cerrar julio, su liquidacion ya pagada guarda el
-- mes entero, asi que el freno de la parte (B) tiene a quien nombrar.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000185006', 'pago tras la reversion') $$,
  'REABIERTO · se le paga la liquidacion completa');

select throws_like(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185104', true) $$,
  '%Reabierta Julio%',
  'REABIERTO · y al recerrar julio el freno la caza: la red de atras si funciona');


-- ── 9 · UNA FOTO NEGATIVA NO SUMA ──────────────────────────────────────────
-- `total` es numeric(12,2) sin check de no-negativo, y `chk_foto_cuadra` la
-- admite en cuanto los descuentos superan lo devengado (se llega con
-- fn_agregar_movimiento sola). Restar un negativo SUMARIA.
insert into planilla_pagada_detalle
  (periodo_id, persona_id, version, origen, nombre, sede_codigo,
   pago_base, descuentos, total, fila)
values
  ('00000000-0000-0000-0000-000000185102', '00000000-0000-0000-0000-000000185007', 3,
   'pago', 'FotoNegativa Abril', 'ZZ185', 0.00, 250.00, -250.00, '{}'::jsonb);

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185007', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  0::numeric,
  'NEGATIVA · una foto negativa acredita CERO, no un numero bajo cero');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000185007', '2026-04-15')->'periodo'->>'monto')::numeric,
  (select a.monto from _antes a where a.pid = '00000000-0000-0000-0000-000000185007'),
  'NEGATIVA · y el sueldo del periodo no SUBE ni un centimo por encima de lo devengado');


-- ── 10 · LA FOTO RETROACTIVA NO SE FRENA ───────────────────────────────────
-- `fn_planilla_congelar_pendientes` (0096) documenta meses YA transferidos que
-- se quedaron sin foto. Ahi la premisa del freno —«el dinero de este cierre
-- todavia no salio»— es falsa por construccion: seguir su instruccion
-- inventaria un descuento que nunca ocurrio sobre el registro de un pago viejo.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000185008', 'liquidacion historica') $$,
  'RETROACTIVO · su liquidacion se pago en su momento');

update periodos_planilla set estado = 'pagado', pagado_at = now()
where id = '00000000-0000-0000-0000-000000185105';

select lives_ok(
  $$ select fn_planilla_congelar_pendientes() $$,
  'RETROACTIVO · el backfill de la 0096 NO se atasca: documenta lo que ya se pago');

select cmp_ok(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000185105'),
  '>', 0,
  'RETROACTIVO · y la foto historica queda tomada, no perdida para siempre');


-- ── 11 · EL FRENO SE LEVANTA CON EL DESCUENTO, NO CON LA FILA EN CERO ──────
-- Agosto: cesa el 10, pero el periodo llega al 30 y trae un feriado el 20. El
-- total del periodo es MAYOR que el sueldo que su liquidacion cobro, asi que
-- descontar lo que el mensaje nombra NO deja su fila en cero. Con `total > 0`
-- como unica salida, el mes no cerraba nunca y las dos escapatorias eran
-- quitarle un saldo ganado o falsear un registro inmutable.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000185009', 'liquidacion en 48h, como manda la ley') $$,
  'SALDO · se liquida dentro del plazo legal, con el periodo abierto');

select cmp_ok(
  (select round((value->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-08-01', '2026-08-30',
              '00000000-0000-0000-0000-000000185106') -> 'filas') as t(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-000000185009'),
  '>',
  (select monto_periodo from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000185009' order by version desc limit 1),
  'SALDO · el periodo le calcula MAS de lo que su liquidacion cobro (montaje de la trampa)');

select throws_like(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185106', true) $$,
  '%SaldoSuyo Agosto%',
  'SALDO · sin el descuento el cierre frena, que es lo correcto');

-- EXACTAMENTE lo que el mensaje manda: el importe que nombra, ni uno mas.
select lives_ok(
  $$ select fn_agregar_movimiento(
       '00000000-0000-0000-0000-000000185106',
       '00000000-0000-0000-0000-000000185009',
       'descuento',
       'Ya pagado el 12/08/2026 — fuera de planilla',
       (select monto_periodo from liquidacion_pagada
         where persona_id = '00000000-0000-0000-0000-000000185009' order by version desc limit 1)) $$,
  'SALDO · se registra el descuento por el importe que el mensaje nombra');

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000185106', true) $$,
  'SALDO · y el mes CIERRA, aunque su fila no quede en cero');

select cmp_ok(
  (select total from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000185106'
      and persona_id = '00000000-0000-0000-0000-000000185009'
    order by version desc limit 1),
  '>', 0::numeric,
  'SALDO · y cobra el saldo que SI gano: el freno no le quita dinero ganado');


-- ── 12 · EL CERO TAMPOCO SE DEJA EN SILENCIO ───────────────────────────────
-- Tras el descuento que el freno OBLIGA a registrar, el devengado del mes baja
-- solo y la hoja quedaba en S/0.00 sin decir por que, mientras
-- `liquidacion_pagada` seguia diciendo el importe entero. La promesa «no se
-- resta en silencio» tiene que cubrir la ruta que la propia 0243 vuelve
-- obligatoria, no solo la comoda.
select alike(
  (fn_liquidacion('00000000-0000-0000-0000-000000185009', '2026-08-10')->>'aviso_periodo'),
  '%liquidación ya se pagó%',
  'SILENCIO · reabrir su hoja tras el descuento explica de donde sale el numero');


-- ── 13 · Y QUIEN PUEDE LLAMAR A CADA UNA ───────────────────────────────────
-- El bloque de comprobacion de la 0244 mira esto, pero corre UNA SOLA VEZ, al
-- pegar. El dia que alguien conceda en masa —ya paso, 0076— la suite tiene que
-- enterarse. `fn_planilla_congelar` no lleva guard adentro: su unica proteccion
-- es este revoke.
select ok(
  has_function_privilege('authenticated', 'fn_liquidacion(uuid, date)', 'execute'),
  'PERMISOS · la pantalla de liquidaciones puede llamar a fn_liquidacion');

select ok(
  not has_function_privilege('anon', 'fn_liquidacion(uuid, date)', 'execute'),
  'PERMISOS · y sin sesion no se ve la liquidacion de nadie');

select ok(
  -- CAMBIO 0323 · fn_planilla_congelar gana un cuarto parámetro (p_grupo,
  -- con valor por defecto) para congelar un grupo a la vez; la firma que
  -- hay que nombrar aquí es la de 4 argumentos, no la vieja de 3.
  not has_function_privilege('authenticated', 'fn_planilla_congelar(uuid, text, uuid, text)', 'execute'),
  'PERMISOS · a fn_planilla_congelar no se llega desde el navegador: solo por sus cuatro llamadores');


-- ── 14 · LAS TRES PIEZAS DEL AVISO QUE NADIE VIGILABA ──────────────────────
-- Van al FINAL, y a propósito: las 48 de arriba están citadas por número en la
-- tabla de mutación de esta cabecera y en la de la 0244, así que insertar una en
-- medio las correría todas y dejaría las dos tablas mintiendo.
--
-- Las tres se descubrieron por mutación el 2026-08-14: rompiendo cada pieza, la
-- 184 y la 185 se quedaban ENTERAS EN VERDE. O sea que las dos ramas que agrega
-- la 0244 estaban probadas y las piezas de abajo no, siendo las que redactan el
-- único texto que explica —a quien firma— por qué le bajó el sueldo del periodo.
select alike(
  (fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-04-15')->>'aviso_periodo'),
  '%ya se le transfirió S/%',
  'AVISO · cuando SI hay resta, la hoja dice cuanto se restó: la rama que puso la 0243');

-- EL FILTRO POR PERIODO del `v_liq`. Sin él, la liquidación de un cese ANTERIOR
-- se citaría en la hoja de un periodo que no tiene nada que ver. El caso real es
-- la reincorporación: ConFoto cesó el 15/04 y cobró su liquidación; si volviera y
-- cesara de nuevo en junio, su hoja de junio no puede decir que ya se le pagó
-- —ese importe era de abril y ya está descontado allá—.
select unalike(
  coalesce(fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-06-15')->>'aviso_periodo', ''),
  '%liquidación ya se pagó%',
  'AVISO · y NO cita la liquidacion de un cese que cayo en otro periodo');

-- EL ORDEN DE VERSIONES del `v_liq`. Una segunda versión con un importe distinto:
-- el aviso tiene que citar la ULTIMA, que es el mismo criterio que usan el freno
-- y la 0210. Con `version asc` citaría la vieja y el número de la hoja no
-- cuadraría con el que la persona cobró.
insert into liquidacion_pagada
  (persona_id, version, congelada_por, persona, fecha_ingreso, fecha_cese,
   monto_periodo, total, detalle)
values
  ('00000000-0000-0000-0000-000000185002', 2,
   '00000000-0000-0000-0000-000000185099', 'ConFoto Abril', '2024-01-02', '2026-04-15',
   123.45, 123.45, '{}'::jsonb);

select alike(
  (fn_liquidacion('00000000-0000-0000-0000-000000185002', '2026-04-15')->>'aviso_periodo'),
  '%S/123.45%',
  'AVISO · manda la ULTIMA version de la liquidacion pagada, no la primera');


select * from finish();
rollback;
