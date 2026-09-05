-- ============================================================================
-- 0225 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/10_storage_fotos.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- 10_storage_fotos.sql — Buzón de fotos de producto en el proyecto dynamic
-- ----------------------------------------------------------------------------
-- CONTRATO
--   Promete: existe un buzón público 'fotos-productos' donde el Líder sube la
--            foto de cada modelo, y cualquiera la puede VER por su URL pública.
--   Asume:   dynamic ya tiene public.fn_rol_actual() (devuelve 'admin' para el
--            Líder) — el MISMO chequeo que usa toda la seguridad de retail.
--
-- POR QUÉ "público" NO alcanza:
--   "Público" solo abre la LECTURA (la vitrina: ver la foto sin login). SUBIR
--   una foto igual pasa por seguridad — sin una política de INSERT/UPDATE, hasta
--   el Líder recibiría un "row-level security" al intentar subir. Estas políticas
--   son ese permiso, y lo dan solo al Líder (igual que editar el catálogo).
-- ============================================================================

-- 1) El buzón. Idempotente: si ya existe, solo asegura que quede público.
insert into storage.buckets (id, name, public)
values ('fotos-productos', 'fotos-productos', true)
on conflict (id) do update set public = excluded.public;

-- 2) Subir foto nueva → solo el Líder.
drop policy if exists "fotos_insert_lider" on storage.objects;
create policy "fotos_insert_lider" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'fotos-productos' and public.fn_rol_actual() = 'admin');

-- 3) Reemplazar foto (el componente usa upsert=true al cambiarla) → solo el Líder.
drop policy if exists "fotos_update_lider" on storage.objects;
create policy "fotos_update_lider" on storage.objects
  for update to authenticated
  using      (bucket_id = 'fotos-productos' and public.fn_rol_actual() = 'admin')
  with check (bucket_id = 'fotos-productos' and public.fn_rol_actual() = 'admin');

-- No hace falta política de LECTURA: al ser buzón público, ver la foto por su URL
-- no pasa por RLS. Tampoco hay borrado (el componente nunca elimina archivos).
