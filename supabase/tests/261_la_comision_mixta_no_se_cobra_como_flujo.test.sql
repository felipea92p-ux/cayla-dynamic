-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 261_la_comision_mixta_no_se_cobra_como_flujo.test.sql
-- ============================================================================
-- La 0114 modeló UN solo esquema de comisión —la comisión sobre flujo— y anotó
-- en su cabecera que el otro, la comisión MIXTA, quedaba sin modelar. Quedó así
-- un año, y quien estaba en mixta pagó cada mes una comisión que su AFP no le
-- cobra: entre 1.47 y 1.69 puntos de su base. Lo encontró el contador el
-- 2026-08-31 comparando las boletas contra AFPnet.
--
-- La prueba central es la tercera: dos personas idénticas —misma sede, mismo
-- sueldo, los mismos dos días trabajados— cuya única diferencia es el esquema
-- de comisión. La de mixta tiene que llevarse a casa exactamente la comisión de
-- diferencia, ni un céntimo más ni menos.
--
-- Las demás cierran las puertas por las que el defecto volvería:
--   · que las tasas nuevas descuenten 11.37 % y no otra cosa;
--   · que agregarlas no haya movido las de flujo, que sí estaban bien;
--   · que los códigos viejos sigan existiendo, porque el historial de la 0261
--     ya tiene filas escritas con ellos;
--   · y la más silenciosa de todas: que la fila de mixta cubra desde tan atrás
--     como la de flujo. Si empezara después, el lateral de fn_planilla_calcular
--     no encontraría fila, caería al interruptor global —que vale 0 desde la
--     0115— y a esa persona dejaría de descontársele TODO sin que nadie lo note.
-- ============================================================================
begin;
select plan(9);


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · Las cuatro tasas, y lo que descuentan
-- ════════════════════════════════════════════════════════════════════════════

select is(
  (select count(*) from tasas_pension where regimen like '%\_mixta'),
  4::bigint,
  'están las cuatro AFP en comisión mixta'
);

-- 10 % de aporte + 1.37 % de prima. La comisión de la mixta no entra acá porque
-- no se retiene del sueldo: la AFP la cobra contra el saldo del fondo.
select is(
  (select round(aporte + comision + prima, 5) from tasas_pension where regimen = 'integra_mixta'),
  0.11370,
  'quien está en mixta aporta 11.37 %, no 12.92 %'
);


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Lo que ya estaba bien sigue igual
-- ════════════════════════════════════════════════════════════════════════════
-- Las comisiones sobre flujo y la prima de la 0114 se volvieron a verificar
-- contra la SBS el 2026-08-31 y son correctas. El defecto era que faltaba el
-- otro esquema, no que estos números estuvieran mal. Si una migración futura
-- "arregla" estos, está arreglando lo que no estaba roto.

select is(
  (select round(aporte + comision + prima, 5) from tasas_pension where regimen = 'integra'),
  0.12920,
  'la comisión sobre flujo de Integra sigue en 12.92 % — no se tocó'
);

-- Los códigos viejos NO se renombraron a `integra_flujo`: `asignaciones_regimen_pension`
-- ya tiene filas escritas con ellos, y renombrarlos reescribiría el pasado.
select is(
  (select count(*) from tasas_pension
    where regimen in ('onp','profuturo','prima','integra','habitat','jubilada')),
  6::bigint,
  'los seis códigos de antes siguen existiendo con su nombre de siempre'
);


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · LA PRUEBA DE PLATA: dos personas idénticas, distinto esquema
-- ════════════════════════════════════════════════════════════════════════════

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000003a0', 'ZZMIX', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000003a1', 'MixAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000003a0', 'admin', 'x',
        '00000000-0000-0000-0000-0000000ffb01', '2024-01-01');
