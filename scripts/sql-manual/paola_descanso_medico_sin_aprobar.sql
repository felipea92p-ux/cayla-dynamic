-- ============================================================================
-- Diagnóstico (solo lectura) — Paola Cahuana: dos días de descanso médico
-- (06 y 07/07/2026) siguen "pendiente de aprobar" y ella ya cesó y ya está
-- liquidada. Por la 0306, un descanso médico sin `aprobada_at` no entra al
-- cálculo de planilla ni de liquidación — hay que confirmar con datos reales
-- si esos dos días se pagaron por algún otro lado antes de tocar nada.
-- No escribe: solo consulta.
-- ============================================================================

-- 1) Las ausencias en cuestión: confirmar que siguen sin aprobar y sin anular.
select a.id, a.tipo, a.fecha_inicio, a.fecha_fin, a.aprobada_at, a.anulada_at,
       a.doc_profesional, a.doc_colegiatura, a.doc_fecha,
       p.nombres, p.apellidos, p.fecha_cese, p.estado, p.sede_base_id
  from ausencias a
  join personas p on p.id = a.persona_id
 where p.nombres ilike '%Paola%' and p.apellidos ilike '%Cahuana%'
   and a.tipo = 'descanso_medico'
 order by a.fecha_inicio;

-- 2) El periodo de planilla que contiene esas fechas, y si ya se cerró/pagó.
select * from periodos_planilla
 where '2026-07-06' between fecha_ini and fecha_fin
    or '2026-07-07' between fecha_ini and fecha_fin;

-- 3) Lo que esa persona cobró en la FOTO de ese periodo (si ya está pagado) —
--    para ver si esos dos días aparecen ahí por otra vía.
select d.persona_id, d.periodo_id, d.total, d.version, d.congelada_at
  from planilla_pagada_detalle d
  join personas p on p.id = d.persona_id
 where p.nombres ilike '%Paola%' and p.apellidos ilike '%Cahuana%'
 order by d.version desc;

-- 4) Su liquidación pagada, si existe — para ver la fecha de cese real y el
--    periodo que cubrió.
select lp.*, p.nombres, p.apellidos
  from liquidacion_pagada lp
  join personas p on p.id = lp.persona_id
 where p.nombres ilike '%Paola%' and p.apellidos ilike '%Cahuana%'
   and lp.anulada is not true;

-- 5) Cuánto valdrían esos 2 días SI se aprobaran — `fn_planilla_calcular`
--    filtra por `aprobada_at is not null` (0306), así que llamarla tal cual
--    solo repetiría el cero actual. Para ver el monto hipotético sin arriesgar
--    nada, se aprueba DENTRO de una transacción y se revierte — el mismo
--    patrón que este repo ya exige para auditar cualquier cálculo de plata
--    antes de proponerlo (ver CLAUDE.md, "se audita empíricamente").
--    Pégalo TODO junto: el ROLLBACK deshace el UPDATE, no queda nada escrito.
begin;

update ausencias set aprobada_at = now()
 where persona_id = (select id from personas
                       where nombres ilike '%Paola%' and apellidos ilike '%Cahuana%'
                       limit 1)
   and tipo = 'descanso_medico'
   and fecha_inicio in ('2026-07-06', '2026-07-07')
   and aprobada_at is null;

select value ->> 'persona_id' as persona_id,
       value ->> 'monto_descanso_medico' as monto_descanso_medico_si_se_aprueba,
       value ->> 'dias_descanso_medico_pagados' as dias_que_pagaria
  from jsonb_array_elements(
    (select fn_planilla_calcular(p.fecha_ini, p.fecha_fin, p.id) -> 'filas'
       from periodos_planilla p
      where '2026-07-06' between p.fecha_ini and p.fecha_fin
      limit 1)
  ) as t(value)
 where (value ->> 'persona_id')::uuid = (
   select id from personas
    where nombres ilike '%Paola%' and apellidos ilike '%Cahuana%'
    limit 1
 );

rollback;
