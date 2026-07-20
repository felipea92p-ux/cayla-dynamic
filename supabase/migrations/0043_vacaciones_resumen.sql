-- ============================================================================
-- 0043_vacaciones_resumen.sql — Días disponibles y monto ESTIMADO de vacaciones
-- ============================================================================
-- SOLO LECTURA. No paga, no descuenta, no toca planilla ni provisiones.
-- Su único trabajo es MOSTRAR, para que Felipe compare contra su cálculo a mano
-- antes de que el sistema pague nada (decisión suya: mirar primero, tocar después).
--
-- Fórmula acordada (2026-07-20), régimen Pequeña Empresa = 15 días/año:
--   factor = (horas marcadas + horas de feriados) / (45 h/sem × semanas del periodo
--            sin contar los días de vacaciones ya tomados)
--   monto  = (salario / 2) × factor × (parte del año ya ganada)
-- Sin tope superior: quien trabajó más que su jornada, cobra más.
--
-- Se devuelve CADA COMPONENTE por separado (horas, días, base, factor) a
-- propósito: un número solo no se puede auditar; los componentes sí.
--
-- NOTA sobre feriados: la planilla los acredita con `7.5 * horas_mes / v_base`
-- (proporcional al mes). Acá, para un cálculo anual, se acreditan con el PROMEDIO
-- de horas por día efectivamente marcado de esa persona — mismo espíritu
-- (proporcional a lo que ella trabaja), calculable sobre la ventana del año.
-- Si al comparar aparece diferencia, es el primer lugar donde mirar.

create or replace function fn_vacaciones_resumen(p_as_of date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_as_of date;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver el resumen de vacaciones.';
  end if;
  v_as_of := coalesce(p_as_of, current_date);

  select coalesce(jsonb_agg(s.fila order by s.nombre), '[]'::jsonb) into v_out
  from (
    select
      (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id',          p.id,
        'nombre',              p.nombres || ' ' || p.apellidos,
        'fecha_ingreso',       p.fecha_ingreso,
        'aniversario_ini',     av.aniv_ini,
        'aniversario_next',    av.aniv_next,
        'dias_transcurridos',  gd.dias_transcurridos,
        'dias_ganados',        gd.dias_ganados,
        'dias_tomados',        gd.dias_tomados,
        'dias_saldo',          round(gd.dias_ganados - gd.dias_tomados, 1),
        'dias_con_marca',      coalesce(hm.dias_con_marca, 0),
        'horas_marcadas',      round(coalesce(hm.horas, 0), 2),
        'feriados_en_periodo', coalesce(fe.n, 0),
        'horas_feriados',      round(gd.horas_feriados, 2),
        'horas_base',          round(gd.base_horas, 2),
        'factor',              case when gd.base_horas > 0
                                 then round((coalesce(hm.horas, 0) + gd.horas_feriados) / gd.base_horas, 4)
                                 else 0 end,
        'salario',             sal.salario,
        'monto_estimado',      case when gd.base_horas > 0 and sal.salario is not null
                                 then round(
                                   (sal.salario / 2)
                                   * ((coalesce(hm.horas, 0) + gd.horas_feriados) / gd.base_horas)
                                   * least(1.0, gd.dias_transcurridos::numeric / 365.0)
                                 , 2)
                                 else null end
      ) as fila
    from personas p
    -- ventana del año de servicios: desde su último aniversario de ingreso
    join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) av on true
    -- horas efectivamente marcadas en la ventana
    left join lateral (
      select sum(j.horas_trabajadas) as horas,
             count(*) filter (where j.horas_trabajadas > 0) as dias_con_marca
      from jornadas j
      where j.persona_id = p.id
        and j.fecha between av.aniv_ini and v_as_of
        and j.horas_trabajadas is not null and j.horas_trabajadas > 0
    ) hm on true
    -- feriados de la ventana en los que NO marcó (los que trabajó ya están en `hm`)
    left join lateral (
      select count(*) as n
      from feriados f
      where f.fecha between av.aniv_ini and v_as_of
        and not exists (
          select 1 from jornadas j2
          where j2.persona_id = p.id and j2.fecha = f.fecha
            and j2.horas_trabajadas is not null and j2.horas_trabajadas > 0
        )
    ) fe on true
    -- días de vacaciones ya tomados dentro de la ventana (recortados a ella)
    left join lateral (
      select coalesce(sum(
               greatest(0, (least(v.fecha_fin, v_as_of) - greatest(v.fecha_inicio, av.aniv_ini)) + 1)
             ), 0)::numeric as dias
      from vacaciones v
      where v.persona_id = p.id
        and v.fecha_inicio <= v_as_of
        and v.fecha_fin >= av.aniv_ini
    ) vt on true
    -- salario vigente a la fecha de corte
    left join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and a.vigente_desde <= v_as_of
        and (a.vigente_hasta is null or a.vigente_hasta >= v_as_of)
      order by a.vigente_desde desc limit 1
    ) sal on true
    -- números derivados (en un lateral para no repetir las cuentas arriba)
    join lateral (
      select
        (v_as_of - av.aniv_ini) as dias_transcurridos,
        round(least(15.0, 15.0 * (v_as_of - av.aniv_ini)::numeric / 365.0), 1) as dias_ganados,
        vt.dias as dias_tomados,
        -- base: 45 h/semana sobre los días del periodo, descontando los ya tomados
        (45.0 * greatest(0, (v_as_of - av.aniv_ini) - vt.dias)::numeric / 7.0) as base_horas,
        -- Feriados acreditados al promedio de horas por día marcado de esa persona.
        -- El coalesce exterior es necesario: quien no marcó ningún día tiene
        -- promedio NULL, y sin esto el NULL se propagaría al factor y al monto.
        coalesce(
          coalesce(fe.n, 0)::numeric
            * coalesce(hm.horas, 0) / nullif(coalesce(hm.dias_con_marca, 0), 0)
        , 0) as horas_feriados
    ) gd on true
    where p.estado = 'activo' and p.fecha_ingreso is not null
  ) s;

  return coalesce(v_out, '[]'::jsonb);
end;
$$;

grant execute on function fn_vacaciones_resumen(date) to authenticated;
