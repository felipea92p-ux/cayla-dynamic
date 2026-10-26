-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 399_el_feriado_posterior_al_cese_no_corresponde.test.sql — 0505
-- ============================================================================
-- El caso real, del 2026-10-02: periodo 29-sep → 28-oct con un solo feriado
-- (8-oct). Dos personas cesaron antes —una practicante y una integrante en
-- planilla— y la planilla las acusaba con «1 feriado(s) sin salario ese día: no
-- se pudo calcular». La baja les había cerrado el salario el día del cese, como
-- debe; el cálculo de feriados no miraba el cese y leía eso como dato faltante.
--
-- Acá se monta lo mismo un mes cualquiera del pasado (para que la prueba no
-- dependa de la fecha en que corra): periodo 29-may → 28-jun, un feriado de
-- laboratorio el 10-jun, y seis personas que solo se distinguen por cuándo
-- cesan. La baja y el salario reabierto se hacen con las funciones REALES
-- (`fn_cesar_persona`, `fn_set_salario`), no a mano: el agujero que cierra la
-- 0505 es justamente el camino Equipo → «Asignar salario» sobre alguien que ya
-- se fue, y un atajo no lo reproduciría.
--
-- Corrida contra la 0397 (sin la 0505), caen 9 de las 15 —1, 2, 4, 5, 6, 7, 12,
-- 13 y 14—. Las otras seis pasan en las dos versiones a propósito: vigilan que
-- la 0505 no le quite el feriado a quien sí le toca (8, 9, 10), que el aviso
-- siga saltando cuando de verdad falta el salario (11), que el monto ya era
-- cero con el tramo cerrado (3) y que el núcleo siga cerrado al navegador (15).
-- ============================================================================
begin;
select plan(15);

insert into sedes (id, codigo, nombre, activa)
values ('00000000-0000-0000-0000-000000399000', 'ZZ399', 'Sede de laboratorio 399', true);

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-000000399099', 'Admin399', 'Laboratorio',
        '00000000-0000-0000-0000-000000399000', 'admin', 'test-hash',
        '00000000-0000-0000-0000-000000399098', '2020-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000399098', true);

-- Un solo feriado en el periodo, puesto a mano: los reales de esa ventana
-- (7-jun) serían ruido.
delete from feriados where fecha between '2026-05-29' and '2026-06-28';
insert into feriados (fecha, nombre) values ('2026-06-10', 'Feriado de laboratorio 399');

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso, tipo_vinculo) values
  ('00000000-0000-0000-0000-000000399001', 'CesaAntes',     'Junio', '00000000-0000-0000-0000-000000399000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000399002', 'Reabierta',     'Junio', '00000000-0000-0000-0000-000000399000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000399003', 'CesaDespues',   'Junio', '00000000-0000-0000-0000-000000399000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000399004', 'CesaElFeriado', 'Junio', '00000000-0000-0000-0000-000000399000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000399005', 'HuecoReal',     'Junio', '00000000-0000-0000-0000-000000399000', 'test-hash', '2024-01-02', 'planilla'),
  ('00000000-0000-0000-0000-000000399006', 'Practicante',   'Junio', '00000000-0000-0000-0000-000000399000', 'test-hash', '2024-01-02', 'practicante');

insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde, vigente_hasta)
select id, 'cayla', 1500.00, '2024-01-02',
       -- HuecoReal: activa, sin cese, y sin salario del 6 al 14 de junio. Es el
       -- caso que el aviso «sin salario» existe para cazar.
       case when id = '00000000-0000-0000-0000-000000399005' then date '2026-06-05' end
from personas
where sede_base_id = '00000000-0000-0000-0000-000000399000'
  and id <> '00000000-0000-0000-0000-000000399099';
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('00000000-0000-0000-0000-000000399005', 'cayla', 1500.00, '2026-06-15');

-- Todas trabajan desde el 29-may hasta su último día; HuecoReal, el mes entero.
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select p.id, d::date, 6.5, 'cerrada'
from (values ('00000000-0000-0000-0000-000000399001'::uuid, date '2026-06-05'),
             ('00000000-0000-0000-0000-000000399002'::uuid, date '2026-06-05'),
             ('00000000-0000-0000-0000-000000399003'::uuid, date '2026-06-12'),
             ('00000000-0000-0000-0000-000000399004'::uuid, date '2026-06-09'),
             ('00000000-0000-0000-0000-000000399005'::uuid, date '2026-06-28'),
             ('00000000-0000-0000-0000-000000399006'::uuid, date '2026-06-05')) p(id, hasta)
cross join lateral generate_series(date '2026-05-29', p.hasta, interval '1 day') d
where d::date <> date '2026-06-10';

-- La baja, por el botón: cierra el salario el día del cese (0415).
select fn_cesar_persona('00000000-0000-0000-0000-000000399001', '2026-06-05', 'renuncia');
select fn_cesar_persona('00000000-0000-0000-0000-000000399002', '2026-06-05', 'renuncia');
select fn_cesar_persona('00000000-0000-0000-0000-000000399003', '2026-06-12', 'renuncia');
select fn_cesar_persona('00000000-0000-0000-0000-000000399004', '2026-06-10', 'renuncia');
select fn_cesar_persona('00000000-0000-0000-0000-000000399006', '2026-06-05', 'fin_convenio_practicas');

