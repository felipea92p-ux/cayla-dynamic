-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 248_el_divisor_del_periodo_se_compensa_dentro_del_ano.test.sql
-- ============================================================================
-- LA DIVERGENCIA QUE LA 244 ESQUIVA, VIGILADA.
--
-- La prueba 244 compara la boleta contra la reserva usando el MES CALENDARIO
-- como periodo. No es capricho: el periodo real de CAYLA va del 29 al 28, y ahí
-- las dos funciones usan divisores distintos. Con el periodo real, la 244
-- mediría dos cosas a la vez y no distinguiría cuál se rompió.
--
-- Pero «lo esquivo» no puede ser el final. Esta prueba corre el periodo REAL y
-- fija lo que de verdad importa de esa divergencia: **que se compense dentro
-- del año**.
--
-- ── QUÉ PASA, EN UNA FRASE ─────────────────────────────────────────────────
--
-- Para el mismo 10 de febrero, la boleta dice que ese día vale salario/31 —los
-- días que tiene el periodo 29-ene → 28-feb— y `fn_provisiones` dice
-- salario/28, los días que tiene febrero. Ninguna de las dos es absurda; el
-- problema es solo que no coinciden.
--
-- ── POR QUÉ NO SE ARREGLÓ (medido el 2026-08-26, S/1.950) ──────────────────
--
--     periodo 29-ene → 28-feb   (31 días)   boleta 115,32   reserva 126,55
--     periodo  1-mar → 28-mar   (28 días)   boleta 116,07   reserva 104,83
--     los dos juntos                        boleta 231,39   reserva 231,38
--
-- Febrero no tiene 29, así que el periodo siguiente empieza el 1 de marzo y solo
-- dura 28 días: la boleta divide entre 28 (día caro) y la reserva entre los 31
-- de marzo (día barato). **Es la misma distorsión, al revés.** El resto del año
-- alterna ±S/3,50 —meses de 30 contra meses de 31— y también se cancela.
--
-- Neto de los once periodos: **S/0,01**. Acumulado al depósito del 15/07:
-- +S/3,49; al del 15/12: −S/3,50. Reescribir el divisor significaría tocar tres
-- ramas del corazón del cálculo para mover cero al año, y esa función ha estado
-- en el centro de cinco errores de plata en una semana. Decidido por Felipe el
-- 2026-08-26: no se toca, se vigila.
--
-- Queda un solo sitio donde no alcanza a compensarse: un CESE a mitad de año se
-- lleva la diferencia acumulada de ese momento — hasta unos S/11 de
-- gratificación, ~S/23 contando CTS y vacaciones, y puede ir para cualquiera de
-- los dos lados.
--
-- ── POR QUÉ ONCE PERIODOS Y NO DOCE ────────────────────────────────────────
--
-- El doceavo cruza el 31 de diciembre, y `fn_provisiones` reparte lo devengado
-- en semestres del AÑO CALENDARIO: los días de diciembre caen en un semestre que
-- la consulta del año siguiente no muestra. Sale una diferencia de S/15,73 que
-- parece grave y es del laboratorio — se comprobó moviendo el año entero: el
-- outlier se muda con el periodo que cruza. Los once que caben dentro de un año
-- cubren igual las tres longitudes de mes que causan todo esto.
--
-- ── LOS UUID NO LLEVAN EL NÚMERO DE LA PRUEBA, Y ES A PROPÓSITO ────────────
--
-- Usan el prefijo `ddd`/`dde`. Cuando el hook de numeración obliga a renumerar
-- —pasa a menudo, con varias sesiones tomando números a la vez— lo natural es
-- un `sed` del número viejo al nuevo, y si los UUID lo llevaran dentro se
-- romperían en silencio dejando la prueba sin comprobar nada. Ya pasó una vez
-- en este repo, y esta prueba nació con el número cambiado dos veces.
-- ============================================================================
begin;
select plan(3);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-00000ddd0000', 'ZZDIV', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-00000ddd00ad', 'ZAdmin', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'admin', 'x', '00000000-0000-0000-0000-00000ddd00ff', '2026-01-01');
set session_replication_role = origin;

