-- ============================================================================
-- Parche de la 0025 (hallazgos de la auditoría empírica v2)
-- ----------------------------------------------------------------------------
-- 1) DOBLE PAGO del plus/asignación: dos periodos que cierran el MISMO mes
--    comparten etiqueta de objetivos → el plus se pagaba en ambos. Ahora solo
--    puede existir UN periodo por mes de cierre (índice único + validación).
-- 2) Bonos/descuentos de una persona inactiva sin jornadas en el rango
--    desaparecían de la planilla → ahora esa persona SÍ aparece en las filas.
-- 3) Carreras en crear/eliminar periodo → serializadas con advisory lock.
-- 4) Editar feriados alteraba los montos de planillas ya PAGADAS → las fechas
--    dentro de un periodo pagado quedan protegidas (reabrir para tocar).
-- Re-ejecutable sin peligro.
-- ============================================================================

-- 1) un periodo por mes-etiqueta
create unique index if not exists periodos_etiqueta_unica
  on periodos_planilla ((extract(year from fecha_fin)::int), (extract(month from fecha_fin)::int));

create or replace function fn_crear_periodo(p_fecha_fin date, p_fecha_ini date default null)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_ini date; v_id uuid; v_ultimo date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede crear periodos.';
  end if;
  if p_fecha_fin is null then raise exception 'La fecha de cierre es obligatoria.'; end if;

  -- serializar contra otra creación/eliminación simultánea (sin huecos por carrera)
  perform pg_advisory_xact_lock(hashtext('periodos_planilla'));

  select max(fecha_fin) into v_ultimo from periodos_planilla;
  if v_ultimo is null then
    if p_fecha_ini is null then
      raise exception 'Para el primer periodo debes indicar la fecha de inicio.';
    end if;
    v_ini := p_fecha_ini;
  else
    v_ini := v_ultimo + 1;
    if p_fecha_ini is not null and p_fecha_ini <> v_ini then
      raise exception 'El inicio se encadena automáticamente al % (día siguiente al último cierre).', v_ini;
    end if;
  end if;

  if p_fecha_fin < v_ini + 19 or p_fecha_fin > v_ini + 45 then
    raise exception 'El periodo debe durar entre 20 y 46 días (inicio %, cierre propuesto %).', v_ini, p_fecha_fin;
  end if;

  -- un solo periodo por mes de cierre (el plus de objetivos se pagaría doble)
  if exists (
    select 1 from periodos_planilla
    where extract(year from fecha_fin)::int = extract(year from p_fecha_fin)::int
      and extract(month from fecha_fin)::int = extract(month from p_fecha_fin)::int
  ) then
    raise exception 'Ya existe un periodo que cierra en %/% — dos periodos con el mismo mes de cierre pagarían el plus de objetivos dos veces. Elige un cierre en otro mes.',
      extract(month from p_fecha_fin)::int, extract(year from p_fecha_fin)::int;
  end if;

  insert into periodos_planilla (fecha_ini, fecha_fin, creado_por)
  values (v_ini, p_fecha_fin, fn_persona_actual_id())
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'fecha_ini', v_ini, 'fecha_fin', p_fecha_fin);
end;
$$;

grant execute on function fn_crear_periodo(date, date) to authenticated;
revoke execute on function fn_crear_periodo(date, date) from public, anon;

create or replace function fn_eliminar_periodo(p_periodo_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_fin date; v_estado text; v_max date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede eliminar periodos.';
  end if;
  perform pg_advisory_xact_lock(hashtext('periodos_planilla'));
  select fecha_fin, estado into v_fin, v_estado from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  select max(fecha_fin) into v_max from periodos_planilla;
  if v_fin <> v_max then
    raise exception 'Solo se puede eliminar el ÚLTIMO periodo (para no romper la cadena).';
  end if;
  if v_estado = 'pagado' then
    raise exception 'Un periodo pagado no se elimina; reábrelo primero si de verdad hace falta.';
  end if;
  delete from periodos_planilla where id = p_periodo_id;
end;
$$;

grant execute on function fn_eliminar_periodo(uuid) to authenticated;
revoke execute on function fn_eliminar_periodo(uuid) from public, anon;

-- 4) feriados dentro de un periodo PAGADO quedan protegidos
create or replace function fn_set_feriado(p_fecha date, p_nombre text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar feriados.';
  end if;
  if p_fecha is null then raise exception 'La fecha es obligatoria.'; end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre del feriado es obligatorio.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae dentro de un periodo ya PAGADO: cambiar sus feriados alteraría una planilla pagada. Reabre el periodo primero.';
  end if;
  insert into feriados (fecha, nombre) values (p_fecha, trim(p_nombre))
  on conflict (fecha) do update set nombre = excluded.nombre;
end;
$$;

grant execute on function fn_set_feriado(date, text) to authenticated;
revoke execute on function fn_set_feriado(date, text) from public, anon;

create or replace function fn_quitar_feriado(p_fecha date)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar feriados.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae dentro de un periodo ya PAGADO: cambiar sus feriados alteraría una planilla pagada. Reabre el periodo primero.';
  end if;
  delete from feriados where fecha = p_fecha;
  if not found then raise exception 'No hay feriado en esa fecha.'; end if;
end;
$$;

grant execute on function fn_quitar_feriado(date) to authenticated;
revoke execute on function fn_quitar_feriado(date) from public, anon;

-- 2) las personas con bonos/descuentos en el periodo SIEMPRE aparecen en las filas
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
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, s.codigo as sede
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
        'rango', ref.rango,
        'salario_ref', ref.salario,
        'horas_mes', round(h.horas_mes, 2),
        'dias_trabajados', h.dias,
        'dias_pendientes', h.pendientes,
        'horas_sin_salario', round(pb.horas_sin_salario, 2),
        'pago_base', round(pb.pago_base, 2),
        'feriados_detalle', fer.detalle,
        'monto_feriados', round(fer.monto, 2),
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
    left join lateral (
      select coalesce(sum(case when tt.salario is not null
               then (coalesce(hf.h, 0) + 7.5 * h.horas_mes / v_base) * tt.salario / v_base end), 0) as monto,
             count(*) filter (where tt.salario is null) as sin_tramo,
             coalesce(jsonb_agg(jsonb_build_object(
               'fecha', f.fecha,
               'horas_trabajadas', coalesce(hf.h, 0),
               'proporcional_horas', round(7.5 * h.horas_mes / v_base, 2),
               'sin_salario', (tt.salario is null)
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
