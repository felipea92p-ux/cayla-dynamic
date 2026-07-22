-- ============================================================================
-- 0062_tardanzas_ultima_fecha.sql — fn_tardanzas_resumen devuelve ultima_fecha
-- ============================================================================
-- Para la franja del Dashboard: mostrar "actúa antes de [fecha]" (principio de
-- inmediatez). El plazo = última tardanza + la ventana del Manual (~10 días
-- hábiles), calculado en la pantalla. Aquí solo se agrega la fecha de la última
-- tardanza contada. Cambia la firma (nueva columna) → drop + create.
-- Todo lo demás es idéntico a 0057 (count distinct, exclusiones, umbral b).

drop function if exists fn_tardanzas_resumen();

create function fn_tardanzas_resumen()
returns table (persona_id uuid, nombre text, sede text, tardanzas_mes int, umbral text, ultima_fecha date)
language sql stable security definer set search_path = public
as $$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  conteo as (
    select m.id as pid, count(distinct j.fecha) as n, max(j.fecha) as ult
    from medibles m
    join jornadas j on j.persona_id = m.id
      and j.fecha >= date_trunc('month', current_date)::date
      and j.fecha <= current_date
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (
        select 1 from tardanzas_justificadas tj
        where tj.persona_id = m.id and tj.fecha = j.fecha)
    group by m.id
  )
  select m.id, m.nombre, m.sede, c.n::int,
    case when c.n >= 3 then 'amonestacion' else 'aviso' end as umbral,
    c.ult
  from medibles m join conteo c on c.pid = m.id
  where c.n >= 2
  order by c.n desc, m.nombre;
$$;

grant execute on function fn_tardanzas_resumen() to authenticated;
