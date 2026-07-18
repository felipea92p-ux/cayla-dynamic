-- ============================================================================
-- Meta de cobertura por TRAMO (mañana / tarde) para operativas
-- ----------------------------------------------------------------------------
-- Felipe 2026-07-17: la meta de cobertura no es un solo número para todo el
-- día. Ej. AQP necesita 2 en la mañana pero 3 en la tarde. Se parte a las 14:15
-- (fijo por ahora, ambas sedes). `meta` pasa a ser la meta de la MAÑANA y se
-- agrega `meta_tarde`. Las encargadas (meta_encargadas) siguen siendo un piso
-- ÚNICO de todo el día (siempre debe haber N encargadas), no por tramo.
-- ============================================================================

alter table metas_cobertura add column if not exists meta_tarde int not null default 0 check (meta_tarde >= 0);

-- Arranque: la tarde hereda el valor único que había, así ningún día cambia de
-- comportamiento hasta que Felipe edite los tramos.
update metas_cobertura set meta_tarde = meta where meta_tarde = 0 and meta > 0;

-- Nueva firma (4 args): mañana + tarde. La firma vieja de 3 args se conserva
-- (setea solo la mañana) para no romper nada entre la migración y el deploy.
create or replace function fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana int, p_meta_manana int, p_meta_tarde int)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador puede definir la meta de cobertura.';
  end if;
  if p_dia_semana < 0 or p_dia_semana > 6 then raise exception 'Día de la semana inválido.'; end if;
  if p_meta_manana < 0 or p_meta_tarde < 0 then raise exception 'La meta no puede ser negativa.'; end if;
  insert into metas_cobertura (sede_id, dia_semana, meta, meta_tarde, updated_at)
  values (p_sede_id, p_dia_semana, p_meta_manana, p_meta_tarde, now())
  on conflict (sede_id, dia_semana) do update set meta = excluded.meta, meta_tarde = excluded.meta_tarde, updated_at = now();
end;
$$;

grant execute on function fn_set_meta_cobertura(uuid, int, int, int) to authenticated;
revoke execute on function fn_set_meta_cobertura(uuid, int, int, int) from public, anon;

notify pgrst, 'reload schema';
