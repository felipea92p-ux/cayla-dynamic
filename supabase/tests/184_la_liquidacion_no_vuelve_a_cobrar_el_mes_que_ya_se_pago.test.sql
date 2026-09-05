-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 184_la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago.test.sql — 0243
-- ============================================================================
-- El sueldo del periodo no es un concepto propio de la liquidación: es la
-- planilla del mismo mes, llamada con el rango que va del inicio del periodo a
-- la fecha de cese (0164:103). Así que el mes está en los dos sitios, y hasta la
-- 0243 nada los hacía hablarse. Seis personas que cesaron entre el 16 y el 25 de
-- julio quedaron dentro del periodo 28/06–28/07, se cerró el mes con ellas
-- dentro, y después se les pagó la liquidación con el mismo mes adentro:
-- S/1,381.59 registrados dos veces.
--
-- LAS DOS MITADES, como manda la 141, y acá la primera es la que más importa:
--
--   · que DONDE NO HAY FOTO no se reste nada. Es la regresión principal: la
--     resta tiene que ser invisible para las ~30 personas que no están en esta
--     situación. La prueba 130 ya la vigila con su propio montaje —periodo
--     `abierto`, nunca congelado—; acá se vigila algo que la 130 no puede ver,
--     porque su base no tiene fotos: que la foto de OTRA gente en OTRO periodo
--     tampoco se cuele.
--   · y que donde SÍ hay foto se reste exactamente lo transferido, ni un
--     céntimo más — con las tres trampas que tiene ese «exactamente»: la
--     versión, el máximo global del periodo, y el suelo en cero.
--
-- LAS TRES TRAMPAS, que son la razón de que este archivo exista:
--
--   1. La `version` de la foto es DEL PERIODO, no de la persona (0201). Un
--      repago deja la versión vieja viva —el trigger bloquea update y delete,
--      nunca insert—, así que sumar versiones multiplica la resta.
--   2. La vista `v_planilla_pagada` resuelve la versión con el máximo GLOBAL del
--      periodo. Quien no salió en el recálculo nuevo tiene su fila pagada en una
--      versión anterior y para la vista es invisible: restaría 0 justo a la
--      población que la 0243 persigue. Acá B1 está SOLO en la v1 mientras el
--      periodo va por la v2, que es ese caso exacto.
--   3. Si lo ya transferido supera lo calculado, el sueldo del periodo va a 0 y
--      NUNCA a negativo — y las tres truncas se pagan enteras, porque no están
--      en la planilla del mes y sí corresponden. Cobrar de menos es el error que
--      este sistema no comete.
--
-- Y el freno del orden inverso, con sus dos mitades también: que salte y NOMBRE
-- a la persona cuando la liquidación se pagó primero, y que se levante solo en
-- cuanto el descuento está registrado — un freno del que no se pueda salir se
-- desactiva a la semana.
--
-- El montaje: S/1,500, jornadas de 6.5 h del 1 al 15, cese el 15. Tres periodos
-- que no se solapan y no se estorban — junio SIN congelar (la regresión), abril
-- CONGELADO (la resta), mayo para el freno.
-- ============================================================================
begin;
select plan(25);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000184000', 'ZZ184', 'Sede de laboratorio 184', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000184099', 'Admin184', 'Laboratorio',
        '00000000-0000-0000-0000-000000184000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000184098', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000184098', true);

-- Sin feriados de por medio: acá lo que se compara son dos llamadas a la misma
-- función, y un feriado dentro de un rango y fuera del otro sería ruido.
delete from feriados where fecha between '2026-04-01' and '2026-06-30';

-- Cinco personas iguales entre sí. Lo único que las distingue es qué le pasa a
-- su periodo, que es justamente lo que esta prueba mide.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000184001', 'SinFoto',    'Junio',  '00000000-0000-0000-0000-000000184000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000184002', 'ConFoto',    'Abril',  '00000000-0000-0000-0000-000000184000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000184003', 'DosVersiones', 'Abril','00000000-0000-0000-0000-000000184000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000184004', 'FotoDeMas',  'Abril',  '00000000-0000-0000-0000-000000184000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000184005', 'FrenoFlor',  'Mayo',   '00000000-0000-0000-0000-000000184000', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 1500.00, '2024-01-02'
from personas
where sede_base_id = '00000000-0000-0000-0000-000000184000'
  and id <> '00000000-0000-0000-0000-000000184099';

