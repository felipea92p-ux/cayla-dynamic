-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 192_una_liquidacion_marcada_por_error_se_puede_anular.test.sql — 0251
-- ============================================================================
-- EL CASO REAL, medido en producción el 2026-08-14:
--
--   Una persona en periodo de prueba, que nunca entró a planilla, cesó el
--   07/08. Se le pagó un adelanto de S/358.73 fuera de planilla. El 10/08
--   alguien apretó «Liquidación pagada» y el sistema congeló S/1,106.82 que
--   NUNCA SALIERON DEL BANCO — y encima inflados unas 3.1 veces, porque se
--   congelaron tres días antes de que la 0239 arreglara el divisor.
--
--   No había forma de deshacerlo: `fn_liquidacion_pagar` solo sabe insertar, y
--   el trigger de inmutabilidad bloquea el update y el delete. La 0251 abre la
--   única puerta compatible con esa tabla —una versión más, en cero, con motivo—
--   y esta prueba la vigila.
--
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   Las dos mitades del arreglo, y la segunda importa tanto como la primera:
--
--   (A) Que anular deje de contar en los CINCO sitios que leen esa tabla, y
--   (B) que NO borre nada. La versión errónea tiene que seguir visible con su
--       importe intacto, porque el registro de por qué se creyó que se pagó
--       S/1,106.82 es justamente lo que hace falta para explicar el lío.
--
--   Y la trampa que costó rediseñar la migración: DOS de esos lectores no miran
--   el monto, miran si HAY FILA. Con una versión en ceros y sin tocarlos, la
--   fila se quedaba «pagada» para siempre, el total salía S/0.00 en vez de lo
--   que aún se le debe, y el botón «Marcar como pagada» DESAPARECÍA — o sea que
--   anular dejaba la liquidación imposible de volver a congelar. Por eso § 4 y
--   § 8 existen: no basta con que los números bajen a cero.
--
--   El control negativo pesa igual: una liquidación que SÍ se pagó no puede
--   dejar de contar porque otra se haya anulado. Va en § 4 y § 5, y usa su
--   propio periodo para que no se cruce con nada.
--
-- QUÉ NO DEFIENDE
--
--   No dice si el dinero salió del banco. Eso no lo sabe ninguna tabla de este
--   sistema; lo dice el extracto. La 0251 tampoco lo finge: anular es una
--   decisión de quien mira la cuenta, y esta prueba solo comprueba que el
--   sistema la sepa registrar.
--
-- COMPROBADO POR MUTACIÓN el 2026-08-14: rompiendo cada pieza de la 0251 una a
-- una contra el Postgres local, mueren exactamente las de su grupo y ninguna
-- otra. Sin esa vuelta, un archivo verde no dice si mide algo o si pasa en
-- vacío — y en el primer intento la mitad de estas aserciones pasaban con la
-- pieza rota, porque el arnés de medición tenía un grep mal escrito.
--
--   pieza de la 0251                                  | mueren
--   --------------------------------------------------+---------------
--   el `on f.anulada is not true` del lateral (§ 5 mig)|  19, 20
--   el filtro DESPUÉS del distinct on   (§ 6 mig)      |  17
--   el corto circuito de fn_liquidacion_diferencias    |  22
--   el guard del motivo                                |  27, 28, 29
--   el guard de permiso                                |  31
--   la salida «no hay nada que anular»                 |  32
--   la salida «ya estaba anulada»                      |  38, 39, 43
--   el CHECK liquidacion_anulada_en_cero               |  44
--   el CHECK liquidacion_anulada_se_explica            |  45
--
-- La 21 no está en la tabla y es a propósito: el badge rojo se apaga por DOS
-- caminos —el lateral y el corto circuito— y solo cae cuando se rompen los dos
-- a la vez (medido). No es una aserción de más: es la única que mira lo que la
-- persona ve, y las otras dos miran cómo se consigue.
--
-- EL MONTAJE: cuatro personas iguales entre sí, S/1,500, jornadas de 6.5 h,
-- cada una en SU PROPIO periodo. Los periodos no se solapan —lo exige el
-- EXCLUDE `periodos_sin_solape`— y separarlas así es a propósito: el freno del
-- cierre mira el periodo entero, y con dos casos en el mismo mes una prueba
-- taparía a la otra.
--
--   ·192001 Fantasma Agosto — el caso real: se paga, se ANULA, se vuelve a pagar
--   ·192002 Cobrada Julio   — control: se paga y NUNCA se anula
--   ·192003 SinNada Junio   — no tiene ninguna liquidación
--   ·192004 Freno Mayo      — el freno del cierre, antes y después de anular
-- ============================================================================
begin;
select plan(48);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000192000', 'ZZ192', 'Sede de laboratorio 192', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values
  ('00000000-0000-0000-0000-000000192099', 'Admin192', 'Laboratorio',
   '00000000-0000-0000-0000-000000192000', 'admin', 'test-hash',
   '00000000-0000-0000-0000-000000192098', '2020-01-01'),
  -- Alguien que no es admin ni líder, para la prueba del permiso.
  ('00000000-0000-0000-0000-000000192097', 'Curiosa192', 'Laboratorio',
   '00000000-0000-0000-0000-000000192000', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000192096', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000192098', true);

