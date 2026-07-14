-- ============================================================================
-- PROVISIONES ACUMULADAS (grati / CTS / vacaciones) hacia su fecha de pago
-- ----------------------------------------------------------------------------
-- Modelo (confirmado con Felipe 2026-07-13): el acumulado = suma de la provision
-- ganada dentro de la VENTANA LEGAL de cada beneficio. Es una PROYECCION; el monto
-- exacto lo cierra el contador al pagar.
--
-- Base de la provision = "sueldo regular ganado" por dia:
--     pago_dia = horas_trabajadas * salario_mensual / (6.5 * dias_del_mes)
--   Sumado por dia, cada mes aporta ~1 sueldo si es full-time. Multiplicado por el
--   factor mensual da el acumulado: factor 8.33% * 6 sueldos (semestre) = medio
--   sueldo = la gratificacion MYPE. (No incluye el recargo de feriados ni bonos:
--   la provision va sobre remuneracion regular; el contador ajusta si aplica.)
--
-- Ventanas / fechas de pago (regimen MYPE pequena empresa):
--   Gratificacion: ene-jun -> paga 15-jul | jul-dic -> paga 15-dic
--   CTS:           nov-abr -> deposita 15-may | may-oct -> deposita 15-nov
--   Vacaciones:    desde su ultimo aniversario de ingreso hasta hoy; 15 dias/ano
-- La ventana arranca en max(inicio_legal, fecha_ingreso) para los recien ingresados.
-- Solo admin/lider. Re-ejecutable sin peligro.
-- ============================================================================

create or replace function fn_provisiones(p_as_of date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_as_of date; v_anio int; v_mes int;
  v_prov jsonb; v_f_grati numeric; v_f_cts numeric; v_f_vac numeric;
  v_grati_ini date; v_grati_fin date; v_grati_pago date;
  v_cts_ini date; v_cts_fin date; v_cts_pago date;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver las provisiones.';
  end if;

  v_as_of := coalesce(p_as_of, current_date);
  v_anio := extract(year from v_as_of)::int;
  v_mes := extract(month from v_as_of)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion":0.08333,"cts":0.04167,"vacaciones":0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts   := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vac   := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- Gratificacion: ventana elegida por FECHA DE PAGO (no por mes). El semestre
  -- ene-jun sigue vigente hasta el 15-jul (dia de pago); recien despues del 15-jul
  -- pasa a jul-dic. El acumulado se topa en el fin del semestre (jun-30 / dic-31).
  if v_as_of <= make_date(v_anio, 7, 15) then
    v_grati_ini := make_date(v_anio, 1, 1);     v_grati_fin := make_date(v_anio, 6, 30);      v_grati_pago := make_date(v_anio, 7, 15);
  elsif v_as_of <= make_date(v_anio, 12, 15) then
    v_grati_ini := make_date(v_anio, 7, 1);     v_grati_fin := make_date(v_anio, 12, 31);     v_grati_pago := make_date(v_anio, 12, 15);
  else
    v_grati_ini := make_date(v_anio + 1, 1, 1); v_grati_fin := make_date(v_anio + 1, 6, 30);  v_grati_pago := make_date(v_anio + 1, 7, 15);
  end if;

  -- CTS: ventana por FECHA DE DEPOSITO (15-may / 15-nov). El periodo nov-abr
  -- sigue vigente hasta el 15-may; el may-oct hasta el 15-nov.
  if v_as_of <= make_date(v_anio, 5, 15) then
    v_cts_ini := make_date(v_anio - 1, 11, 1);  v_cts_fin := make_date(v_anio, 4, 30);       v_cts_pago := make_date(v_anio, 5, 15);
  elsif v_as_of <= make_date(v_anio, 11, 15) then
    v_cts_ini := make_date(v_anio, 5, 1);       v_cts_fin := make_date(v_anio, 10, 31);      v_cts_pago := make_date(v_anio, 11, 15);
  else
    v_cts_ini := make_date(v_anio, 11, 1);      v_cts_fin := make_date(v_anio + 1, 4, 30);   v_cts_pago := make_date(v_anio + 1, 5, 15);
  end if;

  with base as (
    -- sueldo regular ganado por persona y dia (base mensual correcta segun el mes)
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
        -- gratificacion
        'grati_desde', greatest(v_grati_ini, p.fecha_ingreso),
        'grati_pago', v_grati_pago,
        'grati_acumulada', round(v_f_grati * coalesce(g.pago, 0), 2),
        -- cts
        'cts_desde', greatest(v_cts_ini, p.fecha_ingreso),
        'cts_pago', v_cts_pago,
        'cts_acumulada', round(v_f_cts * coalesce(c.pago, 0), 2),
        -- vacaciones
        'vac_desde', va.aniv_ini,
        'proximo_aniversario', va.aniv_next,
        'vac_acumulada', round(v_f_vac * coalesce(vp.pago, 0), 2),
        'vac_dias', round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1)
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    left join lateral (
      select sum(b.pago_dia) as pago from base b
      where b.persona_id = p.id and b.fecha between greatest(v_grati_ini, p.fecha_ingreso) and least(v_as_of, v_grati_fin)
    ) g on true
    left join lateral (
      select sum(b.pago_dia) as pago from base b
      where b.persona_id = p.id and b.fecha between greatest(v_cts_ini, p.fecha_ingreso) and least(v_as_of, v_cts_fin)
    ) c on true
    left join lateral (
      select sum(b.pago_dia) as pago from base b
      where b.persona_id = p.id and b.fecha between va.aniv_ini and v_as_of
    ) vp on true
    where p.estado = 'activo'
  ) sub;

  return jsonb_build_object(
    'as_of', v_as_of,
    'factores', v_prov,
    'grati_pago', v_grati_pago,
    'cts_pago', v_cts_pago,
    'personas', v_out
  );
end;
$$;

grant execute on function fn_provisiones(date) to authenticated;
revoke execute on function fn_provisiones(date) from public, anon;

notify pgrst, 'reload schema';
