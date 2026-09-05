-- ============================================================================
-- a_quien_le_aparece_el_9_por_ciento.sql
-- ============================================================================
-- CÓRRELA ANTES DE PEGAR LA 0372, en el SQL Editor de producción. Solo lee.
--
-- QUÉ RESPONDE
--   A quién le va a aparecer, de golpe, una bonificación extraordinaria (9%,
--   Ley 30334) PENDIENTE en /admin/provisiones cuando la 0372 entre — porque su
--   gratificación se registró por separado y el 9% nunca se registró.
--
--   Si devuelve CERO FILAS, la 0372 no mueve ningún número de la pantalla: solo
--   cierra el hueco hacia adelante. Si devuelve filas, esas son personas a las
--   que probablemente se les deba ese 9%, y conviene revisarlas ANTES de que la
--   pantalla empiece a pedirlo — no después.
--
-- POR QUÉ SOLO MIRA DESDE EL 2026-09-03
--   Antes de ese día la opción separada no existía: el 9% se sumaba a mano
--   dentro del monto de «Gratificación». Esas gratificaciones ya lo llevan
--   dentro y NO se reclaman hacia atrás — es la decisión de Felipe del
--   2026-09-03 al pegar la 0346. La 0372 respeta esa decisión, así que esta
--   consulta mira exactamente lo mismo que va a mirar la función.
--
-- CÓMO LEER EL RESULTADO
--   nueve_estimado — 9% del monto que se registró como gratificación. Es una
--   ESTIMACIÓN para dimensionar: la pantalla calcula el 9% sobre lo DEVENGADO
--   del semestre, no sobre lo que se registró, así que las dos cifras coinciden
--   cuando la gratificación se pagó completa y difieren cuando fue parcial.
--
-- POR QUÉ SOLO A QUIEN SIGUE ACTIVO Y DEVENGA ALGO
--   `fn_provisiones` solo calcula para `p.estado = 'activo' and
--   fn_devenga_algo(p.id)` — quien cesó, o a quien la ley no le da derecho a
--   beneficios (un RxH, por ejemplo), no aparece en /admin/provisiones sin
--   importar qué diga su historial de movimientos. Sin este mismo filtro acá,
--   esta consulta podía señalar a alguien que ya cesó o que nunca tuvo
--   derecho al 9%, y la pantalla real jamás se lo iba a pedir — ruido que le
--   hace perder tiempo a quien revisa la lista antes de pegar. Que a alguien
--   así cesado se le siga debiendo el 9%, si corresponde, se resuelve en su
--   liquidación (`fn_grati_trunca_bruta`), no acá.
-- ============================================================================

with grati_suelta as (
  select
    m.persona_id,
    p.nombres || ' ' || p.apellidos                    as persona,
    s.codigo                                           as sede,
    pp.fecha_ini,
    pp.fecha_fin,
    -- Qué ventana cubre este periodo: la grati de julio o la de diciembre.
    case
      when make_date(extract(year from pp.fecha_fin)::int, 7, 15)
             between pp.fecha_ini and pp.fecha_fin then 'julio (ene-jun)'
      when make_date(extract(year from pp.fecha_fin)::int, 12, 15)
             between pp.fecha_ini and pp.fecha_fin then 'diciembre (jul-dic)'
    end                                                as ventana,
    m.monto                                            as grati_registrada,
    round(m.monto * 0.09, 2)                           as nueve_estimado,
    (m.created_at at time zone 'America/Lima')::date    as se_registro_el
  from movimientos_planilla m
  join periodos_planilla pp on pp.id = m.periodo_id
  join personas p           on p.id  = m.persona_id
  join sedes s              on s.id  = p.sede_base_id
  where m.categoria = 'gratificacion'
    -- Mismo filtro que fn_provisiones: quien cesó o no devenga nada no
    -- aparece en la pantalla, así que tampoco debe aparecer acá.
    and p.estado = 'activo'
    and fn_devenga_algo(p.id)
    -- Solo lo registrado desde que existe la opción separada (0346).
    and (m.created_at at time zone 'America/Lima')::date >= date '2026-09-03'
    -- Y solo si NO hay un movimiento del 9% en el mismo periodo.
    and not exists (
      select 1
      from movimientos_planilla b
      where b.persona_id = m.persona_id
        and b.periodo_id = m.periodo_id
        and b.categoria  = 'bonificacion_extraordinaria'
    )
)
select persona, sede, ventana, fecha_ini, fecha_fin,
       grati_registrada, nueve_estimado, se_registro_el
from grati_suelta
where ventana is not null      -- descarta periodos que no cubren una fecha de pago legal
order by sede, persona;

-- ── Y el resumen de una línea, para saber si hay que mirar o no ────────────
-- Reutiliza la MISMA definición de arriba (misma condición, mismo filtro de
-- ventana) para que este número nunca pueda discrepar de la lista de detalle.
with grati_suelta as (
  select
    m.monto,
    case
      when make_date(extract(year from pp.fecha_fin)::int, 7, 15)
             between pp.fecha_ini and pp.fecha_fin then 'julio (ene-jun)'
      when make_date(extract(year from pp.fecha_fin)::int, 12, 15)
             between pp.fecha_ini and pp.fecha_fin then 'diciembre (jul-dic)'
    end as ventana
  from movimientos_planilla m
  join periodos_planilla pp on pp.id = m.periodo_id
  join personas p           on p.id  = m.persona_id
  where m.categoria = 'gratificacion'
    and p.estado = 'activo'
    and fn_devenga_algo(p.id)
    and (m.created_at at time zone 'America/Lima')::date >= date '2026-09-03'
    and not exists (
      select 1 from movimientos_planilla b
      where b.persona_id = m.persona_id
        and b.periodo_id = m.periodo_id
        and b.categoria  = 'bonificacion_extraordinaria'
    )
)
select count(*)                                  as personas_con_9pct_sin_registrar,
       coalesce(sum(round(monto * 0.09, 2)), 0)   as soles_estimados
from grati_suelta
where ventana is not null;
