-- ============================================================================
-- por_que_una_liquidacion_pagada_ya_no_cuadra.sql
-- ============================================================================
--
-- QUÉ CONTESTA
--   La pantalla de Liquidaciones dice «el cálculo ya no coincide» y muestra la
--   brecha entre lo que se pagó y lo que daría hoy. No dice POR QUÉ. Esta
--   consulta pone nombre a la parte de esa brecha que explica la 0199: el
--   feriado que un locador cobraba y dejó de cobrar.
--
-- POR QUÉ ESTE CONCEPTO Y NO OTRO
--   Hasta la 0199, `fn_planilla_calcular` era la única función de la familia que
--   no miraba `en_planilla` para los feriados: le pagaba a quien factura por
--   honorarios las horas del día feriado OTRA VEZ (la sobretasa) más el día
--   prorrateado. Toda liquidación de un locador congelada antes del 2026-08-08
--   lleva ese monto dentro de «Sueldo del periodo».
--
--   Medido contra el Postgres local el 2026-08-10, un locador sembrado con
--   20 h en el rango 28/06–25/07 y dos de sus días sobre feriado:
--       antes (0193) → pago base 131.87 + feriados 50.43 = 182.30
--       hoy   (0199) → pago base 131.87 + feriados  0.00 = 131.87
--   El pago base no se movió: la brecha entera es el feriado.
--
-- QUÉ ASUME
--   · Que la foto vigente de cada liquidación es la de mayor `version` (0167).
--   · Que el rango que se liquidó va del inicio del periodo que contiene el cese
--     a la fecha de cese, «ni un día más» (0164).
--   · Que para un locador `horas_vacaciones` es 0 — lo apagó la 0186, anterior a
--     la 0199. Por eso la reconstrucción del feriado omite ese sumando.
--
-- LO QUE NO CONTESTA
--   Si el residuo no es cero, la 0199 no lo explica todo y hay otra causa (una
--   marca corregida, una vacación cargada tarde, un cese movido, la 0186 o la
--   0177 si la foto es anterior a ellas). El residuo lo NOMBRA; no lo resuelve.
--
--   Tampoco dice qué hacer con la diferencia. Eso es decisión de negocio, igual
--   que en la 0096 y en la 0167.
--
-- CÓMO SE LEE
--   brecha            = lo pagado − lo que daría hoy  (positivo = se pagó de más)
--   feriado_locador   = lo que la 0199 apagó, reconstruido con la fórmula vieja
--   residuo           = brecha − feriado_locador
--
-- POR QUÉ EMPIEZA PRESTÁNDOSE UNA IDENTIDAD
--   El SQL Editor corre como `postgres` sin sesión de Supabase: `auth.uid()` es
--   NULL y `fn_liquidacion` —guard de la 0090— aborta con «Solo un administrador
--   o líder puede ver la liquidación de una persona». La CTE `identidad` le
--   presta el `sub` de una admin real.
--
--   Va con `is_local => true` y TODO es una sola sentencia a propósito: una
--   sentencia suelta es su propia transacción, así que el ajuste se deshace solo
--   al terminar. Nada queda pegado a la conexión del pool. Si hiciera falta
--   partirla en varias sentencias, habría que envolverlas en `begin … rollback`.
--
--   Si aun así saliera el mismo «Solo un administrador o líder…», es que ninguna
--   persona activa con rol admin o lider_do tiene `auth_user_id` cargado, y hay
--   que poner un UUID a mano en lugar de la subconsulta.
-- ============================================================================

