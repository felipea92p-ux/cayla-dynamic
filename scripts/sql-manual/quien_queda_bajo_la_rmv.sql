-- ############################################################################
-- ####  ¿QUIÉN QUEDA BAJO LA RMV ESTE PERIODO?  — SOLO LEE                ####
-- ############################################################################
--
-- ── ESTO NO ES UN HALLAZGO NUEVO. ESTABA ESCRITO Y LE LLEGÓ LA FECHA ────────
--
-- `docs/analisis-estructura-remunerativa-2026-07-30.md`, al final de su
-- sección 9, lo dejó anotado con estas palabras:
--
--   «el divisor 6.5 × días calendario hace que una base de 1,130 se declare por
--    debajo de la RMV en meses de 31 días. Eso es una inconsistencia que un
--    cruce automático detecta sin esfuerzo, y es puramente técnica — no es una
--    decisión tuya, es un bug. Vale arreglarlo antes que cualquier otra cosa
--    de esta lista.»
--
-- El 30 de julio era hipotético: la escala arrancaba en S/1,320 y el propio
-- `docs/planilla-anexo-tecnico.md` descartaba el riesgo de RMV por eso —«hay
-- 12 % de colchón»—. El 29/07 las bases bajaron a la base declarada por rango
-- (migración 0128), y colibri quedó exactamente en la RMV. El colchón se acabó
-- ese día, y el periodo 29/07→28/08 tiene 31 días.
--
-- ⚠️ Y POR ESO ESA LÍNEA DEL ANEXO YA NO DICE LA VERDAD: sigue diciendo «hoy
-- la escala arranca en 1 320». Quien la lea va a descartar este riesgo por una
-- razón que dejó de ser cierta hace tres semanas.
--
-- ── LA ARITMÉTICA, EN UNA LÍNEA ─────────────────────────────────────────────
--
--   45 h/semana × 31 días ÷ 7 = 199.3 h        (la jornada pactada, completa)
--   199.3 × 1130 ÷ (6.5 × 31) = S/1,117.58     (lo que paga)
--   RMV = S/1,130.00                            → faltan S/12.42
--
-- No es que alguien trabaje de menos: es que el divisor `6.5 × días` crece con
-- los días del calendario y la jornada real no. En un periodo de 31 días la
-- misma jornada completa paga menos que en uno de 30.
--
-- ── ⚠️ EL DEFECTO QUE ESTA CONSULTA TUVO, Y QUE EXPLICA SU FORMA ────────────
--
-- La primera versión, el 2026-08-20, comparó las horas ACUMULADAS a mitad del
-- periodo contra la RMV del mes ENTERO. Marcó en rojo a las catorce personas
-- comparables. Ninguna estaba mal: faltaban ocho días de los treinta y uno.
--
-- Un aviso que grita por el calendario es peor que no tenerlo, y este habría
-- gritado todos los días 20 de todos los meses. Por eso ahora:
--
--   · mientras el periodo esté ABIERTO, se compara la PROYECCIÓN al cierre, y
--     se dice que es una proyección;
--   · cuando esté CERRADO, se compara lo que de verdad se pagó;
--   · y en los dos casos sale a la vista cuántos días han pasado de cuántos.
--
-- ── Y LA OTRA MITAD: LA RMV NO ES IGUAL PARA TODOS ──────────────────────────
--
-- El piso de la RMV es de la jornada COMPLETA. Quien trabaja menos de cuatro
-- horas diarias es part-time y le corresponde proporcionalmente — cobrar menos
-- no es un defecto. Por eso la consulta muestra las horas por día marcado: sin
-- ese dato, quien haga media jornada aparecería en rojo para siempre, que es
-- exactamente el falso positivo que aquí cuesta más caro.
--
-- ── LO QUE ESTA CONSULTA CUIDA DE NO HACER ──────────────────────────────────
--
-- Acusar a quien cobró menos POR BUENAS RAZONES. Quien entró a mitad de
-- periodo, cesó, estuvo de vacaciones, con descanso médico o con cualquier
-- ausencia, cobra proporcionalmente menos y eso es correcto — el pago es por
-- horas marcadas, y esa regla no se reabre. Esas filas salen SEPARADAS y
-- marcadas, nunca mezcladas con las que importan.
--
-- Es la regla de la casa: los falsos positivos son el peor error, y las
-- exclusiones se aplican ANTES de contar, no después.
--
-- LA RMV SE LEE DE `parametros_laborales`, no se escribe acá: está versionada
-- por vigencia y el día que suba, esta consulta tiene que enterarse sola.
--
-- ES UN SOLO SELECT y LA SESIÓN DE ADMIN VA DENTRO. El SQL Editor de Supabase
-- solo muestra el resultado de la última sentencia.
-- ############################################################################

