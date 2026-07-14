-- ============================================================================
-- PLANILLA v2 — periodos encadenados + candado de pago + simulador +
--                asignación familiar + bonos/descuentos por concepto
-- ----------------------------------------------------------------------------
-- Decisiones de Felipe (2026-07-13):
--   · Periodos OFICIALES encadenados: el inicio = día siguiente al cierre del
--     periodo anterior (huecos y dobles conteos imposibles); él elige el cierre.
--   · Periodo PAGADO = congelado (objetivos/bonos/descuentos bloqueados);
--     un admin puede reabrirlo para corregir errores conscientes.
--   · SIMULADOR: cualquier rango de fechas, solo lectura, no guarda nada.
--   · Asignación familiar FIJA (S/ 113 = 10% RMV, editable en configuracion)
--     para quien tenga el flag con_hijos — validar aplicabilidad MYPE con contador.
--   · Bonos y descuentos: lista de líneas concepto + monto por persona/periodo.
-- La fn_proyeccion_planilla(año, mes) de 0024 se CONSERVA (compat); las nuevas
-- van por periodo. Re-ejecutable sin peligro.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Periodos de pago
-- ---------------------------------------------------------------------------
create table if not exists periodos_planilla (
  id uuid primary key default gen_random_uuid(),
  fecha_ini date not null,
  fecha_fin date not null,
  estado text not null default 'abierto' check (estado in ('abierto', 'pagado')),
  pagado_at timestamptz,
  creado_por uuid references personas(id),
  created_at timestamptz not null default now(),
  check (fecha_fin >= fecha_ini + 19 and fecha_fin <= fecha_ini + 45) -- 20 a 46 días
);

-- doble seguro anti-solape (la regla de encadenado vive en fn_crear_periodo)
alter table periodos_planilla drop constraint if exists periodos_sin_solape;
alter table periodos_planilla add constraint periodos_sin_solape
  exclude using gist (daterange(fecha_ini, fecha_fin, '[]') with &&);

alter table periodos_planilla enable row level security;
drop policy if exists periodos_select_admin_lider on periodos_planilla;
create policy periodos_select_admin_lider on periodos_planilla
  for select to authenticated using (fn_es_admin_o_lider());
-- escritura: SOLO vía RPC

-- ---------------------------------------------------------------------------
-- Bonos y descuentos por persona/periodo (línea a línea, con concepto)
-- ---------------------------------------------------------------------------
create table if not exists movimientos_planilla (
  id uuid primary key default gen_random_uuid(),
  periodo_id uuid not null references periodos_planilla(id) on delete cascade,
  persona_id uuid not null references personas(id),
  tipo text not null check (tipo in ('bono', 'descuento')),
  concepto text not null check (length(trim(concepto)) >= 2),
  monto numeric(10,2) not null check (monto > 0),
  creado_por uuid references personas(id),
  created_at timestamptz not null default now()
);

create index if not exists idx_movimientos_periodo on movimientos_planilla(periodo_id, persona_id);

alter table movimientos_planilla enable row level security;
drop policy if exists movimientos_select_admin_lider on movimientos_planilla;
create policy movimientos_select_admin_lider on movimientos_planilla
  for select to authenticated using (fn_es_admin_o_lider());
-- escritura: SOLO vía RPC

-- ---------------------------------------------------------------------------
-- Asignación familiar: flag por persona + monto configurable
-- ---------------------------------------------------------------------------
alter table personas add column if not exists con_hijos boolean not null default false;

insert into configuracion (clave, valor, descripcion) values (
  'asignacion_familiar',
  '{"monto": 113.00}'::jsonb,
  'Asignación familiar por periodo (10% de la RMV S/1,130). FIJA, no proporcional. Validar aplicabilidad en régimen MYPE con el contador.'
) on conflict (clave) do nothing;

