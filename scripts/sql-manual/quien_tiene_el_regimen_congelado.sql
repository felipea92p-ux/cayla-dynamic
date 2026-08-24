-- ############################################################################
-- ####  ¿A QUIÉN NO LE LLEGÓ SU CAMBIO DE RÉGIMEN?  — SOLO LEE            ####
-- ############################################################################
--
-- Para qué. Desde la 0261 el descuento de pensión lo decide el TRAMO vigente de
-- `asignaciones_regimen_pension`, y `personas.regimen_pension` solo se usa como
-- respaldo para quien no tenga tramo. Pero la pantalla de datos personales
-- siguió llamando a `fn_set_regimen_pension`, que escribe únicamente la columna.
--
-- Resultado: a quien YA tenía tramo (todo el que tenía régimen el día que se
-- pegó la 0261), cambiarle el régimen desde la pantalla NO le movió el
-- descuento. La ficha decía una cosa y la boleta hacía otra.
--
-- Esta consulta dice si eso le pasó a alguien de verdad, y a quién. Se corre
-- ANTES de pegar la 0277 — no depende de ella.
--
-- Se lee así:
--   ⚠ = la ficha y el descuento no coinciden. Hay que decidir desde cuándo rige
--       el bueno y aplicarlo con fn_cambiar_regimen_pension (0277).
--   ✓ = nadie divergente: el defecto existía, pero no alcanzó a nadie.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- Va contra las TABLAS y no contra una función de diagnóstico, porque una
-- función con guard de admin devuelve cero filas en el Editor — y cero filas se
-- lee igual que «no hay nadie».
-- ############################################################################

with divergentes as (
  select p.id,
         (p.nombres || ' ' || p.apellidos)             as persona,
         p.estado,
         coalesce(p.regimen_pension, '(sin régimen)')  as dice_la_ficha,
         coalesce(h.regimen, '(sin régimen)')          as paga_la_planilla,
         h.vigente_desde                               as tramo_desde
    from personas p
    join asignaciones_regimen_pension h
      on h.persona_id = p.id
     and h.vigente_hasta is null
   where coalesce(p.regimen_pension, '∅') <> coalesce(h.regimen, '∅')
),
-- Quien no tiene NINGÚN tramo depende del respaldo: ahí la pantalla vieja sí
-- funcionaba, pero conviene verlos — son los que la 0277 empieza a fichar.
sin_tramo as (
  select count(*) as n
    from personas p
   where p.estado = 'activo'
     and not exists (select 1 from asignaciones_regimen_pension a where a.persona_id = p.id)
)
select 1 as orden,
       case when (select count(*) from divergentes) = 0
            then '✓  Nadie divergente: la ficha y el descuento coinciden en todo el equipo.'
            else '⚠  ' || (select count(*) from divergentes)::text
                 || ' persona(s) con la ficha diciendo un régimen y el descuento haciendo otro.'
       end as persona,
       ''::text  as estado,
       ''::text  as dice_la_ficha,
       ''::text  as paga_la_planilla,
       null::date as tramo_desde
union all
select 2,
       'Sin ningún tramo (dependen del respaldo, la pantalla vieja sí les funcionaba): '
         || (select n from sin_tramo)::text || ' activa(s).',
       '', '', '', null::date
union all
select 3, persona, estado, dice_la_ficha, paga_la_planilla, tramo_desde
  from divergentes
order by orden, persona;
