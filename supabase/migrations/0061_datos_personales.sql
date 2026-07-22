-- ============================================================================
-- 0061_datos_personales.sql — Ficha de datos personales (sensibles) por persona
-- ============================================================================
-- PROMETE: guardar los datos personales que NO viven ya en el sistema — nombre
--   legal completo, DNI-foto, dirección, banco, nacimiento, estado civil, etc.
--   Tabla 1:1 con personas, con acceso restringido por su sensibilidad.
-- ASUME: personas, sedes, helpers RLS.
--
-- Núcleo mínimo (no duplicar): el SUELDO vive en asignaciones_salario, el
--   rango/función y la sede en personas, el email en personas.email, el DNI en
--   personas.documento. Aquí SOLO va lo nuevo, para no tener dos fuentes que se
--   contradigan.
--
-- Acceso (decisión de Felipe): admin/líder DO ven todo; la encargada de sede ve
--   la ficha de SU sede; cada colaborador ve solo la suya. (Nota: el número de
--   cuenta bancaria es el campo más sensible; si luego se quiere ocultarlo a la
--   encargada, se hace con una vista de columnas — no altera esta tabla.)

create table if not exists datos_personales (
  persona_id           uuid primary key references personas(id) on delete cascade,
  nombre_dni           text,          -- nombre completo tal como aparece en el DNI (para contratos/memos)
  fecha_nacimiento     date,
  estado_civil         text,
  direccion            text,
  celular              text,
  entidad_bancaria     text,
  numero_cuenta        text,
  grado_instruccion    text,
  hijos_menores        boolean,       -- ¿tiene hijos menores de 18 a su cargo?
  foto_dni_url         text,          -- enlaces de Google Drive (por ahora)
  foto_personal_url    text,
  foto_profesional_url text,
  actualizado_por      uuid references personas(id),
  actualizado_at       timestamptz not null default now()
);

alter table datos_personales enable row level security;

drop policy if exists dp_select_admin_lider on datos_personales;
create policy dp_select_admin_lider on datos_personales
  for select to authenticated using (fn_es_admin_o_lider());

drop policy if exists dp_select_supervisor on datos_personales;
create policy dp_select_supervisor on datos_personales
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona()));

drop policy if exists dp_select_propia on datos_personales;
create policy dp_select_propia on datos_personales
  for select to authenticated using (persona_id = fn_persona_actual_id());

-- Escritura solo por función (valida permiso; nada directo desde el cliente).
create or replace function fn_set_datos_personales(
  p_persona_id uuid,
  p_nombre_dni text default null, p_fecha_nacimiento date default null, p_estado_civil text default null,
  p_direccion text default null, p_celular text default null,
  p_entidad_bancaria text default null, p_numero_cuenta text default null,
  p_grado_instruccion text default null, p_hijos_menores boolean default null,
  p_foto_dni_url text default null, p_foto_personal_url text default null, p_foto_profesional_url text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (fn_es_admin_o_lider()
          or p_persona_id = fn_persona_actual_id()
          or (fn_rol_actual() = 'supervisor_sede'
              and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona())) then
    raise exception 'Sin permiso para editar los datos personales de esta persona.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'La persona no existe.';
  end if;
  insert into datos_personales as dp (
    persona_id, nombre_dni, fecha_nacimiento, estado_civil, direccion, celular,
    entidad_bancaria, numero_cuenta, grado_instruccion, hijos_menores,
    foto_dni_url, foto_personal_url, foto_profesional_url, actualizado_por, actualizado_at)
  values (
    p_persona_id, p_nombre_dni, p_fecha_nacimiento, p_estado_civil, p_direccion, p_celular,
    p_entidad_bancaria, p_numero_cuenta, p_grado_instruccion, p_hijos_menores,
    p_foto_dni_url, p_foto_personal_url, p_foto_profesional_url, fn_persona_actual_id(), now())
  on conflict (persona_id) do update set
    nombre_dni = excluded.nombre_dni, fecha_nacimiento = excluded.fecha_nacimiento,
    estado_civil = excluded.estado_civil, direccion = excluded.direccion, celular = excluded.celular,
    entidad_bancaria = excluded.entidad_bancaria, numero_cuenta = excluded.numero_cuenta,
    grado_instruccion = excluded.grado_instruccion, hijos_menores = excluded.hijos_menores,
    foto_dni_url = excluded.foto_dni_url, foto_personal_url = excluded.foto_personal_url,
    foto_profesional_url = excluded.foto_profesional_url,
    actualizado_por = fn_persona_actual_id(), actualizado_at = now();
end;
$$;

grant execute on function fn_set_datos_personales(uuid,text,date,text,text,text,text,text,text,boolean,text,text,text) to authenticated;