-- Una persona por periodo, todas idénticas. El sueldo vive SOLO dentro de su
-- periodo: así nadie devenga fuera de él y su reserva mide exactamente esa
-- ventana. Es la misma decisión de laboratorio que la 244 explica, y por lo
-- mismo.
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0001', 'R01', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-01-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0001', 'colibri', 1950, '2026-01-29', '2026-02-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0001', '2026-01-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0001', '2026-01-29', '2026-02-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0001', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-01-29'::timestamp, '2026-02-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0002', 'R02', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-03-01', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0002', 'colibri', 1950, '2026-03-01', '2026-03-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0002', '2026-03-01', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0002', '2026-03-01', '2026-03-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0002', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-03-01'::timestamp, '2026-03-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0003', 'R03', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-03-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0003', 'colibri', 1950, '2026-03-29', '2026-04-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0003', '2026-03-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0003', '2026-03-29', '2026-04-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0003', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-03-29'::timestamp, '2026-04-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0004', 'R04', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-04-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0004', 'colibri', 1950, '2026-04-29', '2026-05-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0004', '2026-04-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0004', '2026-04-29', '2026-05-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0004', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-04-29'::timestamp, '2026-05-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0005', 'R05', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-05-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0005', 'colibri', 1950, '2026-05-29', '2026-06-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0005', '2026-05-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0005', '2026-05-29', '2026-06-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0005', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-05-29'::timestamp, '2026-06-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0006', 'R06', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-06-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0006', 'colibri', 1950, '2026-06-29', '2026-07-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0006', '2026-06-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0006', '2026-06-29', '2026-07-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0006', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-06-29'::timestamp, '2026-07-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0007', 'R07', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-07-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0007', 'colibri', 1950, '2026-07-29', '2026-08-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0007', '2026-07-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0007', '2026-07-29', '2026-08-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0007', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-07-29'::timestamp, '2026-08-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0008', 'R08', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-08-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0008', 'colibri', 1950, '2026-08-29', '2026-09-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0008', '2026-08-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0008', '2026-08-29', '2026-09-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0008', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-08-29'::timestamp, '2026-09-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0009', 'R09', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-09-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0009', 'colibri', 1950, '2026-09-29', '2026-10-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0009', '2026-09-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0009', '2026-09-29', '2026-10-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0009', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-09-29'::timestamp, '2026-10-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0010', 'R10', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-10-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0010', 'colibri', 1950, '2026-10-29', '2026-11-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0010', '2026-10-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0010', '2026-10-29', '2026-11-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0010', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-10-29'::timestamp, '2026-11-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;
insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo)
values ('00000000-0000-0000-0000-00000ddd0011', 'R11', 'Div', '00000000-0000-0000-0000-00000ddd0000', 'x', '2026-11-29', 'planilla');
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
values ('00000000-0000-0000-0000-00000ddd0011', 'colibri', 1950, '2026-11-29', '2026-12-28');
insert into horarios_asignados (persona_id, vigente_desde, hora_entrada, hora_salida, dias_laborables)
values ('00000000-0000-0000-0000-00000ddd0011', '2026-11-29', '09:00', '15:30', array[1,2,3,4,5]);
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
values ('00000000-0000-0000-0000-00000dde0011', '2026-11-29', '2026-12-28', 'abierto');
insert into jornadas (persona_id, fecha, sede_id, horas_trabajadas, estado)
select '00000000-0000-0000-0000-00000ddd0011', d::date, '00000000-0000-0000-0000-00000ddd0000', 6.5, 'cerrada'
from generate_series('2026-11-29'::timestamp, '2026-12-28'::timestamp, interval '1 day') d
where extract(dow from d)::int between 1 and 5;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000ddd00ff', true);

create temporary table t_div (periodo text, boleta numeric, reserva numeric) on commit drop;
insert into t_div
select 'R01  (2026-01-29 -> 2026-02-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-01-29','2026-02-28','00000000-0000-0000-0000-00000dde0001') -> 'filas') e
         where e->>'nombre' = 'R01 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-02-28') -> 'personas') e
         where e->>'nombre' = 'R01 Div');
insert into t_div
select 'R02  (2026-03-01 -> 2026-03-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-03-01','2026-03-28','00000000-0000-0000-0000-00000dde0002') -> 'filas') e
         where e->>'nombre' = 'R02 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-03-28') -> 'personas') e
         where e->>'nombre' = 'R02 Div');
insert into t_div
select 'R03  (2026-03-29 -> 2026-04-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-03-29','2026-04-28','00000000-0000-0000-0000-00000dde0003') -> 'filas') e
         where e->>'nombre' = 'R03 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-04-28') -> 'personas') e
         where e->>'nombre' = 'R03 Div');
