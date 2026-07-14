-- ============================================================================
-- APLICAR 0032 — Checklist de objetivos SMART (pegar completo en el SQL Editor
-- de Supabase). Fuente: supabase/migrations/0032_objetivos_checklist.sql
-- Verificado empíricamente contra Postgres local el 2026-07-14: 12/12 PASS
-- (guards null-safe cerrados, sync checklist→plus, candado mes pagado,
--  checklist bloquea el número manual). Idempotente.
-- ============================================================================

-- ============================================================================
-- 0032 — CHECKLIST DE OBJETIVOS SMART (spec Felipe 2026-07-13)
-- ----------------------------------------------------------------------------
-- Reemplaza el número simple de objetivos_mensuales por una lista de objetivos
-- con texto por persona/mes, marcables uno a uno. El plus de la planilla NO
-- cambia: el checklist SINCRONIZA cumplidos/total hacia objetivos_mensuales y
-- fn_planilla_calcular sigue leyendo de ahí (motor de dinero intacto).
--
-- Reglas:
--   · Marcan/gestionan SOLO admin y líder DO (cualquier persona), y la
--     encargada de sede (supervisor_sede) SOLO integrantes de SU sede.
--     Los objetivos de las encargadas los gestiona admin/líder.
--   · El integrante VE los suyos (solo lectura, en Perfil).
--   · Mes con planilla PAGADA = bloqueado (para corregir: reabrir el periodo,
--     mismo patrón que fn_set_objetivos v2 de 0025).
--   · Cuando un mes tiene checklist, el número manual (fn_set_objetivos) se
--     bloquea: el checklist manda.
-- Todo lee/escribe vía RPC jsonb (patrón 0020: el schema cache de PostgREST
-- no es confiable para tablas/columnas nuevas). Guards null-safe:
-- `is not true` (nunca `if not f()`).
-- ============================================================================

