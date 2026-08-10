-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 156_la_foto_cuadra_con_sobretiempo.test.sql
-- ============================================================================
-- La 0185 le sumó el recargo por sobretiempo al total de la planilla. El candado
-- chk_foto_cuadra —que la 0127 había puesto al día con la movilidad, la
-- educación y la pensión— no se enteró, y no había columna donde guardar el
-- monto. Resultado: al cerrar el periodo el insert revienta con 23514, se
-- revierte la transacción entera, y NO SE PUEDE PAGAR A NADIE.
--
-- Esta prueba exige LAS DOS MITADES, como la 141:
--   · que un periodo con sobretiempo se pueda cerrar, y que el monto quede
--     guardado donde se pueda consultar;
--   · que el candado SIGA cerrando cuando la foto no cuadra — incluido el caso
--     nuevo, que es mover el sobretiempo sin mover el total.
--
-- La segunda mitad es la que importa conservar. Un candado que solo se
-- comprueba por el lado bueno se afloja en la primera urgencia sin que ninguna
-- prueba se queje; y aflojar este significa guardar una foto del pago que no se
-- sostiene, que es el único registro que queda de lo que se le transfirió a
-- cada persona.
--
-- El fixture es el de la 143 (OtExceso): salario S/1130, periodo 29-jul →
-- 28-ago-2026 (31 días → v_base = 6.5 × 31 = 201.5 h, hora = S/5.60794…),
-- seis días de 8.5 h = 51 h en un ciclo → 3 h de exceso el sexto día →
-- 2 h al 25 % + 1 h al 35 % = 0.85 h de recargo → S/4.77.
-- ============================================================================
begin;
select plan(8);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000000c1', 'ZZFOT2', 'Sede de laboratorio foto+OT', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000000c0', 'FotoOtAdmin', 'Lab', '00000000-0000-0000-0000-0000000000c1', 'admin', 'x', '00000000-0000-0000-0000-00000000cc00', '2024-01-01');
set session_replication_role = origin;

-- Dos personas, y la segunda es la que prueba el daño de verdad: NO hace
-- sobretiempo, y aun así hoy se queda sin cobrar, porque el insert de la foto es
-- uno solo para todo el equipo y se revierte entero.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo, sueldo_fijo)
values ('00000000-0000-0000-0000-0000000000c2', 'FotoConOt', 'Lab', '00000000-0000-0000-0000-0000000000c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false),
       ('00000000-0000-0000-0000-0000000000c3', 'FotoSinOt', 'Lab', '00000000-0000-0000-0000-0000000000c1', 'x', '2024-01-01', 'taller_produccion', 'planilla', false);

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
select id, 'colibri', 1130, '2024-01-01'
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000c1' and nombres <> 'FotoOtAdmin';

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables)
select id, '2024-01-01', '09:00', '17:00', 0, 0, array[1,2,3,4,5,6]
from personas where sede_base_id = '00000000-0000-0000-0000-0000000000c1' and nombres <> 'FotoOtAdmin';

-- Con sobretiempo: 6 días de 8.5 h = 51 h en un solo ciclo de siete días.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000c2', d::date, 8.5, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-08'::date, '1 day') d;

-- Sin sobretiempo: 5 días de 8 h = 40 h. Muy por debajo de 48.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select '00000000-0000-0000-0000-0000000000c3', d::date, 8.0, 'cerrada'
from generate_series('2026-08-03'::date, '2026-08-07'::date, '1 day') d;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('cccccccc-0000-0000-0000-000000000001', '2026-07-29', '2026-08-28', 'abierto');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000cc00', true);


-- ── 1 · El periodo se puede cerrar ──────────────────────────────────────────
-- Antes de la 0201 esta línea sola tumbaba la prueba entera con 23514.
select lives_ok(
  $$ select fn_periodo_pagado('cccccccc-0000-0000-0000-000000000001', true) $$,
  'CIERRE · un periodo en el que alguien hizo sobretiempo se puede marcar como pagado'
);

