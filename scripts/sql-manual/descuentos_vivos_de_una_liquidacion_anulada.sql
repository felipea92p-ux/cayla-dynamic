-- ============================================================================
-- ¿A alguien ya le mordió el agujero de la 0253?
-- ============================================================================
-- SOLO LEE. No cambia nada. Se pega en el SQL Editor de Supabase.
--
-- QUÉ BUSCA
--   Personas cuya ÚLTIMA versión de liquidación está ANULADA (0251) y que aún
--   tienen descuentos vivos en el periodo que contiene su cese.
--
--   Anular no quita esos descuentos, y hay dos motivos muy distintos por los
--   que pueden estar ahí:
--
--     · un adelanto REAL, pagado fuera de planilla. Ese descuento es correcto
--       y tiene que quedarse. La liquidación pendiente ya sale bien.
--     · el descuento que el FRENO DEL CIERRE (0244) obligó a registrar por la
--       liquidación que después se anuló. Ese importe NO se le pagó a nadie, y
--       tampoco aparece en el total pendiente: se le sigue debiendo.
--
--   El sistema no puede distinguirlos —los dos son un `descuento` en la misma
--   tabla y el mismo periodo—, así que esta consulta los NOMBRA y la decisión
--   es de quien mira la cuenta del banco.
--
-- CÓMO SE LEE LA COLUMNA `pista`
--   `= monto_periodo de la liquidación anulada` es la señal fuerte: el freno
--   pide EXACTAMENTE ese importe y por eso coinciden al céntimo. No es prueba
--   —un adelanto puede coincidir por casualidad— pero es por donde se empieza.
--
-- SI HAY QUE DEVOLVER
--   Con el periodo ABIERTO: se borra el descuento desde Planilla y el saldo se
--   paga con el mes.
--   Con el periodo PAGADO: `fn_agregar_movimiento` lo rechaza («Este periodo ya
--   está PAGADO: reábrelo para modificarlo»). Hay que decidir entre reabrir el
--   periodo o pagarlo por otra vía dejando constancia.
-- ============================================================================

select
  p.nombres || ' ' || p.apellidos                      as persona,
  s.codigo                                             as sede,
  lp.fecha_cese,
  lp.version                                           as version_anulada,
  anu.total                                            as decia_la_anulada,
  anu.monto_periodo                                    as monto_periodo_anulado,
  left(coalesce(lp.motivo_anulacion, ''), 60)          as motivo_anulacion,
  per.fecha_ini || ' a ' || per.fecha_fin              as periodo_del_cese,
  per.estado                                           as periodo_estado,
  m.concepto,
  m.monto                                              as descuento_vivo,
  (m.created_at at time zone 'America/Lima')::date     as registrado_el,
  case
    when m.monto = anu.monto_periodo
      then '⚠ = monto_periodo de la liquidación anulada — huele a descuento del freno'
    else 'revisar a mano contra el extracto'
  end                                                  as pista
from personas p
join lateral (
  -- La ÚLTIMA versión manda, igual que en los cinco lectores de esa tabla.
  select x.* from liquidacion_pagada x
  where x.persona_id = p.id order by x.version desc limit 1
) lp on true
-- Y la versión que esa anulación anuló, para poder comparar importes.
left join liquidacion_pagada anu
  on anu.persona_id = p.id and anu.version = lp.anula_version
join periodos_planilla per
  on lp.fecha_cese between per.fecha_ini and per.fecha_fin
join movimientos_planilla m
  on m.persona_id = p.id and m.periodo_id = per.id and m.tipo = 'descuento'
left join sedes s on s.id = p.sede_base_id
where lp.anulada is true
order by per.fecha_ini desc, p.apellidos, m.created_at;

-- Si no devuelve ninguna fila: nadie tiene hoy una liquidación anulada con
-- descuentos vivos, y el agujero de la 0253 todavía no le costó dinero a nadie.
