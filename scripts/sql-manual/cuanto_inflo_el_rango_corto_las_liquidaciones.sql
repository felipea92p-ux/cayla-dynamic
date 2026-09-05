-- ============================================================================
-- ¿CUÁNTO INFLÓ EL RANGO CORTO CADA LIQUIDACIÓN? — solo LEE. SQL Editor.
-- ============================================================================
--
-- ⚠️ ESTE RESULTADO LLEVA NOMBRES Y MONTOS DE PERSONAS. Es para mirarlo y
--    decidir, no para pegarlo en una conversación. Si hace falta compartirlo,
--    comparte el conteo y la suma, no las filas.
--
-- ── QUÉ MIDE ────────────────────────────────────────────────────────────────
--
-- `fn_planilla_calcular(ini, fin, periodo)` reparte el sueldo mensual entre los
-- días del rango que se le pase:
--
--     v_dias := (p_fin - p_ini) + 1;
--     v_base := 6.5 * v_dias;
--     pago   := horas * salario / v_base;
--
-- La pantalla de Planilla siempre le pasa el PERIODO COMPLETO. `fn_liquidacion`
-- (0164) le pasa del inicio del periodo a la FECHA DE CESE — «ni un día más»,
-- dice su comentario. Con menos días, el divisor se encoge y el mismo trabajo
-- se paga más.
--
-- Medido contra Postgres el 2026-08-10, misma persona y mismas 44.44 horas:
--
--     rango 29/07–28/08 (31 días)  →  pago base S/ 249.44
--     rango 29/07–07/08 (10 días)  →  pago base S/ 773.27
--
-- El encabezado de la 0164 dice, como suposición: «fn_planilla_calcular calcula
-- un rango PARCIAL correctamente. Lo hace desde siempre: es lo que usa la
-- pantalla de planilla con el periodo en curso». Esa suposición es FALSA — la
-- pantalla nunca le pasa un trozo, así que ese camino no se ejercitó nunca.
--
-- ── QUÉ COMPARA ─────────────────────────────────────────────────────────────
--
--   pagado_por_el_periodo   lo que se congeló y se transfirió (monto_periodo)
--   con_el_periodo_completo lo que habría dado el MISMO cálculo pidiéndole a la
--                           planilla el periodo entero, que es lo que hace la
--                           pantalla. Las horas de la persona se acaban en su
--                           cese igual, así que no suma días que no trabajó.
--
-- ⚠️ La segunda columna es una MEDICIÓN, no una sentencia. Dice cuánto habría
--    salido por el otro camino; cuál de los dos es el correcto es una decisión
--    que se toma mirando estos números, no antes.
--
-- ── LO QUE NO PUEDE VER ─────────────────────────────────────────────────────
--
-- Recalcula con los datos de HOY. Si desde el cese alguien corrigió un marcaje,
-- cargó una vacación o cambió un salario, parte de la diferencia viene de ahí y
-- no del rango. La columna `dias_del_tramo` ayuda a distinguirlo: el inflado por
-- rango es proporcional a `dias_del_periodo / dias_del_tramo`, así que si la
-- diferencia no sigue esa proporción, hay algo más.
-- ============================================================================

-- fn_planilla_calcular exige sesión de admin y el SQL Editor no la tiene.
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
  true);

with ultima as (
  -- Una liquidación puede tener varias versiones; manda la última. Y si esa
  -- última es una ANULACIÓN (0251), la persona se descarta: sus cinco montos
  -- están en cero por CHECK, así que entraba con `pagado_por_el_periodo = 0` y
  -- metía una diferencia NEGATIVA —medido: −483.87— en un informe cuyo único
  -- oficio es medir cuánto INFLÓ el divisor viejo. No acusaba a nadie (el
  -- `order by … desc` la manda al fondo), pero es ruido dentro de una suma.
  --
  -- El filtro va DESPUÉS del `distinct on`, nunca dentro: metido en el `where`
  -- de adentro elegiría la última versión NO anulada, o sea la fila errónea que
  -- la anulación vino a apagar, que es justo la que no hay que medir.
  select u.persona_id, u.persona, u.fecha_cese, u.monto_periodo,
         u.total, u.version, u.congelada_at
  from (
    select distinct on (persona_id)
           persona_id, persona, fecha_cese, monto_periodo, total, version,
           congelada_at, anulada
    from liquidacion_pagada
    order by persona_id, version desc
  ) u
  where u.anulada is not true
),
con_periodo as (
  select u.*,
         p.id        as periodo_id,
         p.fecha_ini,
         p.fecha_fin,
         p.estado    as estado_periodo,
         p.pagado_at,
         (u.fecha_cese - p.fecha_ini) + 1        as dias_del_tramo,
         (p.fecha_fin - p.fecha_ini) + 1         as dias_del_periodo
  from ultima u
  left join periodos_planilla p
         on u.fecha_cese between p.fecha_ini and p.fecha_fin
),
recalculado as (
  select c.*,
         (
           select round((f.value->>'total')::numeric, 2)
           from jsonb_array_elements(
                  fn_planilla_calcular(c.fecha_ini, c.fecha_fin, c.periodo_id) -> 'filas'
                ) f
           where (f.value->>'persona_id')::uuid = c.persona_id
         ) as con_el_periodo_completo
  from con_periodo c
  where c.periodo_id is not null
)
select
  persona,
  fecha_cese,
  dias_del_tramo    as dias_trabajados_del_periodo,
  dias_del_periodo,
  monto_periodo     as pagado_por_el_periodo,
  con_el_periodo_completo,
  round(monto_periodo - coalesce(con_el_periodo_completo, 0), 2) as diferencia,
  case
    when con_el_periodo_completo is null or con_el_periodo_completo = 0 then '—'
    else round(monto_periodo / con_el_periodo_completo, 2)::text || ' ×'
  end as cuantas_veces_mas,
  round(dias_del_periodo::numeric / nullif(dias_del_tramo, 0), 2)::text || ' ×'
                    as proporcion_esperada_si_es_solo_el_rango,
  total             as total_de_la_liquidacion,
  -- Si además el periodo se marcó pagado, ese mismo dinero quedó registrado
  -- dos veces: en la liquidación y en la foto del periodo.
  case when pagado_at is not null then '⚠ el periodo también está pagado' else 'periodo no pagado' end
                    as ojo_con_esto
from recalculado
order by (monto_periodo - coalesce(con_el_periodo_completo, 0)) desc;
