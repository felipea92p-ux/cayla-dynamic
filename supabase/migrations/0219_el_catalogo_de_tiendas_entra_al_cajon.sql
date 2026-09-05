-- ============================================================================
-- 0219 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/04_catalogo.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 4 (catálogo)
-- Correr en cayla-DYNAMIC. Crea categorias, productos, variantes en el cajón
-- `retail`, con sus candados (ver = todos los conectados; editar = Líder).
-- ============================================================================

-- Trigger para mantener updated_at (aislado en el cajón).
create or replace function retail.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

-- ---------- categorias ----------
create table retail.categorias (
  id uuid primary key default gen_random_uuid(),
  familia text not null check (familia in ('indumentaria', 'calzado', 'accesorios', 'bisuteria', 'belleza', 'papeleria')),
  nombre text not null,
  tallas_sugeridas text[],
  created_at timestamptz not null default now(),
  unique (familia, nombre)
);
alter table retail.categorias enable row level security;
create policy categorias_select on retail.categorias for select using (auth.role() = 'authenticated');
create policy categorias_insert_lider on retail.categorias for insert with check (retail.es_lider());
create policy categorias_update_lider on retail.categorias for update using (retail.es_lider());

-- ---------- productos ----------
create table retail.productos (
  id uuid primary key default gen_random_uuid(),
  sku_padre text not null unique,
  referencia text not null,
  descripcion text,
  categoria_id uuid references retail.categorias (id),
  genero text,
  marca text,
  temporada text,
  estado text not null default 'activa' check (estado in ('activa', 'descontinuada', 'agotada')),
  foto_url text,
  costo_mano_obra numeric(12, 2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table retail.productos enable row level security;
create policy productos_select on retail.productos for select using (auth.role() = 'authenticated');
create policy productos_insert_lider on retail.productos for insert with check (retail.es_lider());
create policy productos_update_lider on retail.productos for update using (retail.es_lider());
create trigger productos_updated before update on retail.productos for each row execute function retail.set_updated_at();

-- ---------- variantes ----------
create table retail.variantes (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references retail.productos (id) on delete cascade,
  sku text not null unique,
  talla text,
  color text,
  costo numeric(12, 2) not null default 0,
  precio numeric(12, 2) not null default 0,
  precio_oferta numeric(12, 2),
  foto_url text,
  stock_minimo integer not null default 0,
  precio_taller numeric(12, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table retail.variantes enable row level security;
create policy variantes_select on retail.variantes for select using (auth.role() = 'authenticated');
create policy variantes_insert_lider on retail.variantes for insert with check (retail.es_lider());
create policy variantes_update_lider on retail.variantes for update using (retail.es_lider());
create trigger variantes_updated before update on retail.variantes for each row execute function retail.set_updated_at();
