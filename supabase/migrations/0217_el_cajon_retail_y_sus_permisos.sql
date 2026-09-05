-- ============================================================================
-- 0217 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/02_schema_retail.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 2 (el cajón `retail` + sus permisos)
--
-- ⚠️ Este SQL se corre en el proyecto cayla-DYNAMIC (no en retail).
-- ⚠️ RECONSTRUIDO el 2026-08-11. Este paso se había corrido a mano en el
--    dashboard de Supabase y nunca quedó escrito. Los pasos 03..11 lo dan por
--    hecho ("después del paso 2") pero ninguno lo hace. Sin este archivo, la
--    base no se puede rehacer desde cero. Ver docs/adr/0003-unificacion-retail-dynamic.md
--
-- Es idempotente: correrlo sobre la base que YA está unificada no cambia nada
-- (no encuentra la tabla en public, el schema ya existe, los grants se re-otorgan
-- iguales). Correrlo sobre una base limpia, después del paso 1, la deja lista.
--
-- Qué hace, en orden:
--   1) Crea el cajón `retail` — todo lo del ERP de tiendas vive aislado ahí,
--      sin chocar con las tablas que dynamic ya tiene en `public`.
--   2) Mueve la tabla del paso 1 (`public.retail_sede_meta`) adentro del cajón
--      y le quita el prefijo → `retail.sede_meta`. Adentro del cajón el prefijo
--      sobra, y es el nombre que usa el paso 3 (`03_candados.sql:18`).
--   3) Otorga los permisos de tabla del cajón. Mismo patrón que el schema
--      `public` del retail viejo (supabase/migrations/0004_grants.sql):
--      grants abiertos + RLS como la puerta real que restringe fila por fila.
--
-- Lo que este SQL NO puede hacer (queda fuera de Postgres):
--   Exponer el schema `retail` en la API. Eso es configuración del proyecto:
--   Dashboard → Project Settings → API → "Exposed schemas" → agregar `retail`.
--   Sin eso, PostgREST no ve ninguna tabla del cajón y la app responde
--   "schema must be one of the following: public" en cada consulta.
--   La app pide ese schema explícitamente en apps/web/lib/supabase/client.ts:8
--   y server.ts:11 (`db: { schema: "retail" }`).
-- ============================================================================

-- ---------- 1) El cajón ----------
create schema if not exists retail;

-- ---------- 2) La tabla del paso 1 se muda adentro ----------
-- Solo actúa si la tabla sigue en `public` Y todavía no existe en `retail`.
-- Sus políticas RLS y su FK a public.sedes viajan con ella — mudar de schema no
-- las pierde.
do $$
begin
  if to_regclass('public.retail_sede_meta') is not null
     and to_regclass('retail.sede_meta') is null then
    alter table public.retail_sede_meta set schema retail;
    alter table retail.retail_sede_meta rename to sede_meta;
  end if;
end $$;

-- ---------- 3) Permisos del cajón ----------
-- Grants a nivel de TABLA (quién puede tocar la tabla) — distinto de RLS (qué
-- filas puede tocar). Se necesitan los dos: sin grant, PostgREST devuelve
-- "permission denied" antes de siquiera evaluar las políticas.
grant usage on schema retail to authenticated, service_role;

grant all on all tables in schema retail to service_role;
grant all on all sequences in schema retail to service_role;
grant all on all functions in schema retail to service_role;

grant select, insert, update, delete on all tables in schema retail to authenticated;
grant usage on all sequences in schema retail to authenticated;
grant execute on all functions in schema retail to authenticated;

-- Y para todo lo que se cree DESPUÉS de este paso (pasos 03..11 y lo que venga),
-- sin tener que volver a otorgar a mano.
alter default privileges in schema retail grant all on tables to service_role;
alter default privileges in schema retail grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema retail grant execute on functions to authenticated;
