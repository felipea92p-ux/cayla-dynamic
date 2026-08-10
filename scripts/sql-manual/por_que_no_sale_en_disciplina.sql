-- ============================================================================
-- por_que_no_sale_en_disciplina.sql
-- ============================================================================
-- QUÉ RESPONDE
--   Por qué la pantalla de Disciplina muestra —o no muestra— a cada persona
--   activa este mes, y qué umbral le toca HOY según el escalón en el que está.
--
--   Existe porque la pantalla y el generador del memo NO usan la misma regla:
--     · el semáforo (fn_tardanzas_resumen) lista a quien lleva 2+ en el mes y
--       rotula «amonestación» a las 3, sin mirar antecedentes;
--     · el generador (fn_expediente_generar_tardanza) escala según el último
--       memo vigente: 3 sin antecedente · 2 tras amonestación · 1 tras
--       suspensión · imputación vigente = se niega.
--   Para alguien con una suspensión vigente el umbral real es 1, y la pantalla
--   sigue diciendo 3. Esta consulta muestra los dos números lado a lado.
--
-- QUÉ NO HACE
--   No escribe nada. Solo lee. Se pega tal cual en el SQL Editor de Supabase.
--
-- CÓMO SE LEE
--   `sale_en_pantalla`  lo que hace hoy fn_tardanzas_resumen (n>=2 o sin_medir>0)
--   `umbral_real`       las tardanzas que le faltan para que el generador acepte
--   `puerta_cerrada`    el filtro que lo deja fuera del semáforo, si hay uno
--   `en_feriado`        tardanzas contadas en día feriado — hallazgo abierto nº4,
--                       son falsos positivos y no deberían sostener un memo
-- ============================================================================

with hoy as (
  select (now() at time zone 'America/Lima')::date as d
),
gente as (
  select pe.id,
         pe.nombres || ' ' || pe.apellidos as nombre,
         coalesce(s.codigo, '—')           as sede,
         pe.en_planilla, pe.sueldo_fijo
  from personas pe
  left join sedes s on s.id = pe.sede_base_id
  where pe.estado = 'activo'
),
-- El último memo de tardanza ya firmado o entregado. De él salen las dos cosas
-- que gobiernan todo: el corte (non bis in idem) y el escalón siguiente.
ultimo as (
  select distinct on (e.persona_id)
         e.persona_id,
         e.nivel,
         e.correlativo,
         e.periodo_hasta,
         (e.firmado_at at time zone 'America/Lima')::date as firmado,
         (e.firmado_at >= now() - interval '12 months')   as vigente
  from expediente_disciplinario e
  where e.tipo_causal = 'tardanza'
    and e.estado in ('firmado', 'entregado')
  order by e.persona_id, e.firmado_at desc
),
base as (
  select g.*,
         u.nivel       as ultimo_nivel,
         u.correlativo as ultimo_doc,
         u.firmado     as ultimo_firmado,
         coalesce(u.vigente, false) as antecedente_vigente,
         case when u.vigente then u.periodo_hasta end as corte
  from gente g
  left join ultimo u on u.persona_id = g.id
),
dias as (
  select b.id as pid, j.fecha, j.minutos_tarde,
         (j.minutos_tarde <= 180) as medible,
         exists (select 1 from tardanzas_justificadas tj
                  where tj.persona_id = b.id and tj.fecha = j.fecha) as perdonada,
         exists (select 1 from feriados f where f.fecha = j.fecha)   as es_feriado,
         exists (select 1 from vacaciones v
                  where v.persona_id = b.id
                    and j.fecha between v.fecha_inicio and v.fecha_fin) as de_vacaciones
  from base b
  join jornadas j on j.persona_id = b.id
  cross join hoy
  where j.fecha >= date_trunc('month', hoy.d)::date
    and j.fecha <= hoy.d
    and j.minutos_tarde is not null
    and j.minutos_tarde > 0
    and (b.corte is null or j.fecha > b.corte)   -- lo ya sancionado no vuelve
),
conteo as (
  select pid,
    count(*) filter (where medible and not perdonada)      as n,
    count(*) filter (where not medible and not perdonada)  as sin_medir,
    count(*) filter (where perdonada)                      as perdonadas,
    count(*) filter (where medible and not perdonada and (es_feriado or de_vacaciones)) as en_feriado,
    string_agg(to_char(fecha, 'DD') || ': ' || minutos_tarde || ' min', ' · ' order by fecha)
      filter (where medible and not perdonada)             as detalle
  from dias
  group by pid
)
select
  b.nombre,
  b.sede,
  coalesce(c.n, 0)         as tardanzas_del_mes,
  coalesce(c.sin_medir, 0) as sin_medir,
  coalesce(c.perdonadas, 0) as perdonadas,
  coalesce(c.en_feriado, 0) as en_feriado,
  c.detalle,

  -- El escalón en el que está, y lo que el GENERADOR exige desde ahí.
  case
    when not b.antecedente_vigente then 'sin antecedente vigente'
    else b.ultimo_nivel || ' · ' || coalesce(b.ultimo_doc, 's/n')
         || ' · ' || to_char(b.ultimo_firmado, 'DD-Mon')
  end as escalon,
  case
    when b.antecedente_vigente and b.ultimo_nivel = 'imputacion' then 'bloqueado — decide Gerencia'
    when b.antecedente_vigente and b.ultimo_nivel = 'suspension'
      then greatest(0, 1 - coalesce(c.n, 0))::text || ' → imputación de cargos'
    when b.antecedente_vigente and b.ultimo_nivel = 'amonestacion'
      then greatest(0, 2 - coalesce(c.n, 0))::text || ' → suspensión'
    else greatest(0, 3 - coalesce(c.n, 0))::text || ' → amonestación'
  end as umbral_real,

  -- Lo que hace HOY la pantalla, con su rótulo genérico.
  (b.en_planilla and not b.sueldo_fijo
     and (coalesce(c.n, 0) >= 2 or coalesce(c.sin_medir, 0) > 0)) as sale_en_pantalla,
  case
    when not b.en_planilla then 'en_planilla = false (locador: no se le mide)'
    when b.sueldo_fijo     then 'sueldo_fijo = true — INVISIBLE en el semáforo, pero el generador sí lo sanciona'
    when coalesce(c.n, 0) < 2 and coalesce(c.sin_medir, 0) = 0 then 'lleva menos de 2 este mes'
  end as puerta_cerrada

from base b
left join conteo c on c.pid = b.id
where coalesce(c.n, 0) > 0
   or coalesce(c.sin_medir, 0) > 0
   or coalesce(c.perdonadas, 0) > 0
   or b.antecedente_vigente
order by b.antecedente_vigente desc, coalesce(c.n, 0) desc, b.nombre;
