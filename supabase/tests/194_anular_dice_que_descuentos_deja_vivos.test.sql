-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 194_anular_dice_que_descuentos_deja_vivos.test.sql — 0253
-- ============================================================================
-- EL DEFECTO QUE VIGILA, medido el 2026-08-14 contra el Postgres local:
--
--   El freno del cierre (0244) MANDA registrar un descuento por `monto_periodo`
--   antes de dejar cerrar el mes, y nombra el importe exacto. Si esa
--   liquidación resulta estar mal marcada y se ANULA (0251), el descuento se
--   queda. Nadie se lo pagó a la persona y tampoco vuelve al total pendiente:
--   se pierde, y la única frase que lo señalaba —la rama del aviso que la 0244
--   añadió «para poder EXPLICAR el cero»— se apaga con la anulación, porque se
--   enciende con `monto_periodo > 0` y anular lo pone en cero.
--
--   Los mismos hechos, cambiando SOLO el orden: anular ANTES de descontar paga
--   S/2,266.97; hacer lo que el freno manda y anular después paga S/1,637.94.
--
-- QUÉ DEFIENDE ESTE ARCHIVO
--
--   (A) Que el defecto EXISTE y tiene el tamaño que se dice. Las aserciones 6,
--       7, 8 y 9 miden la pérdida al céntimo. Si algún día alguien arregla esto de
--       verdad —devolviendo el importe al total pendiente, o añadiendo la rama
--       que falta en el aviso de `fn_liquidacion`—, esas aserciones fallarán, y
--       ESO ES LO CORRECTO: hay que venir acá, leer el porqué y reescribirlas.
--       Una prueba que fija un defecto tiene que decir que lo está fijando.
--   (B) Que la 0253 lo NOMBRA: `fn_liquidacion_anular` devuelve los descuentos
--       vivos, su suma y un aviso, y deja una fila propia en auditoría.
--   (C) Que NO lo resuelve sola, y que eso es a propósito: el descuento
--       legítimo —un adelanto real— sobrevive intacto y la liquidación de esa
--       persona sigue saliendo bien. Ese es el control negativo, y pesa igual:
--       negarse a anular cuando hay un descuento habría roto justo el caso de
--       producción que la 0251 vino a resolver.
--   (D) Que la 0253 no se llevó por delante nada de la 0251: idempotencia,
--       motivo obligatorio, permiso, los CHECK y los cinco lectores.
--
-- EL MONTAJE: tres personas de S/1,500 con jornadas de 6.5 h, cada una en SU
-- PROPIO periodo. Sin solaparse, que lo exige el EXCLUDE `periodos_sin_solape`,
-- y separadas a propósito: el freno del cierre mira el periodo entero y con dos
-- casos en el mismo mes una prueba taparía a la otra.
--
--   ·194001 Perdida Agosto — el defecto: freno → descuento → cierre → anular
--   ·194002 Adelanto Julio — control: su descuento es REAL y debe sobrevivir
--   ·194003 Limpia Junio   — control: se anula sin ningún descuento de por medio
-- ============================================================================
begin;
select plan(23);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000194000', 'ZZ194', 'Sede de laboratorio 194', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values
  ('00000000-0000-0000-0000-000000194099', 'Admin194', 'Laboratorio',
   '00000000-0000-0000-0000-000000194000', 'admin', 'test-hash',
   '00000000-0000-0000-0000-000000194098', '2020-01-01'),
  ('00000000-0000-0000-0000-000000194097', 'Curiosa194', 'Laboratorio',
   '00000000-0000-0000-0000-000000194000', 'integrante', 'test-hash',
   '00000000-0000-0000-0000-000000194096', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000194098', true);

-- Sin feriados de por medio: lo que se compara son llamadas a la misma función
-- antes y después de anular, y un feriado dentro de un rango sería ruido.
delete from feriados where fecha between '2026-05-01' and '2026-08-31';

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000194001', 'Perdida',  'Agosto', '00000000-0000-0000-0000-000000194000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000194002', 'Adelanto', 'Julio',  '00000000-0000-0000-0000-000000194000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000194003', 'Limpia',   'Junio',  '00000000-0000-0000-0000-000000194000', 'test-hash', '2024-01-02', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'cayla', 1500.00, '2024-01-02'
from personas
where sede_base_id = '00000000-0000-0000-0000-000000194000'
  and id not in ('00000000-0000-0000-0000-000000194099',
                 '00000000-0000-0000-0000-000000194097');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado) values
  ('00000000-0000-0000-0000-000000194101', '2026-08-01', '2026-08-30', 'abierto'),
  ('00000000-0000-0000-0000-000000194102', '2026-07-01', '2026-07-30', 'abierto'),
  ('00000000-0000-0000-0000-000000194103', '2026-06-01', '2026-06-30', 'abierto');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000194001', d::date, 6.5, 'cerrada'
