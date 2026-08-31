-- ============================================================================
-- suspensiones_fuera_del_tope.sql
-- ============================================================================
-- QUÉ RESPONDE
--   El pendiente que la PR #64 (migración 0294) dejó explícitamente sin cerrar:
--   "Los documentos ya firmados o entregados no se revisan solos. Si alguna
--   suspensión pasada quedó fuera de los topes, hay que buscarla a mano."
--
--   Antes de la 0294, `fn_expediente_set_suspension` aceptaba cualquier número
--   de días sin mirar el Reglamento — el caso real que lo destapó fue un
--   borrador de 10 días en Arequipa (2026-08-25). Esta consulta busca si algún
--   documento YA FIRMADO O ENTREGADO —no solo borradores— quedó con un número
--   que el propio RIT no permite.
--
-- QUÉ NO HACE
--   No escribe nada. Solo lee. Se pega tal cual en el SQL Editor de Supabase.
--
-- ── LOS TRES TOPES, Y DE DÓNDE SALEN (igual que la 0294) ────────────────────
--   · NUMERAL 54.5 — ninguna suspensión pasa de TRES días, sea cual sea la
--     causal. Aplica a TODO documento de nivel 'suspension'.
--   · NUMERAL 19.2 c) — la PRIMERA suspensión por TARDANZAS es de uno a dos
--     días.
--   · NUMERAL 19.2 d) — la SEGUNDA (y siguientes) por TARDANZAS tiene que ser
--     de MAYOR duración que la anterior.
--   Los dos últimos son la escalera de IMPUNTUALIDAD y solo rigen tardanzas —
--   la escala de faltas tiene un único peldaño y su generador siempre emite
--   un día (0237), así que no se le aplica el 19.2.
--
--   ⚠ El tope es del REGLAMENTO de CAYLA, no de la ley — por eso esta consulta
--   vale para cualquier suspensión emitida en cualquier fecha, no solo las de
--   después de la 0294: el candado es nuevo, la regla que incumple no lo es.
--
-- ── CÓMO SE MIDE «LA PRIMERA» Y «LA SEGUNDA» ────────────────────────────────
--   Igual que la función: solo cuentan suspensiones ENTREGADAS (una firmada y
--   no entregada no está vigente y no agrava), de la MISMA persona y causal,
--   dentro de los 12 meses antes de la entrega del documento que se evalúa.
--   Si un documento nunca se entregó, se usa su fecha de FIRMA para ordenarlo
--   — es una aproximación razonable para auditar, no la regla exacta que usa
--   la función en vivo (que exige 'entregado').
--
-- ── QUÉ NO CUBRE ─────────────────────────────────────────────────────────────
--   Si dos suspensiones de la misma persona y causal se firmaron/entregaron el
--   mismo instante, el orden entre ellas es arbitrario. No pasó nunca en los
--   datos reales hasta ahora, pero si aparece hay que mirarlas a mano.
-- ============================================================================

with suspensiones as (
  select
    e.id,
    e.correlativo,
    e.persona_id,
    e.tipo_causal,
    e.estado,
    e.suspension_dias,
    e.suspension_desde,
    e.suspension_hasta,
    e.firmado_at,
    e.entregado_at,
    coalesce(e.entregado_at, e.firmado_at) as orden_at
  from expediente_disciplinario e
  where e.nivel = 'suspension'
    and e.estado in ('firmado', 'entregado')
),
con_previa as (
  select
    s.*,
    (
      select max(s2.suspension_dias)
      from suspensiones s2
      where s2.persona_id  = s.persona_id
        and s2.tipo_causal = 'tardanza'
        and s2.estado      = 'entregado'
        and s2.id         <> s.id
        and s2.entregado_at < s.orden_at
        and s2.entregado_at >= s.orden_at - interval '12 months'
    ) as dias_previa_tardanza
  from suspensiones s
)
select
  cp.correlativo,
  p.nombres || ' ' || p.apellidos as persona,
  cp.tipo_causal,
  cp.estado,
  cp.suspension_dias as dias,
  cp.suspension_desde,
  cp.suspension_hasta,
  cp.firmado_at::date as firmado,
  cp.entregado_at::date as entregado,
  case
    when cp.suspension_dias > 3
      then 'NUMERAL 54.5: pasa del tope de 3 días'
    when cp.tipo_causal = 'tardanza' and cp.dias_previa_tardanza is null and cp.suspension_dias > 2
      then 'NUMERAL 19.2 c): es la primera por tardanzas y pasa del tope de 2 días'
    when cp.tipo_causal = 'tardanza' and cp.dias_previa_tardanza is not null
         and cp.suspension_dias <= cp.dias_previa_tardanza
      then format('NUMERAL 19.2 d): no supera la anterior por tardanzas (%s día(s))',
                   cp.dias_previa_tardanza)
  end as defecto
from con_previa cp
join personas p on p.id = cp.persona_id
where cp.suspension_dias > 3
   or (cp.tipo_causal = 'tardanza' and cp.dias_previa_tardanza is null and cp.suspension_dias > 2)
   or (cp.tipo_causal = 'tardanza' and cp.dias_previa_tardanza is not null
       and cp.suspension_dias <= cp.dias_previa_tardanza)
order by cp.orden_at nulls last;
