-- ############################################################################
-- ####  SIMULACIÓN: QUÉ PASARÍA SI LOS PRACTICANTES TUVIERAN TOPE DE HORAS  ####
-- ####  SOLO LEE. NO ESCRIBE NADA. Se pega en el SQL Editor de Supabase.    ####
-- ############################################################################
--
-- Para qué. Decidir cuántas horas pactar con cada practicante ANTES de tocar la
-- planilla. Responde, por persona y con lo que marcó de verdad en sus últimos
-- periodos PAGADOS:
--
--   · ¿Cuántas horas por semana está marcando, y cuántas son más que el máximo
--     de su modalidad (30 h el preprofesional, 48 h el profesional; Ley 28518,
--     art. 44)?
--   · ¿Cuánto cobra hoy por esas horas (la fórmula de la planilla:
--     subvención × horas / (6.5 × días del periodo))?
--   · ¿Cuánto cobraría con un TOPE de horas (las de su convenio, o el máximo de
--     su modalidad si no tiene convenio con horas)?
--   · ¿Cuál sería el PISO LEGAL PROPORCIONAL si se pactan 20, 24 o 30 h por
--     semana (RMV × horas / máximo de la modalidad)? Es la referencia del
--     art. 45 que usa la 0502.
--
-- ⚠️ LO QUE ESTO NO DICE.
--   1. NO decide nada legal. Si pagar por horas marcadas cumple el art. 45 es
--      consulta abierta con el laboralista (docs/estado.md, «Lo que la 0502 NO
--      resuelve»). Esto solo pone números a las opciones.
--   2. «Pago hoy» es solo la SUBVENCIÓN por horas. No incluye movilidad,
--      educación, bono ni EsSalud, y usa la subvención VIGENTE hoy para todos los
--      periodos (no versiona el pasado).
--   3. Para un PROFESIONAL el piso proporcional es solo una referencia: la
--      regla de la 0502 le aplica la RMV entera y no hay dónde cargar sus horas.
--   4. BASE 45 (columnas «b45»): jornada completa = 45 h = RMV entera; pago =
--      RMV × horas ÷ 45 (hora = S/ 6.31). Es solo una simulación: un preprofesional
--      no puede pasar de 30 h, y a 30 h la base 45 le da S/ 820 contra S/ 1 230 de
--      la base 30 — esa diferencia ES la consulta abierta del art. 45.
--   5. Las horas por semana son aproximadas: horas del periodo × 7 ÷ días.
--
-- Cómo se usa. UNA sola consulta (el SQL Editor muestra solo el último
-- resultado). Una fila por practicante activo y una fila final «TOTAL». Los
-- nombres salen solo en el resultado; ninguno está escrito aquí.
-- ############################################################################