from generate_series('2026-08-01'::date, '2026-08-10'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000194002', d::date, 6.5, 'cerrada'
from generate_series('2026-07-01'::date, '2026-07-10'::date, interval '1 day') d;

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000194003', d::date, 6.5, 'cerrada'
from generate_series('2026-06-01'::date, '2026-06-10'::date, interval '1 day') d;

-- El cese se pone a mano, como en la 185 y la 192: `fn_cesar_persona` se niega
-- a cesar dentro de un periodo ya pagado (0176:285-291).
update personas set estado='inactivo', fecha_cese='2026-08-10' where id='00000000-0000-0000-0000-000000194001';
update personas set estado='inactivo', fecha_cese='2026-07-10' where id='00000000-0000-0000-0000-000000194002';
update personas set estado='inactivo', fecha_cese='2026-06-10' where id='00000000-0000-0000-0000-000000194003';

-- Lo que se le debe a Perdida Agosto SI NADIE SE EQUIVOCA. Es la vara contra la
-- que se mide todo lo de abajo, y se toma antes de tocar nada.
create temp table _vara as
select round((fn_liquidacion('00000000-0000-0000-0000-000000194001', '2026-08-10')->>'total')::numeric, 2) as total,
       round((fn_liquidacion('00000000-0000-0000-0000-000000194001', '2026-08-10')->'periodo'->>'monto')::numeric, 2) as periodo;


-- ── § 1 · El freno muerde, se le obedece, y el mes se cierra ────────────────
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000194001', 'marcada por error') $$,
  '1 · se marca la liquidación (por error: el dinero nunca salió del banco)');

select throws_like(
  $$ select fn_planilla_congelar('00000000-0000-0000-0000-000000194101', 'cierre',
                                 '00000000-0000-0000-0000-000000194099') $$,
  '%ya se le pagó su liquidación%',
  '2 · el freno de la 0244 impide cerrar el mes, y nombra el importe');

-- Se hace EXACTAMENTE lo que el mensaje del freno manda.
select lives_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-000000194101',
       '00000000-0000-0000-0000-000000194001', 'descuento', 'Ya le pague aparte (liquidacion)',
       (select monto_periodo from liquidacion_pagada
         where persona_id='00000000-0000-0000-0000-000000194001' order by version desc limit 1)) $$,
  '3 · se registra el descuento que el freno pide, por el importe que nombra');

select lives_ok(
  $$ select fn_periodo_pagado('00000000-0000-0000-0000-000000194101', true) $$,
  '4 · con el descuento puesto el mes ya se puede cerrar y transferir');


-- ── § 2 · EL DEFECTO, al céntimo ────────────────────────────────────────────
-- Estas dos aserciones FIJAN UN DEFECTO CONOCIDO. Si fallan porque alguien lo
-- arregló de verdad, no se «ajusta el número»: se lee la cabecera y se
-- reescriben. Ver (A) arriba.
select lives_ok(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000194001',
       'Conciliado con el banco: esa transferencia nunca se hizo.') $$,
  '5 · se descubre el error y se anula');

-- Todo lo que REALMENTE recibe, sumado en un solo sitio: lo que le transfirió
-- la planilla del mes más lo que la liquidación pendiente le ofrece hoy.
create temp table _tras as
select round((fn_liquidacion('00000000-0000-0000-0000-000000194001')->>'total')::numeric, 2) as liq_pendiente,
       coalesce((select d.total from planilla_pagada_detalle d
                  where d.periodo_id='00000000-0000-0000-0000-000000194101'
                    and d.persona_id='00000000-0000-0000-0000-000000194001'
                  order by d.version desc limit 1), 0)                                       as planilla_transfirio;

select is(
  (select round(liq_pendiente + planilla_transfirio, 2) from _tras),
  (select round(total - periodo, 2) from _vara),
  '6 · DEFECTO FIJADO: tras anular recibe la vara MENOS el sueldo del periodo entero');

select is(
  (select round(v.total - (t.liq_pendiente + t.planilla_transfirio), 2) from _vara v, _tras t),
  (select round(monto, 2) from movimientos_planilla
    where persona_id='00000000-0000-0000-0000-000000194001' and tipo='descuento'),
  '7 · y lo que falta es EXACTAMENTE el descuento, ni un céntimo más');

select is(
  (fn_liquidacion('00000000-0000-0000-0000-000000194001')->>'aviso_periodo'),
  null,
  '8 · DEFECTO FIJADO: el aviso que explicaba el cero se apaga al anular');

select is(
  (select descuadra from fn_liquidaciones_pendientes()
    where persona_id='00000000-0000-0000-0000-000000194001'),
  false,
  '9 · y en la lista de pendientes no se enciende ningún badge');


