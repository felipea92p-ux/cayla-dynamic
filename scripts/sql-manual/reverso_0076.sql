-- ============================================================================
-- REVERSO de 0076_cerrar_ejecucion_anonima.sql
-- ----------------------------------------------------------------------------
-- Deja la base como estaba ANTES de la 0076. Se corre solo si algo sale mal:
-- no es parte de la secuencia de migraciones, por eso vive aquí y no en
-- supabase/migrations.
--
-- ADVERTENCIA: esto vuelve a ABRIR la ejecución anónima de 54 funciones y
-- devuelve la firma escaneada a una columna legible por la API. Es un botón de
-- emergencia, no una alternativa.
--
-- Correr TODO de una vez (es una sola transacción implícita en psql con
-- ON_ERROR_STOP=1; si algo falla, no queda a medias).
-- ============================================================================

begin;

-- ── 1 · Devolver la firma a personas ─────────────────────────────────────────
alter table personas add column if not exists firma_base64 text;

update personas p
   set firma_base64 = f.imagen
  from firmas_escaneadas f
 where f.persona_id = p.id;

do $$
declare n int;
begin
  select count(*) into n from personas where firma_base64 is not null;
  raise notice 'Firmas devueltas a personas.firma_base64: %', n;
end $$;

-- La versión original de 0065 (con el filtro flojo de supervisor_sede, tal como
-- estaba). Se restaura para que el frontend anterior funcione igual que antes.
create or replace function fn_firma_persona(p_persona_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select firma_base64 from personas
  where id = p_persona_id
    and (fn_es_admin_o_lider()
         or id = fn_persona_actual_id()
         or fn_rol_actual() = 'supervisor_sede');
$$;
grant execute on function fn_firma_persona(uuid) to authenticated;

create or replace function fn_set_mi_firma(p_dataurl text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not fn_es_admin_o_lider() then
    raise exception 'Solo un administrador o líder puede guardar su firma.';
  end if;
  if p_dataurl is not null and p_dataurl !~ '^data:image/(png|jpeg);base64,' then
    raise exception 'Formato inválido: la firma debe ser una imagen PNG o JPEG.';
  end if;
  update personas set firma_base64 = p_dataurl where id = fn_persona_actual_id();
  if not found then raise exception 'No se encontró tu persona.'; end if;
end;
$$;
grant execute on function fn_set_mi_firma(text) to authenticated;

drop function if exists fn_firma_de_memo(uuid);
drop function if exists fn_mi_firma();
drop table if exists firmas_escaneadas;

-- ── 2 · Volver a la versión que devolvía NULL ────────────────────────────────
create or replace function fn_expediente_puede_actuar(p_persona_id uuid, p_nivel text)
returns boolean language sql stable security definer set search_path = public as $$
  select fn_es_admin_o_lider()
      or (fn_rol_actual() = 'supervisor_sede'
          and p_nivel in ('verbal','amonestacion')
          and (select sede_base_id from personas where id = p_persona_id) = fn_sede_actual_persona());
$$;

-- ── 3 · Los permisos: este reverso es DELIBERADAMENTE PARCIAL ────────────────
-- NO se reabre la ejecución a PUBLIC, a propósito.
--
-- Dos razones. La primera es que no se puede hacer bien: antes de la 0076 había
-- 54 funciones abiertas a `anon` y 50 cerradas a mano, y aquí no hay registro de
-- cuáles eran cuáles — un `grant to public` en bloque reabriría las 104 y
-- dejaría el sistema MÁS abierto que antes de la migración. La segunda es que
-- reabrir `anon` no arregla ningún problema real: si algo dejó de funcionar por
-- permisos, quien lo necesita es un usuario CON sesión, no uno sin ella.
--
-- La válvula de escape correcta, si una pantalla empieza a dar
-- "permission denied for function ...", es devolver el acceso a los usuarios con
-- sesión sin tocar `anon`:
grant execute on all functions in schema public to authenticated;

-- El default se queda cerrado: que las funciones nuevas nazcan sin acceso
-- anónimo no es lo que había que revertir. Para reabrirlo de verdad (no debería
-- hacer falta nunca) sería:
--   alter default privileges grant execute on functions to public;

notify pgrst, 'reload schema';

commit;
