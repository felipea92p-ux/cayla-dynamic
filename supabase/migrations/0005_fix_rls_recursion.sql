-- Fix: los helpers de RLS consultaban personas/terminales como el rol invocador,
-- lo que dispara las políticas de esas mismas tablas (que a su vez llaman a
-- estos mismos helpers) → recursión infinita ("stack depth limit exceeded").
-- security definer hace que la consulta interna corra como el dueño de la
-- función (postgres, con bypassrls), rompiendo el ciclo.

create or replace function fn_rol_actual()
returns rol_usuario
language sql stable security definer set search_path = public
as $$
  select rol from personas where auth_user_id = auth.uid();
$$;

create or replace function fn_persona_actual_id()
returns uuid
language sql stable security definer set search_path = public
as $$
  select id from personas where auth_user_id = auth.uid();
$$;

create or replace function fn_sede_actual_persona()
returns uuid
language sql stable security definer set search_path = public
as $$
  select sede_base_id from personas where auth_user_id = auth.uid();
$$;

create or replace function fn_sede_actual_terminal()
returns uuid
language sql stable security definer set search_path = public
as $$
  select sede_id from terminales where auth_user_id = auth.uid() and activo;
$$;
