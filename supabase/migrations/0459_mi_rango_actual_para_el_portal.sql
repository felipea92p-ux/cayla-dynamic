-- ============================================================================
-- 0459 — Cada quien puede saber su propia categoría, sin ver la de nadie más
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Una función que le dice a la persona que tiene la sesión abierta cuál es
--   SU categoría vigente (`rango`), y nada más.
--
-- QUÉ ASUME
--
--   · `asignaciones_salario` guarda el tramo vigente con `vigente_hasta is
--     null` (0019/0024).
--
-- QUÉ PROBLEMA CIERRA
--
--   El portal del colaborador de Política salarial (Fase 9, pregunta 9: "tu
--   categoría actual, siguiente categoría, qué cambia") necesita que cada
--   persona sepa su propio rango. Pero `asignaciones_salario` solo se puede
--   leer siendo admin o líder (policy `salario_admin_lider`, 0024) — a
--   propósito: esa tabla también tiene el sueldo real de cada quien, y ese
--   dato no se expone ni siquiera a su dueño por esta vía. La política
--   pública (`fn_cuadro_categorias`, sin guard de rol) ya explica qué
--   significa cada categoría; solo faltaba decir CUÁL es la propia.
--
--   Mismo patrón que `fn_mi_firma` (0076): una función angosta que solo
--   contesta sobre "mí", en vez de abrir la tabla entera.
--
-- QUÉ NO EXPONE
--
--   Ni el sueldo, ni las fechas del tramo, ni la sede. Un solo campo: el
--   código de rango (p.ej. 'support'), que ya es público en el sentido de
--   que `fn_cuadro_categorias` describe qué significa cada uno.
--
-- CÓMO SE REVIERTE
--   drop function fn_mi_rango_actual();
-- ============================================================================

create or replace function fn_mi_rango_actual()
returns text
language sql stable security definer set search_path = public
as $$
  select rango from asignaciones_salario
  where persona_id = fn_persona_actual_id() and vigente_hasta is null;
$$;

grant  execute on function fn_mi_rango_actual() to authenticated;
revoke execute on function fn_mi_rango_actual() from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (459, 'mi_rango_actual_para_el_portal')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

do $mig$
begin
  raise notice '0459 · fn_mi_rango_actual() lista para el portal del colaborador de Politica salarial';
end $mig$;
