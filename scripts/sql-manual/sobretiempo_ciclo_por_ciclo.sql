-- ============================================================================
-- Sobretiempo, ciclo por ciclo — por qué la boleta paga lo que paga
-- ============================================================================
--
-- QUÉ RESPONDE
--   Incidencias avisa «Jornada excedida: 50.4 h en 7 días» y la boleta de la
--   misma persona paga sobretiempo de un solo día. Esta consulta enseña las dos
--   cuentas al lado para que se vea si la diferencia es la de diseño —ventana
--   móvil para avisar, ciclos que no se solapan para pagar— o un error.
--
-- CÓMO SE LEE
--   Una fila = un ciclo (una racha de días seguidos, cortada cada 7 días), que
--   es exactamente la unidad contra la que se mide el tope de 48 h en el pago.
--
--   horas_ciclo      lo que suma ese ciclo
--   exceso_h         lo que pasa de 48 dentro del ciclo
--   exceso_pagable   la parte de ese exceso que cae DENTRO del periodo
--   ventana_movil_7  la ventana de 7 días CALENDARIO más cargada que termina
--                    dentro del ciclo — el número que enseña Incidencias
--   entra_al_pago    si esta persona genera sobretiempo (0185/0187)
--
--   Que `ventana_movil_7` pase de 48 y `exceso_h` sea 0 NO es un error por sí
--   solo: significa que el tramo cargado cruza un descanso, y el descanso abre
--   un ciclo nuevo (Informe 027-2021-MTPE/14). Lo que sí habría que mirar es un
--   ciclo con `horas_ciclo > 48` y `exceso_h = 0`.
--
-- Es un SELECT. No escribe nada.
-- ============================================================================

with per as (
  select fecha_ini, fecha_fin
  from periodos_planilla
  where current_date between fecha_ini and fecha_fin
  order by fecha_ini desc
  limit 1
),
-- Desde 7 días antes del periodo: un ciclo que empezó en el periodo anterior
-- tiene que medirse entero. Igual que `ot_dias` en fn_planilla_calcular.
ot_dias as (
  select j.persona_id, j.fecha, j.horas_trabajadas as h
  from jornadas j, per
  where j.fecha between per.fecha_ini - 7 and per.fecha_fin
    and coalesce(j.horas_trabajadas, 0) > 0
),
ot_islas as (
  select persona_id, fecha, h,
         fecha - (row_number() over (partition by persona_id order by fecha))::int as isla
  from ot_dias
),
ot_ciclos as (
  select persona_id, fecha, h, isla,
         ((row_number() over (partition by persona_id, isla order by fecha) - 1) / 7)::int as bloque
  from ot_islas
),
ot_exceso as (
  select persona_id, fecha, h, isla, bloque,
         greatest(0, least(h, sum(h) over (partition by persona_id, isla, bloque order by fecha) - 48)) as h_exceso
  from ot_ciclos
)
select pe.nombres || ' ' || pe.apellidos                              as persona,
       sd.codigo                                                      as sede,
       min(e.fecha)                                                   as ciclo_desde,
       max(e.fecha)                                                   as ciclo_hasta,
       count(*)                                                       as dias_seguidos,
       round(sum(e.h), 2)                                             as horas_ciclo,
       round(sum(e.h_exceso), 2)                                      as exceso_h,
       round(sum(case when e.fecha between per.fecha_ini and per.fecha_fin
                      then e.h_exceso else 0 end), 2)                 as exceso_pagable,
       (select round(max(v.h7), 1)
          from (select d.fecha,
                       (select sum(x.h) from ot_dias x
                         where x.persona_id = e.persona_id
                           and x.fecha between d.fecha - 6 and d.fecha) as h7
                  from ot_dias d
                 where d.persona_id = e.persona_id
                   and d.fecha between min(e.fecha) and max(e.fecha)) v)
                                                                      as ventana_movil_7,
       (pe.en_planilla is true
        and pe.sueldo_fijo is not true
        and pe.personal_direccion is not true)                        as entra_al_pago
from ot_exceso e
join personas pe on pe.id = e.persona_id
left join sedes sd on sd.id = pe.sede_base_id
cross join per
group by pe.id, pe.nombres, pe.apellidos, sd.codigo, e.persona_id, e.isla, e.bloque,
         pe.en_planilla, pe.sueldo_fijo, pe.personal_direccion,
         per.fecha_ini, per.fecha_fin
having max(e.fecha) >= (select fecha_ini from per)
   and (sum(e.h) > 45 or sum(e.h_exceso) > 0)
order by sum(e.h_exceso) desc, sum(e.h) desc;
