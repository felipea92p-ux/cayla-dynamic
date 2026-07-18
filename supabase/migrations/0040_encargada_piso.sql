-- ============================================================================
-- "Cuenta como encargada de piso" — desacopla la COBERTURA del rol del sistema
-- ----------------------------------------------------------------------------
-- Problema (Felipe 2026-07-17): el rol hace dos trabajos a la vez — define qué
-- puede HACER en el sistema (planilla, sueldos) y qué CUENTA en el piso
-- (cobertura de encargadas, que hoy suma solo rol='supervisor_sede'). Janis es
-- de confianza y actúa como administradora Y encargada a la vez: necesita
-- mantener sus permisos de admin (no se le quita nada) pero además contar como
-- encargada en la cobertura de Turnos.
--
-- Solución: una marca aparte `es_encargada_piso`. No toca ningún permiso de
-- planilla ni de sueldos — solo hace que la persona sume en el conteo de
-- cobertura de encargadas, sin importar su rol. Reversible poniéndola en false.
-- ============================================================================

alter table personas add column if not exists es_encargada_piso boolean not null default false;

-- fn_personas_funciones: exponer también la marca nueva (PostgREST no expone
-- columnas nuevas por REST — por eso funcion/con_hijos ya viajan por este RPC).
create or replace function fn_personas_funciones()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos,
           'es_encargada_piso', p.es_encargada_piso)), '[]'::jsonb)
  from personas p
  where
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
    or p.auth_user_id = auth.uid()
    or (p.estado = 'activo'
        and fn_sede_actual_terminal() is not null
        and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true));
$$;

grant execute on function fn_personas_funciones() to authenticated;

-- fn_set_encargada_piso: solo admin/líder puede cambiar la marca (mismo patrón
-- que fn_set_con_hijos). No es dato sensible — solo afecta el conteo de cobertura.
create or replace function fn_set_encargada_piso(p_persona_id uuid, p_valor boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar quién cuenta como encargada de piso.';
  end if;
  update personas set es_encargada_piso = coalesce(p_valor, false) where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$$;

grant execute on function fn_set_encargada_piso(uuid, boolean) to authenticated;
revoke execute on function fn_set_encargada_piso(uuid, boolean) from public, anon;

-- Janis Revilla: admin que además es encargada de piso de TRU.
update personas set es_encargada_piso = true
where nombres = 'Janis' and apellidos = 'Revilla';

notify pgrst, 'reload schema';
