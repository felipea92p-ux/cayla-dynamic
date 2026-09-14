-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 243_dos_horarios_no_pueden_cubrir_el_mismo_dia.test.sql
-- ============================================================================
-- `horarios_asignados` solo tenía un índice PARCIAL sobre el tramo abierto, así
-- que dos tramos cerrados podían pisarse. Y cuando dos cubren el mismo día,
-- quien decide es un `order by vigente_desde desc limit 1`: elige uno en
-- silencio, y de ahí sale si a esa persona se le cuenta tardanza o falta.
--
-- Medido en producción el 2026-08-26: 10 pares en 8 personas. Nueve eran el
-- mismo error de convención —el tramo anterior cerrando el mismo día en que
-- empieza el siguiente— y uno era un solape real de cuatro días.
--
-- Esta prueba cubre las TRES cosas que la 0309 promete:
--   · que el candado rechace lo que tiene que rechazar, incluido el caso de
--     convención que parece inocente;
--   · que la comprobación previa diga «0» sobre datos como los de producción
--     **y que BLOQUEE** sobre datos donde acortar sí le cambiaría el horario a
--     alguien — un freno probado solo con casos que pasan no está probado;
--   · que el arreglo no cambie el horario efectivo de nadie, medido día a día.
--
-- La consulta de la comprobación va copiada tal cual de la 0309, igual que el
-- `update`. Se la escopeta por persona para poder aislar cada caso; la de la
-- migración es global.
-- ============================================================================
begin;
select plan(12);

insert into sedes (id, codigo, nombre, activa, tipo)
values ('00000000-0000-0000-0000-000000024300', 'ZZHOR', 'Sede de laboratorio', true, 'tienda');

set session_replication_role = replica;
insert into personas (id, nombres, apellidos, sede_base_id, rol, pin_hash, auth_user_id, fecha_ingreso)
values ('00000000-0000-0000-0000-0000000243ad', 'HorAdmin', 'Lab',
        '00000000-0000-0000-0000-000000024300', 'admin', 'x',
        '00000000-0000-0000-0000-0000000243ff', '2024-01-01');
set session_replication_role = origin;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000243ff', true);

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000024301', 'HorPersona', 'Lab',
        '00000000-0000-0000-0000-000000024300', 'x', '2024-01-01');

