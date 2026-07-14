-- ============================================================================
-- Plan B contra el caché de PostgREST trabado (incidente Supabase jul-2026)
-- ----------------------------------------------------------------------------
-- El schema cache no expone las columnas nuevas jornadas.minutos_salida_temprana
-- (0017) ni personas.funcion (0018) vía REST, aunque existen y se calculan bien.
-- Las FUNCIONES sí se recargan en el caché. Estas RPC exponen esos datos
-- devolviendo jsonb (jsonb_agg no depende de metadata de columnas del caché).
--
-- SEGURIDAD: security definer se salta RLS, así que cada WHERE replica EXACTAMENTE
-- las policies de 0003_rls.sql (+ 0008 para el roster del terminal):
--   personas: admin/lider todo · supervisor su sede · propia · terminal su roster
--   jornadas: admin/lider todo · supervisor por sede de la JORNADA · propia · terminal su sede
-- NOTA service role: fn_rol_actual() es null sin persona → estas RPC devuelven []
-- para la service key. El espejo (api/espejo) no usa estas columnas; si algún día
-- las necesita, que vaya por REST (service role bypassea RLS).
-- Cuando Supabase destrabe el caché, nada se rompe: el frontend por RPC sigue válido.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Lectura de personas.funcion (equipo, turnos)
-- ---------------------------------------------------------------------------
create or replace function fn_personas_funciones()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('persona_id', p.id, 'funcion', p.funcion)), '[]'::jsonb)
  from personas p
  where
    -- personas_select_admin_lider
    fn_es_admin_o_lider()
    -- personas_select_supervisor
    or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
    -- personas_select_propia
    or p.auth_user_id = auth.uid()
    -- personas_select_terminal_roster (versión 0008, incluye visible_todas_sedes)
    or (p.estado = 'activo'
        and fn_sede_actual_terminal() is not null
        and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true));
$$;

grant execute on function fn_personas_funciones() to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Lectura de jornadas.minutos_salida_temprana (perfil, incidencias, horas,
--    dashboard, exportar). Devuelve solo filas con minutos > 0: todos los
--    consumidores tratan 0 y null igual ("—" / no cuenta), payload mínimo.
-- ---------------------------------------------------------------------------
create or replace function fn_jornadas_extra(p_desde date, p_hasta date, p_persona_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', j.persona_id, 'fecha', j.fecha,
           'minutos_salida_temprana', j.minutos_salida_temprana)), '[]'::jsonb)
  from jornadas j
  where j.fecha >= p_desde and j.fecha <= p_hasta
    and (p_persona_id is null or j.persona_id = p_persona_id)
    and j.minutos_salida_temprana > 0
    and (
      -- jornadas_select_admin_lider
      fn_es_admin_o_lider()
      -- jornadas_select_supervisor (por sede de la JORNADA, igual que la policy)
      or (fn_rol_actual() = 'supervisor_sede' and j.sede_id = fn_sede_actual_persona())
      -- jornadas_select_propia
      or j.persona_id = fn_persona_actual_id()
      -- jornadas_select_terminal
      or j.sede_id = fn_sede_actual_terminal()
    );
$$;

grant execute on function fn_jornadas_extra(date, date, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3) Escritura de funcion (edición en equipo). El update REST con una columna
--    que el caché no conoce rechaza la operación ENTERA (PGRST204).
-- ---------------------------------------------------------------------------
create or replace function fn_set_funcion(p_persona_id uuid, p_funcion text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  -- "is not true": para identidades sin fila en personas (terminales) el helper
  -- devuelve NULL y "if not NULL" no lanza — sería un guard falla-abierto.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la función.';
  end if;
  if p_funcion is null or p_funcion not in ('atencion', 'ejecutivo', 'procesos') then
    raise exception 'Función inválida: %', coalesce(p_funcion, '(vacía)');
  end if;
  update personas set funcion = p_funcion where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;
end;
$$;

grant execute on function fn_set_funcion(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4) Alta atómica de persona: el insert del panel incluye funcion, así que hoy
--    el alta ENTERA falla con el caché trabado. Atómico mejor que dos pasos: el
--    PIN se muestra una sola vez; no queremos una persona a medio crear.
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
  -- null-safe (ver fn_set_funcion): terminales no deben poder crear personas.
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
  if p_funcion is null or p_funcion not in ('atencion', 'ejecutivo', 'procesos') then
    raise exception 'Función inválida: %', coalesce(p_funcion, '(vacía)');
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
