-- ============================================================================
-- PROYECCIÓN DE PLANILLA — el motor de cálculo (modelo confirmado con Felipe)
-- ----------------------------------------------------------------------------
--   pago_base = Σ por tramo de salario: horas_del_tramo × (salario ÷ base_mes)
--   base_mes  = 6.5 × días del mes (30d→195, 31d→201.5, feb 28→182)
--   feriados (solo NACIONALES por ley PE; tabla editable):
--     · por cada feriado: + proporcional × tarifa   (trabajado o no)
--     · si además lo trabajó: + horas de ese día × tarifa (el "doble"; las horas
--       del feriado se cuentan UNA vez en el total del mes — el doble es premio)
--     · proporcional = 7.5 h × (horas_del_mes ÷ base_mes)
--   plus de objetivos (manual, por mes): 100% cumplidos → 21% del salario de
--     referencia; ≥60% → 12.6%; <60% → 0. COMPLETO (no proporcional a horas).
--   cambios de salario a mitad de mes → POR TRAMOS exactos (decisión 2026-07-13);
--     la práctica "paga desde el próximo mes" se logra poniendo vigente_desde = 1°
--     del mes siguiente.
--   días auto-cerrados pendientes: SÍ suman horas + se reportan para alerta.
-- Solo admin/lider ve la planilla. Todo por RPC (caché PostgREST trabado).
-- Re-ejecutable sin peligro.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Feriados nacionales (ley peruana). Editable desde el panel.
-- ---------------------------------------------------------------------------
create table if not exists feriados (
  fecha date primary key,
  nombre text not null check (length(trim(nombre)) >= 2)
);

insert into feriados (fecha, nombre) values
  ('2026-01-01', 'Año Nuevo'),
  ('2026-04-02', 'Jueves Santo'),
  ('2026-04-03', 'Viernes Santo'),
  ('2026-05-01', 'Día del Trabajo'),
  ('2026-06-07', 'Batalla de Arica y Día de la Bandera'),
  ('2026-06-29', 'San Pedro y San Pablo'),
  ('2026-07-23', 'Día de la Fuerza Aérea del Perú'),
  ('2026-07-28', 'Fiestas Patrias'),
  ('2026-07-29', 'Fiestas Patrias'),
  ('2026-08-06', 'Batalla de Junín'),
  ('2026-08-30', 'Santa Rosa de Lima'),
  ('2026-10-08', 'Combate de Angamos'),
  ('2026-11-01', 'Todos los Santos'),
  ('2026-12-08', 'Inmaculada Concepción'),
  ('2026-12-09', 'Batalla de Ayacucho'),
  ('2026-12-25', 'Navidad')
on conflict (fecha) do nothing;

alter table feriados enable row level security;
drop policy if exists feriados_select_autenticados on feriados;
create policy feriados_select_autenticados on feriados
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Objetivos mensuales por persona (input manual del plus)
-- ---------------------------------------------------------------------------
create table if not exists objetivos_mensuales (
  persona_id uuid not null references personas(id),
  anio int not null check (anio between 2020 and 2100),
  mes int not null check (mes between 1 and 12),
  cumplidos int not null check (cumplidos >= 0),
  total int not null default 10 check (total > 0),
  updated_at timestamptz not null default now(),
  primary key (persona_id, anio, mes),
  check (cumplidos <= total)
);

alter table objetivos_mensuales enable row level security;
drop policy if exists objetivos_admin_lider on objetivos_mensuales;
create policy objetivos_admin_lider on objetivos_mensuales
  for select to authenticated using (fn_es_admin_o_lider());
-- escritura: SOLO vía RPC

-- ---------------------------------------------------------------------------
-- Blindaje de asignaciones_salario (hallazgo del auditor matemático):
-- 1) dos tramos solapados harían que el mismo día se pague con AMBAS tarifas →
--    constraint de exclusión por rango de fechas (imposible insertar solapes);
-- 2) la política era FOR ALL: un admin podía escribir tramos directo por REST
--    saltándose fn_set_salario → queda SOLO lectura; se escribe únicamente vía
--    fn_set_salario (security definer), igual que objetivos_mensuales.
-- ---------------------------------------------------------------------------
create extension if not exists btree_gist;

alter table asignaciones_salario drop constraint if exists asignacion_salario_sin_solape;
alter table asignaciones_salario add constraint asignacion_salario_sin_solape
  exclude using gist (
    persona_id with =,
    daterange(vigente_desde, coalesce(vigente_hasta, 'infinity'::date), '[]') with &&
  );

drop policy if exists salario_admin_lider on asignaciones_salario;
create policy salario_admin_lider on asignaciones_salario
  for select to authenticated
  using (fn_es_admin_o_lider());

-- ---------------------------------------------------------------------------
-- Factores de PROVISIÓN (régimen MYPE pequeña empresa; validar con el contador;
-- editables aquí sin tocar código): gratificación 50% de ley = medio sueldo por
-- semestre (≈8.33%/mes); CTS 15 días/año (≈4.17%); vacaciones 15 días/año (≈4.17%).
-- Se aplican sobre lo GANADO REAL del mes (base + feriados) → proporcional exacto
-- al tiempo laborado, como pidió Felipe.
-- ---------------------------------------------------------------------------
insert into configuracion (clave, valor, descripcion) values (
  'planilla_provisiones',
  '{"gratificacion": 0.08333, "cts": 0.04167, "vacaciones": 0.04167}'::jsonb,
  'Factores mensuales de provisión (MYPE pequeña empresa) aplicados sobre pago_base + feriados. Validar con contador.'
) on conflict (clave) do nothing;

