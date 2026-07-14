-- ============================================================================
-- FERIADO según FECHA DE INGRESO (decisión de Felipe 2026-07-13)
-- ----------------------------------------------------------------------------
-- Problema: un feriado ANTERIOR al ingreso de la persona no le corresponde
--   (ej. recién ingresados no cobran el 29-jun San Pedro y San Pablo).
-- fecha de ingreso = la fecha de su PRIMERA ENTRADA marcada (sembrable, editable),
--   NO el campo por defecto (que suele estar mal, puesto al crear la cuenta).
-- Regla: un feriado se paga solo si `feriado.fecha >= persona.fecha_ingreso`;
--   el pago base y los feriados posteriores NO cambian (ya son proporcionales).
-- Re-ejecutable sin peligro.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- fn_ingresos: por persona, la fecha de ingreso actual + la primera entrada
-- marcada (sugerencia). Solo admin/lider.
-- ---------------------------------------------------------------------------
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
    select ((min(m.timestamp_marca) filter (where m.tipo = 'entrada'))
              at time zone 'America/Lima')::date as primera
    from marcajes m where m.persona_id = p.id
  ) pe on true
  where fn_es_admin_o_lider();
$$;

grant execute on function fn_ingresos() to authenticated;
revoke execute on function fn_ingresos() from public, anon;