-- ── 2 · Y arrastraba a quien no hizo sobretiempo ────────────────────────────
-- Se cuentan las dos del fixture y no las del periodo: el periodo alcanza
-- también a las personas de la semilla, y un total absoluto convertiría esta
-- prueba en un contador de datos ajenos que cambia solo.
select is(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = 'cccccccc-0000-0000-0000-000000000001'
      and persona_id in ('00000000-0000-0000-0000-0000000000c2',
                         '00000000-0000-0000-0000-0000000000c3')),
  2,
  'CIERRE · quedan las dos fotos: el insert es uno solo, y antes se revertía para todo el equipo'
);

-- ── 3 · El monto queda guardado, y es el que se calculó ─────────────────────
select is(
  (select monto_sobretiempo from planilla_pagada_detalle
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  4.77::numeric,
  'MONTO · el recargo (2 h al 25 % + 1 h al 35 %) queda en su columna: S/4.77'
);

select is(
  (select monto_sobretiempo from planilla_pagada_detalle
    where persona_id = '00000000-0000-0000-0000-0000000000c3'),
  0::numeric,
  'MONTO · quien no hizo sobretiempo queda en cero, no en nulo'
);

-- ── 4 · La foto guarda lo mismo que dijo el cálculo ─────────────────────────
-- Si la columna se llenara de otra clave del JSON, el candado seguiría cuadrando
-- —porque el total también saldría de ahí— y nadie lo notaría.
select is(
  (select monto_sobretiempo from planilla_pagada_detalle
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  (select (fila->>'monto_sobretiempo')::numeric from planilla_pagada_detalle
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'MONTO · la columna dice lo mismo que la fila de la que se copió'
);

-- ── 5 · El desglose suma el total, con el sobretiempo dentro ────────────────
select is(
  (select total from planilla_pagada_detalle
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  (select pago_base + monto_feriados + monto_plus + asignacion_familiar
        + monto_movilidad + monto_educacion - descuento_pension
        + monto_sobretiempo + bonos - descuentos
     from planilla_pagada_detalle
    where persona_id = '00000000-0000-0000-0000-0000000000c2'),
  'CUADRA · el desglose de quien hizo sobretiempo suma exactamente su total'
);

-- ── 6 · Y el candado SIGUE cerrando ─────────────────────────────────────────
-- Las dos mitades, como manda la 141. Sin esto, la forma más fácil de "arreglar"
-- un cierre que falla es soltar el CHECK, y ninguna prueba se quejaría.

-- (a) La forma de siempre: un total que no corresponde al desglose.
select throws_ok(
  $$ insert into planilla_pagada_detalle
       (periodo_id, persona_id, version, origen, nombre, sede_codigo, total, fila,
        pago_base, monto_sobretiempo)
     values ('cccccccc-0000-0000-0000-000000000001',
             '00000000-0000-0000-0000-0000000000c2', 99, 'pago', 'FotoConOt Lab',
             'ZZFOT2', 999.99, '{}'::jsonb, 10.00, 0) $$,
  '23514', null,
  'CANDADO · una foto cuyo total no corresponde al desglose se sigue rechazando'
);

-- (b) La forma NUEVA, que es la que esta migración estrena: mover el
--     sobretiempo sin mover el total. Si el término no estuviera dentro del
--     CHECK, esto pasaría y la foto mentiría en silencio.
select throws_ok(
  $$ insert into planilla_pagada_detalle
       (periodo_id, persona_id, version, origen, nombre, sede_codigo, total, fila,
        pago_base, monto_sobretiempo)
     values ('cccccccc-0000-0000-0000-000000000001',
             '00000000-0000-0000-0000-0000000000c2', 98, 'pago', 'FotoConOt Lab',
             'ZZFOT2', 10.00, '{}'::jsonb, 10.00, 4.77) $$,
  '23514', null,
  'CANDADO · y el sobretiempo está DENTRO del candado: moverlo sin mover el total se rechaza'
);

select * from finish();
rollback;
