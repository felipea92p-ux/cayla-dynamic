-- ============================================================================
-- 234_avisar_antes_de_que_venza_un_record_de_vacaciones.test.sql
-- ============================================================================
-- Migración 0299. El sistema avisa de un récord de vacaciones que va a vencer,
-- con meses de antelación, en vez de descubrirlo el día de la liquidación.
--
-- LO QUE ESTA PRUEBA FIJA NO ES UN MONTO: es la ARITMÉTICA DE FECHAS, que es
-- donde esto se equivoca sin que nadie lo note. Un récord se gana al cumplirse
-- el aniversario y debe gozarse antes del siguiente; los días tomados consumen
-- los récords más antiguos primero, así que los pendientes son los más nuevos.
-- Equivocarse por un año en cualquiera de esos dos pasos da un aviso que llega
-- tarde o que no llega.
--
-- LAS TRES PERSONAS, todas con el mismo ingreso y el mismo sueldo:
--   · la que gozó lo que le tocaba  → no debe salir en el aviso
--   · la que no gozó nada           → su récord más antiguo YA venció
--   · la que gozó la mitad          → le queda uno, y vence más adelante
-- ============================================================================
-- ── CAMBIO 0302 ─────────────────────────────────────────────────────────────
-- Esta prueba se escribió para la fn_vacaciones_por_vencer de la 0299, que
-- devolvía `nombre · dias_saldo · records_pendientes · ya_vencido`. En `main`
-- convivían DOS implementaciones de la misma función con firmas distintas —dos
-- migraciones paralelas, no un renumerado— y llamarla reventaba con «function
-- fn_vacaciones_por_vencer(integer) is not unique». La 0302 quita la sobrante y
-- se queda la de la 0297, por decisión de Felipe.
--
-- Los CASOS de esta prueba no cambian: siguen valiendo, y son buenos. Lo que se
-- remapea son las columnas — `nombre` pasa a `persona`, y `ya_vencido` se
-- deriva de `records_vencidos > 0`, que es lo que la función que se queda dice.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000298000', 'ZZ298', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000002980ad', 'DoceAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000298000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000002980ff', '2020-01-01');
set session_replication_role = origin;

-- Ingreso el 01/03/2024. Al 25/08/2026 llevan DOS aniversarios cumplidos:
--   récord 1: 01/03/2024 → 28/02/2025, ganado el 01/03/2025, vence el 01/03/2026
--   récord 2: 01/03/2025 → 28/02/2026, ganado el 01/03/2026, vence el 01/03/2027
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000298001','DoceAlDia',   'Laboratorio','00000000-0000-0000-0000-000000298000','test-hash','2024-03-01','planilla'),
  ('00000000-0000-0000-0000-000000298002','DoceNuncaGozo','Laboratorio','00000000-0000-0000-0000-000000298000','test-hash','2024-03-01','planilla'),
  ('00000000-0000-0000-0000-000000298003','DoceMitad',   'Laboratorio','00000000-0000-0000-0000-000000298000','test-hash','2024-03-01','planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2024-03-01'
from personas where apellidos = 'Laboratorio' and nombres like 'Doce%' and nombres <> 'DoceAdmin';

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2024-03-01', '09:00', '18:00', array[1,2,3,4,5]
from personas where apellidos = 'Laboratorio' and nombres like 'Doce%' and nombres <> 'DoceAdmin';

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000002980ff', true);

-- DoceAlDia gozó 30 días: sus dos récords completos.
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por) values
  ('00000000-0000-0000-0000-000000298001','vacaciones','2025-04-01','2025-04-15','record 1','00000000-0000-0000-0000-0000002980ad'),
  ('00000000-0000-0000-0000-000000298001','vacaciones','2026-04-01','2026-04-15','record 2','00000000-0000-0000-0000-0000002980ad'),
  -- DoceMitad gozó solo los 15 del primero.
  ('00000000-0000-0000-0000-000000298003','vacaciones','2025-04-01','2025-04-15','record 1','00000000-0000-0000-0000-0000002980ad');
-- DoceNuncaGozo no tiene ninguna, a propósito.

create temporary table _av on commit drop as
select * from fn_vacaciones_por_vencer(400);

-- ── 1 · QUIEN GOZÓ LO SUYO NO SALE ──────────────────────────────────────────
-- La mitad que impide que el aviso se vuelva ruido. Si avisa de todo el mundo,
-- nadie lo mira, y el día que avise de alguien de verdad ya no significará nada.
select is(
  (select count(*)::int from _av where persona like 'DoceAlDia%'), 0,
  'SIN RUIDO · quien gozó sus dos récords no aparece en el aviso');

-- ── 2 y 3 · A QUIEN NO GOZÓ NADA, EL MÁS ANTIGUO YA LE VENCIÓ ───────────────
-- Su récord 1 se ganó el 01/03/2025 y debía gozarse antes del 01/03/2026. Esa
-- fecha ya pasó: el aviso tiene que decirlo, y decir que YA venció.
select is(
  -- CAMBIO 0302 — La 0299 devolvía en `vence_el` el récord MÁS ANTIGUO, o sea el
  -- que ya venció (01/03/2026). La 0297 devuelve el PRÓXIMO por vencer y cuenta
  -- aparte los ya vencidos en `records_vencidos`. Son dos preguntas distintas y
  -- las dos son legítimas; la de la 0297 es la que queda, y es más informativa
  -- porque no confunde «lo que ya se perdió» con «lo que hay que programar».
  (select vence_el from _av where persona like 'DoceNuncaGozo%'), '2027-03-01'::date,
  'VENCIDO · a quien no gozó nada, el PRÓXIMO récord vence el 01/03/2027 — el ya vencido se cuenta aparte');
select is(
  (select records_vencidos > 0 from _av where persona like 'DoceNuncaGozo%'), true,
  'VENCIDO · y el aviso lo marca como ya vencido, no como próximo');

-- ── 4 y 5 · A QUIEN GOZÓ LA MITAD, LE QUEDA UNO Y VENCE DESPUÉS ─────────────
-- Sus 15 días consumieron el récord 1 —los más antiguos primero— así que el
-- pendiente es el 2, ganado el 01/03/2026 y vence el 01/03/2027. Si la
-- aritmética se equivocara por un año, esta aserción lo dice.
select is(
  (select vence_el from _av where persona like 'DoceMitad%'), '2027-03-01'::date,
  'FIFO · quien gozó el primer récord tiene pendiente el segundo, que vence en 2027');
select is(
  (select records_vencidos > 0 from _av where persona like 'DoceMitad%'), false,
  'FIFO · y todavía no ha vencido: el aviso llega con tiempo, que es su razón de ser');

-- ── 6 · LA VENTANA DE AVISO FILTRA ──────────────────────────────────────────
-- Con 30 días de antelación, el que vence en 2027 no debe salir. Un aviso que
-- ignora su propia ventana avisa siempre y no sirve.
select is(
  (select count(*)::int from fn_vacaciones_por_vencer(30) where persona like 'DoceMitad%'), 0,
  'VENTANA · con 30 días de aviso, el que vence dentro de un año no aparece');

select * from finish();
rollback;