with identidad as materialized (
  -- Se elige por rol, no por nombre: la consulta no lleva datos de nadie dentro.
  select set_config(
           'request.jwt.claims',
           json_build_object('sub', (
             select p.auth_user_id
             from personas p
             where p.rol in ('admin', 'lider_do')
               and p.auth_user_id is not null
               and p.estado = 'activo'
             order by p.created_at
             limit 1
           ))::text,
           true
         ) as claims
),
foto as (
  select distinct on (lp.persona_id) lp.*
  from liquidacion_pagada lp
  order by lp.persona_id, lp.version desc
),
rango as (
  -- El cese de HOY, no el congelado: moverlo es el motivo más frecuente de que
  -- una liquidación deje de cuadrar (0167).
  select f.persona_id,
         f.persona,
         f.congelada_at,
         f.monto_periodo as pagado_periodo,
         f.total         as pagado_total,
         p.en_planilla,
         p.sueldo_fijo,
         p.fecha_ingreso,
         coalesce(p.fecha_cese, f.fecha_cese) as cese_hoy,
         f.fecha_cese                          as cese_congelado,
         pp.fecha_ini                          as ini
  from foto f
  join personas p on p.id = f.persona_id
  left join periodos_planilla pp
    on coalesce(p.fecha_cese, f.fecha_cese) between pp.fecha_ini and pp.fecha_fin
),
hoy as (
  -- El cruce con `identidad` no filtra nada: está para que el ajuste de sesión
  -- se aplique ANTES de que se evalúe `fn_liquidacion`, que vive en la lista de
  -- selección y por tanto se calcula después del join.
  select r.persona_id,
         round(coalesce((fn_liquidacion(r.persona_id, r.cese_hoy) -> 'periodo' ->> 'monto')::numeric, 0), 2) as hoy_periodo,
         round(coalesce((fn_liquidacion(r.persona_id, r.cese_hoy) ->> 'total')::numeric, 0), 2)              as hoy_total
  from rango r
  cross join identidad i
  where i.claims is not null
),
horas_rango as (
  select r.persona_id, coalesce(sum(j.horas_trabajadas), 0) as horas
  from rango r
  left join jornadas j
    on j.persona_id = r.persona_id
   and j.fecha between r.ini and r.cese_hoy
  group by r.persona_id
),
fer_viejo as (
  -- La fórmula de feriados anterior a la 0199, literal, con `en_planilla` fuera:
  --   Σ [ horas del feriado (0 si hubo descanso sustitutorio)
  --       + 7.5 × horas del rango / base ] × salario / base
  -- donde base = 6.5 × días del rango.
  select r.persona_id,
         round(coalesce(sum(
           ((case when ds.otorgado then 0 else coalesce(j.horas_trabajadas, 0) end)
            + (case when r.sueldo_fijo then 0
                    else 7.5 * hr.horas / (6.5 * ((r.cese_hoy - r.ini) + 1)) end))
           * a.salario_mensual_soles / (6.5 * ((r.cese_hoy - r.ini) + 1))
         ) filter (where a.salario_mensual_soles is not null
                     and f.fecha >= r.fecha_ingreso), 0), 2) as monto
  from rango r
  join horas_rango hr on hr.persona_id = r.persona_id
  left join feriados f on f.fecha between r.ini and r.cese_hoy
  left join lateral (
    select a.salario_mensual_soles
    from asignaciones_salario a
    where a.persona_id = r.persona_id
      and a.vigente_desde <= f.fecha
      and (a.vigente_hasta is null or a.vigente_hasta >= f.fecha)
    order by a.vigente_desde desc
    limit 1
  ) a on true
  left join lateral (
    select true as otorgado
    from feriados_descanso_sustitutorio d
    where d.persona_id = r.persona_id and d.fecha_feriado = f.fecha and d.estado = 'OTORGADO'
    limit 1
  ) ds on true
  left join jornadas j on j.persona_id = r.persona_id and j.fecha = f.fecha
  where not r.en_planilla          -- la 0199 solo tocó a los locadores
  group by r.persona_id
)
select
  r.persona,
  -- Explícito a propósito. La primera vez que se corrió, el único modo de saber
  -- quién era locador era que `feriado_locador` saliera «0.00» (fila calculada)
  -- en vez de «0» (sin fila, porque el filtro la dejó fuera). Eso es un accidente
  -- de formato de numeric, no un dato: mañana un round de más y desaparece.
  case when r.en_planilla then 'planilla' else 'rxh' end as vinculo,
  r.cese_hoy,
  case when r.cese_hoy <> r.cese_congelado
       then 'OJO: el cese se movió — se congeló con ' || r.cese_congelado end as aviso_cese,
  r.congelada_at::date                                as congelada_el,
  r.ini                                               as periodo_desde,
  r.pagado_periodo,
  h.hoy_periodo,
  round(r.pagado_periodo - h.hoy_periodo, 2)          as brecha,
  coalesce(fv.monto, 0)                               as feriado_locador,
  round(r.pagado_periodo - h.hoy_periodo - coalesce(fv.monto, 0), 2) as residuo,
  case
    when abs(r.pagado_periodo - h.hoy_periodo) < 0.01 then 'cuadra'
    when abs(r.pagado_periodo - h.hoy_periodo - coalesce(fv.monto, 0)) < 0.02
      then 'lo explica entero la 0199 (feriado de locador)'
    when coalesce(fv.monto, 0) = 0 then 'la 0199 no interviene: buscar otra causa'
    else 'la 0199 explica parte; queda residuo'
  end                                                 as veredicto
from rango r
join hoy h        on h.persona_id = r.persona_id
left join fer_viejo fv on fv.persona_id = r.persona_id
order by abs(r.pagado_periodo - h.hoy_periodo) desc;
