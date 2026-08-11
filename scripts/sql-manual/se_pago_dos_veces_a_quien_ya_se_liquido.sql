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
  select distinct on (persona_id)
         persona_id, persona, fecha_cese, monto_periodo, total as total_liquidacion,
         congelada_at as liquidacion_congelada_at
  from liquidacion_pagada
  order by persona_id, version desc
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
