-- ============================================================================
-- ¿A quién se le retuvo de más por cobrarle comisión sobre flujo?
-- ============================================================================
-- SOLO LEE. No cambia nada. Se puede pegar en el SQL Editor cuantas veces haga
-- falta, antes o después de la 0328 y de la 0330.
--
-- QUÉ CONTESTA
--   Periodo por periodo y persona por persona: cuánto se le retuvo de pensión y
--   cuánto se le habría retenido en comisión MIXTA — que es el esquema en el que
--   está quien se afilió al SPP desde 2013 (Ley 29903). La diferencia es plata
--   que salió de su sueldo y que su AFP no cobra.
--
--   Sale ordenado por periodo, del más reciente al más viejo, así que **el
--   periodo anterior es el primer bloque**. Cada bloque cierra con su subtotal y
--   al final está el total de todo.
--
-- DE DÓNDE SALEN LOS NÚMEROS, Y POR QUÉ IMPORTA
--   De `planilla_pagada_detalle`, la foto congelada de cada pago. O sea: lo que
--   se retuvo DE VERDAD, no lo que se recalcularía hoy. Un recálculo cambiaría
--   con cualquier cosa que se haya tocado desde entonces —incluida la 0330— y la
--   pregunta acá es histórica.
--
--   La base tampoco se recalcula: se DESPEJA del propio descuento congelado
--   (descuento ÷ tasa). Así el resultado no depende de ninguna función y no puede
--   desviarse de lo que la boleta imprimió.
--
-- CÓMO SE LEE
--   `diferencia` es lo que se le retuvo de más a esa persona en ese mes. Vale si
--   esa persona está de verdad en comisión mixta; se confirma en AFPnet o en su
--   estado de cuenta.
--
-- QUIÉN NO SALE, Y ESTÁ BIEN
--   Quien está en ONP (no tiene comisión), quien ya se jubiló (no aporta) y quien
--   no tiene régimen cargado — a esa persona no se le descuenta nada desde la
--   0115, que es un problema distinto y también hay que mirarlo.
-- ============================================================================

with retenido as (
  select f.periodo_id,
         pp.fecha_ini,
         to_char(pp.fecha_ini,'DD/MM') || '–' || to_char(pp.fecha_fin,'DD/MM/YYYY') as periodo,
         f.nombre,
         f.fila->>'regimen_pension'                            as regimen,
         f.descuento_pension                                   as retenido,
         -- La base sobre la que se aplicó la tasa, despejada del propio descuento
         -- congelado. Ver la cabecera.
         f.descuento_pension / (f.fila->>'tasa_afp')::numeric   as base
  from planilla_pagada_detalle f
  join periodos_planilla pp on pp.id = f.periodo_id
  where f.fila->>'regimen_pension' in ('integra','prima','profuturo','habitat')
    and coalesce((f.fila->>'tasa_afp')::numeric, 0) > 0
    -- Solo la última versión de cada foto: un periodo reabierto y vuelto a pagar
    -- tiene más de una, y sumarlas contaría dos veces el mismo mes.
    -- Se agrupa por periodo y persona, sin nombrar `grupo`: una persona tiene un
    -- solo vínculo, así que aparece en un solo grupo de ese periodo, y la columna
    -- `grupo` recién existe desde la 0323 — nombrarla haría que esta consulta
    -- fallara en una base que todavía no la tenga, por una razón que no tiene
    -- nada que ver con lo que quiere medir.
    and f.version = (select max(f2.version)
                       from planilla_pagada_detalle f2
                      where f2.periodo_id = f.periodo_id
                        and f2.persona_id = f.persona_id)
),
calculado as (
  select fecha_ini, periodo, nombre, regimen,
         round(retenido, 2)                          as se_le_retuvo,
         round(base * 0.11370, 2)                    as le_tocaba_en_mixta,
         round(retenido - round(base * 0.11370, 2), 2) as diferencia
  from retenido
)
select periodo, orden_fila, quien, regimen, se_le_retuvo, le_tocaba_en_mixta, diferencia
from (
  -- Una línea por persona y periodo.
  select fecha_ini, periodo, 1 as orden_fila, nombre as quien, regimen,
         se_le_retuvo, le_tocaba_en_mixta, diferencia
  from calculado

  union all

  -- El subtotal de cada periodo, al pie de su bloque.
  select fecha_ini, periodo, 2, '── subtotal del periodo ──', null,
         sum(se_le_retuvo), sum(le_tocaba_en_mixta), sum(diferencia)
  from calculado group by fecha_ini, periodo

  union all

  -- Y el total de todo, al final del todo.
  select date '1900-01-01', 'TODOS', 3, '══ TOTAL ══', null,
         sum(se_le_retuvo), sum(le_tocaba_en_mixta), sum(diferencia)
  from calculado
) t
order by fecha_ini desc, orden_fila, diferencia desc nulls last;
