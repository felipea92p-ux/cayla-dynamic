-- ============================================================================
-- 0441_ausencia_avisa_dias_con_jornada.sql
-- ============================================================================
-- QUÉ PROMETE
--   Una función de solo lectura que dice, para una persona y un rango de
--   fechas, en qué días ya hay una jornada con horas trabajadas. Sirve para
--   que el formulario de Ausencias avise ANTES de guardar cuando el rango
--   elegido se cruza con marcajes reales — hoy ese cruce solo se descubre
--   tres pasos después, como `dias_solapados` en la boleta del mes (0286).
--
-- QUÉ ASUME
--   Nada nuevo: no toca ninguna tabla ni función existente, ni cambia ninguna
--   regla de pago. Usa el MISMO criterio que ya usa `dias_solapados` en
--   fn_planilla_calcular (0286): un día "trabajado" es uno con fila en
--   `jornadas` con horas_trabajadas > 0 — se mira `jornadas`, no `marcajes`
--   directo, porque `jornadas` es el resumen ya reconciliado (entradas,
--   salidas, marcas offline) que mantiene un trigger, y es exactamente lo que
--   la 0286 ya decidió que cuenta como "vino a trabajar".
--
-- POR QUÉ SOLO AVISA, NUNCA BLOQUEA
--   La 0286 ya decidió que fichar durante un descanso a veces es intencional
--   y legítimo: ese día se paga como trabajado y la ausencia no se consume.
--   Bloquear el registro aquí contradiría esa decisión ya tomada — por eso
--   esta función solo informa (el formulario decide cómo mostrarlo); quien
--   registra sigue decidiendo igual que decide hoy con cualquier otro aviso
--   de esta pantalla ("para mirar, no para sancionar").
--
-- VISIBILIDAD
--   La misma que fn_registrar_ausencia: quien puede registrar una ausencia
--   para esa persona (fn_verificar_corrector — admin, líder DO, o la
--   encargada de su propia sede) puede ver si ya tiene marcajes en el rango.
--   No se expone nada que esa persona no pudiera ya registrar o consultar.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_ausencia_dias_con_jornada(uuid, date, date);
-- ============================================================================

create or replace function fn_ausencia_dias_con_jornada(p_persona_id uuid, p_fecha_inicio date, p_fecha_fin date)
returns table (fecha date, horas_trabajadas numeric)
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  v_editor uuid;
begin
  -- Mismo candado de permiso que fn_registrar_ausencia: si no se puede
  -- registrar la ausencia, tampoco se puede ver si hay marcajes.
  v_editor := fn_verificar_corrector(p_persona_id);

  return query
    select j.fecha, j.horas_trabajadas
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha between p_fecha_inicio and p_fecha_fin
      and j.horas_trabajadas is not null
      and j.horas_trabajadas > 0
    order by j.fecha;
end;
$fn$;

comment on function fn_ausencia_dias_con_jornada(uuid, date, date) is
  'Días con jornada trabajada (horas_trabajadas > 0) de una persona dentro de un rango — mismo criterio que dias_solapados en fn_planilla_calcular (0286). Solo lectura; avisa en el formulario de Ausencias antes de registrar, nunca bloquea.';

grant execute on function fn_ausencia_dias_con_jornada(uuid, date, date) to authenticated;
revoke execute on function fn_ausencia_dias_con_jornada(uuid, date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (441, 'ausencia_avisa_dias_con_jornada')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select count(*) as fn_creada from pg_proc where proname = 'fn_ausencia_dias_con_jornada';
