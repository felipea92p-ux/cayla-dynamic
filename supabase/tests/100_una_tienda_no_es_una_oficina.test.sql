-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 100_una_tienda_no_es_una_oficina.test.sql
-- ============================================================================
-- El resumen de costos ponía a Central al lado de una tienda como si fueran
-- comparables. Central no vende: administra. Leído así, el cuadro dice que hay
-- que recortar donde no se recorta.
--
-- Y aunque las dos fueran tiendas, compararlas por el TOTAL tampoco sirve: una
-- sede con 9 personas siempre va a costar más que una con 4. Lo que se compara
-- es el costo por persona y por hora.
--
-- Estas pruebas fijan las tres cosas: que el tipo existe y no se puede inventar
-- uno, que guardar el nombre de una sede no le borra el tipo, y que las cifras
-- comparables se calculan sobre personas distintas y no sobre filas.
-- ============================================================================
begin;
select plan(9);

insert into sedes (id, codigo, nombre, activa, tipo) values
  ('00000000-0000-0000-0000-00000000ba01'::uuid, 'ZZOFI', 'Oficina de laboratorio', true, 'central'),
  ('00000000-0000-0000-0000-00000000ba02'::uuid, 'ZZTDA', 'Tienda de laboratorio',  true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000000ba03'::uuid, 'TipoAdmin', 'Lab', '00000000-0000-0000-0000-00000000ba01'::uuid, 'admin', 'x', '00000000-0000-0000-0000-00000000ba0a'::uuid, '2024-01-01');
set session_replication_role = origin;

-- Dos personas en la MISMA tienda: el total de la tienda será el doble, pero el
-- costo por persona tiene que seguir siendo comparable con el de la oficina.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, funcion) values
  ('00000000-0000-0000-0000-00000000ba04'::uuid, 'TipoVende', 'Uno', '00000000-0000-0000-0000-00000000ba02'::uuid, 'x', '2024-01-01', 'calidad_servicio'),
  ('00000000-0000-0000-0000-00000000ba05'::uuid, 'TipoVende', 'Dos', '00000000-0000-0000-0000-00000000ba02'::uuid, 'x', '2024-01-01', 'calidad_servicio');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde) values
  ('00000000-0000-0000-0000-00000000ba04'::uuid, 'colibri', 1950, '2024-01-01'),
  ('00000000-0000-0000-0000-00000000ba05'::uuid, 'colibri', 1950, '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, hora_entrada, hora_salida, almuerzo_min_minutos,
   almuerzo_max_minutos, dias_laborables, horas_semana_objetivo, horario_por_dia)
select p, '2024-01-01', '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39,
       '{"1":{"e":"09:00","s":"15:30","r":0},"2":{"e":"09:00","s":"15:30","r":0},
         "3":{"e":"09:00","s":"15:30","r":0},"4":{"e":"09:00","s":"15:30","r":0},
         "5":{"e":"09:00","s":"15:30","r":0},"6":{"e":"09:00","s":"15:30","r":0}}'::jsonb
from unnest(array['00000000-0000-0000-0000-00000000ba04'::uuid,
                  '00000000-0000-0000-0000-00000000ba05'::uuid]) p;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ba0a', true);

-- Las dos trabajan lo mismo: dos días de 6.5 h cada una.
insert into marcajes (client_uuid, persona_id, sede_id, tipo, timestamp_marca)
select gen_random_uuid(), p, '00000000-0000-0000-0000-00000000ba02'::uuid, t, ts
from (values
  ('00000000-0000-0000-0000-00000000ba04'::uuid, 'entrada'::tipo_marca, '2026-01-05T09:00:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000ba04'::uuid, 'salida_final',       '2026-01-05T15:30:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000ba04'::uuid, 'entrada',            '2026-01-06T09:00:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000ba04'::uuid, 'salida_final',       '2026-01-06T15:30:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000ba05'::uuid, 'entrada',            '2026-01-05T09:00:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000ba05'::uuid, 'salida_final',       '2026-01-05T15:30:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000ba05'::uuid, 'entrada',            '2026-01-06T09:00:00-05:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000ba05'::uuid, 'salida_final',       '2026-01-06T15:30:00-05:00'::timestamptz)
) as v(p, t, ts);

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('99999999-0000-0000-0000-000000000099', '2026-01-01', '2026-01-31', 'abierto');
select fn_periodo_pagado('99999999-0000-0000-0000-000000000099', true);

-- ── El tipo existe, y no se puede inventar uno ──────────────────────────────
select is((select tipo from sedes where codigo = 'ZZOFI'),
          'central', 'TIPO · una sede puede declararse como oficina central');

select throws_ok($$ select fn_guardar_sede('ZZTDA', 'Tienda de laboratorio', 'almacen') $$,
                 null, null, 'TIPO · un tipo inventado se rechaza: solo central, taller o tienda');

-- Guardar solo el nombre NO puede borrar el tipo: es el error clásico de un
-- formulario que manda todos los campos y pisa los que no muestra.
select fn_guardar_sede('ZZOFI', 'Oficina renombrada');
select is((select tipo from sedes where codigo = 'ZZOFI'),
          'central', 'TIPO · renombrar una sede no le borra el tipo sin querer');
select is((select nombre from sedes where codigo = 'ZZOFI'),
          'Oficina renombrada', 'TIPO · y el nombre sí se guardó');

-- ── Las cifras que sí permiten comparar ─────────────────────────────────────
select is((select (x->>'tipo') from jsonb_array_elements(
             fn_costos_planilla('2026-01-01','2026-01-31')->'por_sede') x
           where x->>'sede' = 'ZZTDA'),
          'tienda', 'COMPARAR · cada sede llega con su tipo, no suelta');

-- Dos personas idénticas: el total es el doble, el costo por persona es la mitad
-- del total. Si se calculara sobre FILAS y no sobre personas distintas, alguien
-- que cobró en tres periodos contaría como tres y el promedio saldría bajo.
select is((select round((x->>'costo')::numeric / 2, 2) from jsonb_array_elements(
             fn_costos_planilla('2026-01-01','2026-01-31')->'por_sede') x
           where x->>'sede' = 'ZZTDA'),
          (select (x->>'costo_por_persona')::numeric from jsonb_array_elements(
             fn_costos_planilla('2026-01-01','2026-01-31')->'por_sede') x
           where x->>'sede' = 'ZZTDA'),
          'COMPARAR · el costo por persona se calcula sobre personas distintas, no sobre filas');

select cmp_ok((select (x->>'costo_por_hora')::numeric from jsonb_array_elements(
                 fn_costos_planilla('2026-01-01','2026-01-31')->'por_sede') x
               where x->>'sede' = 'ZZTDA'),
              '>', 0::numeric, 'COMPARAR · y el costo por hora sale de las horas realmente trabajadas');

-- ── Operar tiendas vs. administrar ──────────────────────────────────────────
select is((select (x->>'personas')::int from jsonb_array_elements(
             fn_costos_planilla('2026-01-01','2026-01-31')->'por_tipo') x
           where x->>'tipo' = 'tienda'),
          2, 'TIPO · el corte por tipo junta las dos personas de tienda');

-- Una sede sin nadie que haya cobrado no aparece: no cuesta nada este periodo.
select is((select count(*)::int from jsonb_array_elements(
             fn_costos_planilla('2026-01-01','2026-01-31')->'por_tipo') x
           where x->>'tipo' = 'taller'),
          0, 'TIPO · un tipo sin nadie que haya cobrado no inventa una fila en cero');

select * from finish();
rollback;