-- ---------------------------------------------------------------------------
-- fn_set_fecha_ingreso: editar la fecha de ingreso de una persona.
-- ---------------------------------------------------------------------------
create or replace function fn_set_fecha_ingreso(p_persona_id uuid, p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la fecha de ingreso.';
  end if;
  if p_fecha is null then raise exception 'La fecha de ingreso es obligatoria.'; end if;
  if p_fecha > current_date then raise exception 'La fecha de ingreso no puede ser futura.'; end if;
  update personas set fecha_ingreso = p_fecha where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$$;

grant execute on function fn_set_fecha_ingreso(uuid, date) to authenticated;
revoke execute on function fn_set_fecha_ingreso(uuid, date) from public, anon;

-- ---------------------------------------------------------------------------
-- fn_sembrar_ingresos: pone fecha_ingreso = primera entrada marcada, para todos
-- los que difieran. Devuelve el detalle de lo que cambió (para revisión). Solo
-- toca a quien tiene una entrada marcada; las fechas editadas a mano que ya
-- coincidan no se tocan. Es una acción deliberada (la UI confirma antes).
-- ---------------------------------------------------------------------------
create or replace function fn_sembrar_ingresos()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare v_detalle jsonb; v_n int;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede sembrar fechas de ingreso.';
  end if;

  with cambios as (
    select p.id,
           p.fecha_ingreso as antes,
           pe.primera as despues,
           (p.nombres || ' ' || p.apellidos) as nombre
    from personas p
    join lateral (
      select ((min(m.timestamp_marca) filter (where m.tipo = 'entrada'))
                at time zone 'America/Lima')::date as primera
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

-- ---------------------------------------------------------------------------
-- fn_planilla_calcular v4: gatea los feriados por la fecha de ingreso.
-- Un feriado con fecha < ingreso NO suma monto y sale marcado 'antes_ingreso'.
-- (Idéntico a v3 de 0026 salvo el gate del feriado y fecha_ingreso en `pers`.)
-- ---------------------------------------------------------------------------
create or replace function fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_dias int; v_base numeric;
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_asig numeric; v_anio int; v_mes int;
begin
  v_dias := (p_fin - p_ini) + 1;
  v_base := 6.5 * v_dias;
  v_anio := extract(year from p_fin)::int;
  v_mes := extract(month from p_fin)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion": 0.08333, "cts": 0.04167, "vacaciones": 0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vacas := coalesce((v_prov->>'vacaciones')::numeric, 0);

  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
  from configuracion where clave = 'asignacion_familiar';
  if v_asig is null then v_asig := 113.00; end if;

  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_feriados
  from feriados f
  where f.fecha between p_ini and p_fin;

  with pers as (
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, p.fecha_ingreso, s.codigo as sede
    from personas p
    join sedes s on s.id = p.sede_base_id
    where p.estado = 'activo'
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between p_ini and p_fin)
       or (p_periodo_id is not null and exists (
             select 1 from movimientos_planilla m
             where m.persona_id = p.id and m.periodo_id = p_periodo_id))
  ),
  horas as (
    select j.persona_id, j.fecha,
           coalesce(j.horas_trabajadas, 0) as h,
           (j.estado = 'auto_cerrada_pendiente') as pendiente
    from jornadas j
    where j.fecha between p_ini and p_fin
  ),
  tramos as (
    select a.persona_id, a.rango, a.salario_mensual_soles as salario,
           greatest(a.vigente_desde, p_ini) as t_ini,
           least(coalesce(a.vigente_hasta, p_fin), p_fin) as t_fin
    from asignaciones_salario a
    where a.vigente_desde <= p_fin
      and (a.vigente_hasta is null or a.vigente_hasta >= p_ini)
  )
  select jsonb_build_object(
    'fecha_ini', p_ini,
    'fecha_fin', p_fin,
    'anio_etiqueta', v_anio,
    'mes_etiqueta', v_mes,
    'dias', v_dias,
    'base_horas', v_base,
    'feriados', v_feriados,
    'factores_provision', v_prov,
    'asignacion_monto', v_asig,
    'filas', coalesce(jsonb_agg(sub.fila order by sub.orden_nombre), '[]'::jsonb)
  )
  into v_out
  from (
    select (pe.nombres || ' ' || pe.apellidos) as orden_nombre,
      jsonb_build_object(
        'persona_id', pe.id,
        'nombre', pe.nombres || ' ' || pe.apellidos,
        'sede', pe.sede,
        'estado', pe.estado,
        'fecha_ingreso', pe.fecha_ingreso,
        'rango', ref.rango,
        'salario_ref', ref.salario,
        'horas_mes', round(h.horas_mes, 2),
        'dias_trabajados', h.dias,
        'dias_pendientes', h.pendientes,
        'horas_sin_salario', round(pb.horas_sin_salario, 2),
        'pago_base', round(pb.pago_base, 2),
        'feriados_detalle', fer.detalle,
        'monto_feriados', round(fer.monto, 2),
        'feriados_no_corresponde', fer.no_corresponde,
        'objetivos_cumplidos', obj.cumplidos,
        'objetivos_total', obj.total,
        'monto_plus', round(obj.monto, 2),
        'bajo_desempeno', (obj.cumplidos is not null and obj.total > 0
                           and obj.cumplidos::numeric / obj.total < 0.3),
        'feriados_sin_salario', fer.sin_tramo,
        'con_hijos', pe.con_hijos,
        'asignacion_familiar', case when pe.con_hijos then round(v_asig, 2) else 0 end,
        'bonos', round(mov.bonos, 2),
        'descuentos', round(mov.descuentos, 2),
        'movimientos', mov.detalle,
        'provision_gratificacion', round((pb.pago_base + fer.monto) * v_f_grati, 2),
        'provision_cts', round((pb.pago_base + fer.monto) * v_f_cts, 2),
        'provision_vacaciones', round((pb.pago_base + fer.monto) * v_f_vacas, 2),
        'provision_total', round((pb.pago_base + fer.monto) * (v_f_grati + v_f_cts + v_f_vacas), 2),
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
                 + (case when pe.con_hijos then round(v_asig, 2) else 0 end)
                 + round(mov.bonos, 2) - round(mov.descuentos, 2)
      ) as fila
    from pers pe
    left join lateral (
      select coalesce(sum(x.h), 0) as horas_mes,
             count(*) filter (where x.h > 0) as dias,
             count(*) filter (where x.pendiente) as pendientes
      from horas x where x.persona_id = pe.id
    ) h on true
    left join lateral (
      select coalesce(sum(case when tt.salario is not null then x.h * tt.salario / v_base end), 0) as pago_base,
             coalesce(sum(case when tt.salario is null then x.h end), 0) as horas_sin_salario
      from horas x
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = x.persona_id and x.fecha between t.t_ini and t.t_fin
        order by t.t_ini desc limit 1
      ) tt on true
      where x.persona_id = pe.id
    ) pb on true
    left join lateral (
      select t.rango, t.salario
      from tramos t
      where t.persona_id = pe.id
      order by t.t_fin desc, t.t_ini desc
      limit 1
    ) ref on true
    -- feriados: solo cuentan los que caen EN o DESPUÉS del ingreso de la persona
    left join lateral (
      select coalesce(sum(case when tt.salario is not null and f.fecha >= pe.fecha_ingreso
               then (coalesce(hf.h, 0) + 7.5 * h.horas_mes / v_base) * tt.salario / v_base end), 0) as monto,
             count(*) filter (where tt.salario is null and f.fecha >= pe.fecha_ingreso) as sin_tramo,
             count(*) filter (where f.fecha < pe.fecha_ingreso) as no_corresponde,
             coalesce(jsonb_agg(jsonb_build_object(
               'fecha', f.fecha,
               'horas_trabajadas', coalesce(hf.h, 0),
               'proporcional_horas', case when f.fecha >= pe.fecha_ingreso
                                          then round(7.5 * h.horas_mes / v_base, 2) else 0 end,
               'sin_salario', (tt.salario is null and f.fecha >= pe.fecha_ingreso),
               'antes_ingreso', (f.fecha < pe.fecha_ingreso)
             ) order by f.fecha), '[]'::jsonb) as detalle
      from feriados f
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id and f.fecha between t.t_ini and t.t_fin
        order by t.t_ini desc limit 1
      ) tt on true
      left join horas hf on hf.persona_id = pe.id and hf.fecha = f.fecha
      where f.fecha between p_ini and p_fin
    ) fer on true
    left join lateral (
      select om.cumplidos, om.total,
             case
               when om.cumplidos is null or ref.salario is null then 0
               when om.cumplidos::numeric / om.total >= 1 then 0.21 * ref.salario
               when om.cumplidos::numeric / om.total >= 0.6 then 0.126 * ref.salario
               else 0
             end as monto
      from (select 1) uno
      left join objetivos_mensuales om
        on om.persona_id = pe.id and om.anio = v_anio and om.mes = v_mes
    ) obj on true
    left join lateral (
      select coalesce(sum(m.monto) filter (where m.tipo = 'bono'), 0) as bonos,
             coalesce(sum(m.monto) filter (where m.tipo = 'descuento'), 0) as descuentos,
             coalesce(jsonb_agg(jsonb_build_object(
               'id', m.id, 'tipo', m.tipo, 'concepto', m.concepto, 'monto', m.monto
             ) order by m.created_at) filter (where m.id is not null), '[]'::jsonb) as detalle
      from movimientos_planilla m
      where p_periodo_id is not null
        and m.periodo_id = p_periodo_id
        and m.persona_id = pe.id
    ) mov on true
  ) sub;

  return v_out;
end;
$$;

revoke execute on function fn_planilla_calcular(date, date, uuid) from public, anon, authenticated;

notify pgrst, 'reload schema';
