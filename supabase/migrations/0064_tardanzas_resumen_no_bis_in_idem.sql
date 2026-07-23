-- ============================================================================
-- 0064 — La alerta de tardanzas respeta los memos ya emitidos (non bis in idem)
-- ----------------------------------------------------------------------------
-- PROBLEMA: fn_tardanzas_resumen (la franja del Dashboard e Incidencias) contaba
-- TODAS las tardanzas del mes sin mirar si ya se emitió un memo por ellas. Por eso
-- Felipe sancionaba y la alerta seguía gritando lo mismo. Además contradecía a
-- fn_expediente_generar_tardanza, que SÍ respeta lo ya sancionado.
--
-- FIX: mismo corte "no bis in idem" que el generador — se excluyen las tardanzas
-- de fecha <= al periodo del ÚLTIMO memo de tardanza firmado/entregado (vigente
-- 12 meses). Así, al firmar el memo, la alerta se apaga sola y solo vuelve si la
-- persona acumula tardanzas NUEVAS. Firma = ya es acción oficial.
--
-- Sin cambios de firma (mismas columnas). Reversible: restaurar la versión 0062.
-- ============================================================================

create or replace function fn_tardanzas_resumen()
returns table (persona_id uuid, nombre text, sede text, tardanzas_mes int, umbral text, ultima_fecha date)
language sql stable security definer set search_path = public
as $$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
      -- Corte: el periodo del último memo de tardanza YA firmado/entregado, vigente
      -- 12 meses. Las tardanzas de esa fecha o antes NO se vuelven a alertar.
      (select e.periodo_hasta
       from expediente_disciplinario e
       where e.persona_id = pe.id and e.tipo_causal = 'tardanza'
         and e.estado in ('firmado', 'entregado')
         and e.firmado_at >= now() - interval '12 months'
       order by e.firmado_at desc
       limit 1) as corte
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
      and (m.corte is null or j.fecha > m.corte)   -- no cuenta lo ya sancionado
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

notify pgrst, 'reload schema';
