-- ============================================================================
-- Meta de encargadas mínimas por sede/día
-- ----------------------------------------------------------------------------
-- Pedido de Felipe 2026-07-17: además de la meta general de cobertura, asegurar
-- un mínimo de personas con rol supervisor_sede ("encargadas") programadas
-- cada día — varía por sede, editable igual que la meta general.
-- ============================================================================

alter table metas_cobertura add column if not exists meta_encargadas int not null default 0 check (meta_encargadas >= 0);

-- ----------------------------------------------------------------------------
-- fn_set_meta_encargadas — mismo patrón que fn_set_meta_cobertura, guard
-- corregido (fn_es_admin_o_lider() ya usa "is not true", no falla abierto
-- para identidades sin fila en personas como sí le pasaba al guard viejo).
-- ----------------------------------------------------------------------------
create or replace function fn_set_meta_encargadas(p_sede_id uuid, p_dia_semana int, p_meta int)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede definir la meta de encargadas.';
  end if;
  if p_dia_semana < 0 or p_dia_semana > 6 then raise exception 'Día de la semana inválido.'; end if;
  if p_meta < 0 then raise exception 'La meta no puede ser negativa.'; end if;
  insert into metas_cobertura (sede_id, dia_semana, meta, meta_encargadas, updated_at)
  values (p_sede_id, p_dia_semana, 0, p_meta, now())
  on conflict (sede_id, dia_semana) do update set meta_encargadas = excluded.meta_encargadas, updated_at = now();
end;
$$;

grant execute on function fn_set_meta_encargadas(uuid, int, int) to authenticated;
revoke execute on function fn_set_meta_encargadas(uuid, int, int) from public, anon;

-- ----------------------------------------------------------------------------
-- Hallazgo aparte de la auditoría 2026-07-15 (docs/revision-2026-07-15/), no
-- aplicado hasta ahora: fn_set_meta_cobertura usaba fn_rol_actual() NOT IN
-- (...), que falla ABIERTO para identidades sin fila en personas (NULL NOT IN
-- (...) es NULL, no dispara la excepción) — cualquiera sin sesión podía
-- sobrescribir la meta de cobertura. Se corrige al patrón "is not true" que
-- ya usa el resto del código (fn_es_admin_o_lider ya lo hace bien). Cambio de
-- una sola línea, sin impacto de UX — se aprovecha estar tocando este mismo
-- archivo para la meta de encargadas.
-- ----------------------------------------------------------------------------
create or replace function fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana int, p_meta int)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador puede definir la meta de cobertura.';
  end if;
  if p_dia_semana < 0 or p_dia_semana > 6 then raise exception 'Día de la semana inválido.'; end if;
  if p_meta < 0 then raise exception 'La meta no puede ser negativa.'; end if;
  insert into metas_cobertura (sede_id, dia_semana, meta, updated_at)
  values (p_sede_id, p_dia_semana, p_meta, now())
  on conflict (sede_id, dia_semana) do update set meta = excluded.meta, updated_at = now();
end;
$$;

grant execute on function fn_set_meta_cobertura(uuid, int, int) to authenticated;
revoke execute on function fn_set_meta_cobertura(uuid, int, int) from public, anon;

notify pgrst, 'reload schema';
