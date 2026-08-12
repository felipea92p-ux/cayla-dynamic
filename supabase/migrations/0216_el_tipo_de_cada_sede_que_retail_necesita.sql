-- ============================================================================
-- 0216 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/01_sedes.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 1 (sedes)
--
-- ⚠️ Este SQL se corre en el proyecto cayla-DYNAMIC (no en retail).
--
-- Dynamic es la fuente de las sedes. Pero retail necesita saber el "tipo" de
-- cada sede (tienda / fabrica / corporativo) para funcionar — por ejemplo, el
-- Taller lo encuentra por tipo='fabrica', no por su código (así el que en
-- dynamic el código LIM sea el Taller no lo confunde).
--
-- Este paso NO toca la tabla `sedes` de dynamic: solo crea UNA tabla nueva de
-- retail (`retail_sede_meta`) que la referencia y le cuelga el tipo. 100% aditivo.
--
-- Mapeo confirmado con Felipe:
--   TRU, AQP, 003 (Tienda Lima) → tienda   ·   LIM (Taller LIM) → fabrica
--   CCO (Central)               → corporativo
-- ============================================================================

create table if not exists retail_sede_meta (
  sede_id uuid primary key references sedes (id) on delete cascade,
  tipo text not null check (tipo in ('tienda', 'fabrica', 'corporativo', 'almacen')),
  tienda_asociada_id uuid references sedes (id),
  created_at timestamptz not null default now()
);

alter table retail_sede_meta enable row level security;

drop policy if exists retail_sede_meta_read on retail_sede_meta;
create policy retail_sede_meta_read on retail_sede_meta
  for select to authenticated using (true);

insert into retail_sede_meta (sede_id, tipo)
select id,
  case codigo
    when 'LIM' then 'fabrica'      -- Taller LIM = el Taller
    when 'CCO' then 'corporativo'  -- Central = Corporativo
    else 'tienda'                  -- TRU, AQP, 003 (Tienda Lima)
  end as tipo
from sedes
where codigo in ('TRU', 'AQP', '003', 'LIM', 'CCO')
on conflict (sede_id) do update set tipo = excluded.tipo;
