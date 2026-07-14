-- ============================================================================
-- Parche de la 0022 (hallazgos de la revisión adversarial)
-- ----------------------------------------------------------------------------
-- 1) fn_guardar_area: 'calidad_servicio' (área base del sistema) no puede dejar
--    de ser operativa vía upsert — misma protección que ya tenía fn_area_activa.
-- 2) Postgres da EXECUTE a PUBLIC por defecto en funciones nuevas: el rol anon
--    podía INVOCAR las RPC. Los guards internos ya protegen los datos (devuelven
--    vacío o lanzan excepción), pero fn_areas no tiene guard y exponía el
--    catálogo de áreas a anónimos. Se revoca PUBLIC/anon en toda la familia
--    (defensa en profundidad); authenticated conserva su grant explícito.
-- Re-ejecutable sin peligro.
-- ============================================================================

create or replace function fn_guardar_area(
  p_codigo text,
  p_nombre text,
  p_operativa boolean,
  p_orden int default null
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar áreas.';
  end if;
  if p_codigo is null or p_codigo !~ '^[a-z0-9_]{2,40}$' then
    raise exception 'Código inválido (solo minúsculas, números y _): %', coalesce(p_codigo, '(vacío)');
  end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre del área es obligatorio.';
  end if;
  -- El área base del sistema debe seguir contando para la cobertura.
  if p_codigo = 'calidad_servicio' and coalesce(p_operativa, false) is not true then
    raise exception 'Calidad & servicio es el área base del sistema y debe seguir siendo operativa de sede.';
  end if;

  insert into areas (codigo, nombre, operativa, orden)
  values (p_codigo, trim(p_nombre), coalesce(p_operativa, false), coalesce(p_orden, 100))
  on conflict (codigo) do update set
    nombre = excluded.nombre,
    operativa = excluded.operativa,
    orden = coalesce(p_orden, areas.orden);
end;
$$;

grant execute on function fn_guardar_area(text, text, boolean, int) to authenticated;

-- Revocar el EXECUTE implícito de PUBLIC/anon en toda la familia de RPCs del
-- panel (authenticated mantiene su grant explícito; el terminal es authenticated).
revoke execute on function fn_areas() from public, anon;
revoke execute on function fn_guardar_area(text, text, boolean, int) from public, anon;
revoke execute on function fn_area_activa(text, boolean) from public, anon;
revoke execute on function fn_set_funcion(uuid, text) from public, anon;
revoke execute on function fn_crear_persona(text, text, uuid, text, text, text, text) from public, anon;
revoke execute on function fn_personas_funciones() from public, anon;
revoke execute on function fn_jornadas_extra(date, date, uuid) from public, anon;
revoke execute on function fn_set_salario(uuid, text, numeric, date, text) from public, anon;
revoke execute on function fn_salarios_vigentes() from public, anon;
revoke execute on function fn_historial_salario(uuid) from public, anon;

notify pgrst, 'reload schema';
