-- ============================================================================
-- Fix: fecha de ingreso = PRIMERA MARCA de cualquier tipo (no solo 'entrada')
-- ----------------------------------------------------------------------------
-- 0027 usaba min(...) filter (where tipo='entrada'), pero los marcajes históricos
-- importados (origen import_historico) no siempre quedaron con tipo 'entrada' como
-- primera marca del día, asi que devolvia la primera marca en la app (11-jul) en vez
-- de la fecha real (ene/feb/mar...). Se toma min(timestamp_marca) de TODAS las marcas,
-- que es exactamente la fecha real de la primera actividad de cada persona.
-- Solo redefine 2 funciones; no cambia el frontend. Re-ejecutable sin peligro.
-- ============================================================================

create or replace function fn_ingresos()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'persona_id', p.id,
    'fecha_ingreso', p.fecha_ingreso,
    'primera_entrada', pe.primera
  )), '[]'::jsonb)
  from personas p
  left join lateral (
    select (min(m.timestamp_marca) at time zone 'America/Lima')::date as primera
    from marcajes m where m.persona_id = p.id
  ) pe on true
  where fn_es_admin_o_lider();
$$;

grant execute on function fn_ingresos() to authenticated;
revoke execute on function fn_ingresos() from public, anon;

create or replace function fn_sembrar_ingresos()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_detalle jsonb; v_n int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede sembrar fechas de ingreso.';
  end if;

  with cambios as (
    select p.id,
           p.fecha_ingreso as antes,
           pe.primera as despues,
           (p.nombres || ' ' || p.apellidos) as nombre
    from personas p
    join lateral (
      select (min(m.timestamp_marca) at time zone 'America/Lima')::date as primera
      from marcajes m where m.persona_id = p.id
    ) pe on true
    where pe.primera is not null and pe.primera <> p.fecha_ingreso
  ),
  upd as (
    update personas p set fecha_ingreso = c.despues
    from cambios c
    where p.id = c.id
    returning c.nombre, c.antes, c.despues
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'nombre', nombre, 'antes', antes, 'despues', despues
         ) order by nombre), '[]'::jsonb), count(*)
  into v_detalle, v_n
  from upd;

  return jsonb_build_object('actualizados', v_n, 'detalle', v_detalle);
end;
$$;

grant execute on function fn_sembrar_ingresos() to authenticated;
revoke execute on function fn_sembrar_ingresos() from public, anon;

notify pgrst, 'reload schema';