-- ── § 3 · LO QUE LA 0253 SÍ HACE: nombrarlo ─────────────────────────────────
select is(
  (select count(*)::int from fn_liquidacion_descuentos_del_cese('00000000-0000-0000-0000-000000194001')),
  1,
  '10 · fn_liquidacion_descuentos_del_cese ve el descuento que quedó vivo');

select is(
  (select sum(monto) from fn_liquidacion_descuentos_del_cese('00000000-0000-0000-0000-000000194001')),
  (select periodo from _vara),
  '11 · y su importe es el sueldo del periodo que el freno mandó descontar');

select is(
  (select periodo_estado from fn_liquidacion_descuentos_del_cese('00000000-0000-0000-0000-000000194001')),
  'pagado',
  '12 · dice que el periodo ya está pagado — o sea que corregirlo exige reabrirlo');

-- Segunda llamada: la anulación es idempotente, pero el aviso se recalcula.
select is(
  (fn_liquidacion_anular('00000000-0000-0000-0000-000000194001', 'otra vez')->>'descuentos_vivos_suma')::numeric,
  (select periodo from _vara),
  '13 · anular otra vez sigue diciendo la suma que queda viva');

select ok(
  (fn_liquidacion_anular('00000000-0000-0000-0000-000000194001', 'otra vez')->>'ya_estaba_anulada')::boolean,
  '14 · y sigue siendo idempotente: no escribe una versión nueva');

select is(
  (select count(*)::int from liquidacion_pagada where persona_id='00000000-0000-0000-0000-000000194001'),
  2,
  '15 · tres llamadas a anular, dos filas: la marcada y su anulación');

select is(
  (select count(*)::int from correcciones_auditoria
    where persona_id='00000000-0000-0000-0000-000000194001'
      and campo_modificado='descuentos_vivos_tras_anular'),
  1,
  '16 · queda UNA fila de auditoría propia nombrando lo que sigue vivo');


-- ── § 4 · CONTROL NEGATIVO · el descuento legítimo sobrevive ────────────────
-- Adelanto Julio recibió un adelanto DE VERDAD, registrado como descuento. Es
-- el caso real de producción que la 0251 vino a resolver. Si la 0253 se hubiera
-- negado a anular con un descuento vivo, acá se rompería.
select lives_ok(
  $$ select fn_agregar_movimiento('00000000-0000-0000-0000-000000194102',
       '00000000-0000-0000-0000-000000194002', 'descuento', 'Adelanto real pagado fuera de planilla', 300.00) $$,
  '17 · se registra un adelanto REAL como descuento');

select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000194002', 'marcada por error'),
            fn_liquidacion_anular('00000000-0000-0000-0000-000000194002',
              'Nunca salio del banco. Solo el adelanto.') $$,
  '18 · anular NO se niega por tener un descuento vivo — si se negara, no habría arreglo posible');

select is(
  (select monto from movimientos_planilla
    where persona_id='00000000-0000-0000-0000-000000194002' and tipo='descuento'),
  300.00::numeric,
  '19 · el adelanto real sigue entero: la 0253 nombra, no devuelve');

select ok(
  (select total from fn_liquidaciones_pendientes()
    where persona_id='00000000-0000-0000-0000-000000194002') > 0,
  '20 · y su liquidación pendiente sigue saliendo, ya descontado el adelanto');


-- ── § 5 · CONTROL NEGATIVO · sin descuentos no se inventa aviso ─────────────
select lives_ok(
  $$ select fn_liquidacion_pagar('00000000-0000-0000-0000-000000194003', 'marcada por error') $$,
  '21 · Limpia Junio: se marca su liquidación, sin ningún descuento de por medio');

select is(
  (fn_liquidacion_anular('00000000-0000-0000-0000-000000194003',
     'Nunca salio del banco.')->>'descuentos_vivos_aviso'),
  null,
  '22 · sin descuentos vivos el aviso viene NULO: no se avisa de la nada');


-- ── § 6 · La 0251 sigue entera ──────────────────────────────────────────────
-- El guard de sesión de la 0251 era inalcanzable —`fn_rol_actual` y
-- `fn_persona_actual_id` resuelven contra la misma fila, así que si el permiso
-- pasa el id nunca es null— y a un admin sin `set_config` le decía «solo un
-- administrador o líder». La 0253 lo anida dentro del guard, sin debilitarlo.
select set_config('request.jwt.claim.sub', '', true);
select throws_like(
  $$ select fn_liquidacion_anular('00000000-0000-0000-0000-000000194003', 'sin sesion') $$,
  '%No hay sesión%',
  '23 · sin sesión el error dice QUÉ FALTA, no «no eres admin»');

select * from finish();
rollback;
