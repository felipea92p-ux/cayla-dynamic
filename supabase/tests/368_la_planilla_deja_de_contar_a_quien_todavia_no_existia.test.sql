-- ⛔ NO PEGAR ESTE ARCHIVO EN EL SQL EDITOR DE SUPABASE. No es una migración.
-- Es una PRUEBA: usa pgTAP, que solo existe en el Postgres local. En producción
-- falla con "function plan(integer) does not exist" — y falla a propósito.
-- Se corre así, en esta Mac:   npx supabase test db
-- Lo que sí se pega vive en supabase/migrations/ y scripts/sql-manual/.
-- ============================================================================
-- 368_la_planilla_deja_de_contar_a_quien_todavia_no_existia.test.sql — 0464
-- ============================================================================
-- La 0463 (otra rama, mismo día) ya defiende el candado en sí —quien ingresó
-- después de un periodo deja de aparecer en él— en su propia prueba, la 367.
-- Esta prueba defiende lo que la 0463 no cubre: que un periodo que se quedó
-- 'abierto' SOLO por un grupo fantasma (gente que en ese periodo no existía)
-- puede volver a cerrar una vez que el candado de la 0463 ya está puesto — y
-- que uno con un grupo REAL todavía pendiente no se cierra de más.
--
-- El escenario reproduce por qué julio y agosto se quedaron atascados: un
-- grupo con gente real ya pagado (planilla), y un segundo grupo (rxh) que
-- solo tiene gente real en un caso y solo fantasma en el otro.
-- ============================================================================
begin;
select plan(3);

insert into sedes (id, codigo, nombre, activa)
values ('aaaaaaaa-0464-0000-0000-000000000001', 'T64', 'Sede de la prueba 368', true);

-- Sin sesión ni admin: el backfill de la 0464 (igual que se reproduce abajo)
-- llama a fn_planilla_calcular_nucleo directo, no al envoltorio con el guard
-- de rol — corre como el dueño de la migración, no como un usuario.

-- Dos periodos ya pasados, de 30 días, relativos a hoy — nunca fechas fijas.
-- «Agosto»: su único grupo real (planilla) ya está pagado; el «fantasma»
--   (alguien que ingresó después) es lo único que le falta.
-- «Julio»: además del fantasma, tiene un SEGUNDO grupo (rxh) con gente REAL
--   todavía sin pagar — ese no se puede cerrar de más.
create temporary table _datos as
select
  (fn_hoy_lima() - 150) as julio_ini, (fn_hoy_lima() - 121) as julio_fin,
  (fn_hoy_lima() - 90)  as agosto_ini, (fn_hoy_lima() - 61) as agosto_fin,
  (fn_hoy_lima() - 150) as vieja_ingreso,  -- ya existía en los dos periodos
  (fn_hoy_lima() - 30)  as fantasma_ingreso;  -- ingresó después de los dos

