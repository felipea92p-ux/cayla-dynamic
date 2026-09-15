-- ============================================================================
-- 0457 — Editar una categoría incluye su salario declarado, y gana pantalla
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que `fn_set_categoria` (0140) también pueda cambiar
--   `categorias_laborales.salario_declarado` (0145) — el monto que se publica
--   en la política salarial — en la misma llamada que edita propósito,
--   funciones, requisitos y criterio.
--
-- QUÉ ASUME
--
--   · El rango existe (mismo guard que ya tenía la función).
--   · Quien llama es admin o lider_do (mismo guard que ya tenía la función).
--
-- QUÉ PROBLEMA CIERRA
--
--   Hoy `salario_declarado` solo se puede cambiar pegando un `UPDATE` a mano
--   en el SQL Editor: la RPC que existe para editar una categoría ni siquiera
--   lo acepta como parámetro, y no hay una sola pantalla en `apps/web` que la
--   llame — ni para este campo ni para ningún otro de la categoría. Auditado
--   el 2026-09-15: la única escritura sobre esta columna en todo el historial
--   es el `UPDATE` manual de la propia 0145. "Fácil de administrar" (el
--   objetivo del rediseño de Política salarial) no existe todavía para el
--   contenido base del documento.
--
--   Esta migración solo abre la puerta en la base. La pantalla que la llama
--   —`/admin/politica-salarial/categorias`— es parte del mismo rediseño y
--   vive en el frontend, no en una migración.
--
-- POR QUÉ `p_salario_declarado` ES OBLIGATORIO Y NO TIENE VALOR POR DEFECTO
--
--   Si tuviera `default null`, cualquier llamada vieja con cinco argumentos
--   (como la firma anterior) borraría en silencio el monto declarado de la
--   categoría. Hacerlo obligatorio fuerza a que quien llame lea primero el
--   valor actual y lo reenvíe — el mismo patrón "leer antes de escribir" que
--   ya usa el resto de este archivo. Hoy no hay ningún llamador en producción
--   que se rompa: `fn_set_categoria` no se invoca desde ningún lugar de
--   `apps/web` (auditado el 2026-09-15).
--
-- QUÉ NO CAMBIA
--
--   No se agrega un CHECK que obligue a que la escala suba con la categoría:
--   sigue siendo un aviso en pantalla, no un bloqueo — decisión de Felipe ya
--   tomada en la 0145, que no se reabre acá.
--
-- CÓMO SE REVIERTE
--   drop function fn_set_categoria(text, text, text, text, text, numeric);
--   Y volver a aplicar el bloque de fn_set_categoria de la 0140 (sin el
--   parámetro de salario).
-- ============================================================================

drop function if exists fn_set_categoria(text, text, text, text, text);

create or replace function fn_set_categoria(
  p_rango             text,
  p_proposito         text,
  p_funciones         text,
  p_requisitos        text,
  p_criterio          text,
  p_salario_declarado numeric
)
returns void
language plpgsql volatile security definer set search_path = public
as $fn$
declare v_yo uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede editar el cuadro de categorias.';
  end if;

  v_yo := fn_persona_actual_id();
  if v_yo is null then
    raise exception 'No puedo identificar quien hace el cambio, asi que no puedo auditarlo. Inicia sesion con tu usuario.';
  end if;

  if p_salario_declarado is not null and p_salario_declarado <= 0 then
    raise exception 'El monto declarado tiene que ser mayor a cero.';
  end if;

  update categorias_laborales
     set proposito  = nullif(btrim(coalesce(p_proposito, '')), ''),
         funciones  = nullif(btrim(coalesce(p_funciones, '')), ''),
         requisitos = nullif(btrim(coalesce(p_requisitos, '')), ''),
         criterio   = nullif(btrim(coalesce(p_criterio, '')), ''),
         salario_declarado = p_salario_declarado,
         actualizado_por = v_yo,
         actualizado_at  = now()
   where rango = p_rango;

  if not found then
    raise exception 'Ese rango no existe en el cuadro de categorias.';
  end if;
end;
$fn$;

grant  execute on function fn_set_categoria(text, text, text, text, text, numeric) to authenticated;
revoke execute on function fn_set_categoria(text, text, text, text, text, numeric) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (457, 'editar_categoria_incluye_el_salario_declarado')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0457 · fn_set_categoria ahora tambien cambia salario_declarado';
  raise notice '0457 · la pantalla que la llama vive en apps/web/app/(admin)/admin/politica-salarial/categorias';
end $mig$;
