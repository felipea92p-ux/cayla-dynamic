-- ############################################################################
-- ####  ¿QUÉ UMBRAL DE VARIANZA?  — SOLO LEE, NO ESCRIBE NADA             ####
-- ############################################################################
--
-- Para qué. Antes de construir el aviso de «a esta persona le cambió el neto
-- respecto al mes pasado», hay que elegir a partir de cuánto avisa. Ese número
-- no se adivina: se mide contra los dos últimos periodos ya pagados y se elige
-- el que hoy daría entre UNA y CUATRO personas.
--
-- Si un umbral da quince nombres, el aviso nace gritando y se ignora a la
-- semana. Si da cero, o está demasiado alto o el mes de referencia fue
-- anormalmente plano — y entonces hay que repetirlo contra otros dos periodos
-- cambiando `p.rn <= 2` por `p.rn <= 4` y el `b.rn = 2` por `b.rn = 3`.
--
-- ── QUÉ SE COMPARA, Y POR QUÉ NO EL TOTAL A SECAS ───────────────────────────
--
-- Se compara la BASE COMPARABLE por día de periodo:
--
--     total − bonos + descuentos − feriados − sobretiempo − descanso semanal
--
-- Cada resta tiene su motivo, y todas se miden aquí igual que se medirán en el
-- aviso, o el umbral elegido no valdría:
--
--   · **bonos y descuentos** — es la resta que más importa. La gratificación y
--     la CTS NO son conceptos de planilla: entran como movimientos (0049), y
--     `fn_grati_cts_periodo` los dispara en los periodos que contienen el
--     15-may, 15-jul, 15-nov y 15-dic (0088). Sin esta resta, el aviso marcaría
--     al equipo entero CUATRO veces al año. Y restándolos no hace falta ninguna
--     regla de calendario, que además se rompería el año en que el periodo del
--     15-dic cierre en enero — el defecto exacto que la 0088 vino a arreglar.
--   · **feriados** — van de 0 a 4 por periodo y mueven a las ~30 personas a la
--     vez; el descanso sustitutorio además los cambia de mes.
--   · **sobretiempo y descanso semanal** — son presencia binaria: un mes de
--     campaña los enciende y el siguiente los apaga.
--
-- Y se divide entre los DÍAS del periodo porque `fn_crear_periodo` admite de 20
-- a 46 días: comparar un periodo de 30 contra uno de 31 sin normalizar ya mueve
-- ~4 %, que es ruido, no hallazgo.
--
-- ── POR QUÉ VA CONTRA LA TABLA Y NO CONTRA v_planilla_pagada ────────────────
--
-- Porque esa vista resuelve el máximo de `version` del PERIODO entero, y quien
-- solo aparece en una versión anterior se vuelve invisible. Acá el
-- `distinct on … order by version desc` toma el máximo POR PERSONA.
--
-- ES UNA SOLA CONSULTA porque el SQL Editor solo muestra el último select.
-- ############################################################################

with per as (
  select id, fecha_ini, fecha_fin,
         (fecha_fin - fecha_ini + 1)                        as dias,
         row_number() over (order by fecha_fin desc)        as rn
    from periodos_planilla
   where estado = 'pagado'
),
d as (
  select distinct on (p.rn, x.persona_id)
         p.rn, p.dias, x.persona_id, x.nombre,
         (x.total - x.bonos + x.descuentos - x.monto_feriados
          - x.monto_sobretiempo - x.monto_descanso_semanal)::numeric / p.dias as base_dia
    from per p
    join planilla_pagada_detalle x on x.periodo_id = p.id
   where p.rn <= 2
   order by p.rn, x.persona_id, x.version desc
),
v as (
  select a.nombre,
         b.base_dia                                          as ant,
         a.base_dia                                          as act,
         case when b.base_dia > 0
              then abs(a.base_dia - b.base_dia) / b.base_dia end as pct,
         abs(a.base_dia - b.base_dia) * 30                   as soles_mes
    from d a
    join d b on b.persona_id = a.persona_id and b.rn = 2
   where a.rn = 1
),
umbrales (pct_umbral, piso) as (
  values (0.10, 50.0), (0.10, 100.0), (0.15, 50.0), (0.15, 100.0), (0.20, 100.0)
)
select 1 as orden,
       'personas comparables (están en los dos periodos)' as umbral,
       (select count(*) from v)::text                     as dispararian,
       coalesce((select round(max(pct) * 100, 1)::text || ' %' from v), '—') as la_mayor,
       ''::text                                           as quienes
union all
select 2,
       'pct ≥ ' || (u.pct_umbral * 100)::int::text || ' %  ·  piso S/' || u.piso::int::text,
       count(*) filter (where v.pct >= u.pct_umbral and v.soles_mes >= u.piso)::text,
       '',
       coalesce(string_agg(v.nombre, ' · ' order by v.pct desc)
                  filter (where v.pct >= u.pct_umbral and v.soles_mes >= u.piso), '—')
  -- LEFT JOIN y no CROSS JOIN: con `v` vacía, el cross join borra las filas de
  -- umbral enteras y el resultado se lee como si la consulta no hubiera corrido.
  -- Así salen igual, en cero, que es una respuesta y no un silencio.
  from umbrales u left join v on true
 group by u.pct_umbral, u.piso
order by orden, umbral;
