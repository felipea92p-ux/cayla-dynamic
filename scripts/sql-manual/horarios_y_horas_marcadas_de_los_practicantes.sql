-- ############################################################################
-- ####  HORARIOS Y HORAS MARCADAS DE LOS PRACTICANTES — SEPT. Y OCT. 2026   ####
-- ####  SOLO LEE. NO ESCRIBE NADA. Se pega en el SQL Editor de Supabase.    ####
-- ############################################################################
--
-- Para qué. Comparar lo PLANIFICADO con lo MARCADO, por practicante activo:
--
--   1. HORARIO   — cada tramo de `horarios_asignados` que cubre algo entre el
--                  2026-09-01 y el 2026-10-31: desde/hasta, día por día con su
--                  entrada, salida y refrigerio, y las horas por semana que
--                  implica (refrigerio ya descontado). Es la misma cascada que
--                  `jornada-esperada.ts`: horario_por_dia → dias_laborables.
--   2. TURNOS    — los turnos PUNTUALES de ese rango (cambios o descansos de un
--                  día), que PISAN al horario base. Solo se cuentan y se listan:
--                  no se mezclan en las horas por semana de la fila HORARIO.
--   3. MARCADO   — lo que de verdad marcó en sus últimos 3 periodos PAGADOS
--                  (horas del periodo y horas por semana ≈ horas × 7 ÷ días).
--
-- Cómo leerlo. Si en HORARIO sale «32 h/sem» y en MARCADO «20.8 h/sem», no marcó
-- lo que le tocaba: faltó, ingresó a mitad de periodo, o marcó menos. Si sale lo
-- contrario, marcó más que su horario.
--
-- ⚠️ Lo que NO dice. No incluye feriados ni descansos médicos/vacaciones del
-- periodo (restan horas marcadas sin que sea «marcó menos»). Y un practicante
-- sin ningún tramo en el rango aparece solo con sus filas de MARCADO.
--
-- UNA sola consulta (el SQL Editor muestra solo el último resultado). Los nombres
-- salen solo en el resultado; ninguno está escrito aquí.
-- ############################################################################

with
prac as (
  select p.id as persona_id,
         p.apellidos || ', ' || p.nombres as nombre,
         coalesce(p.practicante_modalidad, '(sin modalidad)') as modalidad
    from personas p
   where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
     and coalesce(p.cuenta_de_servicio, false) = false
),
tramos as (
  select h.*
    from horarios_asignados h
    join prac pr on pr.persona_id = h.persona_id
   where h.vigente_desde <= date '2026-10-31'
     and (h.vigente_hasta is null or h.vigente_hasta >= date '2026-09-01')
),
dias as (
  -- Un renglón por día trabajado de cada tramo. Un día AUSENTE del jsonb es
  -- descanso; solo si el tramo no tiene horario_por_dia se cae a dias_laborables.
  select t.persona_id, t.vigente_desde, t.vigente_hasta, d.dow::int as dow,
         d.e, d.s, greatest(coalesce(d.r, 0), 0) as r
    from tramos t
    cross join lateral (
      select k.key as dow,
             (k.value->>'e')::time as e,
             coalesce((k.value->>'s')::time, (k.value->>'e')::time) as s,
             coalesce((k.value->>'r')::int, t.almuerzo_min_minutos) as r
        from jsonb_each(t.horario_por_dia) k
       where t.horario_por_dia is not null and k.value->>'e' is not null
      union all
      select x::text, t.hora_entrada, t.hora_salida, t.almuerzo_min_minutos
        from unnest(t.dias_laborables) x
       where t.horario_por_dia is null and t.hora_entrada is not null
    ) d
),
horas_dia as (
  select d.*,
         greatest(0, (case when extract(epoch from (d.s - d.e)) / 60 <= 0
                           then extract(epoch from (d.s - d.e)) / 60 + 1440
                           else extract(epoch from (d.s - d.e)) / 60 end - d.r) / 60.0) as horas
    from dias d
),
horario as (
  select h.persona_id, h.vigente_desde, h.vigente_hasta,
         count(*)::int as dias_sem,
         round(sum(h.horas), 2) as h_sem,
         string_agg((array['dom','lun','mar','mié','jue','vie','sáb'])[h.dow + 1]
                    || ' ' || to_char(h.e, 'HH24:MI') || '–' || to_char(h.s, 'HH24:MI')
                    || ' (refrig. ' || h.r || ' min)',
                    ' · ' order by ((h.dow + 6) % 7)) as detalle
    from horas_dia h
   group by h.persona_id, h.vigente_desde, h.vigente_hasta
),
turnos_pt as (
  select t.persona_id,
         count(*) filter (where not t.es_descanso) as n_turnos,
         count(*) filter (where t.es_descanso)     as n_descansos,
         string_agg(t.fecha::text || case when t.es_descanso then ' descanso'
                         else ' ' || to_char(t.hora_entrada, 'HH24:MI')
                              || '–' || coalesce(to_char(t.hora_salida, 'HH24:MI'), '?') end,
                    ' · ' order by t.fecha) as lista
    from turnos t
    join prac pr on pr.persona_id = t.persona_id
   where t.fecha between date '2026-09-01' and date '2026-10-31'
   group by t.persona_id
),
periodos as (
  select x.*, row_number() over (partition by x.persona_id order by x.fecha_fin desc) as rn
    from (
      select distinct on (d.persona_id, d.periodo_id)
             d.persona_id, d.horas_mes, pp.fecha_ini, pp.fecha_fin,
             (pp.fecha_fin - pp.fecha_ini + 1) as dias
        from planilla_pagada_detalle d
        join periodos_planilla pp on pp.id = d.periodo_id
        join prac pr on pr.persona_id = d.persona_id
       where pp.estado = 'pagado'
       order by d.persona_id, d.periodo_id, d.version desc
    ) x
),
filas as (
  select pr.nombre, pr.modalidad, 1 as orden, 'HORARIO' as seccion,
         h.vigente_desde as desde, h.vigente_hasta as hasta,
         h.dias_sem || ' días/sem · ' || h.detalle as detalle,
         h.h_sem
    from horario h join prac pr on pr.persona_id = h.persona_id
  union all
  select pr.nombre, pr.modalidad, 2, 'TURNOS PUNTUALES', null, null,
         t.n_turnos || ' turnos y ' || t.n_descansos || ' descansos puntuales: ' || t.lista,
         null
    from turnos_pt t join prac pr on pr.persona_id = t.persona_id
  union all
  select pr.nombre, pr.modalidad, 3, 'MARCADO (periodo pagado)',
         p.fecha_ini, p.fecha_fin,
         round(p.horas_mes, 1) || ' h en ' || p.dias || ' días',
         round(p.horas_mes * 7.0 / p.dias, 2)
    from periodos p join prac pr on pr.persona_id = p.persona_id
   where p.rn <= 3
  union all
  -- Quien no aparece en ninguna de las tres secciones, para no perderlo de vista.
  select pr.nombre, pr.modalidad, 0, 'SIN DATOS', null, null,
         'sin tramo de horario en sept–oct, sin turnos puntuales y sin periodo pagado', null
    from prac pr
   where not exists (select 1 from horario h where h.persona_id = pr.persona_id)
     and not exists (select 1 from turnos_pt t where t.persona_id = pr.persona_id)
     and not exists (select 1 from periodos p where p.persona_id = pr.persona_id)
)
select nombre, modalidad, seccion, desde, hasta, h_sem as horas_por_semana, detalle
  from filas
 order by nombre, orden, desde nulls last;