-- Sin feriados de por medio: lo que se compara acá son llamadas a la misma
-- función antes y después de anular, y un feriado dentro de un rango sería ruido.
delete from feriados where fecha between '2026-05-01' and '2026-08-31';

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000192001', 'Fantasma', 'Agosto', '00000000-0000-0000-0000-000000192000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000192002', 'Cobrada',  'Julio',  '00000000-0000-0000-0000-000000192000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000192003', 'SinNada',  'Junio',  '00000000-0000-0000-0000-000000192000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000192004', 'Freno',    'Mayo',   '00000000-0000-0000-0000-000000192000', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 1500.00, '2024-01-02'
from personas
where sede_base_id = '00000000-0000-0000-0000-000000192000'
  and id not in ('00000000-0000-0000-0000-000000192099',
                 '00000000-0000-0000-0000-000000192097');

-- Un periodo por persona, sin solaparse. Cada uno se queda ABIERTO salvo el de
-- mayo, que es el que esta prueba cierra al final de § 8.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000192101', '2026-08-01', '2026-08-30', 'abierto'),
  ('00000000-0000-0000-0000-000000192102', '2026-07-01', '2026-07-30', 'abierto'),
  ('00000000-0000-0000-0000-000000192103', '2026-06-01', '2026-06-30', 'abierto'),
  ('00000000-0000-0000-0000-000000192104', '2026-05-01', '2026-05-30', 'abierto');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000192001', d::date, 6.5, 'cerrada'
from generate_series('2026-08-01'::date, '2026-08-07'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000192002', d::date, 6.5, 'cerrada'
from generate_series('2026-07-01'::date, '2026-07-15'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000192003', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-15'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000192004', d::date, 6.5, 'cerrada'
from generate_series('2026-05-01'::date, '2026-05-15'::date, interval '1 day') d;

-- El cese se pone a mano, como en la 130, la 133 y la 185: `fn_cesar_persona`
-- se niega a cesar dentro de un periodo ya pagado (0176:285-291).
update personas set estado = 'inactivo', fecha_cese = '2026-08-07' where id = '00000000-0000-0000-0000-000000192001';
update personas set estado = 'inactivo', fecha_cese = '2026-07-15' where id = '00000000-0000-0000-0000-000000192002';
update personas set estado = 'inactivo', fecha_cese = '2026-06-15' where id = '00000000-0000-0000-0000-000000192003';
update personas set estado = 'inactivo', fecha_cese = '2026-05-15' where id = '00000000-0000-0000-0000-000000192004';

-- Lo que la liquidación decía ANTES de que nadie apretara nada. Es contra esto
-- contra lo que se mide que anular DEVUELVA el cálculo a donde estaba: sin este
-- «antes», la prueba solo podría decir que el número es distinto del cero.
create temp table _antes as
select p.id                                                            as pid,
       (fn_liquidacion(p.id, p.fecha_cese)->>'total')::numeric          as total,
       (fn_liquidacion(p.id, p.fecha_cese)->'periodo'->>'monto')::numeric as monto
from personas p
where p.sede_base_id = '00000000-0000-0000-0000-000000192000'
  and p.id not in ('00000000-0000-0000-0000-000000192099',
                   '00000000-0000-0000-0000-000000192097');


-- ── 1 · EL MUNDO CON LA LIQUIDACIÓN FANTASMA ───────────────────────────────
-- Primero se reproduce el error: alguien aprieta el botón y el sistema congela
-- un importe. Sin este montaje, las pruebas de abajo pasarían en vacío.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000192001', 'marcada por error, como el 10/08 en produccion') $$,
  'MONTAJE · se marca la liquidación como pagada, que es el error que hay que deshacer');

select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000192002', 'esta si se pago de verdad') $$,
  'MONTAJE · y otra persona cobra la suya de verdad, en otro periodo: el control');

