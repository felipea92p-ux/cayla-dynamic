-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- ============================================================================
-- 189_la_foto_cuadra_con_la_retencion_de_cuarta.test.sql
-- ============================================================================
-- QUÉ DEFIENDE, Y POR QUÉ EXISTE ESTE ARCHIVO
--
--   Es la TERCERA vez que pasa lo mismo: se le suma o resta un término al total
--   de la planilla y el candado de la foto del pago no se entera. La 0127 con la
--   movilidad, la educación y la pensión; la 0201 con el sobretiempo; la 0248
--   con la retención de cuarta.
--
--   El fallo no se nota al escribirlo. Se nota el día del cierre, cuando
--   «Marcar como PAGADO» aborta —para TODO el periodo, porque
--   `fn_planilla_congelar` inserta las ~30 filas en una sola sentencia— y el mes
--   no se puede cerrar. Es el peor momento posible para descubrirlo.
--
--   La aserción 4 es la que de verdad importa: **no vigila la retención, vigila
--   el patrón.** Compara los términos del CHECK contra las columnas de la tabla
--   y falla si aparece una columna `monto_*` que el candado no conoce. Así, la
--   cuarta vez que alguien añada un concepto, la prueba se pone roja al hacer
--   `db reset` y no el 28 a las ocho de la noche.
--
-- LAS DOS MITADES
--   Se prueba que la fila CON retención entra (2) y que la fila SIN retención
--   sigue cuadrando igual (3). Sin la 3, un candado que aceptara cualquier cosa
--   pasaría igual de verde — y un candado que no cierra nunca es peor que
--   ninguno, porque da la sensación de que algo vigila.
--
-- NOTA DE ENTORNO
--   `session_replication_role = replica` salta las claves foráneas contra
--   auth.users. Los CHECK NO son triggers, así que siguen aplicando: es justo lo
--   que hace falta medir aquí.
-- ============================================================================
begin;
select plan(4);

set local session_replication_role = replica;

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000189000', 'ZZ189', 'Sede de laboratorio 189', true);

insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, fecha_ingreso, estado)
values ('00000000-0000-0000-0000-0000001890a1', 'Lucho', 'Locador',
        '00000000-0000-0000-0000-000000189000', 'integrante', 'h', '2026-01-05', 'activo');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-000000189099', '2026-07-29', '2026-08-28', 'abierto');

-- ── 1 · La foto tiene dónde guardar la retención ────────────────────────────
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'planilla_pagada_detalle'
      and column_name = 'retencion_4ta'),
  1,
  'la foto del pago tiene columna para la retención de cuarta');

-- ── 2 · Y una fila CON retención se puede congelar ──────────────────────────
-- Es el caso que hoy revienta: S/80 retenidos sobre S/1,000 dejan el total en
-- 920, y el candado viejo exigía 1000.
select lives_ok($$
  insert into planilla_pagada_detalle
    (periodo_id, persona_id, version, origen, nombre, sede_codigo,
     pago_base, monto_feriados, monto_plus, asignacion_familiar, monto_movilidad,
     monto_educacion, descuento_pension, monto_sobretiempo, bonos, descuentos, total, fila)
  values ('00000000-0000-0000-0000-000000189099','00000000-0000-0000-0000-0000001890a1',
          1, 'pago', 'Lucho Locador', 'ZZ189',
          1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 920,
          '{"retencion_4ta": 80}'::jsonb)
$$, 'una foto con retención de cuarta se congela — el cierre del mes no se atasca');

-- ── 3 · La otra mitad: sin retención, el candado sigue exigiendo que cuadre ──
select throws_ok($$
  insert into planilla_pagada_detalle
    (periodo_id, persona_id, version, origen, nombre, sede_codigo,
     pago_base, monto_feriados, monto_plus, asignacion_familiar, monto_movilidad,
     monto_educacion, descuento_pension, monto_sobretiempo, bonos, descuentos, total, fila)
  values ('00000000-0000-0000-0000-000000189099','00000000-0000-0000-0000-0000001890a1',
          2, 'pago', 'Lucho Locador', 'ZZ189',
          1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 920,
          '{}'::jsonb)
$$, 23514, null,
  'sin retención, un total que no cuadra sigue rebotando — el candado no se volvió un adorno');

-- ── 4 · EL GUARDIÁN DEL PATRÓN, que es a lo que vino este archivo ───────────
-- No mira la retención: mira que NINGUNA columna de importe de la foto se quede
-- fuera del candado. Si alguien añade `monto_loquesea` a la tabla y no la mete
-- en chk_foto_cuadra, esto se pone rojo en el `db reset` — meses antes de que el
-- cierre reviente un 28 por la noche.
select is(
  (select coalesce(string_agg(c.column_name, ', ' order by c.column_name), '')
     from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'planilla_pagada_detalle'
      and c.column_name like 'monto\_%'
      and position(c.column_name in
            (select pg_get_constraintdef(oid) from pg_constraint
              where conname = 'chk_foto_cuadra'
                and conrelid = 'public.planilla_pagada_detalle'::regclass)) = 0),
  '',
  'ninguna columna monto_* de la foto se quedó fuera de chk_foto_cuadra — va por la tercera vez');

select * from finish();
rollback;