-- Y a Reabierta alguien le sigue el enlace «Equipo →» del aviso y le asigna
-- salario otra vez, con la fecha que la pantalla propone. `fn_set_salario` no
-- mira el cese: le abre un tramo sin fin a quien ya se fue.
select fn_set_salario('00000000-0000-0000-0000-000000399002', 'cayla', 1500.00, '2026-06-06', 'prueba 399: el camino del aviso');

create temp table _fer as
select p.nombres,
       fn_feriado_devengado_nucleo(p.id, '2026-05-29', '2026-06-28', 31) as j
from personas p
where p.sede_base_id = '00000000-0000-0000-0000-000000399000'
  and p.id <> '00000000-0000-0000-0000-000000399099';


-- ── 1 · QUIEN CESÓ ANTES DEL FERIADO: NO CORRESPONDE, Y NO SE ACUSA ─────────
select is((select (j->>'sin_tramo')::int from _fer where nombres = 'CesaAntes'), 0,
  'CESA ANTES · el feriado posterior al cese ya no cuenta como «sin salario»');

select is((select (j->>'no_corresponde')::int from _fer where nombres = 'CesaAntes'), 1,
  'CESA ANTES · cuenta como «no corresponde», igual que uno anterior al ingreso');

select is((select (j->>'monto')::numeric from _fer where nombres = 'CesaAntes'), 0::numeric,
  'CESA ANTES · y paga S/0 (ya lo hacía: el tramo estaba cerrado)');

select is((select (j->'detalle'->0->>'despues_cese')::boolean from _fer where nombres = 'CesaAntes'), true,
  'CESA ANTES · el detalle dice POR QUÉ: despues_cese, para que la pantalla lo explique');

select is((select (j->'detalle'->0->>'proporcional_horas')::numeric from _fer where nombres = 'CesaAntes'), 0::numeric,
  'CESA ANTES · y no le muestra horas proporcionales de un día que no le toca');


-- ── 2 · EL AGUJERO: LE REABREN EL SALARIO DESDE EQUIPO ──────────────────────
-- Con la 0397 esto pagaba el feriado a quien ya se fue, y el aviso desaparecía
-- justo en el momento en que el error empezaba.
select is((select (j->>'monto')::numeric from _fer where nombres = 'Reabierta'), 0::numeric,
  'REABIERTA · aunque le reabran el salario, el feriado posterior al cese paga S/0');

select is((select (j->>'no_corresponde')::int from _fer where nombres = 'Reabierta'), 1,
  'REABIERTA · y sigue diciendo «no corresponde», no un pago');


-- ── 3 · A QUIEN SÍ LE TOCA, SE LE SIGUE PAGANDO ────────────────────────────
select cmp_ok((select (j->>'monto')::numeric from _fer where nombres = 'CesaDespues'), '>', 0::numeric,
  'CESA DESPUÉS · si el feriado cae antes de su cese, se paga como siempre');

select is((select (j->>'no_corresponde')::int from _fer where nombres = 'CesaDespues'), 0,
  'CESA DESPUÉS · y no se marca como «no corresponde»');

select cmp_ok((select (j->>'monto')::numeric from _fer where nombres = 'CesaElFeriado'), '>', 0::numeric,
  'BORDE · el día del cese cuenta como vinculada: el feriado ese mismo día se paga');


-- ── 4 · EL AVISO SIGUE SALTANDO CUANDO DE VERDAD FALTA EL SALARIO ──────────
select is((select (j->>'sin_tramo')::int from _fer where nombres = 'HuecoReal'), 1,
  'HUECO REAL · a quien sigue activa y no tiene salario ese día, el aviso le sigue saltando');


-- ── 5 · EL CASO DE LA CAPTURA: LA PRACTICANTE ──────────────────────────────
select is((select (j->>'sin_tramo')::int from _fer where nombres = 'Practicante'), 0,
  'PRACTICANTE · la que cesó antes del feriado ya no sale con el aviso');


-- ── 6 · LO QUE LEE LA PANTALLA DE PLANILLA ─────────────────────────────────
-- El aviso no sale de esta función sino del núcleo de la planilla, que copia
-- `sin_tramo` y `no_corresponde` a sus propias claves. Se mide ahí también.
select is(
  (select (f->>'feriados_sin_salario')::int
     from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-05-29', '2026-06-28') -> 'filas') f
    where (f->>'persona_id')::uuid = '00000000-0000-0000-0000-000000399001'),
  0,
  'PLANILLA · la fila de quien cesó antes ya no trae «feriados sin salario»');

select is(
  (select (f->>'feriados_no_corresponde')::int
     from jsonb_array_elements(fn_planilla_calcular_nucleo('2026-05-29', '2026-06-28') -> 'filas') f
    where (f->>'persona_id')::uuid = '00000000-0000-0000-0000-000000399001'),
  1,
  'PLANILLA · y lo cuenta entre los que no aplican');


-- ── 7 · EL NÚCLEO SIGUE CERRADO AL NAVEGADOR ───────────────────────────────
-- `create or replace` conserva los permisos, pero el día que alguien lo
-- reescriba con drop + create, el revoke de la 0339 se perdería en silencio.
select ok(
  not has_function_privilege('authenticated', 'fn_feriado_devengado_nucleo(uuid, date, date, integer, date)', 'execute'),
  'PERMISOS · fn_feriado_devengado_nucleo sigue sin poder llamarse desde el navegador');


select * from finish();
rollback;
