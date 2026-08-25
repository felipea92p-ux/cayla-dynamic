-- ############################################################################
-- ####  ¿POR QUÉ NO HAY CON QUÉ COMPARAR?  — SOLO LEE                     ####
-- ############################################################################
--
-- Para qué. `que_umbral_de_varianza.sql` devolvió CERO personas comparables.
-- Eso no es «todo estable»: es que el emparejamiento entre los dos últimos
-- periodos pagados no encontró a nadie. Antes de tocar la consulta hay que
-- saber dónde se corta, y hay tres sitios posibles:
--
--   a) No hay dos periodos con estado 'pagado'.
--   b) Los hay, pero alguno no tiene FOTO — `planilla_pagada_detalle` vacía
--      para él. Existen periodos pagados sin foto: son los que documenta
--      `fn_planilla_congelar_pendientes` (0096), meses transferidos de antes de
--      que la foto existiera.
--   c) Los dos tienen foto, pero no comparten ni una persona (improbable, y si
--      pasa es el hallazgo).
--
-- Esto lo responde sin adivinar: lista los seis últimos periodos pagados con
-- cuántas filas y cuántas personas distintas tiene la foto de cada uno.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with per as (
  select p.id, p.fecha_ini, p.fecha_fin, p.estado, p.pagado_at,
         row_number() over (order by p.fecha_fin desc) as rn
    from periodos_planilla p
   where p.estado = 'pagado'
),
foto as (
  select f.periodo_id,
         count(*)                          as filas,
         count(distinct f.persona_id)      as personas,
         max(f.version)                    as version_max,
         min(f.congelada_at)               as congelada
    from planilla_pagada_detalle f
   group by f.periodo_id
)
select 1 as orden,
       'RESUMEN' as periodo,
       (select count(*) from periodos_planilla where estado = 'pagado')::text
         || ' pagados · '
         || (select count(*) from periodos_planilla where estado = 'abierto')::text
         || ' abiertos · '
         || (select count(distinct periodo_id) from planilla_pagada_detalle)::text
         || ' con foto'                                as dato,
       case
         when (select count(*) from per) < 2
           then '⚠  Hay menos de DOS periodos pagados: no hay contra qué comparar todavía.'
         when (select count(*) from per p left join foto f on f.periodo_id = p.id
                where p.rn <= 2 and f.periodo_id is null) > 0
           then '⚠  Alguno de los dos últimos pagados NO tiene foto. La comparación tiene que saltarse los que no la tengan.'
         else '✓  Los dos últimos pagados tienen foto. Si aun así no hay comparables, el corte está en otro sitio.'
       end                                             as veredicto
union all
select 2,
       to_char(p.fecha_ini, 'DD/MM/YY') || ' → ' || to_char(p.fecha_fin, 'DD/MM/YY')
         || '  (rn ' || p.rn::text || ')',
       coalesce(f.personas, 0)::text || ' personas · ' || coalesce(f.filas, 0)::text
         || ' filas · v' || coalesce(f.version_max, 0)::text,
       case when f.periodo_id is null
            then '⚠  pagado SIN foto'
            else '✓  con foto del ' || to_char(f.congelada, 'DD/MM/YY') end
  from per p
  left join foto f on f.periodo_id = p.id
 where p.rn <= 6
order by orden, periodo desc;