create or replace function fn_set_con_hijos(p_persona_id uuid, p_con_hijos boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la asignación familiar.';
  end if;
  update personas set con_hijos = coalesce(p_con_hijos, false) where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$$;

grant execute on function fn_set_con_hijos(uuid, boolean) to authenticated;
revoke execute on function fn_set_con_hijos(uuid, boolean) from public, anon;

-- fn_personas_funciones ahora incluye con_hijos (columna nueva → viaja por RPC,
-- el caché de PostgREST sigue sin exponer columnas nuevas por REST)
create or replace function fn_personas_funciones()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos)), '[]'::jsonb)
  from personas p
  where
    fn_es_admin_o_lider()
    or (fn_rol_actual() = 'supervisor_sede' and p.sede_base_id = fn_sede_actual_persona())
    or p.auth_user_id = auth.uid()
    or (p.estado = 'activo'
        and fn_sede_actual_terminal() is not null
        and (p.sede_base_id = fn_sede_actual_terminal() or p.visible_todas_sedes = true));
$$;

grant execute on function fn_personas_funciones() to authenticated;
revoke execute on function fn_personas_funciones() from public, anon;

-- ---------------------------------------------------------------------------
-- Gestión de periodos
-- ---------------------------------------------------------------------------
create or replace function fn_periodos()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select case when fn_es_admin_o_lider() is not true then '[]'::jsonb
  else coalesce(jsonb_agg(jsonb_build_object(
         'id', p.id, 'fecha_ini', p.fecha_ini, 'fecha_fin', p.fecha_fin,
         'estado', p.estado, 'pagado_at', p.pagado_at,
         'anio_etiqueta', extract(year from p.fecha_fin)::int,
         'mes_etiqueta', extract(month from p.fecha_fin)::int
       ) order by p.fecha_fin desc), '[]'::jsonb)
  end
  from periodos_planilla p;
$$;

grant execute on function fn_periodos() to authenticated;
revoke execute on function fn_periodos() from public, anon;

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

  select max(fecha_fin) into v_ultimo from periodos_planilla;
  if v_ultimo is null then
    -- primer periodo: el inicio lo elige Felipe
    if p_fecha_ini is null then
      raise exception 'Para el primer periodo debes indicar la fecha de inicio.';
    end if;
    v_ini := p_fecha_ini;
  else
    -- encadenado: el inicio SIEMPRE es el día siguiente al último cierre
    v_ini := v_ultimo + 1;
    if p_fecha_ini is not null and p_fecha_ini <> v_ini then
      raise exception 'El inicio se encadena automáticamente al % (día siguiente al último cierre).', v_ini;
    end if;
  end if;

  if p_fecha_fin < v_ini + 19 or p_fecha_fin > v_ini + 45 then
    raise exception 'El periodo debe durar entre 20 y 46 días (inicio %, cierre propuesto %).', v_ini, p_fecha_fin;
  end if;

  insert into periodos_planilla (fecha_ini, fecha_fin, creado_por)
  values (v_ini, p_fecha_fin, fn_persona_actual_id())
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'fecha_ini', v_ini, 'fecha_fin', p_fecha_fin);
end;
$$;

grant execute on function fn_crear_periodo(date, date) to authenticated;
revoke execute on function fn_crear_periodo(date, date) from public, anon;

create or replace function fn_periodo_pagado(p_periodo_id uuid, p_pagado boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede marcar o reabrir un pago.';
  end if;
  update periodos_planilla
     set estado = case when coalesce(p_pagado, false) then 'pagado' else 'abierto' end,
         pagado_at = case when coalesce(p_pagado, false) then now() else null end
   where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
end;
$$;

grant execute on function fn_periodo_pagado(uuid, boolean) to authenticated;
revoke execute on function fn_periodo_pagado(uuid, boolean) from public, anon;

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

-- ---------------------------------------------------------------------------
-- Bonos / descuentos (bloqueados si el periodo está pagado)
-- ---------------------------------------------------------------------------
create or replace function fn_agregar_movimiento(
  p_periodo_id uuid,
  p_persona_id uuid,
  p_tipo text,
  p_concepto text,
  p_monto numeric
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_estado text; v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar bonos o descuentos.';
  end if;
  select estado into v_estado from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  if p_tipo is null or p_tipo not in ('bono', 'descuento') then
    raise exception 'Tipo inválido (bono o descuento).';
  end if;
  if p_concepto is null or length(trim(p_concepto)) < 2 then
    raise exception 'El concepto es obligatorio.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a 0.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;

  insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
  values (p_periodo_id, p_persona_id, p_tipo, trim(p_concepto), round(p_monto, 2), fn_persona_actual_id())
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

grant execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric) to authenticated;
revoke execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric) from public, anon;

