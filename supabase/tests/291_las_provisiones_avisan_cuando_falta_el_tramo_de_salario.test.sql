-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 291_las_provisiones_avisan_cuando_falta_el_tramo_de_salario.test.sql
-- ============================================================================
-- Cubre la 0365 (hallazgo 23 de la auditoría del 2026-09-03/04). Hasta ella,
-- quien devenga y NO tiene tramo en `asignaciones_salario` salía en Provisiones
-- con S/ 0.00 en todo, igual que quien entró esta semana: los `join lateral`
-- de `base_cruda` son inner, así que los días sin tramo no aportan y la fila
-- sale igual (0274). El contador reservaba de menos sin ninguna señal.
--
-- LAS TRES MITADES, y en este orden:
--   1. quien no tiene tramo SIGUE saliendo (0274) y ahora lo dice:
--      `sin_salario_vigente` y `dias_sin_salario`;
--   2. quien tiene tramo abierto no recibe ningún aviso, y su reserva es
--      EXACTAMENTE la de la fórmula de la casa —salario × horas / (6.5 × días
--      del mes)— por los tres factores: la 0365 avisa, no cambia el número;
--   3. quien tuvo tramo y se le cerró también lo dice, con cuántos días lleva
--      así, y la reserva de los días que SÍ estaban cubiertos no se le mueve;
--   4. el hueco se cuenta hasta donde llega la ventana MÁS ANCHA, y la de
--      vacaciones puede arrancar antes del 01/11 (el aniversario de ingreso):
--      quien hoy tiene tramo pero tuvo un hueco ahí no lleva la bandera y
--      sí lleva los días;
--   5. la pantalla (`authenticated`) puede llamar a la función — la 0338
--      creó la firma `(date, date)` sin volver a conceder `execute`.
--
-- Y la que enseña el defecto sin adornos: TresCerrado marcó veintitrés jornadas
-- de agosto sin tramo y reserva EXACTAMENTE lo mismo que TresConTramo, que no
-- marcó ninguna. Esas jornadas se evaporan en silencio; la bandera es lo único
-- que lo delata.
-- ============================================================================
begin;
select plan(17);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000291000', 'ZZ365', 'Sede de laboratorio', true);

-- La administradora que consulta. `no_trabajador` a propósito: sin eso sería
-- una cuarta persona en planilla sin tramo —el laboratorio la contaría— y la
-- aserción 11 dejaría de decir lo que dice. El permiso sale del rol, no del
-- vínculo (`fn_es_admin_o_lider` solo mira `fn_rol_actual`).
set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-000000291a01', 'TresAdmin', 'Laboratorio',
        '00000000-0000-0000-0000-000000291000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000291a09', '2020-01-01', 'no_trabajador');
set session_replication_role = origin;

-- Tres personas en planilla, por horas, sin hijos. Solo se diferencian en su
-- tramo de salario y en cuándo entraron.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  -- A · entró el 01/08 y nadie le cargó el tramo todavía. El caso del hallazgo.
  ('00000000-0000-0000-0000-000000291001', 'TresSinTramo', 'Laboratorio',
   '00000000-0000-0000-0000-000000291000', 'test-hash', '2026-08-01', 'planilla'),
  -- B · tramo abierto desde su ingreso. La de control.
  ('00000000-0000-0000-0000-000000291002', 'TresConTramo', 'Laboratorio',
   '00000000-0000-0000-0000-000000291000', 'test-hash', '2025-01-01', 'planilla'),
  -- C · tuvo tramo hasta el 28/07 y sigue marcando en agosto sin ninguno.
  ('00000000-0000-0000-0000-000000291003', 'TresCerrado',  'Laboratorio',
   '00000000-0000-0000-0000-000000291000', 'test-hash', '2025-01-01', 'planilla'),
  -- D · entró un 15 de septiembre: su ventana de vacaciones al 28/08/2026 corre
  -- desde el 15/09/2025, ANTES del 01/11 en que arranca la CTS de mayo. Tiene
  -- tramo desde el 01/11/2025 y un hueco del 15/09 al 31/10/2025. Hoy no le
  -- falta tramo —sin bandera— pero esos 47 días sin salario sí restan
  -- vacaciones, y la función tiene que contarlos.
  ('00000000-0000-0000-0000-000000291004', 'TresHueco',    'Laboratorio',
   '00000000-0000-0000-0000-000000291000', 'test-hash', '2020-09-15', 'planilla');

