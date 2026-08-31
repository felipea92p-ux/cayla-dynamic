-- ============================================================================
-- ¿A quién se le retuvo de más por cobrarle comisión sobre flujo?
-- ============================================================================
-- SOLO LEE. No cambia nada. Se puede pegar cuantas veces haga falta, antes o
-- después de la 0328 y de la 0331.
--
-- QUÉ CONTESTA, EN DOS BLOQUES
--
--   1. ESTADO DE HOY · si la 0331 de verdad entró: cuánta gente quedó en
--      comisión mixta y cuánta sigue en comisión sobre flujo. La segunda tiene
--      que decir CERO. Va primero a propósito — «ya pegué» y «se aplicó» no son
--      lo mismo, y el resto del informe se lee distinto según cuál de las dos
--      sea verdad.
--
--   2. LO RETENIDO DE MÁS · periodo por periodo y persona por persona: cuánto se
--      le retuvo de pensión y cuánto se le habría retenido en comisión MIXTA,
--      que es el esquema en el que está quien se afilió al SPP desde 2013 (Ley
--      29903). La diferencia es plata que salió de su sueldo y que su AFP no
--      cobra. Sale del periodo más reciente al más viejo, así que **el periodo
--      anterior es el primer bloque**, y cada uno cierra con su subtotal.
--
-- DE DÓNDE SALEN LOS NÚMEROS, Y POR QUÉ IMPORTA
--   De `planilla_pagada_detalle`, la foto congelada de cada pago. O sea: lo que
--   se retuvo DE VERDAD, no lo que se recalcularía hoy. Un recálculo cambiaría
--   con cualquier cosa que se haya tocado desde entonces —incluida la 0331— y la
--   pregunta acá es histórica: qué se le descontó a esta persona ese mes.
--
--   La base tampoco se recalcula: se DESPEJA del propio descuento congelado
--   (descuento ÷ tasa). Así el resultado no depende de ninguna función y no
--   puede desviarse de lo que la boleta imprimió.
--
-- CÓMO SE LEE
--   `diferencia` es lo que se le retuvo de más a esa persona en ese mes. Vale si
--   esa persona está de verdad en comisión mixta; se confirma en AFPnet o en su
--   estado de cuenta. Es el número que va a la conversación con el contador.
--
-- QUIÉN NO SALE, Y ESTÁ BIEN
--   · Quien está en ONP: no tiene comisión, su 13 % es tasa única.
--   · Quien ya se jubiló: no aporta desde la 0190.
--   · Quien no tiene régimen cargado: no se le descuenta NADA desde la 0115.
--     Es un problema distinto y también hay que mirarlo.
--   · Quien ese mes no tuvo base (descuento en cero): no se le retuvo de más,
--     así que una fila en cero solo sería ruido en una lista que se lee para
--     decidir a quién devolverle plata.
-- ============================================================================

