-- ============================================================================
-- ¿SE REGISTRÓ DOS VECES EL PAGO DE QUIEN YA SE LIQUIDÓ? — solo LEE.
-- ============================================================================
--
-- ⚠️ El resultado lleva nombres y montos. Míralo y decide; no lo pegues entero.
--
-- ── LA PREGUNTA ─────────────────────────────────────────────────────────────
--
-- Medido el 2026-08-10: de 8 liquidaciones pagadas, SEIS pertenecen a periodos
-- que además se cerraron y se congelaron. Las dos tablas no se hablan:
-- `liquidacion_pagada` aparece en un solo archivo de todo el repositorio (la
-- 0167) y ni fn_planilla_congelar ni fn_planilla_calcular la leen jamás.
--
-- Así que la misma persona pudo quedar registrada dos veces por el mismo mes:
--   · en `liquidacion_pagada.monto_periodo`  — lo que cobró al irse
--   · en `planilla_pagada_detalle.total`     — lo que la foto del periodo dice
--                                              que se le pagó
--
-- ── LO QUE ESTA CONSULTA SÍ RESPONDE ────────────────────────────────────────
--
-- Si la foto del periodo guardó un total DISTINTO DE CERO para alguien que ya
-- tenía su liquidación congelada. Un cero significa que se usó el botón
-- «💸 Ya le pagué aparte» —el descuento deja su total en cero— o que no tenía
-- nada pendiente. Cualquier cifra por encima de cero es un segundo registro del
-- mismo trabajo.
--
-- ── LO QUE NO PUEDE RESPONDER ───────────────────────────────────────────────
--
-- Si el dinero SALIÓ dos veces del banco. Eso solo lo sabe el extracto. La foto
-- dice lo que el sistema registró como pagado, que es la mejor pista disponible
-- pero no es el movimiento bancario.
--
-- Y el orden importa al leerlo: si la foto se congeló ANTES que la liquidación,
-- la duplicidad se produjo al revés —primero el periodo, después la
-- liquidación— y quien decidió pagar la segunda vez pudo estar mirando una
-- pantalla que ya no tenía nada pendiente. La columna `que_paso_primero` lo
-- dice.
-- ============================================================================

with liq as (
  -- La ÚLTIMA versión de cada persona. Y si esa última versión es una ANULACIÓN
  -- (0251), la persona se descarta entera: ya no hay liquidación que cruzar
  -- contra la foto del periodo.
  --
  -- Sin este filtro la consulta ACUSABA JUSTO A QUIEN SE SALVÓ. Medido el
  -- 2026-08-14 sobre el camino feliz completo —congelar, anular, cerrar el mes,
  -- que es exactamente para lo que existe la 0251—: la fila de anulación tiene
  -- `monto_periodo = 0`, la foto del periodo tiene el sueldo del mes, y el
  -- veredicto salía «⚠ DOS REGISTROS del mismo mes» habiendo UNO SOLO. Encima
  -- el `order by` del final la ponía la primera de la lista.
  --
  -- El filtro va DESPUÉS del `distinct on`, nunca dentro. Metido en el `where`
  -- de adentro elegiría la última versión NO anulada —o sea, precisamente la
  -- fila errónea que la anulación vino a apagar— y el cruce seguiría acusando.
  -- Es la misma trampa que la 0251 dejó documentada en
  -- `fn_liquidaciones_del_periodo`.
  --
  -- Y no rompe el caso legítimo: si después de anular se congela la liquidación
  -- correcta, la última versión vuelve a ser un pago de verdad y la persona
  -- reaparece con sus cifras reales.
  select u.persona_id, u.persona, u.fecha_cese, u.monto_periodo,
         u.total_liquidacion, u.liquidacion_congelada_at
  from (
    select distinct on (persona_id)
           persona_id, persona, fecha_cese, monto_periodo, total as total_liquidacion,
           congelada_at as liquidacion_congelada_at, anulada
    from liquidacion_pagada
    order by persona_id, version desc
  ) u
  where u.anulada is not true
),
foto as (
  select distinct on (persona_id, periodo_id)
         persona_id, periodo_id, total as total_en_la_foto, congelada_at as foto_congelada_at, version
  from planilla_pagada_detalle
  order by persona_id, periodo_id, version desc
)
select
  l.persona,
  l.fecha_cese,
  l.monto_periodo                as cobro_al_irse,
  f.total_en_la_foto             as y_la_foto_del_periodo_dice,
  case
    when f.persona_id is null      then 'el periodo no se congeló — nada que cruzar'
    when f.total_en_la_foto = 0    then '✅ cero en la foto: no se duplicó'
    -- Esta rama la añadió la revisión del 2026-08-14, y es la otra mitad de la
    -- pregunta. Duplicar exige que el mes esté registrado DOS veces: en la foto
    -- del periodo Y en la liquidación. Mirar solo la foto acusaba a quien cobró
    -- el mes por planilla y cuya liquidación, correctamente, no volvió a
    -- cobrarlo.
    --
    -- Antes de la 0243 eso no podía pasar —`monto_periodo` siempre traía el mes
    -- entero, que es justo lo que este informe vino a cazar— y por eso la
    -- cabecera dice «cualquier cifra por encima de cero es un segundo
    -- registro». Desde la 0243/0244 `fn_liquidacion` resta lo que la foto ya
    -- pagó, así que un `monto_periodo` en cero es la PRUEBA de que no se
    -- duplicó, no un dato que se pueda ignorar. Medido el 2026-08-14: cerrar el
    -- mes y congelar después la liquidación daba «⚠ DOS REGISTROS» con
    -- `cobro_al_irse = 0.00`, y la persona había cobrado exactamente lo suyo.
    --
    -- Las filas viejas, anteriores a la 0243, siguen saliendo: son las que
    -- tienen `monto_periodo > 0`, que son las que este informe busca.
    when l.monto_periodo = 0       then '✅ la liquidación no cobró este mes: no se duplicó'
    else '⚠ DOS REGISTROS del mismo mes'
  end                            as veredicto,
  case
    when f.foto_congelada_at is null then '—'
    when f.foto_congelada_at < l.liquidacion_congelada_at
      then 'primero el periodo, después la liquidación'
    else 'primero la liquidación, después el periodo'
  end                            as que_paso_primero,
  p.fecha_ini || ' a ' || p.fecha_fin as periodo,
  l.total_liquidacion
from liq l
left join periodos_planilla p
       on l.fecha_cese between p.fecha_ini and p.fecha_fin
left join foto f
       on f.persona_id = l.persona_id and f.periodo_id = p.id
order by
  case when f.total_en_la_foto > 0 then 0 else 1 end,
  f.total_en_la_foto desc nulls last;
