-- ============================================================================
-- ¿A quién se le retuvo de más, por sede? — el mismo dato de
-- afp_cuanto_se_retuvo_de_mas.sql, con la sede de cada persona.
-- ============================================================================
-- SOLO LEE. No cambia nada. Se puede pegar en el SQL Editor las veces que
-- haga falta.
--
-- PARA QUÉ
--   La consulta original (afp_cuanto_se_retuvo_de_mas.sql) no dice la sede de
--   cada persona porque no hacía falta para decidir la reasignación (0331).
--   Sí hace falta para repartir la devolución por sede, así que esta consulta
--   agrega solo esa columna y filtra al periodo 29/07–28/08/2026, que es el
--   único con diferencia pendiente (confirmado el 2026-08-31).
--
-- DE DÓNDE SALEN LOS NÚMEROS
--   Igual que la original: de `planilla_pagada_detalle` (la foto congelada de
--   lo que se pagó), con la base despejada del propio descuento congelado. No
--   depende de ninguna función ni se recalcula.
--
-- CÓMO SE LEE
--   `sede` es la sede BASE de la persona hoy — si alguien se movió de sede
--   después de julio, esta consulta no lo distingue; para ese caso hay que
--   mirar `personas_sedes_historial` a mano.
-- ============================================================================

with retenido as (
  select f.nombre,
         coalesce(s.codigo, '?')                               as sede,
         f.fila->>'regimen_pension'                            as regimen,
         f.descuento_pension                                   as retenido,
         f.descuento_pension / (f.fila->>'tasa_afp')::numeric   as base
  from planilla_pagada_detalle f
  join periodos_planilla pp on pp.id = f.periodo_id
  left join personas p on p.id = f.persona_id
  left join sedes s on s.id = p.sede_base_id
  where f.fila->>'regimen_pension' in ('integra','prima','profuturo','habitat')
    and coalesce((f.fila->>'tasa_afp')::numeric, 0) > 0
    and pp.fecha_ini = date '2026-07-29'
    and f.version = (select max(f2.version)
                       from planilla_pagada_detalle f2
                      where f2.periodo_id = f.periodo_id
                        and f2.persona_id = f.persona_id)
)
select nombre as persona, sede, regimen,
       round(retenido, 2)                            as se_le_retuvo,
       round(base * 0.11370, 2)                       as le_tocaba_en_mixta,
       round(retenido - round(base * 0.11370, 2), 2)  as diferencia
from retenido
where sede = 'AQP'
order by diferencia desc;
