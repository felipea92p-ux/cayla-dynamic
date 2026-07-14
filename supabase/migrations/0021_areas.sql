-- ============================================================================
-- "Función" → Áreas de CAYLA
-- ----------------------------------------------------------------------------
-- La estructura real de CAYLA no es atencion/ejecutivo/procesos sino sus áreas:
--   OPERATIVAS DE SEDE (cuentan para la cobertura de tienda en /admin/turnos):
--     'calidad_servicio'         → Calidad & servicio al cliente
--     'taller_produccion'        → Taller y producción
--   OTRAS ÁREAS (no cuentan para cobertura):
--     'estrategia_comercial'     → Estrategia comercial
--     'desarrollo_organizacional'→ Desarrollo organizacional
--     'experiencia_marca'        → Experiencia, marca y comunidad
--     'crecimiento_expansion'    → Crecimiento y expansión
-- La columna sigue llamándose personas.funcion (renombrarla crearía superficie
-- nueva en el schema cache trabado); "Área" es solo el nombre en la UI.
-- ============================================================================

alter table personas drop constraint if exists personas_funcion_check;

-- Migrar valores viejos (todos los existentes eran 'atencion'; los otros dos por si acaso)
update personas set funcion = case funcion
  when 'atencion'  then 'calidad_servicio'
  when 'ejecutivo' then 'estrategia_comercial'
  when 'procesos'  then 'taller_produccion'
  else funcion
end
where funcion in ('atencion', 'ejecutivo', 'procesos');

alter table personas alter column funcion set default 'calidad_servicio';

alter table personas add constraint personas_funcion_check
  check (funcion in (
    'calidad_servicio', 'taller_produccion',
    'estrategia_comercial', 'desarrollo_organizacional',
    'experiencia_marca', 'crecimiento_expansion'
  ));

-- ---------------------------------------------------------------------------
-- fn_set_funcion con la lista nueva (mismo guard null-safe de 0020)
-- ---------------------------------------------------------------------------
create or replace function fn_set_funcion(p_persona_id uuid, p_funcion text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el área.';
  end if;
  if p_funcion is null or p_funcion not in (
    'calidad_servicio', 'taller_produccion',
    'estrategia_comercial', 'desarrollo_organizacional',
    'experiencia_marca', 'crecimiento_expansion'
  ) then
    raise exception 'Área inválida: %', coalesce(p_funcion, '(vacía)');
  end if;
  update personas set funcion = p_funcion where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;
end;
$$;

grant execute on function fn_set_funcion(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- fn_crear_persona con la lista nueva (mismo guard null-safe de 0020)
-- ---------------------------------------------------------------------------
create or replace function fn_crear_persona(
  p_nombres text,
  p_apellidos text,
  p_sede_base_id uuid,
  p_rol text,
  p_funcion text,
  p_email text,
  p_pin_hash text
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede crear personas.';
  end if;
  if trim(coalesce(p_nombres, '')) = '' or trim(coalesce(p_apellidos, '')) = '' then
    raise exception 'Nombres y apellidos son obligatorios.';
  end if;
  if not exists (select 1 from sedes where id = p_sede_base_id) then
    raise exception 'Sede inválida.';
  end if;
  if p_rol is null or p_rol not in ('integrante', 'supervisor_sede', 'lider_do', 'admin') then
    raise exception 'Rol inválido: %', coalesce(p_rol, '(vacío)');
  end if;
  if p_funcion is null or p_funcion not in (
    'calidad_servicio', 'taller_produccion',
    'estrategia_comercial', 'desarrollo_organizacional',
    'experiencia_marca', 'crecimiento_expansion'
  ) then
    raise exception 'Área inválida: %', coalesce(p_funcion, '(vacía)');
  end if;
  if p_pin_hash is null or p_pin_hash = '' then
    raise exception 'Falta el PIN.';
  end if;

  insert into personas (nombres, apellidos, sede_base_id, rol, funcion, email, pin_hash)
  values (
    trim(p_nombres), trim(p_apellidos), p_sede_base_id,
    p_rol::rol_usuario, p_funcion, nullif(trim(coalesce(p_email, '')), ''), p_pin_hash
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

grant execute on function fn_crear_persona(text, text, uuid, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
