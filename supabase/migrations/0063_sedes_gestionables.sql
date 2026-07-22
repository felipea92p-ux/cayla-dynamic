-- ============================================================================
-- 0063 — Sedes gestionables
-- ----------------------------------------------------------------------------
-- CONTEXTO: hasta hoy "sede = ciudad" con un candado que solo permitía TRU/LIM/AQP.
-- CAYLA tendrá dos locales en Lima (tienda + taller) y gente sin sede fija
-- (dirección/DO). Este cambio suelta el candado y da funciones para crear,
-- renombrar y activar/desactivar sedes desde el panel — SIN permitir borrar
-- (borrar una sede con gente asignada dejaría personas huérfanas).
--
-- Nada en el código depende de las letras "LIM/AQP/TRU": las sedes se
-- referencian siempre por su id. Por eso agregar sedes nuevas es seguro.
-- ============================================================================

-- 1) Soltar el candado viejo (enum de 3 valores). Se identifica por su definición
--    (contiene 'TRU'), así el DROP no depende del nombre exacto del constraint.
do $$
declare c text;
begin
  select conname into c
  from pg_constraint
  where conrelid = 'sedes'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) like '%TRU%';
  if c is not null then
    execute format('alter table sedes drop constraint %I', c);
  end if;
end $$;

-- 2) Nuevo candado de FORMATO (no de lista): código = 2 a 8 letras/números en
--    mayúsculas. Sigue evitando basura, pero ya no limita cuáles pueden existir.
alter table sedes drop constraint if exists sedes_codigo_formato;
alter table sedes add constraint sedes_codigo_formato check (codigo ~ '^[A-Z0-9]{2,8}$');

-- 3) fn_guardar_sede: crear una sede nueva o renombrar una existente (upsert por
--    código). El código es la identidad estable (aparece en tablas y reportes) y
--    NO cambia al renombrar; lo editable es el nombre. Admin o líder (DO).
create or replace function fn_guardar_sede(p_codigo text, p_nombre text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar sedes.';
  end if;
  if p_codigo is null or upper(trim(p_codigo)) !~ '^[A-Z0-9]{2,8}$' then
    raise exception 'Código inválido (2 a 8 letras/números, ej. LIMT): %', coalesce(p_codigo, '(vacío)');
  end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre de la sede es obligatorio.';
  end if;

  insert into sedes (codigo, nombre)
  values (upper(trim(p_codigo)), trim(p_nombre))
  on conflict (codigo) do update set nombre = excluded.nombre;
end;
$$;
grant execute on function fn_guardar_sede(text, text) to authenticated;
revoke execute on function fn_guardar_sede(text, text) from public, anon;

-- 4) fn_sede_activa: activar/desactivar. Desactivar NO borra: la gente asignada
--    la conserva; solo desaparece del selector para nuevas asignaciones.
create or replace function fn_sede_activa(p_codigo text, p_activa boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar sedes.';
  end if;
  update sedes set activa = coalesce(p_activa, true) where codigo = upper(trim(p_codigo));
end;
$$;
grant execute on function fn_sede_activa(text, boolean) to authenticated;
revoke execute on function fn_sede_activa(text, boolean) from public, anon;

-- ============================================================================
-- Bandera "visible en todas las sedes"
-- ----------------------------------------------------------------------------
-- Ya existía la columna personas.visible_todas_sedes (mig. 0008) y la RLS del
-- terminal ya la respeta: una persona con esta bandera aparece en el terminal de
-- CUALQUIER sede (para quien rota entre locales). Faltaba poder verla y tocarla
-- desde el panel. La columna está atrapada en el schema cache de PostgREST (como
-- funcion/con_hijos), así que se LEE por fn_personas_funciones y se ESCRIBE por
-- una RPC dedicada — mismo patrón que es_encargada_piso.
-- ============================================================================

-- 5) fn_personas_funciones: agregar visible_todas_sedes al payload (sin quitar nada).
create or replace function fn_personas_funciones()
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', p.id, 'funcion', p.funcion, 'con_hijos', p.con_hijos,
           'es_encargada_piso', p.es_encargada_piso,
           'visible_todas_sedes', p.visible_todas_sedes)), '[]'::jsonb)
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

-- 6) fn_set_visible_todas_sedes: activar/desactivar la bandera. Admin o líder.
create or replace function fn_set_visible_todas_sedes(p_persona_id uuid, p_valor boolean)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la visibilidad entre sedes.';
  end if;
  update personas set visible_todas_sedes = coalesce(p_valor, false) where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$$;
grant execute on function fn_set_visible_todas_sedes(uuid, boolean) to authenticated;
revoke execute on function fn_set_visible_todas_sedes(uuid, boolean) from public, anon;

notify pgrst, 'reload schema';