-- ---------------------------------------------------------------------------
-- Gestión de feriados
-- ---------------------------------------------------------------------------
create or replace function fn_feriados(p_anio int)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
  from feriados f
  where extract(year from f.fecha) = p_anio;
$$;

grant execute on function fn_feriados(int) to authenticated;
revoke execute on function fn_feriados(int) from public, anon;

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
  delete from feriados where fecha = p_fecha;
  if not found then raise exception 'No hay feriado en esa fecha.'; end if;
end;
$$;

grant execute on function fn_quitar_feriado(date) to authenticated;
revoke execute on function fn_quitar_feriado(date) from public, anon;

-- ---------------------------------------------------------------------------
-- Registro de objetivos del mes
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
-- EL MOTOR: fn_proyeccion_planilla(año, mes) → jsonb con el desglose por persona
-- ---------------------------------------------------------------------------
create or replace function fn_proyeccion_planilla(p_anio int, p_mes int)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_ini date; v_fin date; v_dias int; v_base numeric;
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la proyección de planilla.';
  end if;
  if p_anio is null or p_mes is null or p_mes not between 1 and 12 then
    raise exception 'Mes inválido.';
  end if;

  v_ini := make_date(p_anio, p_mes, 1);
  v_fin := (v_ini + interval '1 month' - interval '1 day')::date;
  v_dias := extract(day from v_fin)::int;
  v_base := 6.5 * v_dias;

  -- factores de provisión (editables en configuracion.planilla_provisiones)
  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion": 0.08333, "cts": 0.04167, "vacaciones": 0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vacas := coalesce((v_prov->>'vacaciones')::numeric, 0);

  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_feriados
  from feriados f
  where f.fecha between v_ini and v_fin;

  with pers as (
    -- activos + cualquiera que haya trabajado en el mes (bajas a mitad de mes)
    select p.id, p.nombres, p.apellidos, p.estado, s.codigo as sede
    from personas p
    join sedes s on s.id = p.sede_base_id
    where p.estado = 'activo'
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between v_ini and v_fin)
  ),
  horas as (
    select j.persona_id, j.fecha,
           coalesce(j.horas_trabajadas, 0) as h,
           (j.estado = 'auto_cerrada_pendiente') as pendiente
    from jornadas j
    where j.fecha between v_ini and v_fin
  ),
  tramos as (
    -- tramos de salario que tocan el mes, recortados al mes
    select a.persona_id, a.rango, a.salario_mensual_soles as salario,
           greatest(a.vigente_desde, v_ini) as t_ini,
           least(coalesce(a.vigente_hasta, v_fin), v_fin) as t_fin
    from asignaciones_salario a
    where a.vigente_desde <= v_fin
      and (a.vigente_hasta is null or a.vigente_hasta >= v_ini)
  )
  select jsonb_build_object(
    'anio', p_anio,
    'mes', p_mes,
    'dias_mes', v_dias,
    'base_horas', v_base,
    'feriados', v_feriados,
    'factores_provision', v_prov,
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
        -- observación por bajo desempeño (menos del 30% de objetivos): en contra
        -- de los principios de CAYLA — se marca para conversación, nunca automático
        'bajo_desempeno', (obj.cumplidos is not null and obj.total > 0
                           and obj.cumplidos::numeric / obj.total < 0.3),
        'feriados_sin_salario', fer.sin_tramo,
        -- provisiones MYPE sobre lo ganado real del mes (base + feriados):
        -- proporcional exacto al tiempo laborado
        'provision_gratificacion', round((pb.pago_base + fer.monto) * v_f_grati, 2),
        'provision_cts', round((pb.pago_base + fer.monto) * v_f_cts, 2),
        'provision_vacaciones', round((pb.pago_base + fer.monto) * v_f_vacas, 2),
        'provision_total', round((pb.pago_base + fer.monto) * (v_f_grati + v_f_cts + v_f_vacas), 2),
        -- total = suma de las partes YA redondeadas (el desglose siempre cuadra al céntimo)
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
      ) as fila
    from pers pe
    -- horas del mes (los días pendientes de revisión SÍ suman; se reportan aparte)
    left join lateral (
      select coalesce(sum(x.h), 0) as horas_mes,
             count(*) filter (where x.h > 0) as dias,
             count(*) filter (where x.pendiente) as pendientes
      from horas x where x.persona_id = pe.id
    ) h on true
    -- pago base por tramos: cada día se paga con la tarifa de UN SOLO tramo que
    -- lo cubre (lateral con limit 1: aunque existieran datos solapados por vías
    -- imprevistas, un día jamás se paga dos veces)
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
    -- salario de referencia (para mostrar y para el plus): el último tramo del mes
    left join lateral (
      select t.rango, t.salario
      from tramos t
      where t.persona_id = pe.id
      order by t.t_fin desc, t.t_ini desc
      limit 1
    ) ref on true
    -- feriados: (horas trabajadas ese día [doble] + proporcional) × tarifa del
    -- ÚNICO tramo que cubre el feriado; un feriado sin tramo se REPORTA (no se
    -- omite en silencio) para que se le asigne salario
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
      where f.fecha between v_ini and v_fin
    ) fer on true
    -- plus de objetivos: completo (no proporcional a horas), sobre el salario de referencia
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
        on om.persona_id = pe.id and om.anio = p_anio and om.mes = p_mes
    ) obj on true
  ) sub;

  return v_out;
end;
$$;

grant execute on function fn_proyeccion_planilla(int, int) to authenticated;
revoke execute on function fn_proyeccion_planilla(int, int) from public, anon;

notify pgrst, 'reload schema';
