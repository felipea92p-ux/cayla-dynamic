-- ============================================================================
-- 0218 — IMPORTADA DEL REPOSITORIO cayla-retail
-- ============================================================================
--
-- ⚠️ ESTE SQL YA ESTÁ APLICADO EN PRODUCCIÓN. No es un cambio nuevo: se pegó el
--    2026-07-23, cuando el ERP de tiendas se mudó a esta base. Entra al historial
--    ahora, el 2026-08-11, porque hasta hoy vivía únicamente en el otro
--    repositorio y este historial no sabía que el schema `retail` existe.
--    Quien reconstruyera la base desde `supabase/migrations` habría obtenido
--    asistencia y planilla completas, y ningún ERP de tiendas.
--
--    Se anota en `migraciones_aplicadas` en la 0227, no aquí. Mismo criterio
--    que la 0146: a una migración ya aplicada no se le cambia el cuerpo, porque
--    entonces el archivo del repositorio deja de ser lo que se pegó.
--
--    Origen: `cayla-retail/supabase/unificacion/03_candados.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 3 (candados + vistas puente)
-- Correr en cayla-DYNAMIC, después del paso 2 (schema retail + sede_meta).
--
-- Todo va en el cajón `retail` (aislado). Reusa las funciones de identidad de
-- dynamic (fn_rol_actual, fn_sede_actual_persona) → una sola fuente de identidad.
--
-- Mapeo de roles: admin → Líder (ve todo) · supervisor_sede → su sede + números
-- · integrante → su sede.
-- ============================================================================

-- Vista de SEDES que retail entiende (le agrega el `tipo`). security_invoker:
-- respeta las políticas de dynamic sobre sedes.
create or replace view retail.sedes
with (security_invoker = true) as
select s.id, s.codigo, s.nombre, m.tipo, m.tienda_asociada_id, s.activa as activo
from public.sedes s
join retail.sede_meta m on m.sede_id = s.id;

-- Vista de PERSONAS que retail entiende (nombre junto, sede, rol).
create or replace view retail.personas
with (security_invoker = true) as
select p.id, p.auth_user_id,
       (p.nombres || ' ' || coalesce(p.apellidos, '')) as nombre,
       p.sede_base_id as sede_id,
       p.rol::text as rol,
       p.email, p.estado
from public.personas p;

-- Identidad SEGURA del usuario actual (solo su propia fila, sin exponer a otros).
create or replace function retail.persona_actual()
returns table (id uuid, auth_user_id uuid, nombre text, sede_id uuid, rol text, email text)
language sql stable security definer set search_path = public
as $$
  select p.id, p.auth_user_id, (p.nombres || ' ' || coalesce(p.apellidos, '')),
         p.sede_base_id, p.rol::text, p.email
  from public.personas p where p.auth_user_id = auth.uid();
$$;

-- Candados (reusan las funciones de dynamic, que ya son SECURITY DEFINER).
create or replace function retail.es_lider()
returns boolean language sql stable set search_path = public
as $$ select public.fn_rol_actual() = 'admin'; $$;

create or replace function retail.es_supervisor()
returns boolean language sql stable set search_path = public
as $$ select public.fn_rol_actual() = 'supervisor_sede'; $$;

create or replace function retail.mi_sede()
returns uuid language sql stable set search_path = public
as $$ select public.fn_sede_actual_persona(); $$;

create or replace function retail.puede_operar_sede(p_sede_id uuid)
returns boolean language sql stable set search_path = public
as $$ select public.fn_rol_actual() = 'admin' or public.fn_sede_actual_persona() = p_sede_id; $$;