select cmp_ok(
  (select total from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' and version = 1),
  '>', 0::numeric,
  'MONTAJE · la v1 guarda un importe de verdad, no un cero (si no, no habría nada que anular)');

select ok(
  (select pagada from fn_liquidaciones_pendientes()
    where persona_id = '00000000-0000-0000-0000-000000192001'),
  'ANTES · la pantalla de Liquidaciones la da por pagada');

select ok(
  fn_liquidaciones_del_periodo('00000000-0000-0000-0000-000000192101')
    ? '00000000-0000-0000-0000-000000192001',
  'ANTES · y la pantalla de Planilla anuncia el cobro que nunca ocurrió');


-- ── 2 · ANULAR ESCRIBE, NO BORRA ───────────────────────────────────────────
select lives_ok(
  $$ select fn_liquidacion_anular(
       '00000000-0000-0000-0000-000000192001',
       'Marcada por error. El dinero nunca salio del banco: solo se pago un adelanto, ya registrado como descuento.') $$,
  'ANULAR · se puede anular una liquidación marcada por error');

-- LA MITAD QUE MÁS IMPORTA. En este repo nada se borra: si la v1 desapareciera,
-- dentro de un año nadie podría explicar por qué se creyó que se había pagado
-- ese importe, ni con qué cifra.
select cmp_ok(
  (select total from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' and version = 1),
  '>', 0::numeric,
  'ANULAR · la v1 SIGUE ahí con su importe intacto: se corrige a la vista, no por debajo');

select is(
  (select version from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' order by version desc limit 1),
  2,
  'ANULAR · la anulación es una versión MÁS, la 2');

select is(
  (select total from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' order by version desc limit 1),
  0::numeric,
  'ANULAR · y la última versión queda en cero');

select is(
  (select monto_periodo from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' order by version desc limit 1),
  0::numeric,
  'ANULAR · también el sueldo del mes, que es la cifra que se solapa con la planilla');

select ok(
  (select anulada from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' order by version desc limit 1),
  'ANULAR · y queda MARCADA como anulación, no como un pago de S/0.00 — que también existe');

select alike(
  (select motivo_anulacion from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' order by version desc limit 1),
  '%nunca salio del banco%',
  'ANULAR · con el motivo escrito, no con un texto por defecto');

select is(
  (select anula_version from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' order by version desc limit 1),
  1,
  'ANULAR · y diciendo qué versión anula, para que la fila se explique sola');

-- La fila de anulación tiene que poder leerse sin cruzarla con la anterior.
select is(
  (select (detalle->'lo_que_decia_la_version_anulada'->>'total')::numeric
     from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' and version = 2),
  (select total from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' and version = 1),
  'ANULAR · el detalle guarda lo que decía la versión anulada: la fila se cuenta sola');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000192001'
      and campo_modificado = 'liquidacion_pagada'
      and motivo like '%nunca salio del banco%'),
  1,
  'RASTRO · queda en correcciones_auditoria con el motivo, igual que al marcarla pagada');

-- `fn_liquidacion_pagar` deja `valor_anterior` en null porque no había nada
-- antes. Una anulación sí lo tiene, y sin él la fila de auditoría no diría de
-- cuánto a cuánto sin ir a buscarlo a otra tabla.
select alike(
  (select valor_anterior from correcciones_auditoria
    where persona_id = '00000000-0000-0000-0000-000000192001'
      and valor_nuevo like 'ANULADA%'),
  '%version 1%',
  'RASTRO · y el rastro dice de cuánto venía, no solo que ahora es cero');


-- ── 3 · LA PANTALLA DE PLANILLA DEJA DE ANUNCIARLO ─────────────────────────
-- Este es el lector que decide por EXISTENCIA de clave: la pantalla hace
-- `if (!liq) return null`, así que devolverla en ceros dejaría el cartel
-- pintado con otro número falso. Tiene que desaparecer del objeto.
select ok(
  not (fn_liquidaciones_del_periodo('00000000-0000-0000-0000-000000192101')
         ? '00000000-0000-0000-0000-000000192001'),
  'PLANILLA · anulada, ya no se anuncia «ya cobró su liquidación»');

-- EL CONTROL NEGATIVO. Una anulación no puede apagar el aviso de quien SÍ cobró.
select ok(
  fn_liquidaciones_del_periodo('00000000-0000-0000-0000-000000192102')
    ? '00000000-0000-0000-0000-000000192002',
  'PLANILLA · y quien SÍ cobró la suya se sigue anunciando: no se apagó el aviso entero');


-- ── 4 · LA LISTA DE LIQUIDACIONES VUELVE A VERLA COMO PENDIENTE ────────────
-- El otro lector por existencia, y el que más duele: con `pagada` en true la
-- fila se queda en el bloque «Pagadas» y el botón «Marcar como pagada»
-- desaparece (page.tsx:409). Sin esto, anular dejaba la liquidación correcta
-- imposible de congelar desde la interfaz.
select ok(
  not (select pagada from fn_liquidaciones_pendientes()
        where persona_id = '00000000-0000-0000-0000-000000192001'),
  'PENDIENTES · vuelve a estar SIN pagar, que es lo que la devuelve al bloque con botón');

-- `coalesce(f.total, …)` se quedaba con el 0.00 de la anulación porque un cero
-- no es un nulo: la pantalla mostraba S/0.00 justo donde tiene que decir lo que
-- todavía se le debe.
select is(
  (select total from fn_liquidaciones_pendientes()
    where persona_id = '00000000-0000-0000-0000-000000192001'),
  (select round(a.total, 2) from _antes a where a.pid = '00000000-0000-0000-0000-000000192001'),
  'PENDIENTES · y su total vuelve a ser lo que se le debe, no el cero de la anulación');

select ok(
  not (select descuadra from fn_liquidaciones_pendientes()
        where persona_id = '00000000-0000-0000-0000-000000192001'),
  'PENDIENTES · sin badge rojo: no hay cifra pagada contra la que descuadrar');

select is(
  (select count(*)::int from fn_liquidacion_diferencias('00000000-0000-0000-0000-000000192001')),
  0,
  'DIFERENCIAS · comparar contra una anulación no devuelve cinco diferencias contra un cero');

-- El control negativo también acá.
select ok(
  (select pagada from fn_liquidaciones_pendientes()
    where persona_id = '00000000-0000-0000-0000-000000192002'),
  'PENDIENTES · y quien SÍ cobró sigue apareciendo como pagada');


-- ── 5 · LA HOJA VUELVE A CALCULAR COMO SI NADIE HUBIERA APRETADO NADA ──────
-- No es solo que el número baje: tiene que volver EXACTAMENTE al que había
-- antes de la marca errónea. Un «distinto de cero» pasaría con cualquier cifra.
select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000192001', '2026-08-07')->>'total')::numeric,
  (select a.total from _antes a where a.pid = '00000000-0000-0000-0000-000000192001'),
  'HOJA · el total vuelve exactamente al de antes de la marca errónea');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000192001', '2026-08-07')->'periodo'->>'monto')::numeric,
  (select a.monto from _antes a where a.pid = '00000000-0000-0000-0000-000000192001'),
  'HOJA · y el sueldo del periodo también: no se le resta una liquidación anulada');

-- El aviso de la 0244 se apaga solo porque su condición es `v_liq > 0`, y el
-- CHECK de la 0251 garantiza que una fila anulada esté en cero. Esta aserción es
-- la que vigila esa cadena: si alguien quitara el CHECK, el cartel volvería.
select unalike(
  coalesce(fn_liquidacion('00000000-0000-0000-0000-000000192001', '2026-08-07')->>'aviso_periodo', ''),
  '%liquidación ya se pagó%',
  'HOJA · y deja de decir «su liquidación ya se pagó» en la hoja que se imprime');


-- ── 6 · EXIGE MOTIVO ───────────────────────────────────────────────────────
-- Una fila en cero sin motivo es ilegible dentro de un año. Y el CHECK de
-- `correcciones_auditoria` pide tres caracteres, así que sin esta comprobación
-- el usuario vería un error crudo de Postgres en vez de una frase en español.
select throws_like(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000192002', '') $$,
  '%motivo escrito%',
  'MOTIVO · sin motivo no se anula, y el error lo dice en español');

select throws_like(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000192002', '   ') $$,
  '%motivo escrito%',
  'MOTIVO · y un puñado de espacios tampoco cuela');

select throws_like(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000192002', 'ok') $$,
  '%motivo escrito%',
  'MOTIVO · ni dos caracteres: el mismo mínimo que exige correcciones_auditoria');

-- Y ninguno de los tres intentos pudo dejar rastro a medias.
select ok(
  (select pagada from fn_liquidaciones_pendientes()
    where persona_id = '00000000-0000-0000-0000-000000192002'),
  'MOTIVO · tras los tres rechazos, la liquidación del control sigue intacta');


-- ── 7 · Y NO LA ANULA CUALQUIERA ───────────────────────────────────────────
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000192096', true);

select throws_like(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000192002', 'no deberia poder') $$,
  '%administrador o líder%',
  'PERMISO · quien no es admin ni líder no anula nada');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000192098', true);

select throws_like(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000192003', 'no hay nada que anular') $$,
  '%no hay nada que anular%',
  'VACÍO · a quien no tiene ninguna liquidación se le dice, no se le inventa una fila en cero');


-- ── 8 · EL FRENO DEL CIERRE (0244) DEJA DE CONTARLA ────────────────────────
-- Persona propia y periodo propio: el freno mira el periodo entero, así que
-- montarlo junto a otro caso taparía uno de los dos.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000192004', 'marcada por error tambien') $$,
  'FRENO · se marca su liquidación como pagada');

select throws_like(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000192104', true) $$,
  '%Freno Mayo%',
  'FRENO · con la liquidación viva el cierre del mes se niega y la NOMBRA');

select lives_ok(
  $$ select fn_liquidacion_anular(
       '00000000-0000-0000-0000-000000192004',
       'Marcada por error: ese dinero no salio del banco.') $$,
  'FRENO · se anula');

-- El freno filtra por `monto_periodo > 0` y la anulación escribe ceros: por eso
-- se levanta sin tocar una línea de la 0244, que es lo que la migración promete.
-- Que esa condición siga cumpliéndose cuando escriba OTRO —no esta función— lo
-- sostiene el CHECK, y de eso se ocupa § 11.
select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000192104', true) $$,
  'FRENO · y entonces el mes CIERRA: el freno deja de contar una liquidación anulada');


-- ── 9 · ANULAR DOS VECES NO ROMPE NI ENSUCIA ───────────────────────────────
-- La PK es (persona_id, version) y la versión sale de max+1, así que sin salida
-- explícita la segunda llamada insertaría una v3 en cero anulando una v2 que ya
-- estaba en cero: ruido que un año después se lee como si hubiera pasado algo
-- dos veces.
select lives_ok(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000192001', 'otra vez, por si acaso') $$,
  'DOS VECES · anular lo ya anulado no revienta');

select is(
  (select count(*)::int from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001'),
  2,
  'DOS VECES · y no escribe una tercera fila: no hace nada y devuelve lo que ya había');

select ok(
  (fn_liquidacion_anular('00000000-0000-0000-0000-000000192001', 'otra vez, por si acaso')
     ->>'ya_estaba_anulada')::boolean,
  'DOS VECES · lo dice en la respuesta, en vez de fingir que anuló algo');


-- ── 10 · Y SE PUEDE CONGELAR LA CORRECTA — el final del caso real ──────────
-- Para la persona de arriba quedan S/298.73 realmente ganados. Si tras anular
-- no se pudiera volver a congelar, la 0251 habría cambiado un problema por otro.
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000192001', 'esta vez con el importe correcto') $$,
  'REHACER · tras anular se puede volver a congelar la liquidación correcta');

select cmp_ok(
  (select total from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001' order by version desc limit 1),
  '>', 0::numeric,
  'REHACER · y la v3 guarda el importe de verdad, no hereda el cero de la anulación');

select ok(
  (select pagada from fn_liquidaciones_pendientes()
    where persona_id = '00000000-0000-0000-0000-000000192001'),
  'REHACER · la fila vuelve a contar como pagada');

select is(
  (select count(*)::int from liquidacion_pagada
    where persona_id = '00000000-0000-0000-0000-000000192001'),
  3,
  'REHACER · y las tres versiones siguen ahí: el histórico completo, sin un borrado');


-- ── 11 · LA INVARIANTE ESTÁ EN EL ESQUEMA, NO EN LA COSTUMBRE ──────────────
-- Es lo que permite NO tocar la 0244: sus dos lectores filtran por monto, así
-- que una fila anulada con importe volvería a activar el freno y el cartel. Que
-- eso no pase no puede depender de que quien escriba la próxima función se
-- acuerde de poner ceros.
select throws_like(
  $$ insert into liquidacion_pagada
       (persona_id, version, congelada_por, persona, fecha_cese,
        monto_periodo, total, detalle, anulada, motivo_anulacion, anula_version)
     values ('00000000-0000-0000-0000-000000192002', 9,
             '00000000-0000-0000-0000-000000192099', 'Cobrada Julio', '2026-07-15',
             500.00, 500.00, '{}'::jsonb, true, 'con importe', 1) $$,
  '%liquidacion_anulada_en_cero%',
  'ESQUEMA · una fila anulada CON importe se rechaza: los lectores por monto quedan a salvo');

select throws_like(
  $$ insert into liquidacion_pagada
       (persona_id, version, congelada_por, persona, fecha_cese,
        monto_periodo, total, detalle, anulada)
     values ('00000000-0000-0000-0000-000000192002', 9,
             '00000000-0000-0000-0000-000000192099', 'Cobrada Julio', '2026-07-15',
             0, 0, '{}'::jsonb, true) $$,
  '%liquidacion_anulada_se_explica%',
  'ESQUEMA · y una anulación sin motivo tampoco entra, ni por la puerta de atrás');

-- Que el CHECK no muerda a quien no debe: un pago legítimo de S/0.00 EXISTE
-- —una persona sin salario asignado— y es justamente por eso que «anulada» es
-- una columna y no un `total = 0`.
--
-- Versión 8 y no 9 a propósito: las dos de arriba tienen que fallar, y si una
-- dejara de fallar su fila entraría y ésta chocaría contra la PK. Sería una
-- aserción roja que no habla de lo suyo, y a quien lea el fallo lo mandaría a
-- buscar el defecto donde no está.
select lives_ok(
  $$ insert into liquidacion_pagada
       (persona_id, version, congelada_por, persona, fecha_cese,
        monto_periodo, total, detalle)
     values ('00000000-0000-0000-0000-000000192002', 8,
             '00000000-0000-0000-0000-000000192099', 'Cobrada Julio', '2026-07-15',
             0, 0, '{}'::jsonb) $$,
  'ESQUEMA · pero un pago legítimo de S/0.00 sigue entrando: cero no significa anulada');


-- ── 12 · QUIÉN PUEDE LLAMARLA ──────────────────────────────────────────────
-- El bloque de comprobación de la 0251 mira esto, pero corre UNA SOLA VEZ, al
-- pegar. El día que alguien conceda en masa —ya pasó, 0076— la suite se entera.
select ok(
  has_function_privilege('authenticated', 'fn_liquidacion_anular(uuid, text)', 'execute'),
  'PERMISOS · la pantalla podrá llamarla cuando tenga botón');

select ok(
  not has_function_privilege('anon', 'fn_liquidacion_anular(uuid, text)', 'execute'),
  'PERMISOS · y sin sesión no se anula la liquidación de nadie');


select * from finish();
rollback;
