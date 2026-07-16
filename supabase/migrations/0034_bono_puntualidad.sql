-- ============================================================================
-- BONO DE PUNTUALIDAD — auto-calculable por periodo de planilla
-- ----------------------------------------------------------------------------
-- Decisiones de Felipe (2026-07-15):
--   · Se mide por PERIODO de planilla (periodos_planilla), se repite cada vez
--     que se cierra uno (más o menos mensual).
--   · "Puntual" = 0 minutos de tardanza en TODOS los días MEDIDOS del periodo
--     (tolerancia cero, "puntualidad es ser impecable") + al menos 66.66% de
--     asistencia MEDIDA sobre el total de días del periodo (evita que alguien
--     con casi nada de asistencia califique por pura casualidad).
--   · Un día "cuenta" (para asistencia y para tardanza) SOLO si el sistema
--     pudo medirlo de verdad — había turno/horario real ese día y no era un
--     día de descanso. Si no se pudo medir (sin horario configurado para esa
--     fecha, horario aún no vigente, o descanso trabajado/extra), ese día se
--     IGNORA por completo: no suma ni resta, ni para asistencia ni tardanza.
--     Con esta regla, alguien SIN NINGÚN horario configurado (ej. el dueño)
--     queda excluido de forma natural — 0 días medidos ÷ días del periodo
--     nunca llega al 66.66%, sin necesidad de una excepción aparte por rol.
--   · Monto FIJO por persona (S/60, ~4-5% del sueldo base de un integrante):
--     cada quien que califica gana el monto completo, sin importar cuántos
--     más también lo logren — sin bolsa que repartir, sin tramos por % de
--     equipo (se descartaron por dudas de equidad al repartir entre pocos).
--   · Si nadie califica, no se paga nada ese periodo. No se acumula entre
--     periodos.
--   · Se guarda como una fila más en movimientos_planilla (tipo='bono',
--     concepto 'Bono puntualidad', creado_por NULL para distinguirlo de los
--     manuales) — aparece solo en la misma columna "Bonos" y en el Total.
--   · Recalculable sin duplicar: cada corrida borra las filas auto-generadas
--     previas de ESE periodo antes de insertar las nuevas. Bloqueado si el
--     periodo ya está 'pagado' (mismo candado que fn_agregar_movimiento).
--   · Monto en `configuracion` (clave 'bono_puntualidad'): editable sin
--     deploy, mismo patrón que planilla_provisiones / asignacion_familiar.
-- ----------------------------------------------------------------------------
-- HISTORIAL de correcciones el mismo día (2026-07-15, antes de marcar nada
-- como pagado):
--   v1: coalesce(minutos_tarde, 0) trataba "sin medir" como "0 tardanza" —
--       premiaba a quien el sistema nunca pudo medir (Felipe sin horario).
--   v2: exigía TODOS los días del periodo medidos — con la cobertura real de
--       horarios, prácticamente nadie calificaba nunca (rompía con días de
--       descanso trabajados, que ni siquiera deberían exigir medición).
--   v3 (esta versión): los días sin medir se IGNORAN (no descalifican por sí
--       solos) + exige 66.66% de asistencia MEDIDA sobre el periodo completo.
--       Balance entre no premiar sin datos y no bloquear por huecos parciales.
-- Re-ejecutable sin peligro.
-- ============================================================================

insert into configuracion (clave, valor, descripcion) values (
  'bono_puntualidad',
  '{"monto": 60, "asistencia_minima": 0.6666}'::jsonb,
  'Bono de puntualidad por periodo: monto fijo para cada persona con cero tardanzas en sus días MEDIDOS (con horario real, sin contar descansos trabajados ni días sin horario configurado) y al menos asistencia_minima de días medidos sobre el total del periodo.'
) on conflict (clave) do nothing;

create or replace function fn_calcular_bono_puntualidad(p_periodo_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_estado text; v_ini date; v_fin date; v_dias_periodo int;
  v_cfg jsonb; v_monto numeric; v_asistencia_min numeric;
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
  -- Mientras el periodo sigue corriendo, el 66.66% se mide contra los días que
  -- YA PASARON, no contra el periodo completo — si no, nadie podría llegar al
  -- umbral hasta el último día, aunque tenga asistencia perfecta hasta hoy.
  v_dias_periodo := least(v_fin, current_date) - v_ini + 1;

  select valor into v_cfg from configuracion where clave = 'bono_puntualidad';
  if v_cfg is null then
    v_cfg := '{"monto": 60, "asistencia_minima": 0.6666}'::jsonb;
  end if;
  v_monto := coalesce((v_cfg->>'monto')::numeric, 0);
  v_asistencia_min := coalesce((v_cfg->>'asistencia_minima')::numeric, 0.6666);

  -- Un día "cuenta" solo si minutos_tarde no es NULL — fn_recalcular_jornada ya
  -- lo deja NULL cuando no hubo hora esperada con qué comparar (sin turno/
  -- horario vigente para esa fecha, o día de descanso trabajado). Los días sin
  -- medir se ignoran por completo: no entran en dias_medidos ni en tarde_total.
  with dias_trabajo as (
    select j.persona_id, j.minutos_tarde
    from jornadas j
    where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
  ),
  por_persona as (
    select persona_id,
           count(*) filter (where minutos_tarde is not null) as dias_medidos,
           sum(minutos_tarde) filter (where minutos_tarde is not null) as tarde_total
    from dias_trabajo
    group by persona_id
  )
  select count(*), count(*) filter (
    where coalesce(tarde_total, 0) = 0
      and dias_medidos::numeric / v_dias_periodo >= v_asistencia_min
  )
  into v_poblacion, v_puntuales
  from por_persona;

  -- recalculable sin duplicar: borra solo las filas AUTO-generadas de este periodo
  delete from movimientos_planilla
  where periodo_id = p_periodo_id
    and concepto = 'Bono puntualidad'
    and creado_por is null;

  if v_monto > 0 and v_puntuales > 0 then
    with dias_trabajo as (
      select j.persona_id, j.minutos_tarde
      from jornadas j
      where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
    ),
    por_persona as (
      select persona_id,
             count(*) filter (where minutos_tarde is not null) as dias_medidos,
             sum(minutos_tarde) filter (where minutos_tarde is not null) as tarde_total
      from dias_trabajo
      group by persona_id
    )
    insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
    select p_periodo_id, pp.persona_id, 'bono', 'Bono puntualidad', v_monto, null
    from por_persona pp
    where coalesce(pp.tarde_total, 0) = 0
      and pp.dias_medidos::numeric / v_dias_periodo >= v_asistencia_min;
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