-- ── UNA SOLA FOTO POR PERSONA Y PERIODO ─────────────────────────────────────
--
-- Un periodo reabierto y vuelto a pagar deja VARIAS filas de la misma persona, y
-- sumarlas contaría dos veces el mismo mes. Hay que quedarse con una.
--
-- Se usa `distinct on` por la última congelada, y NO `version = max(version)`,
-- que es lo que decía la primera versión de esta consulta y estaba MAL. Desde la
-- 0323 el número de versión es por (periodo, GRUPO), no por periodo: se calcula
-- con `max(version) ... where periodo_id = ? and grupo = ?`. O sea que dos filas
-- de la misma persona en el mismo periodo pero en grupos distintos —le pasa a
-- quien sale de periodo de prueba y pasa a planilla con el mes ya congelado—
-- pueden tener las dos `version = 1`, y `max(version)` las daba por buenas a las
-- dos: la persona aparecía dos veces y su diferencia se contaba doble. Al revés
-- es peor y más silencioso: con `prueba` en v2 y `planilla` en v1, el máximo es 2
-- y la fila de planilla —la que de verdad se le pagó— desaparecía del informe.
--
-- `congelada_at` desempata bien porque es cuándo se tomó la foto, que es
-- exactamente el criterio que se quiere: la última que se tomó es la que se
-- pagó. `version` y `grupo` quedan de segundo y tercer desempate para el caso de
-- dos congeladas dentro de la misma transacción, que comparten el `now()`.
--
-- Y no nombra `grupo` en un WHERE: la columna existe recién desde la 0323, y
-- hacer que la consulta falle en una base que no la tenga sería fallar por una
-- razón que no tiene nada que ver con lo que se quiere medir.
with foto as (
  select distinct on (f.periodo_id, f.persona_id)
         f.periodo_id, f.persona_id, f.nombre, f.descuento_pension, f.fila
  from planilla_pagada_detalle f
  order by f.periodo_id, f.persona_id, f.congelada_at desc, f.version desc
),
retenido as (
  select pp.fecha_ini,
         to_char(pp.fecha_ini,'DD/MM') || '–' || to_char(pp.fecha_fin,'DD/MM/YYYY') as periodo,
         f.nombre,
         f.fila->>'regimen_pension'                           as regimen,
         f.descuento_pension                                  as retenido,
         -- La base sobre la que se aplicó la tasa, despejada del propio descuento
         -- congelado. Ver la cabecera.
         f.descuento_pension / (f.fila->>'tasa_afp')::numeric  as base
  from foto f
  join periodos_planilla pp on pp.id = f.periodo_id
  where f.fila->>'regimen_pension' in ('integra','prima','profuturo','habitat')
    and coalesce((f.fila->>'tasa_afp')::numeric, 0) > 0
    and f.descuento_pension > 0
),
calculado as (
  select fecha_ini, periodo, nombre, regimen,
         round(retenido, 2)                            as se_le_retuvo,
         round(base * 0.11370, 2)                      as le_tocaba_en_mixta,
         round(retenido - round(base * 0.11370, 2), 2) as diferencia
  from retenido
)
select periodo, quien, regimen, se_le_retuvo, le_tocaba_en_mixta, diferencia
from (
  -- ── Bloque 1 · el estado de hoy ──────────────────────────────────────────
  -- Se cuenta sobre `personas.regimen_pension`, que es lo que la 0331 deja en
  -- sintonía con el tramo vigente, y no sobre `asignaciones_regimen_pension`:
  -- así una persona sin tramo —que existe— también se cuenta.
  select date '9999-12-31', 'ESTADO DE HOY', 0,
         (select count(*)::text from personas where regimen_pension like '%\_mixta')
         || ' personas están en comisión mixta',
         null::text, null::numeric, null::numeric, null::numeric

  union all

  select date '9999-12-31', 'ESTADO DE HOY', 1,
         (select count(*)::text from personas
           where regimen_pension in ('integra','prima','profuturo','habitat'))
         || ' siguen en comisión sobre flujo  ←  TIENE QUE DECIR 0',
         null, null, null, null

  union all

  -- ── Bloque 2 · una línea por persona y periodo ───────────────────────────
  select fecha_ini, periodo, 2, nombre, regimen,
         se_le_retuvo, le_tocaba_en_mixta, diferencia
  from calculado

  union all

  -- El subtotal de cada periodo, al pie de su bloque.
  select fecha_ini, periodo, 3, '── subtotal del periodo ──', null,
         sum(se_le_retuvo), sum(le_tocaba_en_mixta), sum(diferencia)
  from calculado group by fecha_ini, periodo

  union all

  -- Y el total de todo, al final del todo.
  select date '1900-01-01', 'TODOS', 4, '══ TOTAL ══', null,
         sum(se_le_retuvo), sum(le_tocaba_en_mixta), sum(diferencia)
  from calculado
) t(fecha_ini, periodo, orden_fila, quien, regimen, se_le_retuvo, le_tocaba_en_mixta, diferencia)
order by fecha_ini desc, orden_fila, diferencia desc nulls last;
