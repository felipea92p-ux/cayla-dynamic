-- ============================================================================
-- 0379_fn_set_meta_cobertura_vuelve_a_ser_null_safe.sql
-- ============================================================================
-- QUÉ ARREGLA. fn_set_meta_cobertura arma su guard como
--   «if fn_rol_actual() not in ('admin', 'lider_do') then raise exception ...»
-- La 0039 ya había corregido exactamente este defecto en esta misma función,
-- cambiándola a la forma null-safe «if fn_es_admin_o_lider() is not true».
-- La 0195 ("las cuatro funciones que el repositorio no conocía") la
-- reescribió con create or replace copiando el cuerpo VIEJO —anterior a la
-- 0039— y el guard inseguro volvió sin que nadie lo pidiera.
--
-- POR QUÉ ES UN AGUJERO, en el mismo mecanismo que la 0374/0376 ya
-- documentaron: para una identidad autenticada sin rol determinista
-- (hoy, cualquier persona CESADA — desde la 0374, fn_rol_actual() de un
-- inactivo es NULL), «NULL not in ('admin', 'lider_do')» es NULL, no TRUE.
-- Un «if null then raise exception» en PL/pgSQL no dispara: la función
-- sigue de largo como si estuviera autorizada.
--
-- REPRODUCIDO contra Postgres local, sin tocar ninguna tabla:
--   select (null::rol_usuario not in ('admin', 'lider_do'));   -- null
--   do $$ begin if (null::boolean) then raise exception 'no debería'; end if; end $$;
-- no lanza excepción.
--
-- EFECTO CONCRETO. Cualquier persona cesada con sesión de Supabase Auth
-- viva podría definir la meta de cobertura de cualquier sede — un dato que
-- alimenta el aviso de "cobertura floja" del panel, no la planilla
-- directamente, pero sigue siendo una escritura de alguien sin permiso real.
--
-- QUÉ NO CAMBIA. Ni un carácter del cuerpo salvo la línea del guard —misma
-- pregunta (¿es admin o líder DO?), misma respuesta para quien ya estaba
-- autorizado legítimamente. El resto del cuerpo es el vigente de la 0195.
--
-- MD5 DE PARTIDA — medido en esta Mac (Postgres local), ANTES de escribir
-- este cambio. Como manda la casa, esto NO reemplaza pedirlo a producción:
-- se vuelve a pedir en el mensaje en que se entregue este SQL, no en este.
--
--   fn_set_meta_cobertura   tal_cual = 59e0308d6a280ffa3e1ab38be0289dfc
--                    sin_comentarios = 59e0308d6a280ffa3e1ab38be0289dfc
--
--   select md5(p.prosrc) as tal_cual,
--          md5(array_to_string(array(
--            select regexp_replace(l, '[[:space:]]*--.*$', '')
--            from unnest(string_to_array(p.prosrc, chr(10))) as l
--            where btrim(l) not like '--%'
--          ), chr(10)))                 as sin_comentarios
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_set_meta_cobertura';
--
-- CÓMO SE REVIERTE. Restaurar el cuerpo de la 0195 tal cual — pero no se
-- debería: eso reabre el agujero para cualquier persona cesada con sesión
-- viva.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana integer, p_meta integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- CAMBIO 0379 — vuelve al patrón null-safe de la 0039: fn_es_admin_o_lider()
  -- ya hace coalesce(..., false), así que un rol NULL (persona cesada) nunca
  -- pasa como autorizado.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador puede definir la meta de cobertura.';
  end if;
  if p_dia_semana < 0 or p_dia_semana > 6 then raise exception 'Día de la semana inválido.'; end if;
  if p_meta < 0 then raise exception 'La meta no puede ser negativa.'; end if;
  insert into metas_cobertura (sede_id, dia_semana, meta, updated_at)
  values (p_sede_id, p_dia_semana, p_meta, now())
  on conflict (sede_id, dia_semana) do update set meta = excluded.meta, updated_at = now();
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (379, 'fn_set_meta_cobertura_vuelve_a_ser_null_safe')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