-- Tres periodos que no se solapan (lo exige el EXCLUDE `periodos_sin_solape`, y
-- es lo que hace fiable deducir el periodo por la fecha de cese).
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000184101', '2026-06-01', '2026-06-30', 'abierto'),  -- nunca se congela
  ('00000000-0000-0000-0000-000000184102', '2026-04-01', '2026-04-30', 'abierto'),  -- se congela
  ('00000000-0000-0000-0000-000000184103', '2026-05-01', '2026-05-30', 'abierto');  -- el freno

-- Cada una trabaja del 1 al 15 de SU mes y cesa el 15.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000184001', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 6.5, 'cerrada'
from generate_series('2026-04-01'::date, '2026-04-15'::date, interval '1 day') d
cross join (values ('00000000-0000-0000-0000-000000184002'::uuid),
                   ('00000000-0000-0000-0000-000000184003'::uuid),
                   ('00000000-0000-0000-0000-000000184004'::uuid)) p(id);

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000184005', d::date, 6.5, 'cerrada'
from generate_series('2026-05-01'::date, '2026-05-15'::date, interval '1 day') d;

-- El cese se pone a mano, como en la 130 y la 133: `fn_cesar_persona` se niega a
-- cesar dentro de un periodo ya pagado (0176:285-291) y acá hace falta cesar
-- antes y después del congelamiento.
update personas set estado = 'inactivo', fecha_cese = '2026-06-15' where id = '00000000-0000-0000-0000-000000184001';
update personas set estado = 'inactivo', fecha_cese = '2026-04-15' where id in (
  '00000000-0000-0000-0000-000000184002',
  '00000000-0000-0000-0000-000000184003',
  '00000000-0000-0000-0000-000000184004');
update personas set estado = 'inactivo', fecha_cese = '2026-05-15' where id = '00000000-0000-0000-0000-000000184005';

-- Lo que la liquidación decía ANTES de que existiera ninguna foto. Es contra
-- esto contra lo que se mide la resta: sin este «antes», la prueba solo podría
-- decir que el número es distinto, no que bajó en lo que se transfirió.
create temp table _antes as
select p.id                                                  as pid,
       (fn_liquidacion(p.id, p.fecha_cese)->'periodo'->>'monto')::numeric as monto,
       (fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric            as total
from personas p
where p.sede_base_id = '00000000-0000-0000-0000-000000184000'
  and p.id <> '00000000-0000-0000-0000-000000184099';


-- ── 1 · SIN FOTO NO SE RESTA NADA — la regresión principal ──────────────────
-- El periodo de junio no se congela en ningún momento de este archivo. Aunque
-- la base se llene de fotos de abril, esta persona tiene que cobrar lo mismo que
-- cobraba antes de la 0243.
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184001', '2026-06-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  0::numeric,
  'SIN FOTO · no hay nada que restar, y se dice con un cero, no con un nulo');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184001', '2026-06-15')->'periodo'->>'monto')::numeric,
  (select round((value->>'total')::numeric, 2)
     from jsonb_array_elements(
            fn_planilla_calcular('2026-06-01', '2026-06-15',
              '00000000-0000-0000-0000-000000184101') -> 'filas') as t(value)
    where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-000000184001'),
  'SIN FOTO · el sueldo sigue siendo EXACTAMENTE lo que calcula la planilla');

select ok(
  (fn_liquidacion('00000000-0000-0000-0000-000000184001', '2026-06-15')->>'aviso_periodo') is null,
  'SIN FOTO · y no se avisa de un descuento que no existe');


-- ── 2 · Congelar abril no frena, porque nadie cobró su liquidación ──────────
-- Control negativo. Si el freno se escribiera demasiado ancho —mirando
-- `liquidacion_pagada` sin acotar al periodo, o sin exigir monto_periodo > 0—
-- esta línea sola tumbaría el cierre de un mes normal.
select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000184102', true) $$,
  'CIERRE · un periodo con gente cesada pero sin liquidaciones pagadas se cierra igual');

