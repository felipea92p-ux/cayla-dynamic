-- ============================================================================
-- Elegir quién firma (sin PIN — decisión de Felipe: prioriza velocidad sobre
-- la verificación extra; el indicador de sesión en el nav ya mitiga el riesgo
-- de firmar sin darse cuenta con la cuenta de otra persona).
-- ----------------------------------------------------------------------------
-- fn_expediente_firmar ahora acepta un firmante explícito (opcional). Si no se
-- pasa, usa la sesión actual (comportamiento idéntico al de antes). Si se pasa
-- uno distinto, se valida que esa persona tenga rol admin/lider_do — no se
-- puede firmar "como" alguien sin ese rol, evita elegir a un integrante o
-- encargada de sede por error desde el desplegable.
-- ============================================================================

-- ── Lista de quiénes pueden aparecer en el desplegable de firmante ───────────
create or replace function fn_firmantes_disponibles()
returns table (id uuid, nombre text)
language sql stable security definer set search_path = public as $$
  select p.id, p.nombres || ' ' || p.apellidos as nombre
  from personas p
  where p.rol in ('admin', 'lider_do') and p.estado = 'activo'
    and fn_es_admin_o_lider()  -- solo quien ya puede firmar ve la lista
  order by p.nombres;
$$;
grant execute on function fn_firmantes_disponibles() to authenticated;
revoke execute on function fn_firmantes_disponibles() from public, anon;

-- ── Firmar: borrador → firmado, con firmante explícito opcional ──────────────
create or replace function fn_expediente_firmar(p_id uuid, p_firmante_id uuid default null)
returns text language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype; v_corr text; v_firmante uuid; v_rol_firmante text;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then
    raise exception 'Solo se puede firmar un borrador (estado actual: %).', r.estado;
  end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then
    raise exception 'Sin permiso para firmar un documento de nivel %.', r.nivel;
  end if;

  v_firmante := coalesce(p_firmante_id, fn_persona_actual_id());

  if p_firmante_id is not null then
    select rol into v_rol_firmante from personas where id = p_firmante_id;
    if v_rol_firmante is null then raise exception 'El firmante elegido no existe.'; end if;
    if v_rol_firmante not in ('admin', 'lider_do') then
      raise exception 'Solo un administrador o líder puede figurar como firmante.';
    end if;
  end if;

  v_corr := fn_expediente_correlativo(fn_expediente_doc_code(r.tipo_causal, r.nivel));
  update expediente_disciplinario
    set estado = 'firmado', firmante_id = v_firmante, firmado_at = now(), correlativo = v_corr
    where id = p_id;
  return v_corr;
end;
$$;

grant execute on function fn_expediente_firmar(uuid, uuid) to authenticated;
revoke execute on function fn_expediente_firmar(uuid, uuid) from public, anon;

notify pgrst, 'reload schema';
