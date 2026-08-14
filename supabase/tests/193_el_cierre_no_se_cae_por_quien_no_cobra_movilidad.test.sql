-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 193_el_cierre_no_se_cae_por_quien_no_cobra_movilidad.test.sql
-- ============================================================================
-- `monto_movilidad` —el concepto que imprime la boleta— filtra por
-- `cobra_movilidad` desde la 0166. El `total` no lo hacía: pagaba una movilidad
-- que la boleta imprimía en S/0.00. `chk_foto_cuadra` rechazaba esa fila, y como
-- `fn_planilla_congelar` inserta las ~30 del periodo en UNA sola sentencia, no
-- se congelaba NINGUNA: el cierre del mes se caía entero por una persona.
--
-- Esto fija las tres mitades: que el total ya no la paga, que a quien sí la
-- cobra no se le mueve un céntimo, y —lo que de verdad importaba— que el
-- periodo se puede cerrar.
-- ============================================================================
begin;
select plan(6);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-0000000003a1', 'ZZMOV', 'Sede de laboratorio', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000003a2', 'MovAdmin', 'Lab',
        '00000000-0000-0000-0000-0000000003a1', 'admin', 'x',
        '00000000-0000-0000-0000-0000000003ff', '2024-01-01');
set session_replication_role = origin;

-- Quien viaja entre sedes y se cubre por viáticos: no devenga movilidad.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion,
                      tipo_vinculo, cobra_movilidad, movilidad_motivo)
values ('00000000-0000-0000-0000-0000000003a3', 'MovExcluida', 'Lab',
        '00000000-0000-0000-0000-0000000003a1', 'x', '2024-01-01', 'taller_produccion',
        'planilla', false, 'Viaja entre sedes — se cubre por viáticos');

-- Y quien sí la devenga, para comprobar que no se le toca nada.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion, tipo_vinculo)
values ('00000000-0000-0000-0000-0000000003a4', 'MovNormal', 'Lab',
        '00000000-0000-0000-0000-0000000003a1', 'x', '2024-01-01', 'taller_produccion', 'planilla');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-0000000003a3', 'colibri', 1950, '2024-01-01'),
       ('00000000-0000-0000-0000-0000000003a4', 'colibri', 1950, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select id, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39,
       '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
         "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
         "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb
from personas where id in ('00000000-0000-0000-0000-0000000003a3',
                           '00000000-0000-0000-0000-0000000003a4');

-- Una tarifa VIVA para esa sede. Sin ella no hay nada que descuadrar y la
-- prueba pasaría por la razón equivocada.
insert into parametros_laborales (clave, valor, vigente_desde, sede_codigo, sustento)
values ('movilidad_diaria', 8.00, '2024-01-01', 'ZZMOV', 'pasaje de laboratorio');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000003ff', true);

-- Dos días trabajados cada una.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p.id, '00000000-0000-0000-0000-0000000003a1', m.tipo, m.ts
from personas p,
     (values ('entrada'::tipo_marca,      timestamptz '2026-05-04T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-05-04T15:30:00-05:00'),
             ('entrada'::tipo_marca,      timestamptz '2026-05-05T09:00:00-05:00'),
             ('salida_final'::tipo_marca, timestamptz '2026-05-05T15:30:00-05:00')) m(tipo, ts)
where p.id in ('00000000-0000-0000-0000-0000000003a3', '00000000-0000-0000-0000-0000000003a4');

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('eeeeeeee-0000-0000-0000-0000000003e1', '2026-05-01', '2026-05-31', 'abierto');

create or replace function pg_temp.fila(p_nombre text) returns jsonb
language sql as $f$
  select x from jsonb_array_elements(fn_planilla_calcular('2026-05-01','2026-05-31') -> 'filas') x
  where x->>'nombre' = p_nombre;
$f$;

-- La suma que exige chk_foto_cuadra, calculada igual que la restricción.
create or replace function pg_temp.suma(p_nombre text) returns numeric
language sql as $f$
  select round((x->>'pago_base')::numeric, 2)
       + round(coalesce((x->>'monto_feriados')::numeric, 0), 2)
       + round(coalesce((x->>'monto_plus')::numeric, 0), 2)
       + round(coalesce((x->>'asignacion_familiar')::numeric, 0), 2)
       + round(coalesce((x->>'monto_movilidad')::numeric, 0), 2)
       + round(coalesce((x->>'monto_educacion')::numeric, 0), 2)
       - round(coalesce((x->>'descuento_pension')::numeric, 0), 2)
       + round(coalesce((x->>'monto_sobretiempo')::numeric, 0), 2)
       + round(coalesce((x->>'bonos')::numeric, 0), 2)
       - round(coalesce((x->>'descuentos')::numeric, 0), 2)
       - round(coalesce((x->>'retencion_4ta')::numeric, 0), 2)
  from (select pg_temp.fila(p_nombre) as x) t;
$f$;

-- 1 · La boleta sigue diciendo que no la devenga. Esto ya era así (0166) y
--     tiene que seguir siéndolo: si cambia, el arreglo fue por el lado malo.
select is(
  (pg_temp.fila('MovExcluida Lab')->>'monto_movilidad')::numeric, 0.00::numeric,
  'quien no cobra movilidad la sigue viendo en 0.00 en su boleta');

-- 2 · Y ahora el total tampoco la paga. Era el descuadre de 16.00 (2 x S/8).
select is(
  (pg_temp.fila('MovExcluida Lab')->>'total')::numeric - pg_temp.suma('MovExcluida Lab'),
  0.00::numeric,
  'el total de quien no cobra movilidad cuadra con sus lineas');

-- 3 y 4 · A quien sí la cobra no se le mueve nada.
select is(
  (pg_temp.fila('MovNormal Lab')->>'monto_movilidad')::numeric, 16.00::numeric,
  'quien sí cobra movilidad sigue devengando sus 2 dias x S/8');

select is(
  (pg_temp.fila('MovNormal Lab')->>'total')::numeric - pg_temp.suma('MovNormal Lab'),
  0.00::numeric,
  'y su total sigue cuadrando, como siempre cuadró');

-- 5 · LO QUE DE VERDAD IMPORTABA: el periodo se puede cerrar. Antes esto
--     lanzaba «violates check constraint "chk_foto_cuadra"» y no congelaba
--     NINGUNA de las filas, ni siquiera las que estaban bien.
select lives_ok(
  $$select fn_planilla_congelar('eeeeeeee-0000-0000-0000-0000000003e1', 'pago',
                                '00000000-0000-0000-0000-0000000003a2')$$,
  'el periodo se congela con una persona que no cobra movilidad dentro');

-- 6 · Y congeló a las dos, no solo a la que no daba problemas.
select is(
  (select count(*)::int from planilla_pagada_detalle
    where periodo_id = 'eeeeeeee-0000-0000-0000-0000000003e1'
      and nombre in ('MovExcluida Lab', 'MovNormal Lab')),
  2,
  'las dos filas quedaron congeladas');

select * from finish();
rollback;