-- POR QUÉ EL TRAMO DE C SE CIERRA EL 28/07 Y NO EL 31/07. Se probó primero con
-- el 31 y la aserción 10 salió roja por S/7,69: `fn_feriado_devengado` valora
-- cada feriado con el sueldo vigente ESE día y lo prorratea por las horas de
-- su bloque de planilla (29→28). El feriado del 29/07 caía DENTRO del tramo
-- —tenía sueldo— y su bloque (29/07→28/08) contenía las jornadas de agosto
-- sin tramo, así que esas horas sí reservaban algo por esa vía. Es una regla
-- de la boleta y de la reserva desde la 0276, no de la 0365, y no se discute
-- acá. Cerrando el tramo justo al final de un bloque, ningún feriado con
-- sueldo mira horas sin sueldo, y C reserva exactamente lo mismo que B.
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta) values
  ('00000000-0000-0000-0000-000000291002', 'colibri', 1300, '2025-01-01', null),
  ('00000000-0000-0000-0000-000000291003', 'colibri', 1300, '2025-01-01', '2026-07-28'),
  ('00000000-0000-0000-0000-000000291004', 'colibri', 1300, '2025-11-01', null);

-- B y C: las mismas jornadas de FEBRERO (un mes sin feriados, para que la
-- fórmula de la aserción 14 sea la de la casa y nada más). 8 h de lunes a sábado.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8, 'cerrada'
from unnest(array['00000000-0000-0000-0000-000000291002'::uuid,
                  '00000000-0000-0000-0000-000000291003'::uuid]) p,
     generate_series('2026-02-02'::date, '2026-02-28'::date, interval '1 day') d
where extract(dow from d) <> 0;

-- A y C: además, agosto entero de jornadas — sin tramo que las valore.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p, d::date, 8, 'cerrada'
from unnest(array['00000000-0000-0000-0000-000000291001'::uuid,
                  '00000000-0000-0000-0000-000000291003'::uuid]) p,
     generate_series('2026-08-03'::date, '2026-08-28'::date, interval '1 day') d
where extract(dow from d) <> 0;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000291a09', true);

create temporary table _j on commit drop as
select fn_provisiones('2026-08-28') as j;

create temporary table _lista on commit drop as
select (e ->> 'persona_id')::uuid                      as persona_id,
       (e ->> 'nombre')                                as nombre,
       (e ->> 'sin_salario_vigente')::boolean          as sin_salario_vigente,
       (e ->> 'dias_sin_salario')::int                 as dias_sin_salario,
       (e ->> 'gran_total')::numeric                   as gran_total,
       (e ->> 'tasa_be')::numeric                      as tasa_be
from _j, jsonb_array_elements(_j.j -> 'personas') e;

-- ── 1 a 4 · A: sin tramo, sigue en la lista y ahora lo dice ─────────────────
select is((select sin_salario_vigente from _lista where nombre like 'TresSinTramo%'), true,
  'SIN TRAMO · quien no tiene ningún tramo de salario lleva la bandera encendida');
-- Del 01/08 al 28/08 inclusive: días de calendario desde su ingreso, no jornadas.
select is((select dias_sin_salario from _lista where nombre like 'TresSinTramo%'),
  ('2026-08-28'::date - '2026-08-01'::date) + 1,
  'SIN TRAMO · y dice cuántos días de calendario lleva así, desde su ingreso');
select is((select count(*)::int from _lista where nombre like 'TresSinTramo%'), 1,
  'SIN TRAMO · sigue apareciendo en la lista (0274): la bandera no la esconde');
select is((select gran_total from _lista where nombre like 'TresSinTramo%'), 0::numeric,
  'SIN TRAMO · su reserva sigue en cero — el número no cambia, solo se explica');

-- ── 5 y 6 · B: tramo abierto, ningún aviso ──────────────────────────────────
select is((select sin_salario_vigente from _lista where nombre like 'TresConTramo%'), false,
  'CON TRAMO · quien tiene tramo abierto no lleva la bandera');
select is((select dias_sin_salario from _lista where nombre like 'TresConTramo%'), 0,
  'CON TRAMO · y sus días sin salario son cero');

-- ── 7 a 10 · C: tramo cerrado el 28/07 ──────────────────────────────────────
select is((select sin_salario_vigente from _lista where nombre like 'TresCerrado%'), true,
  'CERRADO · a quien se le cerró el tramo también se le avisa');
select is((select dias_sin_salario from _lista where nombre like 'TresCerrado%'),
  ('2026-08-28'::date - '2026-07-28'::date),
  'CERRADO · con los días que lleva sin tramo desde que se cerró');
select cmp_ok((select gran_total from _lista where nombre like 'TresCerrado%'), '>', 0::numeric,
  'CERRADO · la reserva de los días que SÍ estaban cubiertos no se le quita');