insert into t_div
select 'R04  (2026-04-29 -> 2026-05-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-04-29','2026-05-28','00000000-0000-0000-0000-00000dde0004') -> 'filas') e
         where e->>'nombre' = 'R04 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-05-28') -> 'personas') e
         where e->>'nombre' = 'R04 Div');
insert into t_div
select 'R05  (2026-05-29 -> 2026-06-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-05-29','2026-06-28','00000000-0000-0000-0000-00000dde0005') -> 'filas') e
         where e->>'nombre' = 'R05 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-06-28') -> 'personas') e
         where e->>'nombre' = 'R05 Div');
insert into t_div
select 'R06  (2026-06-29 -> 2026-07-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-06-29','2026-07-28','00000000-0000-0000-0000-00000dde0006') -> 'filas') e
         where e->>'nombre' = 'R06 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-07-28') -> 'personas') e
         where e->>'nombre' = 'R06 Div');
insert into t_div
select 'R07  (2026-07-29 -> 2026-08-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-07-29','2026-08-28','00000000-0000-0000-0000-00000dde0007') -> 'filas') e
         where e->>'nombre' = 'R07 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-08-28') -> 'personas') e
         where e->>'nombre' = 'R07 Div');
insert into t_div
select 'R08  (2026-08-29 -> 2026-09-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-08-29','2026-09-28','00000000-0000-0000-0000-00000dde0008') -> 'filas') e
         where e->>'nombre' = 'R08 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-09-28') -> 'personas') e
         where e->>'nombre' = 'R08 Div');
insert into t_div
select 'R09  (2026-09-29 -> 2026-10-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-09-29','2026-10-28','00000000-0000-0000-0000-00000dde0009') -> 'filas') e
         where e->>'nombre' = 'R09 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-10-28') -> 'personas') e
         where e->>'nombre' = 'R09 Div');
insert into t_div
select 'R10  (2026-10-29 -> 2026-11-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-10-29','2026-11-28','00000000-0000-0000-0000-00000dde0010') -> 'filas') e
         where e->>'nombre' = 'R10 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-11-28') -> 'personas') e
         where e->>'nombre' = 'R10 Div');
insert into t_div
select 'R11  (2026-11-29 -> 2026-12-28)',
       (select (e->>'provision_gratificacion')::numeric
          from jsonb_array_elements(fn_planilla_calcular('2026-11-29','2026-12-28','00000000-0000-0000-0000-00000dde0011') -> 'filas') e
         where e->>'nombre' = 'R11 Div'),
       (select (e->>'grati_s1')::numeric + (e->>'grati_s2')::numeric
          from jsonb_array_elements(fn_provisiones('2026-12-28') -> 'personas') e
         where e->>'nombre' = 'R11 Div');
-- ── 1 · Los once periodos se midieron ──────────────────────────────────────
-- Guard obligatorio: las dos de abajo miran sumas, y una suma sobre una tabla
-- vacía da 0 o null y podría pasar sin haber comprobado nada.
select is(
  (select count(*)::int from t_div where boleta is not null and reserva is not null), 11,
  'los once periodos reales 29-28 se construyeron y se midieron en los dos lados'
);

-- ── 2 · LA IMPORTANTE: el año cierra en cero ───────────────────────────────
-- Cinco céntimos de margen para el redondeo. Medido el 2026-08-26: S/0,01.
select cmp_ok(
  (select abs(sum(reserva) - sum(boleta)) from t_div),
  '<',
  0.05::numeric,
  'el divisor se compensa: sumado el ano, la reserva y la boleta dicen lo mismo'
);

-- ── 3 · Y no cierra en cero porque no pase nada ────────────────────────────
-- La comprobación 2 pasaría igual si alguien igualara los divisores, y también
-- si el laboratorio se quedara sin contenido. Ésta fija que la divergencia
-- MENSUAL sigue ahí, que es lo que se decidió no arreglar: si algún día
-- desaparece, esta prueba se pone roja para que quien lo hizo actualice la
-- cabecera en vez de dejarla mintiendo.
select cmp_ok(
  (select max(abs(reserva - boleta)) from t_div),
  '>',
  1::numeric,
  'y sigue habiendo periodos sueltos que divergen: lo que se compensa es el ano, no el mes'
);

select * from finish();
rollback;