create table if not exists objetivos_items (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references personas(id),
  anio int not null check (anio between 2020 and 2100),
  mes int not null check (mes between 1 and 12),
  descripcion text not null check (length(btrim(descripcion)) between 1 and 300),
  cumplido boolean not null default false,
  orden int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_objetivos_items_persona_mes
  on objetivos_items (persona_id, anio, mes);

alter table objetivos_items enable row level security;

-- Lectura: admin/líder todo · encargada su sede · la propia persona.
-- Escritura: SIN policies — solo vía RPC security definer (como objetivos_mensuales).
drop policy if exists objetivos_items_select on objetivos_items;
create policy objetivos_items_select on objetivos_items
  for select to authenticated
  using (
    fn_es_admin_o_lider() is true
    or (fn_rol_actual() = 'supervisor_sede' and exists (
          select 1 from personas p
          where p.id = objetivos_items.persona_id
            and p.sede_base_id = fn_sede_actual_persona()))
    or persona_id = fn_persona_actual_id()
  );

-- ---------------------------------------------------------------------------
-- ¿Quién puede GESTIONAR (crear/marcar/editar/borrar) los objetivos de X?
-- admin y lider_do: cualquiera. Encargada: solo integrantes de SU sede
-- (ni otras encargadas ni ella misma: sus objetivos los gestiona admin).
-- ---------------------------------------------------------------------------
create or replace function fn_puede_gestionar_objetivos(p_persona_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select case
    when fn_es_admin_o_lider() is true then true
    when fn_rol_actual() = 'supervisor_sede' then exists (
      select 1 from personas p
      where p.id = p_persona_id
        and p.sede_base_id = fn_sede_actual_persona()
        and p.rol = 'integrante'
    )
    else false
  end;
$$;

grant execute on function fn_puede_gestionar_objetivos(uuid) to authenticated;
revoke execute on function fn_puede_gestionar_objetivos(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Candado de mes pagado (mismo criterio que fn_set_objetivos v2: el periodo
-- cuya etiqueta — mes de fecha_fin — coincide y está 'pagado').
-- ---------------------------------------------------------------------------
create or replace function fn_mes_planilla_pagado(p_anio int, p_mes int)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and extract(year from fecha_fin)::int = p_anio
      and extract(month from fecha_fin)::int = p_mes
  );
$$;

revoke execute on function fn_mes_planilla_pagado(int, int) from public, anon;
grant execute on function fn_mes_planilla_pagado(int, int) to authenticated;

-- ---------------------------------------------------------------------------
-- Sincronización checklist → objetivos_mensuales (el plus sale de ahí).
-- Interna: la llaman las RPC de mutación; sin grant a authenticated.
-- Si el mes queda sin items, se borra la fila (vuelve a "sin registro").
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_sync_mes(p_persona_id uuid, p_anio int, p_mes int)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_total int;
  v_cumplidos int;
begin
  select count(*), count(*) filter (where cumplido)
    into v_total, v_cumplidos
  from objetivos_items
  where persona_id = p_persona_id and anio = p_anio and mes = p_mes;

  if v_total = 0 then
    delete from objetivos_mensuales
    where persona_id = p_persona_id and anio = p_anio and mes = p_mes;
  else
    insert into objetivos_mensuales (persona_id, anio, mes, cumplidos, total)
    values (p_persona_id, p_anio, p_mes, v_cumplidos, v_total)
    on conflict (persona_id, anio, mes) do update set
      cumplidos = excluded.cumplidos,
      total = excluded.total,
      updated_at = now();
  end if;
end;
$$;

revoke execute on function fn_objetivos_sync_mes(uuid, int, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Lectura del checklist (jsonb, visibilidad = policy de arriba replicada)
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_checklist(p_anio int, p_mes int, p_persona_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', oi.id,
           'persona_id', oi.persona_id,
           'descripcion', oi.descripcion,
           'cumplido', oi.cumplido,
           'orden', oi.orden
         ) order by oi.orden, oi.created_at), '[]'::jsonb)
  from objetivos_items oi
  where oi.anio = p_anio and oi.mes = p_mes
    and (p_persona_id is null or oi.persona_id = p_persona_id)
    and (
      fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and exists (
            select 1 from personas p
            where p.id = oi.persona_id
              and p.sede_base_id = fn_sede_actual_persona()))
      or oi.persona_id = fn_persona_actual_id()
    );
$$;

grant execute on function fn_objetivos_checklist(int, int, uuid) to authenticated;
revoke execute on function fn_objetivos_checklist(int, int, uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Resumen cumplidos/total por persona del mes (para barras de progreso y para
-- avisar cuando un mes tiene registro manual sin checklist).
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_resumen(p_anio int, p_mes int)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', om.persona_id,
           'cumplidos', om.cumplidos,
           'total', om.total,
           'con_checklist', exists (
             select 1 from objetivos_items oi
             where oi.persona_id = om.persona_id and oi.anio = om.anio and oi.mes = om.mes
           )
         )), '[]'::jsonb)
  from objetivos_mensuales om
  where om.anio = p_anio and om.mes = p_mes
    and (
      fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and exists (
            select 1 from personas p
            where p.id = om.persona_id
              and p.sede_base_id = fn_sede_actual_persona()))
      or om.persona_id = fn_persona_actual_id()
    );
$$;

grant execute on function fn_objetivos_resumen(int, int) to authenticated;
revoke execute on function fn_objetivos_resumen(int, int) from public, anon;

-- ---------------------------------------------------------------------------
-- Agregar objetivo
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_agregar(p_persona_id uuid, p_anio int, p_mes int, p_descripcion text)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_desc text := btrim(coalesce(p_descripcion, ''));
  v_item objetivos_items;