-- EL DEFECTO, SIN ADORNOS. C marcó veintitrés jornadas de agosto y B ninguna,
-- y reservan lo mismo al céntimo: sin tramo, esas jornadas no existen para la
-- reserva. La 0365 no cambia eso —no inventa un salario—; lo hace visible.
select is((select gran_total from _lista where nombre like 'TresCerrado%'),
          (select gran_total from _lista where nombre like 'TresConTramo%'),
  'CERRADO · sus jornadas de agosto sin tramo no reservan nada: reserva igual que quien no las marcó');

-- ── 11 · El conteo de arriba de la tabla ────────────────────────────────────
-- Cuenta sobre TODA la base, como los conteos de la 211: en CI (reset sin
-- seed) es exacto. Si en el Postgres local compartido sale rojo con la
-- función bien, es que otra persona activa que devenga no tiene tramo.
select is((select (j ->> 'personas_sin_salario')::int from _j), 2,
  'CONTEO · personas_sin_salario cuenta a las dos que llevan la bandera');

-- ── 12 y 13 · D: hueco dentro de la ventana de vacaciones, antes del 01/11 ──
select is((select sin_salario_vigente from _lista where nombre like 'TresHueco%'), false,
  'HUECO · quien hoy tiene tramo no lleva la bandera');
-- Del 15/09 al 31/10/2025 inclusive: el hueco cae dentro de su ventana de
-- vacaciones (desde el aniversario 15/09) y ANTES del 01/11 en que arranca la
-- CTS de mayo. Sin `va.aniv_ini` en el rango, esto daba 0.
select is((select dias_sin_salario from _lista where nombre like 'TresHueco%'),
  ('2025-10-31'::date - '2025-09-15'::date) + 1,
  'HUECO · pero sí cuenta los días sin tramo de su ventana de vacaciones, aunque caigan antes del 01/11');

-- ── 14 y 15 · El cambio está, y es uno solo ─────────────────────────────────
select ok((select prosrc like '%CAMBIO 0365%' from pg_proc where proname = 'fn_provisiones'),
  'MARCADOR · fn_provisiones lleva el CAMBIO 0365');
select is((select count(*)::int from pg_proc where proname = 'fn_provisiones'), 1,
  'UNA SOLA · la firma no cambió, así que no hay una fn_provisiones gemela');

-- ── 16 · La pantalla puede llamarla ─────────────────────────────────────────
-- La 0338 creó `fn_provisiones(date, date)` sin `grant`; con la revocación por
-- defecto (0076/0315) la pantalla recibía «permission denied». Esta prueba
-- corre como `postgres`, así que se pregunta por el privilegio, no se llama.
select ok(has_function_privilege('authenticated', 'public.fn_provisiones(date, date)', 'execute')
          and not has_function_privilege('anon', 'public.fn_provisiones(date, date)', 'execute'),
  'PERMISO · authenticated puede ejecutar fn_provisiones(date, date) y anon no');

-- ── 17 · NO REGRESIÓN: la reserva de B es la fórmula de la casa ─────────────
-- pago por día = horas × salario / (6.5 × días del mes)  (CLAUDE.md, reglas
-- que no se reabren). Febrero cae dentro de las tres ventanas que corren al
-- 28/08 —grati ene-jun, CTS nov-abr, vacaciones desde el aniversario 01/01—
-- así que cada factor se aplica una vez sobre la misma base, y el gran total
-- es la suma de las cuatro columnas YA REDONDEADAS (0273). Los factores se
-- leen del propio jsonb, para que la aserción no dependa de la configuración
-- de esta base. Si la 0365 hubiera movido un céntimo del cálculo, esto se pone
-- rojo y dice en cuánto.
create temporary table _formula on commit drop as
with base as (
  select sum(j.horas_trabajadas * 1300
             / (6.5 * extract(day from (date_trunc('month', j.fecha) + interval '1 month - 1 day'))::numeric)) as b
  from jornadas j where j.persona_id = '00000000-0000-0000-0000-000000291002'
),
f as (
  select (j -> 'factores' ->> 'gratificacion')::numeric        as grati,
         (j -> 'factores' ->> 'cts')::numeric                  as cts,
         (j -> 'factores' ->> 'vacaciones')::numeric           as vac,
         coalesce((j -> 'factores' ->> 'sexto_cts')::numeric, 0) as sexto
  from _j
)
select round(f.grati * base.b, 2)
     + round(f.grati * base.b * l.tasa_be, 2)
     + round(f.cts * (1 + f.sexto) * base.b, 2)
     + round(f.vac * base.b, 2) as esperado
from base, f, _lista l where l.nombre like 'TresConTramo%';

select is((select gran_total from _lista where nombre like 'TresConTramo%'),
          (select esperado from _formula),
  'NO REGRESIÓN · la reserva de quien tiene tramo es exactamente salario × horas / (6.5 × días) por los tres factores');

select * from finish();
rollback;
