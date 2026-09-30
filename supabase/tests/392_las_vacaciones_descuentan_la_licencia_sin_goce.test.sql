-- ============================================================================
-- 392_las_vacaciones_descuentan_la_licencia_sin_goce.test.sql
-- ============================================================================
-- Migración 0498. Con el interruptor de `licencia_sin_goce` ENCENDIDO, los días de
-- vacaciones (saldo, liquidación al cesar, resumen y provisiones) restan los días
-- que la persona estuvo fuera del servicio. Con él APAGADO —que es como nace—,
-- nada cambia.
--
-- Fechas INVENTADAS (las reales de una persona no se commitean). Dos personas
-- idénticas —ingreso el 15/01/2025, mismo sueldo— y una sola diferencia: Ana estuvo
-- 71 días fuera (02/06 → 11/08/2025) y Beto no. Se les pregunta el 10/01/2026.
--
-- LO QUE DE VERDAD HAY QUE DEFENDER, EN ESTE ORDEN:
--   1 · APAGADO, Ana y Beto son idénticos en las cuatro funciones. Es la promesa de
--       poder pegar la migración sin que se mueva un sol ni un día.
--   2 · ENCENDIDO, las cuatro funciones dicen LO MISMO sobre Ana: un solo reloj. Lo
--       que ya costó una vez (0297/0299) es tener la misma cuenta en dos sitios y
--       que se corrija uno.
--   3 · Beto, que no tiene ninguna interrupción, no se entera del interruptor.
--   4 · La MAGNITUD: la reserva en soles NO cambia (un día fuera no tiene pago que
--       devengar); cambian los días, el trunco de la liquidación y el vencimiento.
-- ============================================================================
begin;
select plan(24);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000004b0', 'ZZ498', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000004b9', 'CuatroAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-0000000004b0', 'admin', 'test-hash',
        '00000000-0000-0000-0000-0000000004bf', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-0000000004b1', 'CuatroAna',  'Laboratorio',
   '00000000-0000-0000-0000-0000000004b0', 'test-hash', '2025-01-15', 'planilla'),
  ('00000000-0000-0000-0000-0000000004b2', 'CuatroBeto', 'Laboratorio',
   '00000000-0000-0000-0000-0000000004b0', 'test-hash', '2025-01-15', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1950.00, '2025-01-15'
  from personas where nombres in ('CuatroAna', 'CuatroBeto');

insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
select id, '2025-01-15', '09:00', '18:00', array[1,2,3,4,5]
  from personas where nombres in ('CuatroAna', 'CuatroBeto');

-- Ana: la licencia sin goce, APROBADA (si no lo estuviera, no contaría).
insert into ausencias (persona_id, tipo, fecha_inicio, fecha_fin, motivo, registrada_por, aprobada_por, aprobada_at) values
  ('00000000-0000-0000-0000-0000000004b1', 'licencia_sin_goce', '2025-06-02', '2025-08-11',
   'acuerdo', '00000000-0000-0000-0000-0000000004b9',
   '00000000-0000-0000-0000-0000000004b9', now());

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000004bf', true);

-- Lo que cada función dice de Ana y de Beto, con el interruptor APAGADO.
create temporary table _off on commit drop as
select p.nombres as quien,
       (fn_vacaciones_saldo_interno(p.id, '2026-01-10')->>'dias_ganados')::numeric       as saldo_ganados,
       (fn_vacaciones_saldo_interno(p.id, '2026-01-10')->>'dias_fuera_del_servicio')::int as fuera,
       (fn_vacaciones_truncas(p.id, '2026-01-10')->>'dias_ganados')::numeric              as trunc_ganados,
       (fn_vacaciones_truncas(p.id, '2026-01-10')->>'monto')::numeric                     as trunc_monto,
       (select (e->>'dias_ganados')::numeric from jsonb_array_elements(fn_vacaciones_resumen('2026-01-10')) e
         where e->>'persona_id' = p.id::text)                                             as res_ganados,
       (select (e->>'horas_base')::numeric   from jsonb_array_elements(fn_vacaciones_resumen('2026-01-10')) e
         where e->>'persona_id' = p.id::text)                                             as res_base,
       (select (e->>'vac_dias')::numeric     from jsonb_array_elements(fn_provisiones('2026-01-10')->'personas') e
         where e->>'persona_id' = p.id::text)                                             as prov_dias,
       (select (e->>'vac')::numeric          from jsonb_array_elements(fn_provisiones('2026-01-10')->'personas') e
         where e->>'persona_id' = p.id::text)                                             as prov_vac
  from personas p where p.nombres in ('CuatroAna', 'CuatroBeto');

-- ── 1 · APAGADO: Ana y Beto son idénticos en las cuatro funciones ────────────
select is(
  (select row(saldo_ganados, fuera, trunc_ganados, trunc_monto, res_ganados, res_base, prov_dias, prov_vac)::text
     from _off where quien = 'CuatroAna'),
  (select row(saldo_ganados, fuera, trunc_ganados, trunc_monto, res_ganados, res_base, prov_dias, prov_vac)::text
     from _off where quien = 'CuatroBeto'),
  'APAGADO · con el interruptor apagado, una licencia sin goce APROBADA no mueve ni un día ni un sol en ninguna de las cuatro funciones');

-- `fn_meses_y_dias` cuenta meses completos desde el día 1 y días sueltos contando
-- ambos extremos: del 15/01/2025 al 10/01/2026 son 11 meses y 27 días, no 26.
select is((select saldo_ganados from _off where quien = 'CuatroBeto'), 14.88::numeric,
  'APAGADO · 11 meses y 27 días: 15×11/12 + 15×27/360 = 14.875 → 14.88 (la cuenta de siempre)');

select is((select fuera from _off where quien = 'CuatroAna'), 0,
  'APAGADO · el saldo dice 0 días fuera del servicio: la licencia está registrada pero no cuenta');

-- ── ENCENDER ────────────────────────────────────────────────────────────────
update tipos_ausencia set suspende_record = true where codigo = 'licencia_sin_goce';

create temporary table _on on commit drop as
select p.nombres as quien,
       fn_vacaciones_saldo_interno(p.id, '2026-01-10')                                    as saldo,
       fn_vacaciones_truncas(p.id, '2026-01-10')                                          as trunca,
       (select e from jsonb_array_elements(fn_vacaciones_resumen('2026-01-10')) e
         where e->>'persona_id' = p.id::text)                                             as resumen,
       (select e from jsonb_array_elements(fn_provisiones('2026-01-10')->'personas') e
         where e->>'persona_id' = p.id::text)                                             as prov
  from personas p where p.nombres in ('CuatroAna', 'CuatroBeto');

-- ── 2 · ENCENDIDO: el saldo de Ana baja lo que estuvo fuera ─────────────────
-- Ingreso efectivo = 15/01/2025 + 71 días = 27/03/2025. De ahí al 10/01/2026 son
-- 9 meses y 15 días: 15×9/12 + 15×15/360 = 11.25 + 0.625 = 11.875 → 11.88.
-- (Tres días menos que Beto, como debe ser: 14.88 − 11.88 = 3.00.)
select is((select (saldo->>'dias_ganados')::numeric from _on where quien = 'CuatroAna'), 11.88::numeric,
  'ENCENDIDO · Ana gana 11.88 días, no 14.88: los 71 que estuvo fuera no cuentan');

select is((select saldo->>'fecha_ingreso_efectiva' from _on where quien = 'CuatroAna'), '2025-03-27',
  'ENCENDIDO · el saldo dice desde cuándo corre su servicio: 27/03/2025');

select is((select (saldo->>'dias_fuera_del_servicio')::int from _on where quien = 'CuatroAna'), 71,
  'ENCENDIDO · y cuántos días estuvo fuera: 71');

select is((select saldo->>'fecha_ingreso' from _on where quien = 'CuatroAna'), '2025-01-15',
  'ENCENDIDO · el ingreso REAL no se toca: sigue siendo 15/01/2025');

-- ── 3 · Beto no se entera del interruptor ───────────────────────────────────
select is((select (saldo->>'dias_ganados')::numeric from _on where quien = 'CuatroBeto'), 14.88::numeric,
  'SIN INTERRUPCIÓN · Beto sigue con 14.88 aunque el interruptor esté encendido');

select is((select saldo->>'fecha_ingreso_efectiva' from _on where quien = 'CuatroBeto'), '2025-01-15',
  'SIN INTERRUPCIÓN · su ingreso efectivo es exactamente su ingreso');

-- ── 4 · UN SOLO RELOJ: las cuatro funciones dicen lo mismo de Ana ───────────
select is((select (trunca->>'dias_ganados')::numeric from _on where quien = 'CuatroAna'),
          (select (saldo->>'dias_ganados')::numeric  from _on where quien = 'CuatroAna'),
  'UN RELOJ · la liquidación al cesar y el saldo dicen los mismos días ganados');

select is((select (trunca->>'dias_del_trunco')::numeric from _on where quien = 'CuatroAna'), 11.88::numeric,
  'UN RELOJ · la hoja de liquidación muestra el trunco de 11.88 días, el mismo que paga');

select cmp_ok((select (trunca->>'monto')::numeric from _on where quien = 'CuatroAna'), '<',
              (select (trunca->>'monto')::numeric from _on where quien = 'CuatroBeto'),
  'DINERO · la liquidación de Ana paga menos que la de Beto: son 3 días menos de vacaciones');

select cmp_ok((select (trunca->>'monto')::numeric from _on where quien = 'CuatroAna'), '>', 0::numeric,
  'DINERO · y sigue pagando: recortar la interrupción no la deja en cero');

-- Ana 11.88 de 14.88 días ⇒ el monto guarda la misma proporción (misma base, mismo
-- sueldo). Producto cruzado con una tolerancia de medio sol: cada monto va redondeado
-- al centavo y ese redondeo se multiplica por ~15.
select cmp_ok(
  abs((select (trunca->>'monto')::numeric * 14.88 from _on where quien = 'CuatroAna')
    - (select (trunca->>'monto')::numeric * 11.88 from _on where quien = 'CuatroBeto')),
  '<', 0.5::numeric,
  'DINERO · el monto es proporcional a los días: monto(Ana)/11.88 = monto(Beto)/14.88');

select is((select (resumen->>'dias_ganados')::numeric from _on where quien = 'CuatroAna'), 11.9::numeric,
  'RESUMEN · Ana: 15 × (360 − 71) ÷ 365 = 11.9 días ganados');

select is((select (resumen->>'dias_ganados')::numeric from _on where quien = 'CuatroBeto'), 14.8::numeric,
  'RESUMEN · Beto: 15 × 360 ÷ 365 = 14.8, sin cambio');

select is((select (resumen->>'horas_base')::numeric from _on where quien = 'CuatroAna'), 1857.86::numeric,
  'RESUMEN · la base de horas esperadas de Ana no exige trabajar los 71 días fuera: 45 × 289 ÷ 7');

select is((select (resumen->>'horas_base')::numeric from _on where quien = 'CuatroBeto'), 2314.29::numeric,
  'RESUMEN · la de Beto queda entera: 45 × 360 ÷ 7');

select is((select (prov->>'vac_dias')::numeric from _on where quien = 'CuatroAna'), 11.9::numeric,
  'PROVISIONES · Ana muestra 11.9 días de este año');

select is((select (prov->>'vac_dias')::numeric from _on where quien = 'CuatroBeto'), 14.8::numeric,
  'PROVISIONES · Beto muestra 14.8, sin cambio');

-- ── 5 · LA MAGNITUD: la reserva en soles NO se mueve ────────────────────────
-- Un día fuera no tiene pago que devengar, así que la reserva ya lo excluía. Lo
-- que cambia son los DÍAS que se muestran, no el dinero apartado.
select is(
  (select (prov->>'vac')::numeric from _on where quien = 'CuatroAna'),
  (select prov_vac from _off where quien = 'CuatroAna'),
  'RESERVA · el monto reservado para vacaciones es el mismo con el interruptor encendido o apagado');

-- ── 6 · EL VENCIMIENTO SE CORRE CON EL AÑO ──────────────────────────────────
-- El 01/02/2026 Beto ya cerró su primer récord (15+ días ganados, 1 récord sin
-- gozar) y Ana todavía no (12+): su año cierra recién el 27/03/2026.
select is(
  (select row((s->>'records_sin_gozar')::int, s->>'vence_el')::text
     from (select fn_vacaciones_saldo_interno(id, '2026-02-01') as s from personas where nombres = 'CuatroAna') x),
  '(0,)',
  'VENCIMIENTO · el 01/02/2026 Ana aún no cerró su récord: nada que gozar ni que vencer');

select is(
  (select row((s->>'records_sin_gozar')::int, s->>'vence_el')::text
     from (select fn_vacaciones_saldo_interno(id, '2026-02-01') as s from personas where nombres = 'CuatroBeto') x),
  '(1,2027-01-15)',
  'VENCIMIENTO · el mismo día Beto sí cerró su récord y su vencimiento es 15/01/2027, sin cambio');

-- ── 7 · Apagar el interruptor lo devuelve todo, sin tocar los datos ─────────
update tipos_ausencia set suspende_record = false where codigo = 'licencia_sin_goce';
select is((select (fn_vacaciones_saldo_interno(id, '2026-01-10')->>'dias_ganados')::numeric from personas where nombres = 'CuatroAna'),
          14.88::numeric,
  'REVERSIBLE · apagado otra vez, Ana vuelve a 14.88 con la licencia todavía registrada');

select * from finish();
rollback;
