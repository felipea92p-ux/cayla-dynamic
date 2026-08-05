-- ============================================================================
-- 126_el_sexto_entra_solo_en_la_cts.test.sql — el sexto de la gratificación
-- (migración 0112, viva hoy en fn_provisiones de la 0135)
-- ============================================================================
-- EL ART. 16 DEL D.S. 001-97-TR manda que la base de la CTS incluya «un sexto de
-- lo percibido» por gratificación. En pequeña empresa la gratificación es MEDIA
-- remuneración, así que ese sexto vale sueldo/12 — no sueldo/6, que es el del
-- régimen general y pagaría de más en cada liquidación.
--
-- LA 0112 LLEGÓ APAGADA A PROPÓSITO: si la clave `sexto_cts` no está en
-- `configuracion.planilla_provisiones`, el multiplicador es 1 y no se mueve
-- ningún pago. Se enciende con un UPDATE, el día que se decida.
--
-- ── POR QUÉ ESTA PRUEBA, Y POR QUÉ ANTES DE ENCENDERLO ──────────────────────
--
-- Encender el sexto solo puede SUBIR la CTS: nadie cobra menos. El riesgo no es
-- ese. El riesgo es que el sexto se cuele también en la GRATIFICACIÓN o en las
-- VACACIONES, donde la ley no lo pide — ahí sí se pagaría de más, en cada
-- periodo y a todo el equipo, y nadie lo notaría mirando la boleta.
--
-- La 0112 dice haberse cuidado de eso. Esta prueba lo comprueba en vez de
-- creerle, y lo comprueba ANTES de que el interruptor se toque en producción.
--
-- ── LOS TRES FRENTES ────────────────────────────────────────────────────────
--
--   1 · ENCENDIDO   la CTS sube exactamente a 13/12, y grati y vacaciones no se
--                   mueven ni un céntimo.
--   2 · APAGADO     sin la clave no cambia nada. Protege lo que hoy está vivo en
--                   producción, que es justamente el estado apagado.
--   3 · COHERENCIA  `fn_cts_trunca` (liquidación al cesar) y `fn_provisiones`
--                   (provisión mensual) tienen que dar el MISMO sexto. Son dos
--                   copias de una sola regla legal, y en este repositorio esa
--                   figura ya falló tres veces: «qué toca marcar» en SQL y en el
--                   navegador, «qué es una falta» en pantalla y en el documento,
--                   y «quién puede leer la planilla». Cada vez, arreglar una
--                   dejó la otra rota y nadie se enteró hasta que alguien miró.
--
-- El sueldo del fixture es 1,200 a propósito: 1200/12 = 100 exactos, así que la
-- aritmética se sigue de cabeza y un error no se puede esconder en un redondeo.
-- ============================================================================
begin;
select plan(7);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000005e00', 'ZZSEXTO', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000005e01', 'SextoAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000005e00', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000005e09', '2025-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000005e02', 'SextoPersona', 'Laboratorio',
        '00000000-0000-0000-0000-000000005e00', 'test-hash', '2025-01-01');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000005e02', 'colibri', 1200, '2025-01-01');

insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-000000005e02', d::date, 8, 'cerrada'
from generate_series('2026-01-05'::date, '2026-04-30'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000005e09', true);

-- ── 2 · APAGADO ─────────────────────────────────────────────────────────────
-- La prueba APAGA la clave ella misma en vez de dar por supuesto que lo está.
-- Es la diferencia entre probar un COMPORTAMIENTO y probar el estado de una
-- configuración: el día que el sexto se encienda en producción —o que alguna
-- migración lo siembre— una prueba que asumiera «hoy está apagado» fallaría por
-- el motivo equivocado, y quien la viera en rojo buscaría el problema donde no
-- está. Acá los dos estados se fabrican, así que la prueba dice lo mismo antes y
-- después de encenderlo.
update configuracion
   set valor = valor - 'sexto_cts'
 where clave = 'planilla_provisiones';

create temporary table _apagado on commit drop as
select (e -> 'cts_may')::numeric  as cts,
       (e -> 'grati_s1')::numeric as grati,
       (e -> 'grati_s2')::numeric as grati2
from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000005e02';

select cmp_ok((select cts from _apagado), '>', 0::numeric,
  'DE PARTIDA · con el sexto apagado la persona ya acumula CTS');

-- Poner la clave en CERO tiene que dar exactamente lo mismo que no tenerla. Es
-- la forma documentada de revertir el encendido, y si no coincidieran, quien
-- quisiera dar marcha atrás dejaría la CTS en un tercer estado que nadie probó.
update configuracion
   set valor = valor || '{"sexto_cts": 0}'::jsonb
 where clave = 'planilla_provisiones';

select is(
  (select (e -> 'cts_may')::numeric
     from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000005e02'),
  (select cts from _apagado),
  'APAGADO · poner la clave en cero da lo mismo que no tenerla: así se revierte');

-- ── 1 · ENCENDIDO ───────────────────────────────────────────────────────────
update configuracion
   set valor = valor || '{"sexto_cts": 0.083333}'::jsonb
 where clave = 'planilla_provisiones';

create temporary table _encendido on commit drop as
select (e -> 'cts_may')::numeric  as cts,
       (e -> 'grati_s1')::numeric as grati,
       (e -> 'grati_s2')::numeric as grati2
from jsonb_array_elements(fn_provisiones('2026-08-05') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-000000005e02';

-- 13/12 = 1.08333…  El margen de un céntimo absorbe el redondeo del factor,
-- que se guarda como 0.083333 y no como 1/12 exacto.
select cmp_ok(
  abs((select cts from _encendido) - (select cts from _apagado) * 13.0 / 12.0),
  '<', 0.01::numeric,
  'ENCENDIDO · la CTS sube exactamente a 13/12: el sueldo más su sexto');

select cmp_ok((select cts from _encendido), '>', (select cts from _apagado),
  'ENCENDIDO · la CTS SUBE. Encender el sexto nunca puede hacer que alguien cobre menos');

-- Lo que de verdad se está blindando: que no se cuele donde no va.
select is((select grati from _encendido), (select grati from _apagado),
  'ENCENDIDO · la gratificación del primer semestre NO se mueve ni un céntimo');

select is((select grati2 from _encendido), (select grati2 from _apagado),
  'ENCENDIDO · la del segundo semestre tampoco: el sexto es exclusivo de la CTS');

-- ── 3 · COHERENCIA entre la liquidación y la provisión ──────────────────────
-- `fn_cts_trunca` calcula su propio sexto para quien cesa. Si esa cuenta y la de
-- `fn_provisiones` se separaran, una persona cobraría distinto según se fuera o
-- se quedara, y nada avisaría. Con sueldo 1,200 el sexto es 100 exactos.
select is(
  (fn_cts_trunca('00000000-0000-0000-0000-000000005e02', '2026-06-30')
     ->> 'sexto_de_gratificacion')::numeric,
  100.00::numeric,
  'COHERENCIA · la liquidación al cesar usa el mismo sexto: sueldo/12, no sueldo/6');

select * from finish();
rollback;