create or replace function fn_quitar_movimiento(p_movimiento_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_estado text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar bonos o descuentos.';
  end if;
  select pp.estado into v_estado
  from movimientos_planilla m join periodos_planilla pp on pp.id = m.periodo_id
  where m.id = p_movimiento_id;
  if not found then raise exception 'Movimiento inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  delete from movimientos_planilla where id = p_movimiento_id;
end;
$$;

grant execute on function fn_quitar_movimiento(uuid) to authenticated;
revoke execute on function fn_quitar_movimiento(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- fn_set_objetivos v2: bloquea el mes cuya planilla (por etiqueta del periodo)
-- ya está pagada
-- ---------------------------------------------------------------------------
create or replace function fn_set_objetivos(
  p_persona_id uuid,
  p_anio int,
  p_mes int,
  p_cumplidos int,
  p_total int default 10
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar objetivos.';
  end if;
  if p_persona_id is null or not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;
  if p_anio is null or p_mes is null or p_mes not between 1 and 12 then
    raise exception 'Mes inválido.';
  end if;
  if coalesce(p_total, 0) <= 0 or coalesce(p_cumplidos, -1) < 0 or p_cumplidos > p_total then
    raise exception 'Objetivos inválidos: % de %.', p_cumplidos, p_total;
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and extract(year from fecha_fin)::int = p_anio
      and extract(month from fecha_fin)::int = p_mes
  ) then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  insert into objetivos_mensuales (persona_id, anio, mes, cumplidos, total)
  values (p_persona_id, p_anio, p_mes, p_cumplidos, p_total)
  on conflict (persona_id, anio, mes) do update set
    cumplidos = excluded.cumplidos,
    total = excluded.total,
    updated_at = now();
end;
$$;

grant execute on function fn_set_objetivos(uuid, int, int, int, int) to authenticated;
revoke execute on function fn_set_objetivos(uuid, int, int, int, int) from public, anon;

-- ---------------------------------------------------------------------------
-- NÚCLEO de cálculo por RANGO de fechas (privado: sin grant — lo usan los
-- wrappers). Misma matemática auditada 26/26 de 0024, generalizada:
-- base = 6.5 × días del rango; objetivos por la etiqueta (mes de fecha_fin);
-- + asignación familiar fija + bonos/descuentos del periodo (si lo hay).
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
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, s.codigo as sede
    from personas p
    join sedes s on s.id = p.sede_base_id
    where p.estado = 'activo'
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between p_ini and p_fin)
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
        -- total = partes redondeadas (el desglose siempre cuadra al céntimo)
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

-- núcleo privado: nadie lo llama directo
revoke execute on function fn_planilla_calcular(date, date, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Wrapper 1: proyección OFICIAL por periodo (incluye bonos/descuentos y estado)
-- ---------------------------------------------------------------------------
create or replace function fn_proyeccion_periodo(p_periodo_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_p record; v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la planilla.';
  end if;
  select * into v_p from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_out := fn_planilla_calcular(v_p.fecha_ini, v_p.fecha_fin, v_p.id);
  return v_out || jsonb_build_object(
    'periodo_id', v_p.id,
    'estado', v_p.estado,
    'pagado_at', v_p.pagado_at,
    'simulacion', false
  );
end;
$$;

grant execute on function fn_proyeccion_periodo(uuid) to authenticated;
revoke execute on function fn_proyeccion_periodo(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Wrapper 2: SIMULADOR por rango libre (solo lectura, sin bonos/descuentos)
-- ---------------------------------------------------------------------------
create or replace function fn_simular_planilla(p_ini date, p_fin date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede simular la planilla.';
  end if;
  if p_ini is null or p_fin is null or p_fin < p_ini then
    raise exception 'Rango de fechas inválido.';
  end if;
  if (p_fin - p_ini) + 1 > 62 then
    raise exception 'La simulación admite máximo 62 días.';
  end if;
  return fn_planilla_calcular(p_ini, p_fin, null) || jsonb_build_object('simulacion', true);
end;
$$;

grant execute on function fn_simular_planilla(date, date) to authenticated;
revoke execute on function fn_simular_planilla(date, date) from public, anon;

notify pgrst, 'reload schema';
