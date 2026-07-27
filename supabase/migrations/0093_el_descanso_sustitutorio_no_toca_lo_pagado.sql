-- ============================================================================
-- 0093 — El descanso sustitutorio tampoco toca una planilla ya pagada
-- ----------------------------------------------------------------------------
-- PROMETE: que otorgar o quitar un descanso sustitutorio no pueda cambiar el
--   total de un periodo de planilla que ya se pagó.
--
-- ASUME: 0069 a 0072 (feriados y descanso sustitutorio) y la 0092.
--
-- EL DEFECTO. fn_planilla_calcular lee `feriados_descanso_sustitutorio` en vivo:
--   cuando el estado es OTORGADO, anula la sobretasa de ese feriado. Pero
--   fn_otorgar_descanso_sustitutorio no consultaba `periodos_planilla` en
--   ninguna línea, así que se podía otorgar un descanso por un feriado que cae
--   dentro de un periodo ya cerrado y pagado. El total bajaba, la boleta
--   reimpresa dejaba de coincidir con lo que se transfirió, y el periodo seguía
--   marcado como pagado. Medido en laboratorio: S/65 menos, sin reapertura y
--   sin ningún registro de que algo hubiera cambiado.
--
--   Era la ÚNICA puerta de su familia sin candado. Ya lo tenían
--   fn_agregar_marcaje, fn_anular_marcaje, fn_corregir_marca,
--   fn_eliminar_marcaje, fn_reactivar_marcaje, fn_confirmar_auto_cierre,
--   fn_set_vacaciones, fn_set_feriado, fn_quitar_feriado, fn_set_salario,
--   fn_set_fecha_ingreso y fn_set_objetivos — doce funciones con el mismo
--   mensaje, y estas dos sin él.
--
-- SE MIRAN LAS DOS FECHAS. El feriado y el día compensatorio pueden caer en
--   periodos distintos, y basta con que cualquiera de los dos esté cerrado para
--   no tocar nada.
--
-- Y QUITARLO TAMBIÉN CUENTA: devuelve la sobretasa y SUBE el total, así que
--   necesita el mismo candado. Antes ni siquiera comprobaba que la fila
--   existiera: borrar un id inexistente no daba error.
--
-- CÓMO SE REVIERTE: restaurar las dos desde la 0072.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_otorgar_descanso_sustitutorio(p_persona_id uuid, p_fecha_feriado date, p_fecha_descanso date, p_estado text DEFAULT 'PENDIENTE'::text, p_acta_ref text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar un descanso sustitutorio.';
  end if;

  if p_estado not in ('PENDIENTE', 'OTORGADO', 'NO_OTORGADO') then
    raise exception 'Estado inválido: %. Debe ser PENDIENTE, OTORGADO o NO_OTORGADO.', p_estado;
  end if;

  if not exists (select 1 from feriados where fecha = p_fecha_feriado) then
    raise exception 'El % no está registrado como feriado.', to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  -- El mismo candado que ya tienen las otras once funciones que mueven dinero.
  -- Otorgar o quitar un descanso sustitutorio cambia el TOTAL del periodo donde
  -- cae el feriado: cuando está OTORGADO, fn_planilla_calcular anula la sobretasa.
  -- Sin esto se podía bajar una planilla ya cerrada y pagada sin reabrirla y sin
  -- dejar rastro; medido en laboratorio: S/65 menos en un periodo pagado.
  --
  -- Se mira el feriado Y el día compensatorio: los dos pueden caer en periodos
  -- distintos, y cualquiera de los dos cerrado basta para no tocar nada.
  perform 1 from periodos_planilla
   where p_fecha_feriado between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha_feriado between fecha_ini and fecha_fin
  ) then
    raise exception 'Ese feriado (%) cae en un periodo ya PAGADO: cambiar su descanso sustitutorio alteraría una planilla ya pagada. Reabre el periodo primero.',
      to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha_descanso between fecha_ini and fecha_fin
  ) then
    raise exception 'El día compensatorio (%) cae en un periodo ya PAGADO. Reabre el periodo primero.',
      to_char(p_fecha_descanso, 'DD/MM/YYYY');
  end if;

  -- ⇩ CAMBIO 0071: la exigencia de horas marcadas aplica SOLO a OTORGADO.
  -- PENDIENTE es el acuerdo previo; exigirle horas haría imposible registrarlo
  -- antes del feriado, que es justo cuando se acuerda.
  if p_estado = 'OTORGADO' and not exists (
    select 1 from jornadas j
    where j.persona_id = p_persona_id and j.fecha = p_fecha_feriado
      and coalesce(j.horas_trabajadas, 0) > 0
  ) then
    raise exception 'No se puede dar por OTORGADO: esa persona no tiene horas marcadas el %. Déjalo en PENDIENTE hasta que el feriado se haya trabajado.',
      to_char(p_fecha_feriado, 'DD/MM/YYYY');
  end if;

  insert into feriados_descanso_sustitutorio (
    persona_id, fecha_feriado, fecha_descanso_sustitutorio, estado, acta_ref, otorgado_por
  )
  values (
    p_persona_id, p_fecha_feriado, p_fecha_descanso, p_estado, nullif(trim(p_acta_ref), ''), fn_persona_actual_id()
  )
  on conflict (persona_id, fecha_feriado) do update set
    fecha_descanso_sustitutorio = excluded.fecha_descanso_sustitutorio,
    estado = excluded.estado,
    acta_ref = excluded.acta_ref,
    otorgado_por = excluded.otorgado_por,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_quitar_descanso_sustitutorio(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fila feriados_descanso_sustitutorio;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar un descanso sustitutorio.';
  end if;

  select * into v_fila from feriados_descanso_sustitutorio where id = p_id for update;
  if not found then
    raise exception 'Ese descanso sustitutorio ya no existe.';
  end if;

  -- Quitarlo devuelve la sobretasa del feriado y sube el total del periodo, así
  -- que hace falta el mismo candado que para otorgarlo.
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_fila.fecha_feriado  between fecha_ini and fecha_fin
        or v_fila.fecha_descanso_sustitutorio between fecha_ini and fecha_fin)
  ) then
    raise exception 'Ese descanso sustitutorio toca un periodo ya PAGADO: quitarlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  delete from feriados_descanso_sustitutorio where id = p_id;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (93, 'el_descanso_sustitutorio_no_toca_lo_pagado')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