begin
  if fn_puede_gestionar_objetivos(p_persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if p_persona_id is null or not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;
  if p_anio is null or p_mes is null or p_mes not between 1 and 12 or p_anio not between 2020 and 2100 then
    raise exception 'Mes inválido.';
  end if;
  if length(v_desc) < 1 or length(v_desc) > 300 then
    raise exception 'El objetivo debe tener entre 1 y 300 caracteres.';
  end if;
  if fn_mes_planilla_pagado(p_anio, p_mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  if (select count(*) from objetivos_items
      where persona_id = p_persona_id and anio = p_anio and mes = p_mes) >= 20 then
    raise exception 'Máximo 20 objetivos por persona y mes.';
  end if;

  insert into objetivos_items (persona_id, anio, mes, descripcion, orden)
  values (
    p_persona_id, p_anio, p_mes, v_desc,
    coalesce((select max(orden) from objetivos_items
              where persona_id = p_persona_id and anio = p_anio and mes = p_mes), 0) + 1
  )
  returning * into v_item;

  perform fn_objetivos_sync_mes(p_persona_id, p_anio, p_mes);

  return jsonb_build_object(
    'id', v_item.id, 'persona_id', v_item.persona_id,
    'descripcion', v_item.descripcion, 'cumplido', v_item.cumplido, 'orden', v_item.orden
  );
end;
$$;

grant execute on function fn_objetivo_agregar(uuid, int, int, text) to authenticated;
revoke execute on function fn_objetivo_agregar(uuid, int, int, text) from public, anon;

-- ---------------------------------------------------------------------------
-- Marcar / desmarcar
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_marcar(p_item_id uuid, p_cumplido boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item objetivos_items;
begin
  select * into v_item from objetivos_items where id = p_item_id;
  if not found then raise exception 'Objetivo inexistente.'; end if;
  if fn_puede_gestionar_objetivos(v_item.persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if fn_mes_planilla_pagado(v_item.anio, v_item.mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  if p_cumplido is null then raise exception 'Valor inválido.'; end if;

  update objetivos_items set cumplido = p_cumplido, updated_at = now() where id = p_item_id;
  perform fn_objetivos_sync_mes(v_item.persona_id, v_item.anio, v_item.mes);
end;
$$;

grant execute on function fn_objetivo_marcar(uuid, boolean) to authenticated;
revoke execute on function fn_objetivo_marcar(uuid, boolean) from public, anon;

-- ---------------------------------------------------------------------------
-- Editar el texto
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_editar(p_item_id uuid, p_descripcion text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item objetivos_items;
  v_desc text := btrim(coalesce(p_descripcion, ''));
begin
  select * into v_item from objetivos_items where id = p_item_id;
  if not found then raise exception 'Objetivo inexistente.'; end if;
  if fn_puede_gestionar_objetivos(v_item.persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if fn_mes_planilla_pagado(v_item.anio, v_item.mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  if length(v_desc) < 1 or length(v_desc) > 300 then
    raise exception 'El objetivo debe tener entre 1 y 300 caracteres.';
  end if;

  update objetivos_items set descripcion = v_desc, updated_at = now() where id = p_item_id;
end;
$$;

grant execute on function fn_objetivo_editar(uuid, text) to authenticated;
revoke execute on function fn_objetivo_editar(uuid, text) from public, anon;

-- ---------------------------------------------------------------------------
-- Eliminar
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_eliminar(p_item_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item objetivos_items;
begin
  select * into v_item from objetivos_items where id = p_item_id;
  if not found then raise exception 'Objetivo inexistente.'; end if;
  if fn_puede_gestionar_objetivos(v_item.persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if fn_mes_planilla_pagado(v_item.anio, v_item.mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;

  delete from objetivos_items where id = p_item_id;
  perform fn_objetivos_sync_mes(v_item.persona_id, v_item.anio, v_item.mes);
end;
$$;

grant execute on function fn_objetivo_eliminar(uuid) to authenticated;
revoke execute on function fn_objetivo_eliminar(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- fn_set_objetivos v3: si el mes ya tiene checklist, el número manual se
-- bloquea (el checklist manda). Resto idéntico a v2 (0025).
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
    select 1 from objetivos_items
    where persona_id = p_persona_id and anio = p_anio and mes = p_mes
  ) then
    raise exception 'Ese mes ya usa checklist de objetivos: gestiónalo en la página Objetivos.';
  end if;
  if fn_mes_planilla_pagado(p_anio, p_mes) is true then
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
