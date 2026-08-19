-- ============================================================================
-- 210_el_libro_vale_para_los_cinco_beneficios.test.sql
-- ============================================================================
-- El caso real, medido el 2026-08-19: `desembolsos_beneficios` admite cinco
-- ventanas y `fn_provisiones` solo restaba las dos de CTS. Con S/700 anotados
-- en `grati_s1`, la provisión no se movía de S/749.97 y seguía diciendo
-- `grati_s1_pagada: false`.
--
-- Y eso no se quedaba en la reserva: `fn_grati_cts_periodo` lee esos mismos
-- campos para proponer el bono al cerrar el mes, así que proponía volver a
-- pagar lo ya pagado.
--
-- CÓMO ESTÁ ESCRITO. No afirma montos absolutos: lee primero cuánto acumula la
-- persona sin desembolsos y comprueba que cada depósito baje la provisión en
-- exactamente ese monto. Así mide lo que la 0273 cambió —la resta— y no la
-- fórmula del acumulado, que es de otras migraciones. Es la misma forma de la
-- prueba 124, que hizo lo propio para la CTS.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-00000000c700', 'ZZLIB', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000c701', 'LibAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c700', 'admin', 'test-hash',
        '00000000-0000-0000-0000-00000000c709', '2024-01-01');
set session_replication_role = origin;

-- Sueldo fijo: devenga por día de calendario, así que acumula sin depender de
-- que haya jornadas marcadas. Menos fixture, mismo camino de código.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, sueldo_fijo)
values ('00000000-0000-0000-0000-00000000c702', 'LibPersona', 'Laboratorio',
        '00000000-0000-0000-0000-00000000c700', 'test-hash', '2024-01-01', true);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-00000000c702', 'colibri', 1300, '2024-01-01');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000c709', true);

-- Lo que acumula SIN ningún desembolso. Todo lo demás se mide contra esto.
create temporary table _base on commit drop as
select ((e -> 'grati_s1')::numeric)   as grati_s1,
       ((e -> 'grati_total')::numeric) as grati_total,
       ((e -> 'be_total')::numeric)    as be_total,
       ((e -> 'vac')::numeric)         as vac,
       ((e -> 'gran_total')::numeric)  as gran_total
from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702';

select cmp_ok((select grati_s1 from _base), '>', 0::numeric,
  'DE PARTIDA · sin desembolsos, la persona acumula gratificación');

select cmp_ok((select vac from _base), '>', 0::numeric,
  'DE PARTIDA · y también vacaciones');

-- ── 1 · La GRATIFICACIÓN descuenta lo depositado fuera de planilla ──────────
-- Era el defecto: esta ventana no miraba el libro. El monto sale del propio
-- acumulado para que sea un pago PARCIAL de verdad y no un sobrepago.
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
select '00000000-0000-0000-0000-00000000c702', 'grati_s1', 2026,
       round(grati_s1 / 2, 2), '2026-07-15', 'transferencia'
from _base;

select is(
  (select ((e -> 'grati_s1')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  (select round(grati_s1 - round(grati_s1 / 2, 2), 2) from _base),
  'GRATI · la provisión baja exactamente lo depositado, no salta a cero');

select is(
  (select ((e ->> 'grati_s1_pagada')::boolean)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  true,
  'GRATI · y consta que algo se pagó');

-- ── 2 · La BONIFICACIÓN sigue a lo que queda de la gratificación ────────────
-- Antes era todo-o-nada. Con medio pago queda media bonificación, no la entera
-- ni cero.
select is(
  (select ((e -> 'be_total')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  (select round(((e -> 'grati_total')::numeric) * ((e -> 'tasa_be')::numeric), 2)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  'BONIFICACIÓN · es la tasa sobre lo que queda de gratificación, no sobre lo devengado');

-- ── 3 · Las VACACIONES también descuentan ──────────────────────────────────
insert into desembolsos_beneficios (persona_id, ventana, anio, monto, fecha_pago, origen)
select '00000000-0000-0000-0000-00000000c702', 'vacaciones', 2026,
       round(vac / 4, 2), '2026-03-01', 'transferencia'
from _base;

select is(
  (select ((e -> 'vac')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  (select round(vac - round(vac / 4, 2), 2) from _base),
  'VACACIONES · la quinta ventana del libro por fin se descuenta');

-- ── 4 · Sin arrastre entre ventanas ────────────────────────────────────────
-- Lo depositado en el primer semestre no puede tocar el segundo.
select is(
  (select ((e -> 'grati_s2_monto_pagado'))
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  'null'::jsonb,
  'SIN ARRASTRE · un depósito de grati_s1 no marca pagado el segundo semestre');

-- ── 5 · Anotado en los DOS sitios, se descuenta UNA vez ─────────────────────
-- La decisión de la 0158 que esta migración conserva: manda la mayor, no la
-- suma. Sumarlas dejaría la provisión corta.
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000000c7aa', '2026-07-01', '2026-07-31', 'pagado');
insert into movimientos_planilla (periodo_id, persona_id, concepto, monto, categoria, tipo)
values ('00000000-0000-0000-0000-00000000c7aa', '00000000-0000-0000-0000-00000000c702',
        'Grati julio', 100.00, 'gratificacion', 'bono');

select is(
  (select ((e -> 'grati_s1')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  0::numeric,
  'DOS FUENTES · la planilla asume la ventana completa y manda por ser la mayor');

-- ── 6 · El gran total cuadra con las columnas que se ven, al céntimo ────────
-- Es la queja que originó todo esto: un total que no suma lo que se muestra.
select is(
  (select ((e -> 'gran_total')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  (select ((e -> 'grati_total')::numeric) + ((e -> 'be_total')::numeric)
        + ((e -> 'cts_total')::numeric)   + ((e -> 'vac')::numeric)
     from jsonb_array_elements(fn_provisiones('2026-08-19') -> 'personas') e
    where (e ->> 'persona_id')::uuid = '00000000-0000-0000-0000-00000000c702'),
  'GRAN TOTAL · es exactamente la suma de las cuatro columnas visibles');

select * from finish();
rollback;
