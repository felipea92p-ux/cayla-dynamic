-- Amplía quién puede corregir marcajes:
--  · admin (Carlos, Felipe): cualquier persona.
--  · supervisor_sede (encargadas): SOLO personas de su misma sede base,
--    EXCEPTO su propia asistencia y EXCEPTO registros de admins/líderes.
-- Todo sigue auditado. Reemplaza el candado "solo admin".

-- ============================================================================
-- fn_verificar_corrector: devuelve el id del corrector si tiene permiso sobre
-- la persona objetivo; si no, lanza excepción. Central para las 3 funciones.
-- ============================================================================

create or replace function fn_verificar_corrector(p_persona_objetivo uuid)
returns uuid
language plpgsql stable security definer set search_path = public
as $$
declare
  v_corr_id uuid; v_corr_rol rol_usuario; v_corr_sede uuid;
  v_obj_rol rol_usuario; v_obj_sede uuid;
begin
  select id, rol, sede_base_id into v_corr_id, v_corr_rol, v_corr_sede
  from personas where auth_user_id = auth.uid();

  if v_corr_rol is null then
    raise exception 'No autorizado.';
  end if;

  -- admin y líder de DO: pueden corregir a cualquiera
  if v_corr_rol in ('admin', 'lider_do') then
    return v_corr_id;
  end if;

  -- supervisor de sede: solo su sede, ni a sí misma, ni a admins/líderes
  if v_corr_rol = 'supervisor_sede' then
    select rol, sede_base_id into v_obj_rol, v_obj_sede from personas where id = p_persona_objetivo;
    if v_obj_sede is distinct from v_corr_sede then
      raise exception 'Solo puedes corregir marcajes de tu propia sede.';
    end if;
    if p_persona_objetivo = v_corr_id then
      raise exception 'No puedes corregir tu propia asistencia. Pídeselo a un administrador.';
    end if;
    if v_obj_rol in ('admin', 'lider_do') then
      raise exception 'No puedes corregir la asistencia de un administrador.';
    end if;
    return v_corr_id;
  end if;

  raise exception 'Tu rol no permite corregir marcajes.';
end;
$$;

-- ============================================================================
-- Reemplazar las 3 funciones para usar fn_verificar_corrector
-- ============================================================================

create or replace function fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamptz, p_motivo text)
returns marcajes
language plpgsql security definer set search_path = public
as $$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes set timestamp_marca = p_nuevo_ts, estado_revision = 'revisada'
  where id = p_marcaje_id returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, p_nuevo_ts::text, v_corr, trim(p_motivo));

  return v_nuevo;
end;
$$;

create or replace function fn_agregar_marcaje(
  p_persona_id uuid, p_tipo tipo_marca, p_ts timestamptz, p_motivo text, p_motivo_otro text default null
)
returns marcajes
language plpgsql security definer set search_path = public
as $$
declare v_sede uuid; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  v_corr := fn_verificar_corrector(p_persona_id);

  select sede_base_id into v_sede from personas where id = p_persona_id;
  if v_sede is null then raise exception 'Persona no encontrada.'; end if;

  insert into marcajes (client_uuid, persona_id, sede_id, tipo, motivo_otro, timestamp_marca, origen, estado_revision)
  values (gen_random_uuid(), p_persona_id, v_sede, p_tipo, p_motivo_otro, p_ts, 'admin_correccion', 'revisada')
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_nuevo.id, p_persona_id, 'marcaje_agregado', null, p_tipo::text || ' @ ' || p_ts::text, v_corr, trim(p_motivo));

  return v_nuevo;
end;
$$;

create or replace function fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_ant marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (null, v_ant.persona_id, 'marcaje_eliminado', v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, null, v_corr, trim(p_motivo));

  delete from marcajes where id = p_marcaje_id;
end;
$$;
