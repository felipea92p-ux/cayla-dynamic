-- ============================================================================
-- ¿A quién se le retuvo de más por cobrarle comisión sobre flujo?
-- ============================================================================
-- SOLO LEE. No cambia nada. Se puede pegar en el SQL Editor cuantas veces haga
-- falta, también antes de aplicar la 0328.
--
-- QUÉ CONTESTA
--   Persona por persona: cuánto se le retuvo de pensión en los meses YA PAGADOS
--   y cuánto se le habría retenido si su AFP le cobrara comisión MIXTA — que es
--   el esquema en el que está quien se afilió al SPP desde 2013 (Ley 29903).
--   La diferencia es plata que salió de su sueldo y que su AFP no cobra.
--
-- DE DÓNDE SALEN LOS NÚMEROS, Y POR QUÉ IMPORTA
--   De `planilla_pagada_detalle`, la foto congelada de cada pago. O sea: lo que
--   se retuvo DE VERDAD, no lo que se recalcularía hoy. Un recálculo cambiaría
--   con cualquier cosa que se haya tocado desde entonces, y la pregunta acá es
--   histórica.
--
--   La base no se recalcula tampoco: se DESPEJA del propio descuento congelado
--   (descuento ÷ tasa). Así el resultado no depende de ninguna función y no
--   puede desviarse de lo que la boleta imprimió.
--
-- CÓMO SE LEE
--   `diferencia` es el techo del problema para esa persona, no el problema: vale
--   solo si esa persona está de verdad en comisión mixta. Eso se confirma en
--   AFPnet o en su estado de cuenta, una por una. La última fila es el total.
--
-- QUIÉN NO SALE, Y ESTÁ BIEN
--   Quien está en ONP (no tiene comisión), quien ya se jubiló (no aporta) y
--   quien no tiene régimen cargado (a esa persona no se le descuenta nada desde
--   la 0115, que es un problema distinto y también hay que mirarlo).
-- ============================================================================

with retenido as (
  select f.persona_id,
         f.nombre,
         f.fila->>'regimen_pension'                    as regimen,
         (f.fila->>'tasa_afp')::numeric                as tasa,
         f.descuento_pension                           as retenido,
         -- La base sobre la que se aplicó la tasa, despejada del propio
         -- descuento congelado. Ver la cabecera.
         f.descuento_pension / (f.fila->>'tasa_afp')::numeric as base
  from planilla_pagada_detalle f
  where f.fila->>'regimen_pension' in ('integra','prima','profuturo','habitat')
    and coalesce((f.fila->>'tasa_afp')::numeric, 0) > 0
    -- Solo la última versión de cada foto: un periodo reabierto y vuelto a
    -- pagar tiene más de una, y sumarlas contaría dos veces el mismo mes.
    and f.version = (select max(f2.version)
                       from planilla_pagada_detalle f2
                      where f2.periodo_id = f.periodo_id
                        and f2.persona_id = f.persona_id
                        and f2.grupo = f.grupo)
),
por_persona as (
  select nombre,
         min(regimen)                                     as regimen,
         count(*)                                         as meses,
         round(sum(retenido), 2)                          as se_le_retuvo,
         round(sum(round(base * 0.11370, 2)), 2)          as le_tocaba_en_mixta,
         round(sum(retenido - round(base * 0.11370, 2)), 2) as diferencia
  from retenido
  group by nombre
)
select *
from (
  select 1 as orden, nombre, regimen, meses, se_le_retuvo, le_tocaba_en_mixta, diferencia
  from por_persona
  union all
  select 2, '── TOTAL ──', null, sum(meses), sum(se_le_retuvo), sum(le_tocaba_en_mixta), sum(diferencia)
  from por_persona
) t
order by orden, diferencia desc nulls last;
