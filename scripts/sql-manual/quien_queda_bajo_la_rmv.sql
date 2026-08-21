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
         6.5 * ((p.fecha_fin - p.fecha_ini) + 1)        as v_base
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
  select j.persona_id, coalesce(sum(j.horas_trabajadas), 0) as h
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
         (select a.salario_mensual_soles from asignaciones_salario a
           where a.persona_id = g.id
             and a.vigente_desde <= per.fecha_fin
             and (a.vigente_hasta is null or a.vigente_hasta >= per.fecha_fin)
           order by a.vigente_desde desc limit 1)                 as salario,
         g.sueldo_base_legal, per.dias, per.v_base, r.valor       as rmv
  from gente g
  cross join per
  cross join rmv r
  join motivos m on m.id = g.id
  left join horas h on h.persona_id = g.id
),
filas as (
  select
    c.quien, c.sede,
    round(c.horas, 2)                                             as horas,
    c.salario,
    -- La BÁSICA que se declara, tal como la arma `fn_planilla_calcular`:
    -- `horas × least(sueldo_base_legal, salario) / v_base` (ver la 0128).
    round(c.horas * least(coalesce(c.sueldo_base_legal, c.salario), c.salario)
          / c.v_base, 2)                                          as basica_declarada,
    c.rmv,
    round(c.horas * least(coalesce(c.sueldo_base_legal, c.salario), c.salario)
          / c.v_base - c.rmv, 2)                                  as contra_la_rmv,
    c.motivo,
    case when c.motivo is not null then 2 else 1 end              as bloque
  from calculo c
  where c.salario is not null
)
select
  case when f.bloque = 1 and f.contra_la_rmv < 0 then '🔴 BAJO LA RMV'
       when f.bloque = 1                        then '✓  por encima'
       else '·  no comparable' end                                as veredicto,
  f.quien, f.sede, f.horas, f.salario, f.basica_declarada, f.rmv,
  f.contra_la_rmv,
  coalesce(f.motivo, '— periodo completo, sin ausencias')         as por_que_no_comparable
from filas f
order by
  -- Primero quien queda por debajo y ES comparable. Lo demás es contexto.
  case when f.bloque = 1 and f.contra_la_rmv < 0 then 0
       when f.bloque = 1 then 1 else 2 end,
  f.contra_la_rmv, f.quien;