-- Una versión 2 SOLO para dos de las tres. La tercera (ConFoto) se queda en la
-- v1 mientras el periodo va por la v2: es el caso de la cesada que ya no sale en
-- el recálculo, y el que la vista v_planilla_pagada no sabría resolver.
insert into planilla_pagada_detalle
  (periodo_id, persona_id, version, origen, nombre, sede_codigo, pago_base, total, fila)
values
  ('00000000-0000-0000-0000-000000184102', '00000000-0000-0000-0000-000000184003', 2,
   'pago', 'DosVersiones Abril', 'ZZ184', 10.00, 10.00, '{}'::jsonb),
  ('00000000-0000-0000-0000-000000184102', '00000000-0000-0000-0000-000000184004', 2,
   'pago', 'FotoDeMas Abril', 'ZZ184', 9999.00, 9999.00, '{}'::jsonb);


-- ── 3 · CON FOTO se resta exactamente lo transferido ───────────────────────
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184002', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  (select total from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000184102'
      and persona_id = '00000000-0000-0000-0000-000000184002'
      and version = 1),
  'CON FOTO · lo que se resta es exactamente lo que dice la foto del pago');

select is(
  (select a.total from _antes a where a.pid = '00000000-0000-0000-0000-000000184002')
  - (fn_liquidacion('00000000-0000-0000-0000-000000184002', '2026-04-15')->>'total')::numeric,
  (fn_liquidacion('00000000-0000-0000-0000-000000184002', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  'CON FOTO · el total baja exactamente en lo transferido, ni un centimo mas');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184002', '2026-04-15')->'periodo'->>'devengado')::numeric,
  (select a.monto from _antes a where a.pid = '00000000-0000-0000-0000-000000184002'),
  'CON FOTO · el devengado sigue diciendo lo que tocaba por el mes, sin descontar');

-- LA TRAMPA DEL MÁXIMO GLOBAL. El periodo va por la version 2, pero ConFoto solo
-- existe en la 1. `v_planilla_pagada` le devolvería cero filas y la resta seria
-- 0 — justo para quien la 0243 viene a cazar.
select is(
  (select max(version) from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000184102'),
  2,
  'VERSION · el periodo va por la v2 (montaje de la trampa siguiente)');

select cmp_ok(
  (fn_liquidacion('00000000-0000-0000-0000-000000184002', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  '>', 0::numeric,
  'VERSION · a quien solo existe en la v1 se le sigue restando: no se usa el max del PERIODO');


-- ── 4 · Dos versiones no duplican la resta ─────────────────────────────────
-- La v1 vale ~750 y la v2 vale 10. Sumarlas restaria ~760; la respuesta es 10.
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184003', '2026-04-15')->'periodo'->>'ya_pagado_en_planilla')::numeric,
  10.00::numeric,
  'VERSION · manda la ULTIMA version de esa persona, no la suma de todas');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184003', '2026-04-15')->'periodo'->>'foto_version')::int,
  2,
  'VERSION · y lo dice, para que la hoja pueda citar de que foto salio');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184003', '2026-04-15')->'periodo'->>'monto')::numeric,
  round((select a.monto from _antes a where a.pid = '00000000-0000-0000-0000-000000184003') - 10.00, 2),
  'VERSION · el neto descuenta 10.00 y no 760.00: la resta no se duplica');


-- ── 5 · Nunca negativo, y las truncas se pagan enteras ─────────────────────
-- La foto vigente dice 9999.00 sobre un mes de ~750. La respuesta no es -9249.
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184004', '2026-04-15')->'periodo'->>'monto')::numeric,
  0::numeric,
  'SUELO · si lo ya transferido supera lo calculado, el sueldo del periodo va a 0');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000184004', '2026-04-15')->>'total')::numeric,
  round((fn_vacaciones_truncas('00000000-0000-0000-0000-000000184004', '2026-04-15')->>'monto')::numeric
      + (fn_grati_trunca('00000000-0000-0000-0000-000000184004', '2026-04-15')->>'monto')::numeric
      + (fn_cts_trunca('00000000-0000-0000-0000-000000184004', '2026-04-15')->>'monto')::numeric, 2),
  'SUELO · y las tres truncas se pagan ENTERAS: no estan en la planilla del mes');

