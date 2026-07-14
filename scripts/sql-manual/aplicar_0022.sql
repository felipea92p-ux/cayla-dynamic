-- ============================================================================
-- Catálogo de ÁREAS editable por Felipe (deja de ser una lista fija en código)
-- ----------------------------------------------------------------------------
-- `areas` guarda el catálogo: nombre visible, si es OPERATIVA DE SEDE (cuenta
-- para la cobertura de tienda en /admin/turnos), si está activa, y el orden.
-- personas.funcion pasa de CHECK fijo a FK → areas(codigo).
-- OJO caché PostgREST trabado: la tabla nueva NO se lee por REST — todo va por
-- RPC jsonb (fn_areas / fn_guardar_area / fn_area_activa), igual que 0020.
-- Re-ejecutable sin peligro (if exists / on conflict / create or replace).
-- ============================================================================

create table if not exists areas (
  codigo text primary key check (codigo ~ '^[a-z0-9_]{2,40}$'),
  nombre text not null check (length(trim(nombre)) >= 2),
  operativa boolean not null default false,
  activa boolean not null default true,
  orden int not null default 100,
  created_at timestamptz not null default now()
);

insert into areas (codigo, nombre, operativa, orden) values
  ('calidad_servicio', 'Calidad & servicio al cliente', true, 1),
  ('taller_produccion', 'Taller y producción', true, 2),
  ('estrategia_comercial', 'Estrategia comercial', false, 3),
  ('desarrollo_organizacional', 'Desarrollo organizacional', false, 4),
  ('experiencia_marca', 'Experiencia, marca y comunidad', false, 5),
  ('crecimiento_expansion', 'Crecimiento y expansión', false, 6)
on conflict (codigo) do nothing;

alter table areas enable row level security;
drop policy if exists areas_select_autenticados on areas;
create policy areas_select_autenticados on areas
  for select to authenticated using (true);
-- escritura: SOLO vía RPC (sin policies de insert/update)

-- personas.funcion: de CHECK fijo → FK al catálogo
alter table personas drop constraint if exists personas_funcion_check;
alter table personas drop constraint if exists personas_funcion_fk;
alter table personas add constraint personas_funcion_fk
  foreign key (funcion) references areas(codigo);

-- ---------------------------------------------------------------------------
-- fn_areas: catálogo completo (activas e inactivas, con flag) para el panel.
-- ---------------------------------------------------------------------------
create or replace function fn_areas()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'codigo', a.codigo, 'nombre', a.nombre, 'operativa', a.operativa,
           'activa', a.activa, 'orden', a.orden)
           order by a.orden, a.nombre), '[]'::jsonb)
  from areas a;
$$;

grant execute on function fn_areas() to authenticated;

-- ---------------------------------------------------------------------------
-- fn_guardar_area: crea o edita un área (upsert por código). Solo admin/líder.
-- ---------------------------------------------------------------------------
create or replace function fn_guardar_area(
  p_codigo text,
  p_nombre text,
  p_operativa boolean,
  p_orden int default null
)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar áreas.';
  end if;
  if p_codigo is null or p_codigo !~ '^[a-z0-9_]{2,40}$' then
    raise exception 'Código inválido (solo minúsculas, números y _): %', coalesce(p_codigo, '(vacío)');
  end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre del área es obligatorio.';
  end if;

  insert into areas (codigo, nombre, operativa, orden)
  values (p_codigo, trim(p_nombre), coalesce(p_operativa, false), coalesce(p_orden, 100))
  on conflict (codigo) do update set
    nombre = excluded.nombre,
    operativa = excluded.operativa,
    orden = coalesce(p_orden, areas.orden);
end;
$$;

grant execute on function fn_guardar_area(text, text, boolean, int) to authenticated;

-- ---------------------------------------------------------------------------
-- fn_area_activa: activar/desactivar un área. Desactivar NO borra nada: la
-- gente que la tiene la conserva (FK sigue válida); solo desaparece del
-- selector para nuevas asignaciones. 'calidad_servicio' no se puede desactivar
-- (es el default del sistema para altas y degradaciones).
-- ---------------------------------------------------------------------------
create or replace function fn_area_activa(p_codigo text, p_activa boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar áreas.';
  end if;
  if p_codigo = 'calidad_servicio' and p_activa is not true then
    raise exception 'Calidad & servicio es el área base del sistema y no se puede desactivar.';
  end if;
  update areas set activa = coalesce(p_activa, true) where codigo = p_codigo;
  if not found then
    raise exception 'Área inexistente: %', coalesce(p_codigo, '(vacía)');
  end if;
end;
$$;

grant execute on function fn_area_activa(text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- fn_set_funcion v3 / fn_crear_persona v3: validan contra el catálogo (solo
-- áreas ACTIVAS para nuevas asignaciones). Mismos guards null-safe.
-- ---------------------------------------------------------------------------
create or replace function fn_set_funcion(p_persona_id uuid, p_funcion text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar el área.';
  end if;
  if p_funcion is null or not exists (select 1 from areas where codigo = p_funcion and activa) then
    raise exception 'Área inválida o inactiva: %', coalesce(p_funcion, '(vacía)');
  end if;
  update personas set funcion = p_funcion where id = p_persona_id;
  if not found then
    raise exception 'Persona inválida.';
  end if;
end;
$$;

grant execute on function fn_set_funcion(uuid, text) to authenticated;

create or replace function fn_crear_persona(
  p_nombres text,
  p_apellidos text,
  p_sede_base_id uuid,
  p_rol text,
  p_funcion text,
  p_email text,
  p_pin_hash text
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede crear personas.';
  end if;
  if trim(coalesce(p_nombres, '')) = '' or trim(coalesce(p_apellidos, '')) = '' then
    raise exception 'Nombres y apellidos son obligatorios.';
  end if;
  if not exists (select 1 from sedes where id = p_sede_base_id) then
    raise exception 'Sede inválida.';
  end if;
  if p_rol is null or p_rol not in ('integrante', 'supervisor_sede', 'lider_do', 'admin') then
    raise exception 'Rol inválido: %', coalesce(p_rol, '(vacío)');
  end if;
  if p_funcion is null or not exists (select 1 from areas where codigo = p_funcion and activa) then
    raise exception 'Área inválida o inactiva: %', coalesce(p_funcion, '(vacía)');
  end if;
  if p_pin_hash is null or p_pin_hash = '' then
    raise exception 'Falta el PIN.';
  end if;

  insert into personas (nombres, apellidos, sede_base_id, rol, funcion, email, pin_hash)
  values (
    trim(p_nombres), trim(p_apellidos), p_sede_base_id,
    p_rol::rol_usuario, p_funcion, nullif(trim(coalesce(p_email, '')), ''), p_pin_hash
  )
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$$;

grant execute on function fn_crear_persona(text, text, uuid, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
