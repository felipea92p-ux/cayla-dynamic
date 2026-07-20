-- ============================================================================
-- 0046_en_planilla.sql — Distinguir a quien NO es trabajador
-- ============================================================================
-- POR QUÉ: Catherine Pereyra es accionista, no trabajadora ("figura de forma
-- conmemorativa", palabras de Felipe 2026-07-20). Pero el sistema la trataba
-- como colaboradora: aparecía como "Sin marcar" en el Dashboard todos los días,
-- ocupaba lugar en Turnos, y acumulaba días de vacaciones por antigüedad.
--
-- Peor aún, mirando hacia adelante: la detección de faltas (Fase 2) la habría
-- contado con ~200 faltas — causal de despido varias veces sobre — sobre una
-- persona a la que nunca se le pidió marcar.
--
-- LA MARCA ES LA CAUSA, NO EL SÍNTOMA: en vez de un flag por pantalla
-- ("ocultar_en_dashboard", "no_medir_faltas"…) se guarda el hecho de negocio —
-- si está o no en planilla como trabajador — y cada pantalla deriva su
-- comportamiento de ahí. Un solo dato, una sola verdad.
--
-- NO afecta plata: sus provisiones ya eran 0, porque se calculan sobre
-- pago_base + feriados y ella no tiene horas marcadas. No hay nada que revertir.

alter table personas
  add column if not exists en_planilla boolean not null default true;

comment on column personas.en_planilla is
  'false = figura en el sistema pero NO es trabajador (p. ej. accionista). No se le mide asistencia ni faltas, no acumula beneficios y no aparece en pantallas operativas.';

-- Catherine Pereyra: accionista, no trabajadora.
update personas
set en_planilla = false
where nombres = 'Catherine' and apellidos = 'Pereyra';

-- Verificación: debe listar solo a quienes NO están en planilla.
select nombres, apellidos, rol, estado, en_planilla
from personas
where en_planilla = false
order by nombres;
