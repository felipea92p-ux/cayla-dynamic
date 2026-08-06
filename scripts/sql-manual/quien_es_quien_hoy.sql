-- ============================================================================
-- ¿Quién es quién hoy? — para mirar los mismos datos antes de decidir
-- ============================================================================
-- Solo LEE. No cambia nada. Pégala en el SQL Editor.
--
-- Responde tres preguntas que hoy se contestan de memoria:
--   · quién está activa y quién no, y con qué vínculo
--   · a quién le falta la fecha de cese estando inactiva (el sistema no la ve)
--   · quién no tiene NINGÚN rastro de trabajo (candidata a ocultar, nunca a borrar)
-- ============================================================================

select
  p.nombres || ' ' || p.apellidos            as persona,
  p.estado,
  p.tipo_vinculo,
  p.en_planilla,
  coalesce(s.codigo, '—')                    as sede,
  p.fecha_ingreso,
  p.fecha_cese,

  -- Lo que decide si el sistema puede o no calcularle algo.
  case
    when p.estado = 'inactivo' and p.fecha_cese is null
      then '⚠ inactiva SIN fecha de cese: invisible para liquidaciones'
    when p.estado = 'activo' and p.tipo_vinculo = 'rxh'
      then 'locadora activa: no cobra movilidad, educación ni beneficios'
    when p.estado = 'activo'
      then 'activa en planilla'
    else 'cesada, con su fecha'
  end                                        as situacion,

  -- Rastro real de trabajo. Quien no tiene NADA de esto nunca generó historial,
  -- así que ocultarla no rompe ningún reporte pasado.
  (select count(*) from jornadas j where j.persona_id = p.id)            as dias_con_jornada,
  (select count(*) from marcajes m where m.persona_id = p.id
     and m.anulada_at is null)                                            as marcajes,
  (select count(*) from movimientos_planilla mp where mp.persona_id = p.id) as movimientos,
  (select count(*) from planilla_pagada_detalle d where d.persona_id = p.id) as veces_en_una_planilla_pagada

from personas p
left join sedes s on s.id = p.sede_base_id
order by
  (p.estado = 'inactivo' and p.fecha_cese is null) desc,   -- primero lo que hay que arreglar
  p.estado,
  p.apellidos;
