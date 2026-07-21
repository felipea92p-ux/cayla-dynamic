-- ============================================================================
-- 0052_incidencias_aceptadas.sql — "Aceptar" una incidencia (visto bueno)
-- ============================================================================
-- Felipe: en Trujillo a veces cierran antes de forma eventual; esa salida
-- anticipada la revisa y la da por buena, y no quiere que le siga apareciendo.
-- Un botón "Aceptar" marca la incidencia como revisada-y-aceptada y la saca de la
-- lista activa — pero con RASTRO (quién y cuándo), no la borra: consta que la
-- aceptaste. Por ahora solo aplica a salida anticipada (decisión de Felipe), pero
-- la tabla guarda `tipo` para poder extenderlo sin migrar de nuevo.

create table if not exists incidencias_aceptadas (
  id            uuid primary key default gen_random_uuid(),
  persona_id    uuid not null references personas(id),
  fecha         date not null,
  tipo          text not null,          -- p. ej. 'salida_anticipada'
  nota          text,
  aceptado_por  uuid not null references personas(id),
  aceptado_at   timestamptz not null default now(),
  unique (persona_id, fecha, tipo)      -- una incidencia se acepta una vez
);
create index if not exists idx_inc_acept on incidencias_aceptadas (persona_id, fecha);

alter table incidencias_aceptadas enable row level security;
drop policy if exists inc_acept_select_admin_lider on incidencias_aceptadas;
create policy inc_acept_select_admin_lider on incidencias_aceptadas
  for select to authenticated using (fn_es_admin_o_lider());
drop policy if exists inc_acept_select_supervisor on incidencias_aceptadas;
create policy inc_acept_select_supervisor on incidencias_aceptadas
  for select to authenticated using (
    fn_rol_actual() = 'supervisor_sede'
    and persona_id in (select id from personas where sede_base_id = fn_sede_actual_persona())
  );

-- Aceptar (permiso vía fn_verificar_corrector: admin/líder o encargada de su sede).
create or replace function fn_aceptar_incidencia(
  p_persona_id uuid, p_fecha date, p_tipo text, p_nota text default null
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if p_tipo is null or length(trim(p_tipo)) = 0 then
    raise exception 'Tipo de incidencia inválido.';
  end if;
  insert into incidencias_aceptadas (persona_id, fecha, tipo, nota, aceptado_por)
  values (p_persona_id, p_fecha, trim(p_tipo), nullif(trim(coalesce(p_nota,'')),''), v_editor)
  on conflict (persona_id, fecha, tipo)
  do update set nota = excluded.nota, aceptado_por = excluded.aceptado_por, aceptado_at = now();
end;
$$;

-- Deshacer (por si aceptó por error).
create or replace function fn_quitar_aceptacion(p_persona_id uuid, p_fecha date, p_tipo text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform fn_verificar_corrector(p_persona_id);
  delete from incidencias_aceptadas where persona_id = p_persona_id and fecha = p_fecha and tipo = trim(p_tipo);
end;
$$;

grant execute on function fn_aceptar_incidencia(uuid, date, text, text) to authenticated;
grant execute on function fn_quitar_aceptacion(uuid, date, text) to authenticated;