with
rmv as (
  select pl.valor
    from parametros_laborales pl
   where pl.clave = 'rmv' and pl.sede_codigo is null
     and pl.vigente_desde <= current_date
     and (pl.vigente_hasta is null or pl.vigente_hasta >= current_date)
   order by pl.vigente_desde desc
   limit 1
),
prac as (
  select p.id as persona_id,
         p.apellidos || ', ' || p.nombres as nombre,
         p.practicante_modalidad          as modalidad,
         case p.practicante_modalidad when 'preprofesional' then 30
                                      when 'profesional'    then 48 end as max_h,
         a.salario_mensual_soles          as sal
    from personas p
    left join asignaciones_salario a
      on a.persona_id = p.id and a.vigente_hasta is null
   where p.tipo_vinculo = 'practicante' and p.estado = 'activo'
     and coalesce(p.cuenta_de_servicio, false) = false
),
conv as (
  -- Horas pactadas en convenios de prácticas no anulados (firmados o borrador).
  select c.persona_id,
         min(c.horas_semanales)                as horas,
         count(distinct c.horas_semanales) > 1 as conflicto
    from contratos_generados c
   where c.tipo = 'convenio_practicas' and c.anulado_at is null
     and c.horas_semanales is not null
   group by c.persona_id
),
periodos as (
  -- Una fila por persona y periodo pagado (la última versión), numerada del más
  -- reciente al más antiguo. Se miran hasta los 3 últimos.
  select x.*, row_number() over (partition by x.persona_id order by x.fecha_fin desc) as rn
    from (
      select distinct on (d.persona_id, d.periodo_id)
             d.persona_id, d.horas_mes,
             pp.fecha_fin, (pp.fecha_fin - pp.fecha_ini + 1) as dias
        from planilla_pagada_detalle d
        join periodos_planilla pp on pp.id = d.periodo_id
       where pp.estado = 'pagado'
       order by d.persona_id, d.periodo_id, d.version desc
    ) x
),
medido as (
  select pr.persona_id,
         count(*)                                               as n_periodos,
         max(case when pr.rn = 1 then pr.horas_mes * 7.0 / pr.dias end) as h_sem_ult,
         avg(pr.horas_mes * 7.0 / pr.dias)                      as h_sem_prom,
         max(case when pr.rn = 1 then pr.horas_mes end)         as horas_ult,
         max(case when pr.rn = 1 then pr.dias end)              as dias_ult
    from periodos pr
   where pr.rn <= 3
   group by pr.persona_id
),
calc as (
  select p.nombre, p.modalidad, p.max_h, p.sal,
         (select valor from rmv)                         as rmv,
         cv.horas                                        as h_convenio,
         coalesce(cv.conflicto, false)                   as conflicto,
         coalesce(cv.horas, p.max_h)                     as h_tope,
         m.n_periodos, m.h_sem_ult, m.h_sem_prom, m.horas_ult, m.dias_ult
    from prac p
    left join conv cv   on cv.persona_id = p.persona_id
    left join medido m  on m.persona_id  = p.persona_id
),
filas as (
  select c.nombre,
         coalesce(c.modalidad, '(sin modalidad)')                  as modalidad,
         c.sal                                                     as subvencion_vigente,
         case when c.h_convenio is not null then c.h_convenio::text || ' h (convenio)'
              else 'sin horas pactadas → se supone ' || coalesce(c.max_h::text, '?') || ' h' end as horas_pactadas,
         case when c.conflicto then 'CONFLICTO DE CONVENIOS: horas distintas' else '' end as aviso,
         c.n_periodos                                              as periodos_pagados_vistos,
         round(c.h_sem_ult, 1)                                     as h_sem_ultimo,
         round(c.h_sem_prom, 1)                                    as h_sem_prom_3,
         round(greatest(c.h_sem_ult - c.max_h, 0), 1)              as exceso_sobre_max_modalidad,
         round(c.sal * c.horas_ult / (6.5 * c.dias_ult), 2)        as pago_hoy_ultimo,
         round(c.sal * least(c.horas_ult, c.h_tope * c.dias_ult / 7.0)
                       / (6.5 * c.dias_ult), 2)                    as pago_con_tope,
         round(c.sal * c.horas_ult / (6.5 * c.dias_ult)
             - c.sal * least(c.horas_ult, c.h_tope * c.dias_ult / 7.0)
                       / (6.5 * c.dias_ult), 2)                    as se_ahorra_con_tope,
         round(c.rmv * 20 / c.max_h, 2)                            as piso_20h,
         round(c.rmv * 24 / c.max_h, 2)                            as piso_24h,
         round(c.rmv * 30 / c.max_h, 2)                            as piso_30h,
         round(c.sal * c.horas_ult / (6.5 * c.dias_ult)
             - c.rmv * c.h_tope / c.max_h, 2)                      as hoy_menos_piso_de_su_tope,
         -- ── BASE 45 h (jornada completa = 45 h = RMV entera; factor = horas ÷ 45) ──
         -- Es la hoja «equivalencia de jornadas» con base B. Solo SIMULA: para un
         -- preprofesional queda bajo el piso proporcional de la base 30 (art. 45).
         case when c.h_sem_ult is not null then round(least(c.h_sem_ult / 45.0, 1), 2) end as factor_b45_marcado,
         case when c.h_sem_ult is not null then round(c.rmv * least(c.h_sem_ult / 45.0, 1), 2) end as pago_b45_marcado,
         case when c.h_sem_ult is not null then round(c.rmv * least(c.h_sem_ult, c.h_tope) / 45.0, 2) end as pago_b45_con_tope,
         round(c.rmv * 15 / 45.0, 2)                               as b45_15h,
         round(c.rmv * 20 / 45.0, 2)                               as b45_20h,
         round(c.rmv * 24 / 45.0, 2)                               as b45_24h,
         round(c.rmv * 30 / 45.0, 2)                               as b45_30h
    from calc c
)
select * from (
select 0 as o, f.* from filas f
union all
select 1, 'TOTAL (' || count(*) || ' practicantes)', '', sum(subvencion_vigente), '', '',
       null, null, null, null,
       sum(pago_hoy_ultimo), sum(pago_con_tope), sum(se_ahorra_con_tope),
       sum(piso_20h), sum(piso_24h), sum(piso_30h), sum(hoy_menos_piso_de_su_tope),
       null, sum(pago_b45_marcado), sum(pago_b45_con_tope),
       sum(b45_15h), sum(b45_20h), sum(b45_24h), sum(b45_30h)
  from filas
) t
order by o, nombre;