-- Vieja: grupo 'planilla', con salario, en las dos ventanas.
insert into personas (id, nombres, apellidos, sede_base_id, estado, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
select 'cccccccc-0464-0000-0000-000000000002', 'Vieja', 'DeAntes',
       'aaaaaaaa-0464-0000-0000-000000000001', 'activo', 'x', d.vieja_ingreso, 'planilla', true
  from _datos d;
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('cccccccc-0464-0000-0000-000000000002', 'colibri', 1950, '2020-01-01');

-- RxhReal: grupo 'rxh', con jornada marcada SOLO en julio — su pago sigue
-- pendiente de verdad en julio; en agosto no tiene ninguna fila.
insert into personas (id, nombres, apellidos, sede_base_id, estado, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
select 'cccccccc-0464-0000-0000-000000000003', 'RxhReal', 'DeJulio',
       'aaaaaaaa-0464-0000-0000-000000000001', 'activo', 'x', d.vieja_ingreso, 'rxh', false
  from _datos d;
insert into asignaciones_salario (persona_id, rango, salario_mensual_soles, vigente_desde)
values ('cccccccc-0464-0000-0000-000000000003', 'colibri', 1950, '2020-01-01');
insert into jornadas (persona_id, fecha, horas_trabajadas, estado)
select 'cccccccc-0464-0000-0000-000000000003', d.julio_ini + 2, 6.5, 'cerrada'
  from _datos d;

-- Fantasma: ingresó después de los DOS periodos. Con la 0463 ya puesta, no
-- aparece en ninguno de los dos rangos.
insert into personas (id, nombres, apellidos, sede_base_id, estado, pin_hash, fecha_ingreso, tipo_vinculo, sueldo_fijo)
select 'cccccccc-0464-0000-0000-000000000004', 'Fantasma', 'DeSeptiembre',
       'aaaaaaaa-0464-0000-0000-000000000001', 'activo', 'x', d.fantasma_ingreso, 'practicante', false
  from _datos d;

insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
select 'dddddddd-0464-0000-0000-000000000001', d.julio_ini, d.julio_fin, 'abierto' from _datos d;
insert into periodos_planilla (id, fecha_ini, fecha_fin, estado)
select 'dddddddd-0464-0000-0000-000000000002', d.agosto_ini, d.agosto_fin, 'abierto' from _datos d;

-- El estado se monta A MANO en periodo_grupo_pago, no llamando a
-- fn_periodo_pagado: con la 0463 ya puesta en el mismo schema de esta
-- prueba, pagar el ÚLTIMO grupo real de agosto por esa función cerraría el
-- periodo ella sola —correctamente— y no quedaría nada que el backfill
-- tuviera que hacer. Esto reproduce el estado real con el que se encontró
-- producción: los grupos reales pagados ANTES de que la 0463 existiera, con
-- el periodo todavía 'abierto' porque en ese momento el fantasma contaba.
insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at)
values ('dddddddd-0464-0000-0000-000000000001', 'planilla', 'pagado', now()),
       ('dddddddd-0464-0000-0000-000000000002', 'planilla', 'pagado', now());
-- Julio no lleva fila de 'rxh': ese grupo real todavía no se pagó de verdad.

-- ── El backfill de la 0464, reproducido tal cual lo hace la migración ──────
do $$
declare
  v_per record;
  v_grupos_con_gente text[];
begin
  for v_per in
    select id, fecha_ini, fecha_fin from periodos_planilla
     where estado = 'abierto'
       and id in ('dddddddd-0464-0000-0000-000000000001', 'dddddddd-0464-0000-0000-000000000002')
  loop
    select array_agg(distinct f->>'tipo_vinculo') into v_grupos_con_gente
    from jsonb_array_elements(
      coalesce(fn_planilla_calcular_nucleo(v_per.fecha_ini, v_per.fecha_fin, v_per.id)->'filas', '[]'::jsonb)
    ) f;
    if v_grupos_con_gente is not null and not exists (
      select 1 from unnest(v_grupos_con_gente) g(grupo)
       where not exists (
         select 1 from periodo_grupo_pago
          where periodo_id = v_per.id and grupo = g.grupo and estado = 'pagado'
       )
    ) then
      update periodos_planilla set estado = 'pagado', pagado_at = now() where id = v_per.id;
    end if;
  end loop;
end $$;

-- ── § 1 · agosto cierra: su único grupo real ya estaba pagado ───────────────
select is(
  (select estado from periodos_planilla where id = 'dddddddd-0464-0000-0000-000000000002'),
  'pagado',
  '0464: agosto cierra — sin el fantasma, planilla era el único grupo real y ya estaba pagado');

-- ── § 2 · julio NO cierra: rxh sigue pendiente de verdad ────────────────────
select is(
  (select estado from periodos_planilla where id = 'dddddddd-0464-0000-0000-000000000001'),
  'abierto',
  '0464: julio se queda abierto — rxh es un grupo real y todavía no se pagó, el backfill no inventa ese pago');

-- ── § 3 · y julio sigue apareciendo así en periodo_grupo_pago: rxh sin fila ─
select is(
  (select count(*)::int from periodo_grupo_pago
    where periodo_id = 'dddddddd-0464-0000-0000-000000000001' and grupo = 'rxh'),
  0,
  '0464: el backfill no le inventó a rxh un pago que nadie hizo');

select * from finish();
rollback;