-- Un tramo base, para tener contra qué chocar.
insert into horarios_asignados
  (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values ('00000000-0000-0000-0000-000000024301', '2026-07-01', '2026-07-15',
        '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39);


-- ── 1 · Lo que sí se puede: tramos que no se tocan ─────────────────────────

select lives_ok(
  $$ insert into horarios_asignados
       (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
        almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
     values ('00000000-0000-0000-0000-000000024301', '2026-07-16', '2026-07-31',
             '10:00', '18:00', 0, 0, array[1,2,3,4,5,6], 39) $$,
  'Un tramo que empieza al DÍA SIGUIENTE del anterior entra sin problema');


-- ── 2 · El caso de convención, que es el que había en producción ───────────

select throws_ok(
  $$ insert into horarios_asignados
       (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
        almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
     values ('00000000-0000-0000-0000-000000024301', '2026-07-31', '2026-08-10',
             '08:00', '14:00', 0, 0, array[1,2,3,4,5,6], 39) $$,
  '23P01', null,
  'Empezar el MISMO día en que cierra el anterior se rechaza — era el error de nueve de los diez pares');


-- ── 3 · El solape de verdad, tipo Chiara ──────────────────────────────────

select throws_ok(
  $$ insert into horarios_asignados
       (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
        almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
     values ('00000000-0000-0000-0000-000000024301', '2026-07-20', '2026-07-25',
             '08:00', '14:00', 0, 0, array[1,2,3,4,5,6], 39) $$,
  '23P01', null,
  'Un tramo metido dentro de otro se rechaza');


-- ── 4 y 5 · El tramo abierto también cuenta ────────────────────────────────

select lives_ok(
  $$ insert into horarios_asignados
       (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
        almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
     values ('00000000-0000-0000-0000-000000024301', '2026-08-01', null,
             '09:00', '17:00', 0, 0, array[1,2,3,4,5,6], 39) $$,
  'El tramo abierto entra si empieza después del último cerrado');

select throws_ok(
  $$ insert into horarios_asignados
       (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
        almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
     values ('00000000-0000-0000-0000-000000024301', '2026-09-01', '2026-09-30',
             '08:00', '14:00', 0, 0, array[1,2,3,4,5,6], 39) $$,
  '23P01', null,
  'Y nada puede meterse DENTRO del tramo abierto: llega hasta el infinito');


-- ── 6 · Otra persona con las mismas fechas no molesta ──────────────────────

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000024302', 'HorOtra', 'Lab',
        '00000000-0000-0000-0000-000000024300', 'x', '2024-01-01');

select lives_ok(
  $$ insert into horarios_asignados
       (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
        almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
     values ('00000000-0000-0000-0000-000000024302', '2026-07-01', '2026-07-15',
             '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39) $$,
  'El candado es POR PERSONA: dos personas pueden tener el mismo tramo');


-- ── 7 a 10 · La comprobación previa y el arreglo ───────────────────────────
--
-- Se quita el candado y se reproduce el estado de producción: el solape de
-- convención y el real de cuatro días.

alter table horarios_asignados drop constraint horarios_sin_solape;

insert into horarios_asignados
  (id, persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values
  -- Convención: cierra el mismo día en que empieza el siguiente.
  ('00000000-0000-0000-0000-0000002430a1', '00000000-0000-0000-0000-000000024302',
   '2026-07-16', '2026-07-26', '10:00', '18:00', 0, 0, array[1,2,3,4,5,6], 39),
  ('00000000-0000-0000-0000-0000002430a2', '00000000-0000-0000-0000-000000024302',
   '2026-07-26', '2026-08-02', '08:00', '14:00', 0, 0, array[1,2,3,4,5,6], 39),
  -- Real, tipo Chiara: cuatro días con dos horarios vivos.
  ('00000000-0000-0000-0000-0000002430b1', '00000000-0000-0000-0000-000000024302',
   '2026-08-03', '2026-08-08', '07:00', '13:00', 0, 0, array[1,2,3,4,5,6], 39),
  ('00000000-0000-0000-0000-0000002430b2', '00000000-0000-0000-0000-000000024302',
   '2026-08-05', '2026-08-08', '11:00', '19:00', 0, 0, array[1,2,3,4,5,6], 39);

-- 7 · La comprobación de la 0309, copiada tal cual, dice que no cambiaría nada.
select is(
  (with por_perder as (
     select a.id, a.persona_id, a.vigente_desde, a.vigente_hasta as cierre,
            (select min(b.vigente_desde) from horarios_asignados b
              where b.persona_id = a.persona_id and b.vigente_desde > a.vigente_desde)
              as arranque_del_siguiente
       from horarios_asignados a
      where a.vigente_hasta is not null
        and a.persona_id = '00000000-0000-0000-0000-000000024302'
   )
   select count(*)::int
     from por_perder t
    cross join lateral generate_series(t.arranque_del_siguiente, t.cierre, interval '1 day') g
    where t.arranque_del_siguiente is not null
      and t.cierre >= t.arranque_del_siguiente
      and not exists (select 1 from horarios_asignados c
                       where c.persona_id = t.persona_id
                         and c.vigente_desde > t.vigente_desde
                         and c.vigente_desde <= g::date
                         and (c.vigente_hasta is null or c.vigente_hasta >= g::date))),
  0,
  'COMPROBACIÓN · sobre datos como los de producción dice 0: acortar no le cambia el horario a nadie');


-- 8 · Y AHORA EL CASO QUE DEBE BLOQUEAR. Un freno probado solo con lo que pasa
-- no está probado. Aquí un tramo largo (01→31 jul) se pisa con uno corto
-- (10→15 jul) que empieza después. Acortar el largo al día 9 dejaría a esa
-- persona SIN horario del 16 al 31 — dieciséis días en los que hoy sí manda.

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000024304', 'HorFreno', 'Lab',
        '00000000-0000-0000-0000-000000024300', 'x', '2024-01-01');

insert into horarios_asignados
  (persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
   almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horas_semana_objetivo)
values
  ('00000000-0000-0000-0000-000000024304', '2026-07-01', '2026-07-31',
   '09:00', '15:30', 0, 0, array[1,2,3,4,5,6], 39),
  ('00000000-0000-0000-0000-000000024304', '2026-07-10', '2026-07-15',
   '10:00', '18:00', 0, 0, array[1,2,3,4,5,6], 39);

select is(
  (with por_perder as (
     select a.id, a.persona_id, a.vigente_desde, a.vigente_hasta as cierre,
            (select min(b.vigente_desde) from horarios_asignados b
              where b.persona_id = a.persona_id and b.vigente_desde > a.vigente_desde)
              as arranque_del_siguiente
       from horarios_asignados a
      where a.vigente_hasta is not null
        and a.persona_id = '00000000-0000-0000-0000-000000024304'
   )
   select count(*)::int
     from por_perder t
    cross join lateral generate_series(t.arranque_del_siguiente, t.cierre, interval '1 day') g
    where t.arranque_del_siguiente is not null
      and t.cierre >= t.arranque_del_siguiente
      and not exists (select 1 from horarios_asignados c
                       where c.persona_id = t.persona_id
                         and c.vigente_desde > t.vigente_desde
                         and c.vigente_desde <= g::date
                         and (c.vigente_hasta is null or c.vigente_hasta >= g::date))),
  16,
  'FRENO · cuenta los 16 días del 16 al 31 de julio en que acortar SÍ dejaría sin horario: la 0309 abortaría');

-- Ese caso queda fuera del resto: el candado de abajo no lo admitiría, y con
-- razón — es un solape que exige decidir a mano cuál tramo vale.
delete from horarios_asignados where persona_id = '00000000-0000-0000-0000-000000024304';


-- 9 · Y la invarianza medida día a día, no deducida.

create temporary table _antes on commit drop as
select d::date as fecha,
       (select h.id from horarios_asignados h
         where h.persona_id = '00000000-0000-0000-0000-000000024302'
           and h.vigente_desde <= d and (h.vigente_hasta is null or h.vigente_hasta >= d)
         order by h.vigente_desde desc limit 1) as tramo
  from generate_series('2026-07-01'::date, '2026-08-31'::date, interval '1 day') d;

-- El update, copiado tal cual de la 0309.
update horarios_asignados h
   set vigente_hasta = s.limite
  from (
    select a.id, min(b.vigente_desde) - 1 as limite
      from horarios_asignados a
      join horarios_asignados b
        on b.persona_id = a.persona_id and b.vigente_desde > a.vigente_desde
     where a.vigente_hasta is not null and a.vigente_hasta >= b.vigente_desde
     group by a.id
  ) s
 where h.id = s.id and h.vigente_hasta <> s.limite;

select is(
  (select count(*)::int from _antes a
    where a.tramo is distinct from
      (select h.id from horarios_asignados h
        where h.persona_id = '00000000-0000-0000-0000-000000024302'
          and h.vigente_desde <= a.fecha and (h.vigente_hasta is null or h.vigente_hasta >= a.fecha)
        order by h.vigente_desde desc limit 1)),
  0,
  'INVARIANZA · el arreglo no cambió qué horario manda en NI UN SOLO día');

select lives_ok(
  $$ alter table horarios_asignados add constraint horarios_sin_solape
       exclude using gist (
         persona_id with =,
         daterange(vigente_desde, coalesce(vigente_hasta, 'infinity'::date), '[]') with &&
       ) $$,
  'Y con los datos ya arreglados, el candado entra sin protestar');


-- ── 11 y 12 · LA PREGUNTA QUE MÁS IMPORTA: ¿sigue funcionando la pantalla? ──
--
-- Un candado nuevo sobre una tabla viva puede romper el camino que la escribe, y
-- eso no se vería hasta que alguien intentara asignar un horario. `fn_set_
-- horario_semanal` cierra el tramo anterior en `p_vigente_desde - 1` —bien, no
-- el mismo día— pero eso hay que DEMOSTRARLO contra el candado, no leerlo.

insert into personas (id, nombres, apellidos, sede_base_id, pin_hash, fecha_ingreso)
values ('00000000-0000-0000-0000-000000024303', 'HorTercera', 'Lab',
        '00000000-0000-0000-0000-000000024300', 'x', '2024-01-01');

select lives_ok(
  $$ select fn_set_horario_semanal('00000000-0000-0000-0000-000000024303', '2026-09-01',
              '{"1":{"e":"09:00","s":"17:00","r":0}}'::jsonb, 'Prueba pgTAP.'),
            fn_set_horario_semanal('00000000-0000-0000-0000-000000024303', '2026-09-15',
              '{"1":{"e":"10:00","s":"18:00","r":0}}'::jsonb, 'Prueba pgTAP.'),
            fn_set_horario_semanal('00000000-0000-0000-0000-000000024303', '2026-09-20',
              '{"1":{"e":"08:00","s":"16:00","r":0}}'::jsonb, 'Prueba pgTAP.') $$,
  'PANTALLA · asignar horario tres veces seguidas sigue funcionando con el candado puesto');

select is(
  (select string_agg(vigente_desde::text || '→' || coalesce(vigente_hasta::text, 'abierto'),
                     ' · ' order by vigente_desde)
     from horarios_asignados where persona_id = '00000000-0000-0000-0000-000000024303'),
  '2026-09-01→2026-09-14 · 2026-09-15→2026-09-19 · 2026-09-20→abierto',
  'Y los tramos quedan pegados sin pisarse: cada uno cierra la VÍSPERA del siguiente');


select * from finish();
rollback;