set session_replication_role = origin;

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, regimen_pension)
values ('00000000-0000-0000-0000-0000000003a2', 'MixFlujo', 'Lab',
        '00000000-0000-0000-0000-0000000003a0', 'x', '2024-01-01', 'taller_produccion', 'integra'),
       ('00000000-0000-0000-0000-0000000003a3', 'MixMixta', 'Lab',
        '00000000-0000-0000-0000-0000000003a0', 'x', '2024-01-01', 'taller_produccion', 'integra_mixta');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000003a2', 'colibri', 1500, '2024-01-01'),
       ('00000000-0000-0000-0000-0000000003a3', 'colibri', 1500, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values ('00000000-0000-0000-0000-0000000003a2', '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39),
       ('00000000-0000-0000-0000-0000000003a3', '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39);

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000ffb01', true);

-- Los mismos dos días para las dos. Sin base trabajada la tasa daría igual y la
-- prueba no probaría nada.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p, '00000000-0000-0000-0000-0000000003a0', t::tipo_marca, ts
from (values
  ('00000000-0000-0000-0000-0000000003a2'::uuid, 'entrada'::text,      '2026-03-03T09:00:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-0000000003a2', 'salida_final', '2026-03-03T15:30:00-05:00'),
  ('00000000-0000-0000-0000-0000000003a2', 'entrada',      '2026-03-04T09:00:00-05:00'),
  ('00000000-0000-0000-0000-0000000003a2', 'salida_final', '2026-03-04T15:30:00-05:00'),
  ('00000000-0000-0000-0000-0000000003a3', 'entrada',      '2026-03-03T09:00:00-05:00'),
  ('00000000-0000-0000-0000-0000000003a3', 'salida_final', '2026-03-03T15:30:00-05:00'),
  ('00000000-0000-0000-0000-0000000003a3', 'entrada',      '2026-03-04T09:00:00-05:00'),
  ('00000000-0000-0000-0000-0000000003a3', 'salida_final', '2026-03-04T15:30:00-05:00')
) as v(p, t, ts);

create temp view pg_temp_planilla as
select f->>'persona_id'                as persona_id,
       (f->>'tasa_afp')::numeric       as tasa,
       (f->>'descuento_afp')::numeric  as descuento,
       (f->>'total')::numeric          as total
from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-31')->'filas') f;

select is(
  (select round(tasa, 5) from pg_temp_planilla
    where persona_id = '00000000-0000-0000-0000-0000000003a3'),
  0.11370,
  'la planilla le aplica 11.37 % a quien está en comisión mixta'
);

-- ── AQUÍ ESTABA EL DEFECTO ──────────────────────────────────────────────────
-- Antes de la 0328 las dos filas daban 12.92 %: la de mixta pagaba la comisión
-- de 1.55 % que su AFP no le cobra.
select is(
  (select round(f.descuento - m.descuento, 2)
     from pg_temp_planilla f, pg_temp_planilla m
    where f.persona_id = '00000000-0000-0000-0000-0000000003a2'
      and m.persona_id = '00000000-0000-0000-0000-0000000003a3'),
  round((select descuento / tasa from pg_temp_planilla
          where persona_id = '00000000-0000-0000-0000-0000000003a2') * 0.01550, 2),
  'la diferencia entre las dos es EXACTAMENTE la comisión sobre flujo de Integra'
);

-- Y esa diferencia va al bolsillo de la persona, que es de lo que se trata.
select cmp_ok(
  (select total from pg_temp_planilla where persona_id = '00000000-0000-0000-0000-0000000003a3'),
  '>',
  (select total from pg_temp_planilla where persona_id = '00000000-0000-0000-0000-0000000003a2'),
  'quien está en mixta se lleva a casa más que quien está en flujo'
);


-- ════════════════════════════════════════════════════════════════════════════
-- 4 · El modo de fallo silencioso: una vigencia que empieza tarde
-- ════════════════════════════════════════════════════════════════════════════
-- Si la fila de mixta empezara después que la de flujo, asignarle mixta a
-- alguien desde una fecha intermedia no encontraría tasa, caería al interruptor
-- global `configuracion.tasa_afp` —que vale 0 desde la 0115— y esa persona
-- dejaría de aportar del todo. Un descuento que desaparece se ve exactamente
-- igual que un descuento correcto en una boleta que nadie mira con lupa.
select cmp_ok(
  (select min(vigente_desde) from tasas_pension where regimen like '%\_mixta'),
  '<=',
  (select min(vigente_desde) from tasas_pension
    where regimen in ('integra','prima','profuturo','habitat')),
  'la vigencia de mixta cubre desde tan atrás como la de flujo'
);

-- Y la puerta por la que se asigna: si el CHECK del historial no se hubiera
-- ensanchado, esto reventaría al insertar el tramo —no al validar—, y el error
-- saldría en la pantalla de Datos personales sin decir por qué.
select lives_ok(
  $$select fn_cambiar_regimen_pension(
      '00000000-0000-0000-0000-0000000003a2', 'integra_mixta', '2026-09-01',
      'confirmado en AFPnet')$$,
  'se puede pasar a alguien de flujo a mixta por la puerta de siempre'
);

select * from finish();
rollback;
