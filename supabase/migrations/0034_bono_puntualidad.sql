-- ============================================================================
-- BONO DE PUNTUALIDAD — auto-calculable por periodo de planilla
-- ----------------------------------------------------------------------------
-- Decisiones de Felipe (2026-07-15):
--   · Se mide por PERIODO de planilla (periodos_planilla), se repite cada vez
--     que se cierra uno (más o menos mensual).
--   · "Puntual" = 0 minutos de tardanza acumulados en TODOS los días trabajados
--     del periodo (tolerancia cero, "puntualidad es ser impecable"). Solo
--     cuentan personas con ≥1 día trabajado (horas_trabajadas > 0) en el
--     periodo — quien no marcó ningún día no entra ni resta.
--   · Monto FIJO por persona (S/60, ~4-5% del sueldo base de un integrante):
--     cada quien que logra cero tardanzas gana el monto completo, sin importar
--     cuántos más también lo logren — sin bolsa que repartir, sin tramos por
--     % de equipo. Se descartó el modelo de bolsa dividida (premiaba distinto
--     según cuánta gente calificaba, generaba dudas de equidad) y el de
--     base+extra de equipo (mismo problema en menor escala).
--   · Si nadie logra cero tardanzas, no se paga nada ese periodo. No se
--     acumula entre periodos.
--   · Se guarda como una fila más en movimientos_planilla (tipo='bono',
--     concepto 'Bono puntualidad', creado_por NULL para distinguirlo de los
--     manuales) — aparece solo en la misma columna "Bonos" y en el Total.
--   · Recalculable sin duplicar: cada corrida borra las filas auto-generadas
--     previas de ESE periodo antes de insertar las nuevas. Bloqueado si el
--     periodo ya está 'pagado' (mismo candado que fn_agregar_movimiento).
--   · Monto en `configuracion` (clave 'bono_puntualidad'): editable sin
--     deploy, mismo patrón que planilla_provisiones / asignacion_familiar.
-- ----------------------------------------------------------------------------
-- CORRECCIÓN el mismo día (2026-07-15, antes de marcar nada como pagado):
-- minutos_tarde queda NULL cuando no hay horario/turno con qué comparar (ej.
-- Felipe como dueño, o alguien recién ingresado sin horario aún) — la primera
-- versión trataba ese NULL como "0 tardanza" con coalesce, premiando a gente
-- que el sistema nunca pudo medir. Ahora exige que TODOS los días tengan
-- medición real (dias_sin_medir = 0), no solo que sumen 0.
-- Re-ejecutable sin peligro.
-- ============================================================================

insert into configuracion (clave, valor, descripcion) values (
  'bono_puntualidad',
  '{"monto": 60}'::jsonb,
  'Bono de puntualidad por periodo: monto fijo para cada persona que no tuvo ninguna tardanza en sus días trabajados del periodo. No depende de cuántas otras personas también lo logren.'
) on conflict (clave) do nothing;

create or replace function fn_calcular_bono_puntualidad(p_periodo_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_estado text; v_ini date; v_fin date;
  v_cfg jsonb; v_monto numeric;
  v_poblacion int; v_puntuales int;
  v_personas jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular el bono de puntualidad.';
  end if;

  select estado, fecha_ini, fecha_fin into v_estado, v_ini, v_fin
  from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;

  select valor into v_cfg from configuracion where clave = 'bono_puntualidad';
  if v_cfg is null then
    v_cfg := '{"monto": 60}'::jsonb;
  end if;
  v_monto := coalesce((v_cfg->>'monto')::numeric, 0);

  -- población y puntuales del periodo (solo días con horas_trabajadas > 0).
  -- ¡OJO! minutos_tarde queda NULL cuando ese día no hay hora esperada con la
  -- que comparar (sin turno/horario asignado) — NO es lo mismo que "llegó a
  -- tiempo". Si tratáramos NULL como 0 (coalesce sin más), cualquiera sin
  -- horario configurado (ej. el dueño, alguien recién ingresado) calificaría
  -- por default sin que el sistema haya medido nada. Por eso dias_sin_medir:
  -- si tiene AUNQUE SEA UN día sin poder medirse, no califica ese periodo.
  with por_persona as (
    select j.persona_id,
           sum(coalesce(j.minutos_tarde, 0)) as tarde_total,
           count(*) filter (where j.minutos_tarde is null) as dias_sin_medir
    from jornadas j
    where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
    group by j.persona_id
  )
  select count(*), count(*) filter (where tarde_total = 0 and dias_sin_medir = 0)
  into v_poblacion, v_puntuales
  from por_persona;

  -- recalculable sin duplicar: borra solo las filas AUTO-generadas de este periodo
  delete from movimientos_planilla
  where periodo_id = p_periodo_id
    and concepto = 'Bono puntualidad'
    and creado_por is null;

  if v_monto > 0 and v_puntuales > 0 then
    with por_persona as (
      select j.persona_id,
             sum(coalesce(j.minutos_tarde, 0)) as tarde_total,
             count(*) filter (where j.minutos_tarde is null) as dias_sin_medir
      from jornadas j
      where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
      group by j.persona_id
    )
    insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
    select p_periodo_id, pp.persona_id, 'bono', 'Bono puntualidad', v_monto, null
    from por_persona pp
    where pp.tarde_total = 0 and pp.dias_sin_medir = 0;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', pe.id, 'nombre', pe.nombres || ' ' || pe.apellidos
         ) order by pe.nombres), '[]'::jsonb)
    into v_personas
  from movimientos_planilla m
  join personas pe on pe.id = m.persona_id
  where m.periodo_id = p_periodo_id and m.concepto = 'Bono puntualidad' and m.creado_por is null;

  return jsonb_build_object(
    'poblacion', v_poblacion,
    'puntuales', v_puntuales,
    'monto_por_persona', v_monto,
    'personas', v_personas
  );
end;
$$;

grant execute on function fn_calcular_bono_puntualidad(uuid) to authenticated;
revoke execute on function fn_calcular_bono_puntualidad(uuid) from public, anon;

notify pgrst, 'reload schema';
