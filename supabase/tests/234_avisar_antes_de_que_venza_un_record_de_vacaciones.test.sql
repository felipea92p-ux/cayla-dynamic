-- ============================================================================
-- 234_avisar_antes_de_que_venza_un_record_de_vacaciones.test.sql
-- ============================================================================
-- Escrita para la 0299 y PORTADA a la función que sobrevivió (0297), cuando la
-- 0302 retiró la duplicada. Sus tres casos son los que la 231 no cubría —quien
-- ya gozó, el consumo FIFO y la ventana— así que se conservan enteros; lo que
-- cambia son los nombres de las columnas y una expectativa, marcada abajo.
--
-- El sistema avisa de un récord de vacaciones que va a vencer, con meses de
-- antelación, en vez de descubrirlo el día de la liquidación.
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
select * from fn_vacaciones_por_vencer(400, null);

-- ── 1 · QUIEN GOZÓ LO SUYO NO SALE ──────────────────────────────────────────
-- La mitad que impide que el aviso se vuelva ruido. Si avisa de todo el mundo,
-- nadie lo mira, y el día que avise de alguien de verdad ya no significará nada.
select is(
  (select count(*)::int from _av where persona like 'DoceAlDia%'), 0,
  'SIN RUIDO · quien gozó sus dos récords no aparece en el aviso');

-- ── 2 y 3 · A QUIEN NO GOZÓ NADA YA LE VENCIÓ UNO ──────────────────────────
-- Su récord 1 se ganó el 01/03/2025 y debía gozarse antes del 01/03/2026: esa
-- fecha ya pasó.
--
-- ⇩ EXPECTATIVA CAMBIADA AL PORTARLA ⇩ La 0299 devolvía en `vence_el` el récord
-- más ANTIGUO pendiente —una fecha ya pasada—. La que quedó informa el PRÓXIMO
-- vencimiento y cuenta los ya vencidos aparte, que es lo que hace falta para
-- programar: la fecha que todavía se puede evitar. Las dos dicen lo mismo con
-- distinto reparto; lo que no puede fallar es que se sepa que hay uno vencido.
select is(
  (select records_vencidos from _av where persona like 'DoceNuncaGozo%'), 1,
  'VENCIDO · a quien no gozó nada le venció exactamente UN récord, no dos');
select is(
  (select vence_el from _av where persona like 'DoceNuncaGozo%'), '2027-03-01'::date,
  'VENCIDO · y el siguiente —el que todavía se puede salvar— vence el 01/03/2027');

-- ── 4 y 5 · A QUIEN GOZÓ LA MITAD, LE QUEDA UNO Y VENCE DESPUÉS ─────────────
-- Sus 15 días consumieron el récord 1 —los más antiguos primero— así que el
-- pendiente es el 2, ganado el 01/03/2026 y vence el 01/03/2027. Si la
-- aritmética se equivocara por un año, esta aserción lo dice.
select is(
  (select vence_el from _av where persona like 'DoceMitad%'), '2027-03-01'::date,
  'FIFO · quien gozó el primer récord tiene pendiente el segundo, que vence en 2027');
select is(
  (select records_vencidos from _av where persona like 'DoceMitad%'), 0,
  'FIFO · y no ha vencido ninguno: el aviso llega con tiempo, que es su razón de ser');

-- ── 6 · LA VENTANA DE AVISO FILTRA ──────────────────────────────────────────
-- Con 30 días de antelación, el que vence en 2027 no debe salir. Un aviso que
-- ignora su propia ventana avisa siempre y no sirve.
select is(
  (select count(*)::int from fn_vacaciones_por_vencer(30, null) where persona like 'DoceMitad%'), 0,
  'VENTANA · con 30 días de aviso, el que vence dentro de un año no aparece');

select * from finish();
rollback;