with sesion as (
  select set_config('request.jwt.claim.sub',
           (select auth_user_id::text from personas
             where rol = 'admin' and auth_user_id is not null
             order by (nombres ilike '%Felipe%') desc limit 1), true) as jwt
),
per as (
  select p.id, p.fecha_ini, p.fecha_fin,
         (p.fecha_fin - p.fecha_ini) + 1                as dias,
         6.5 * ((p.fecha_fin - p.fecha_ini) + 1)        as v_base,
         -- Días YA vividos del periodo. Es la pieza que faltaba.
         (least((now() at time zone 'America/Lima')::date, p.fecha_fin)
            - p.fecha_ini) + 1                          as dias_corridos,
         ((now() at time zone 'America/Lima')::date > p.fecha_fin) as cerrado
  from periodos_planilla p, sesion
  where (now() at time zone 'America/Lima')::date between p.fecha_ini and p.fecha_fin
  order by p.fecha_ini desc
  limit 1
),
rmv as (
  select pl.valor
  from parametros_laborales pl, per
  where pl.clave = 'rmv'
    and pl.vigente_desde <= per.fecha_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= per.fecha_fin)
  order by pl.vigente_desde desc
  limit 1
),
gente as (
  select p.id, p.apellidos || ', ' || p.nombres as quien,
         coalesce(s.codigo, '?')                as sede,
         p.fecha_ingreso, p.fecha_cese, p.sueldo_base_legal
  from personas p
  left join sedes s on s.id = p.sede_base_id
  cross join sesion
  where coalesce(p.en_planilla, false)
    and not coalesce(p.sueldo_fijo, false)   -- su pago no depende de horas
),
horas as (
  select j.persona_id, coalesce(sum(j.horas_trabajadas), 0) as h,
         count(*) filter (where coalesce(j.horas_trabajadas, 0) > 0) as dias_marcados
  from jornadas j, per
  where j.fecha between per.fecha_ini and per.fecha_fin
  group by j.persona_id
),
-- Los motivos LEGÍTIMOS por los que alguien cobra menos este periodo. Se
-- calculan antes de comparar nada.
motivos as (
  select g.id,
    case
      when g.fecha_ingreso > per.fecha_ini
        then 'entró el ' || to_char(g.fecha_ingreso, 'DD/MM') || ', periodo parcial'
      when g.fecha_cese is not null and g.fecha_cese <= per.fecha_fin
        then 'cesó el ' || to_char(g.fecha_cese, 'DD/MM') || ', periodo parcial'
      when exists (
        select 1 from ausencias a
        where a.persona_id = g.id and a.anulada_at is null
          and a.fecha_inicio <= per.fecha_fin and a.fecha_fin >= per.fecha_ini)
        then (select string_agg(distinct a.tipo, ', ') from ausencias a
              where a.persona_id = g.id and a.anulada_at is null
                and a.fecha_inicio <= per.fecha_fin and a.fecha_fin >= per.fecha_ini)
             || ' en el periodo'
      else null
    end as motivo
  from gente g, per
),
calculo as (
  select g.quien, g.sede, m.motivo,
         coalesce(h.h, 0)                                         as horas,
         coalesce(h.dias_marcados, 0)                              as dias_marcados,
         (select a.salario_mensual_soles from asignaciones_salario a
           where a.persona_id = g.id
             and a.vigente_desde <= per.fecha_fin
             and (a.vigente_hasta is null or a.vigente_hasta >= per.fecha_fin)
           order by a.vigente_desde desc limit 1)                 as salario,
         g.sueldo_base_legal, per.dias, per.v_base, r.valor       as rmv,
         per.dias_corridos, per.cerrado
  from gente g
  cross join per
  cross join rmv r
  join motivos m on m.id = g.id
  left join horas h on h.persona_id = g.id
),
filas as (
  select
    c.quien, c.sede, c.motivo, c.rmv, c.dias, c.dias_corridos, c.cerrado,
    round(c.horas, 2)                                             as horas,
    c.dias_marcados,
    round(c.horas / nullif(c.dias_marcados, 0), 2)                as h_por_dia,
    c.salario,
    -- La BÁSICA tal como la arma `fn_planilla_calcular`:
    -- `horas × least(sueldo_base_legal, salario) / v_base` (ver la 0128).
    round(c.horas * least(coalesce(c.sueldo_base_legal, c.salario), c.salario)
          / c.v_base, 2)                                          as basica_hoy,
    -- LA PROYECCIÓN AL CIERRE: las mismas horas por día vividas hasta hoy,
    -- extendidas a los días que faltan. No adivina nada más — si alguien
    -- cambia de ritmo la última semana, esto no lo sabe, y por eso se dice
    -- que es una proyección y no un pronóstico.
    round(c.horas * c.dias / nullif(c.dias_corridos, 0)
          * least(coalesce(c.sueldo_base_legal, c.salario), c.salario)
          / c.v_base, 2)                                          as basica_al_cierre
  from calculo c
  where c.salario is not null
),
juzgado as (
  select f.*,
         -- Cerrado: manda lo real. Abierto: manda la proyección.
         case when f.cerrado then f.basica_hoy else f.basica_al_cierre end as a_comparar,
         -- Menos de 4 h/día es jornada parcial: la RMV le toca proporcional,
         -- así que compararlo contra el piso entero sería acusarlo de nada.
         (f.h_por_dia is not null and f.h_por_dia < 4)                     as es_parcial
  from filas f
)
select
  case
    when j.motivo is not null              then '·  no comparable'
    when j.es_parcial                      then '·  jornada parcial (<4 h/día)'
    when j.a_comparar < j.rmv and j.cerrado then '🔴 QUEDÓ BAJO LA RMV'
    when j.a_comparar < j.rmv              then '🟠 VA A QUEDAR BAJO — proyección'
    else                                        '✓  por encima'
  end                                                             as veredicto,
  j.quien, j.sede,
  j.dias_corridos || ' de ' || j.dias || ' días'                  as periodo,
  j.horas, j.dias_marcados, j.h_por_dia, j.salario,
  j.basica_hoy,
  case when j.cerrado then null else j.basica_al_cierre end       as basica_al_cierre,
  j.rmv,
  round(j.a_comparar - j.rmv, 2)                                  as contra_la_rmv,
  coalesce(j.motivo, '— periodo completo, sin ausencias')         as nota
from juzgado j
order by
  case when j.motivo is not null then 3
       when j.es_parcial then 2
       when j.a_comparar < j.rmv then 0
       else 1 end,
  j.a_comparar - j.rmv, j.quien;
