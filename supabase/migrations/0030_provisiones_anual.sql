-- ============================================================================
-- PROVISIONES v2 — vista ANUAL: las 2 gratis y las 2 CTS del ano, separadas,
-- con sus sumas, gran total y proximo desembolso por persona.
-- ----------------------------------------------------------------------------
-- Decisiones de Felipe (2026-07-14):
--   Gratificacion: 2 ventanas -> ene-jun (paga 15-jul) y jul-dic (paga 15-dic).
--   CTS: 2 ventanas (periodos legales) -> nov(ano-1)-abr (deposita 15-may) y
--        may-oct (deposita 15-nov). El tramo nov-dic del ano anterior se llena
--        solo cuando se cargue ese historico; hoy suma lo que exista.
--   Vacaciones: una sola, desde el ultimo aniversario de ingreso.
--   Suma grati, suma CTS y GRAN TOTAL por persona. Proximo pago = el desembolso
--   mas cercano (>= hoy) con el monto de esa persona.
--   El acumulado requiere que el salario cubra los meses (ver update de salarios).
-- Base = sueldo regular por dia: horas * salario / (6.5 * dias_del_mes). MYPE.
-- Solo admin/lider. Re-ejecutable sin peligro.
-- ============================================================================

create or replace function fn_provisiones(p_as_of date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_as_of date; v_y int;
  v_prov jsonb; v_f_grati numeric; v_f_cts numeric; v_f_vac numeric;
  g1_ini date; g1_fin date; g1_pago date;
  g2_ini date; g2_fin date; g2_pago date;
  c1_ini date; c1_fin date; c1_pago date;
  c2_ini date; c2_fin date; c2_pago date;
  v_prox_fecha date; v_prox_tipo text; v_prox_ref text;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver las provisiones.';
  end if;
  v_as_of := coalesce(p_as_of, current_date);
  v_y := extract(year from v_as_of)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion":0.08333,"cts":0.04167,"vacaciones":0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts   := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vac   := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- Ventanas del ano (periodos legales)
  g1_ini := make_date(v_y,1,1);    g1_fin := make_date(v_y,6,30);  g1_pago := make_date(v_y,7,15);
  g2_ini := make_date(v_y,7,1);    g2_fin := make_date(v_y,12,31); g2_pago := make_date(v_y,12,15);
  c1_ini := make_date(v_y-1,11,1); c1_fin := make_date(v_y,4,30);  c1_pago := make_date(v_y,5,15);
  c2_ini := make_date(v_y,5,1);    c2_fin := make_date(v_y,10,31); c2_pago := make_date(v_y,11,15);

  -- Proximo desembolso: la fecha de pago mas cercana que aun no pasa.
  -- Incluye tambien las ventanas del ANO SIGUIENTE: entre el 16 y el 31 de dic,
  -- tras el ultimo pago del ano (grati_s2, 15-dic), el proximo desembolso cae en
  -- el ano v_y+1 (CTS may). Sin estas filas, 'proximo' quedaria NULL esas dos
  -- semanas de cada diciembre.
  select fecha, tipo, ref into v_prox_fecha, v_prox_tipo, v_prox_ref
  from (values
    (c1_pago, 'CTS',           'cts_may'),
    (g1_pago, 'Gratificacion', 'grati_s1'),
    (c2_pago, 'CTS',           'cts_nov'),
    (g2_pago, 'Gratificacion', 'grati_s2'),
    (make_date(v_y+1, 5,15), 'CTS',           'cts_may'),
    (make_date(v_y+1, 7,15), 'Gratificacion', 'grati_s1'),
    (make_date(v_y+1,11,15), 'CTS',           'cts_nov'),
    (make_date(v_y+1,12,15), 'Gratificacion', 'grati_s2')
  ) t(fecha, tipo, ref)
  where fecha >= v_as_of
  order by fecha
  limit 1;

  with base as (
    -- sueldo regular ganado por persona y dia (base mensual correcta)
    select j.persona_id, j.fecha,
           j.horas_trabajadas * tt.salario
             / (6.5 * extract(day from (date_trunc('month', j.fecha) + interval '1 month - 1 day'))::numeric) as pago_dia
    from jornadas j
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = j.persona_id
        and j.fecha >= a.vigente_desde
        and (a.vigente_hasta is null or j.fecha <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where j.horas_trabajadas is not null and j.horas_trabajadas > 0
  )
  select coalesce(jsonb_agg(sub.fila order by sub.nombre), '[]'::jsonb) into v_out
  from (
    select (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id', p.id,
        'nombre', p.nombres || ' ' || p.apellidos,
        'sede', s.codigo,
        'fecha_ingreso', p.fecha_ingreso,
        'grati_s1', round(v_f_grati * coalesce(g1.pago,0), 2),
        'grati_s2', round(v_f_grati * coalesce(g2.pago,0), 2),
        'grati_total', round(v_f_grati * (coalesce(g1.pago,0) + coalesce(g2.pago,0)), 2),
        'cts_may', round(v_f_cts * coalesce(cm.pago,0), 2),
        'cts_nov', round(v_f_cts * coalesce(cn.pago,0), 2),
        'cts_total', round(v_f_cts * (coalesce(cm.pago,0) + coalesce(cn.pago,0)), 2),
        'vac', round(v_f_vac * coalesce(vv.pago,0), 2),
        'vac_dias', round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1),
        'proximo_aniversario', va.aniv_next,
        'gran_total', round(
          v_f_grati * (coalesce(g1.pago,0) + coalesce(g2.pago,0))
          + v_f_cts * (coalesce(cm.pago,0) + coalesce(cn.pago,0))
          + v_f_vac * coalesce(vv.pago,0), 2)
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g1_ini,p.fecha_ingreso) and least(v_as_of,g1_fin)) g1 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g2_ini,p.fecha_ingreso) and least(v_as_of,g2_fin)) g2 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c1_ini,p.fecha_ingreso) and least(v_as_of,c1_fin)) cm on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c2_ini,p.fecha_ingreso) and least(v_as_of,c2_fin)) cn on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between va.aniv_ini and v_as_of) vv on true
    where p.estado = 'activo'
  ) sub;

  return jsonb_build_object(
    'as_of', v_as_of,
    'factores', v_prov,
    'proximo', jsonb_build_object('fecha', v_prox_fecha, 'tipo', v_prox_tipo, 'ref', v_prox_ref),
    'grati_s1_pago', g1_pago, 'grati_s2_pago', g2_pago,
    'cts_may_pago', c1_pago, 'cts_nov_pago', c2_pago,
    'grati_s1_periodo', 'ene-jun', 'grati_s2_periodo', 'jul-dic',
    'cts_may_periodo', 'nov-abr', 'cts_nov_periodo', 'may-oct',
    'personas', v_out
  );
end;
$$;

grant execute on function fn_provisiones(date) to authenticated;
revoke execute on function fn_provisiones(date) from public, anon;

notify pgrst, 'reload schema';