select cmp_ok(
  (fn_liquidacion('00000000-0000-0000-0000-000000184004', '2026-04-15')->>'total')::numeric,
  '>', 0::numeric,
  'SUELO · el total sigue siendo positivo: nadie cobra de menos por este arreglo');


-- ── 6 · El freno del orden inverso ─────────────────────────────────────────
-- Mayo sigue abierto, asi que la liquidacion cobra el mes entero: es el orden
-- que produjo los seis casos de julio.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000184005', 'pago de laboratorio') $$,
  'FRENO · con el periodo abierto la liquidacion se paga y se lleva el mes entero');

select cmp_ok(
  (select monto_periodo from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000184005' order by version desc limit 1),
  '>', 0::numeric,
  'FRENO · esa liquidacion guarda el sueldo del mes: es lo que se solaparia');

-- Y ahora cerrar mayo pagaria el mismo mes por segunda vez. Un «no se puede»
-- sin nombre obligaria a revisar a las 30 personas del periodo una por una.
select throws_like(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000184103', true) $$,
  '%FrenoFlor Mayo%',
  'FRENO · el cierre se niega y NOMBRA a la persona, no dice solo que no se puede');

select throws_like(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000184103', true) $$,
  '%Ya le pagué aparte%',
  'FRENO · y dice el paso exacto que lo levanta, que en este estado si esta disponible');

select is(
  (select estado from periodos_planilla where id = '00000000-0000-0000-0000-000000184103'),
  'abierto',
  'FRENO · el periodo sigue ABIERTO: no se congelo nada a medias');

select is(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = '00000000-0000-0000-0000-000000184103'),
  0,
  'FRENO · y no queda ni una fila de foto: el insert es uno solo y se revirtio entero');

-- LA SEGUNDA MITAD, que es la que evita que esto acabe en `--no-verify`: el
-- freno se levanta solo en cuanto el descuento esta registrado. El boton
-- «Ya le pague aparte» hace exactamente esto (planilla/page.tsx:1357-1363).
select lives_ok(
  $$ select fn_agregar_movimiento(
       '00000000-0000-0000-0000-000000184103',
       '00000000-0000-0000-0000-000000184005',
       'descuento',
       'Ya pagado el 15/05/2026 — fuera de planilla',
       (select round((value->>'total')::numeric, 2)
          from jsonb_array_elements(
                 fn_planilla_calcular('2026-05-01', '2026-05-30',
                   '00000000-0000-0000-0000-000000184103') -> 'filas') as t(value)
         where (value->>'persona_id')::uuid = '00000000-0000-0000-0000-000000184005')) $$,
  'FRENO · con el periodo abierto el descuento SI se puede registrar');

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000184103', true) $$,
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
select '00000000-0000-0000-0000-000000184002', 1,
       '00000000-0000-0000-0000-000000184099', 'ConFoto Abril', '2024-01-02', '2026-04-15',
       d.total, d.total, '{}'::jsonb
from planilla_pagada_detalle d
where d.periodo_id = '00000000-0000-0000-0000-000000184102'
  and d.persona_id = '00000000-0000-0000-0000-000000184002'
  and d.version = 1;

select throws_like(
  $$ select fn_repagar_periodo('00000000-0000-0000-0000-000000184102', 'recalculo de laboratorio') $$,
  '%ConFoto Abril%',
  'REPAGO · volver a congelar un periodo pagado tambien frena, y nombra a la persona');

select throws_like(
  $$ select fn_repagar_periodo('00000000-0000-0000-0000-000000184102', 'recalculo de laboratorio') $$,
  '%Revertir pago%',
  'REPAGO · y manda al rodeo que SI existe en ese estado, no al boton que esta bloqueado');

select * from finish();
rollback;
