-- ============================================================================
-- El botón Justificar vuelve a funcionar
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE
--   Que `fn_set_justificacion` —la que llama el botón «Justificar» de la
--   pantalla de Incidencias— vuelva a guardar la justificación, registrándola
--   donde hoy viven todas las ausencias.
--
-- QUÉ ESTABA ROTO
--   La 0101 unificó las ausencias en un solo lugar: convirtió
--   `justificaciones_asistencia` de TABLA en VISTA sobre `ausencias`, con un
--   trigger `instead of insert`. Actualizó `fn_quitar_justificacion` para leer
--   de `ausencias`, pero `fn_set_justificacion` se quedó como la escribió la
--   0051, haciendo un upsert contra la vista:
--
--       insert into justificaciones_asistencia (...)
--       on conflict (persona_id, fecha) do update ...
--
--   Una vista no tiene índices únicos, así que Postgres rechaza la operación
--   entera con 42P10 «there is no unique or exclusion constraint matching the
--   ON CONFLICT specification». Resultado en producción: QUITAR una
--   justificación funcionaba y PONERLA no, desde que se aplicó la 0101.
--
--   El fallo no se notó antes porque la 0101 sí creó una función nueva y sana
--   (`fn_justificar_falta`), pero la pantalla de Incidencias nunca dejó de
--   llamar a la vieja.
--
-- QUÉ ASUME
--   · `fn_registrar_ausencia` existe (0101) y trae su propio control de
--     permisos (`fn_verificar_corrector`), su candado de planilla pagada y la
--     validación del catálogo `tipos_ausencia`. No se duplica nada de eso aquí.
--   · Los códigos `permiso_personal`, `cumpleanos`, `estudios` y `otro` están
--     activos en `tipos_ausencia`.
--
-- POR QUÉ SE ELIGIÓ ASÍ
--   1. Se arregla la función, no la pantalla. `fn_set_justificacion` está
--      concedida a `authenticated` desde la 0051 y puede tener otros llamantes;
--      cambiar solo el React dejaría la puerta rota abierta para el siguiente.
--
--   2. Se conserva el comportamiento de REEMPLAZAR. El upsert original permitía
--      volver a justificar un día ya justificado y cambiarle el motivo. Como
--      `ausencias` tiene el EXCLUDE `ausencias_sin_solape`, registrar encima
--      fallaría; por eso primero se anula la ausencia vigente de ese día (igual
--      que hace `fn_quitar_justificacion`) y luego se registra la nueva. Sin
--      esto, corregir un motivo mal puesto sería imposible desde la pantalla.
--
--   3. `descanso_medico` NO se traduce en silencio. Es el único motivo del
--      desplegable que PAGA, y desde la 0101 exige documento (profesional,
--      colegiatura y fecha) que el diálogo rápido de Incidencias no pide.
--      Mandarlo a `salud` —el tipo sin documento— haría que a quien entregó su
--      certificado se le dejara de pagar el día sin que nadie lo viera. Se
--      prefiere un mensaje que explique y derive a Ausencias: el sistema avisa,
--      la persona decide. (Decisión de Felipe, 01-ago-2026.)
--
--   4. Las vacaciones no se tocan. `fn_quitar_justificacion` de la 0101 excluye
--      `tipo <> 'vacaciones'` al buscar qué anular, y aquí se usa el mismo
--      criterio: justificar un día no debe borrar unas vacaciones aprobadas.
--
-- CÓMO SE REVIERTE
--   Volviendo a crear `fn_set_justificacion` con el cuerpo de la 0051. No hace
--   falta tocar datos: esta migración no crea ni borra tablas ni columnas, solo
--   reemplaza el cuerpo de una función. Revertir devuelve el error 42P10.
--
-- Idempotente: `create or replace`. Se puede pegar dos veces sin peligro.
-- ============================================================================

create or replace function fn_set_justificacion(
  p_persona_id uuid, p_fecha date, p_motivo text, p_observacion text default null
)
returns void
language plpgsql security definer set search_path = public
as $fn$
declare
  v_tipo text;
  v_id uuid;
begin
  if p_motivo is null or p_motivo not in
       ('permiso_concedido', 'cumpleanos', 'estudios', 'descanso_medico', 'otro') then
    raise exception 'Motivo inválido.';
  end if;

  if p_motivo = 'otro' and (p_observacion is null or length(trim(p_observacion)) < 3) then
    raise exception 'Para el motivo "otro" la observación es obligatoria.';
  end if;

  -- El descanso médico paga, y por eso exige el documento que este diálogo no
  -- pide. No se degrada a «Descanso por salud» a espaldas de nadie: eso
  -- convertiría un día pagado en uno no pagado sin que se note.
  if p_motivo = 'descanso_medico' then
    raise exception 'El descanso médico se paga, así que necesita su documento (profesional o institución, colegiatura y fecha). Regístralo en la pantalla de Ausencias. Si no hay documento, ahí mismo existe «Descanso por salud», que no cuenta como falta pero no paga.';
  end if;

  -- `permiso_concedido` es el nombre viejo del motivo; en el catálogo unificado
  -- de la 0101 se llama `permiso_personal`.
  v_tipo := case p_motivo when 'permiso_concedido' then 'permiso_personal' else p_motivo end;

  -- Reemplazar, no acumular: se retira la justificación vigente de ese día
  -- antes de poner la nueva. Las vacaciones quedan fuera a propósito.
  select a.id into v_id
    from ausencias a
   where a.persona_id = p_persona_id
     and a.tipo <> 'vacaciones'
     and a.anulada_at is null
     and p_fecha between a.fecha_inicio and a.fecha_fin
   limit 1;

  if v_id is not null then
    perform fn_anular_ausencia(v_id, 'Reemplazada al cambiar el motivo desde Incidencias');
  end if;

  -- El permiso, el candado de planilla pagada y la validación del tipo viven
  -- dentro de fn_registrar_ausencia. Aquí no se repiten.
  perform fn_registrar_ausencia(
    p_persona_id, v_tipo, p_fecha, p_fecha,
    nullif(trim(coalesce(p_observacion, '')), '')
  );
end;
$fn$;

grant execute on function fn_set_justificacion(uuid, date, text, text) to authenticated;
revoke execute on function fn_set_justificacion(uuid, date, text, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (124, 'justificar_vuelve_a_funcionar')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
