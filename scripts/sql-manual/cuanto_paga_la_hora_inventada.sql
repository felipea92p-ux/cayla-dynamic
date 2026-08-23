-- ############################################################################
-- ####  ¿CUÁNTO SOBRETIEMPO PAGA UNA HORA QUE NADIE MARCÓ?  — SOLO LEE    ####
-- ############################################################################
--
-- Para qué. Cuando alguien olvida marcar su salida, `fn_auto_cierre` cierra el
-- día poniéndole una hora que el sistema inventa, y la jornada queda en estado
-- `auto_cerrada_pendiente` esperando que una encargada la confirme.
--
-- `fn_recalcular_jornada` se NIEGA a medir tardanza o salida temprana contra esa
-- hora — la 0249 lo dice con todas las letras: «esa hora la inventó el sistema y
-- medir contra ella sería acusar con un dato falso».
--
-- Pero esa MISMA hora sí entra a `horas_trabajadas`, y de ahí al cálculo de
-- sobretiempo de `fn_planilla_calcular`, donde puede cruzar las 48 h del ciclo y
-- generar un recargo del 25 % / 35 % que se paga, entra a la base de EsSalud y
-- pensión (0193) y se declara en la PLAME.
--
-- O sea: el sistema considera esa hora demasiado poco fiable para una
-- conversación, y suficientemente fiable para una transferencia.
--
-- ESTA CONSULTA NO ARREGLA NADA. Mide cuánto cuesta hoy, que es lo que hay que
-- saber antes de decidir si se bloquea el cierre o solo se avisa.
--
-- Se lee así:
--   ✓ = el mecanismo existe pero no le ha pasado a nadie: nada que reparar.
--   ⚠ = hay días auto-cerrados que sí generaron recargo. Si el periodo está
--       PAGADO, ya salió del banco; si está ABIERTO, todavía se puede evitar.
--
-- El bloque de ciclos replica `ot_dias → ot_islas → ot_ciclos → ot_exceso` tal
-- como está en la versión viva de `fn_planilla_calcular` (0276), incluida la
-- ventana de 7 días hacia atrás y el corte de ciclo que no se solapa. Las horas
-- de recargo son las EQUIVALENTES (25 % las dos primeras del día, 35 % las
-- siguientes), que es exactamente lo que la función guarda: las horas en sí ya
-- están dentro de `pago_base`.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with base as (
  select pp.id            as periodo_id,
         pp.fecha_ini, pp.fecha_fin,
         pp.estado        as periodo_estado,
         j.persona_id,
         j.fecha,
         j.horas_trabajadas as h,
         (j.estado = 'auto_cerrada_pendiente') as pend
    from periodos_planilla pp
    join jornadas j
      on j.fecha between pp.fecha_ini - 7 and pp.fecha_fin
   where coalesce(j.horas_trabajadas, 0) > 0
),
islas as (
  select b.*,
         b.fecha - (row_number() over (partition by b.periodo_id, b.persona_id
                                           order by b.fecha))::int as isla
    from base b
),
ciclos as (
  select i.*,
         ((row_number() over (partition by i.periodo_id, i.persona_id, i.isla
                                  order by i.fecha) - 1) / 7)::int as bloque
    from islas i
),
exceso as (
  select c.*,
         greatest(0, least(c.h,
           sum(c.h) over (partition by c.periodo_id, c.persona_id, c.isla, c.bloque
                              order by c.fecha) - 48)) as h_exceso
    from ciclos c
),
dentro as (
  select e.*,
         (least(e.h_exceso, 2) * 0.25 + greatest(e.h_exceso - 2, 0) * 0.35) as h_recargo
    from exceso e
   where e.fecha between e.fecha_ini and e.fecha_fin
     and e.h_exceso > 0
),
resumen as (
  select periodo_estado,
         count(*) filter (where pend)                         as dias_pend,
         coalesce(sum(h_exceso)  filter (where pend), 0)      as horas_pend,
         coalesce(sum(h_recargo) filter (where pend), 0)      as recargo_pend,
         coalesce(sum(h_recargo) filter (where not pend), 0)  as recargo_bueno
    from dentro
   group by periodo_estado
),
pendientes_totales as (
  select count(*) as dias, coalesce(sum(horas_trabajadas), 0) as horas
    from jornadas where estado = 'auto_cerrada_pendiente'
)
select 1 as orden,
       case when (select coalesce(sum(recargo_pend), 0) from resumen) = 0
            then '✓  Ningún día auto-cerrado llegó a generar recargo de sobretiempo. El mecanismo existe; no le ha pasado a nadie.'
            else '⚠  Hay recargo de sobretiempo apoyado en horas que nadie marcó. Detalle abajo.'
       end                                                as concepto,
       ''::text as periodo, ''::text as dias, ''::text as horas_recargo
union all
select 2,
       -- OJO: `jornadas.estado` es el estado de HOY, no un historial. Confirmar
       -- un día lo pasa a `revisada` y deja de contarse acá. Un cero significa
       -- «ninguno pendiente ahora», NO «nunca pasó»: eso lo responde
       -- cuantas_veces_cierra_el_cron.sql, que cuenta los marcajes.
       'Días auto-cerrados SIN revisar en este momento',
       '',
       (select dias::text  from pendientes_totales),
       (select round(horas, 2)::text || ' h trabajadas' from pendientes_totales)
union all
select 3,
       'Recargo apoyado en hora inventada',
       periodo_estado,
       dias_pend::text,
       round(recargo_pend, 2)::text || ' h de recargo (' || round(horas_pend, 2)::text || ' h de exceso)'
  from resumen
 where recargo_pend > 0
union all
select 4,
       'Recargo legítimo, para comparar',
       periodo_estado,
       '',
       round(recargo_bueno, 2)::text || ' h de recargo'
  from resumen
 where recargo_bueno > 0
order by orden, periodo, concepto;
