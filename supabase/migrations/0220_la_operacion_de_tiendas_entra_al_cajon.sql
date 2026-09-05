-- ============================================================================
-- 0220 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/05_operacion.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 5 · BLOQUE A (operación)
-- Correr en cayla-DYNAMIC. Todo en el cajón `retail`; FKs a public.sedes /
-- public.personas (de dynamic) y a las tablas de retail ya creadas.
-- Candados: operativas = Líder o su sede; finanzas/compras = solo Líder.
-- ============================================================================

-- ---------- proveedores ----------
create table if not exists retail.proveedores (
  id uuid primary key default gen_random_uuid(),
  nombre text not null, ruc text, categoria text, marca text,
  score numeric, contacto text, telefono text, banco text,
  cuenta_bancaria text, direccion text, nota text,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table retail.proveedores enable row level security;
drop policy if exists proveedores_select on retail.proveedores;
create policy proveedores_select on retail.proveedores for select using (auth.role() = 'authenticated');
drop policy if exists proveedores_write_lider on retail.proveedores;
create policy proveedores_write_lider on retail.proveedores for all using (retail.es_lider()) with check (retail.es_lider());
drop trigger if exists proveedores_updated on retail.proveedores;
create trigger proveedores_updated before update on retail.proveedores for each row execute function retail.set_updated_at();

-- ---------- contenedores ----------
create table if not exists retail.contenedores (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  codigo text not null,
  tipo text not null check (tipo in ('estante', 'caja')),
  created_at timestamptz not null default now(),
  unique (sede_id, codigo)
);
alter table retail.contenedores enable row level security;
drop policy if exists contenedores_select on retail.contenedores;
create policy contenedores_select on retail.contenedores for select using (retail.puede_operar_sede(sede_id));
drop policy if exists contenedores_insert on retail.contenedores;
create policy contenedores_insert on retail.contenedores for insert with check (retail.puede_operar_sede(sede_id));

-- ---------- cajas ----------
create table if not exists retail.cajas (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  monto_apertura numeric(12, 2) not null,
  abierta_por uuid references public.personas (id),
  abierta_en timestamptz not null default now(),
  monto_cierre_contado numeric(12, 2),
  monto_cierre_esperado numeric(12, 2),
  diferencia numeric(12, 2),
  cerrada_por uuid references public.personas (id),
  cerrada_en timestamptz,
  estado text not null default 'abierta' check (estado in ('abierta', 'cerrada'))
);
create unique index if not exists cajas_sede_abierta_unique on retail.cajas (sede_id) where estado = 'abierta';
alter table retail.cajas enable row level security;
drop policy if exists cajas_select on retail.cajas;
create policy cajas_select on retail.cajas for select using (retail.puede_operar_sede(sede_id));
drop policy if exists cajas_insert on retail.cajas;
create policy cajas_insert on retail.cajas for insert with check (retail.puede_operar_sede(sede_id));
drop policy if exists cajas_update on retail.cajas;
create policy cajas_update on retail.cajas for update using (retail.puede_operar_sede(sede_id));

-- ---------- ventas ----------
create table if not exists retail.ventas (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  caja_id uuid not null references retail.cajas (id),
  metodo_pago text not null check (metodo_pago in ('efectivo', 'pos', 'yape', 'transferencia')),
  monto_total numeric(12, 2) not null,
  usuario_id uuid references public.personas (id),
  nota text,
  created_at timestamptz not null default now()
);
create index if not exists ventas_caja_id_idx on retail.ventas (caja_id);
create index if not exists ventas_sede_id_idx on retail.ventas (sede_id);
alter table retail.ventas enable row level security;
drop policy if exists ventas_select on retail.ventas;
create policy ventas_select on retail.ventas for select using (retail.puede_operar_sede(sede_id));
drop policy if exists ventas_insert on retail.ventas;
create policy ventas_insert on retail.ventas for insert with check (retail.puede_operar_sede(sede_id));

-- ---------- gastos (solo Líder) ----------
create table if not exists retail.gastos (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  categoria text not null,
  subtotal numeric(12, 2) not null default 0,
  igv numeric(12, 2) not null default 0,
  total numeric(12, 2) not null check (total > 0),
  especificacion text,
  usuario_id uuid references public.personas (id),
  created_at timestamptz not null default now(),
  metodo_pago text
);
alter table retail.gastos enable row level security;
drop policy if exists gastos_all_lider on retail.gastos;
create policy gastos_all_lider on retail.gastos for all using (retail.es_lider()) with check (retail.es_lider());

-- ---------- depositos_bancarios ----------
create table if not exists retail.depositos_bancarios (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  fecha date not null default current_date,
  monto numeric(12, 2) not null,
  nota text,
  usuario_id uuid references public.personas (id),
  created_at timestamptz not null default now()
);
alter table retail.depositos_bancarios enable row level security;
drop policy if exists depositos_select on retail.depositos_bancarios;
create policy depositos_select on retail.depositos_bancarios for select using (retail.puede_operar_sede(sede_id));
drop policy if exists depositos_insert on retail.depositos_bancarios;
create policy depositos_insert on retail.depositos_bancarios for insert with check (retail.puede_operar_sede(sede_id));

-- ---------- ajustes_efectivo (solo Líder) ----------
create table if not exists retail.ajustes_efectivo (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  fecha date not null default current_date,
  monto numeric(12, 2) not null,
  motivo text not null,
  usuario_id uuid references public.personas (id),
  created_at timestamptz not null default now()
);
alter table retail.ajustes_efectivo enable row level security;
drop policy if exists ajustes_all_lider on retail.ajustes_efectivo;
create policy ajustes_all_lider on retail.ajustes_efectivo for all using (retail.es_lider()) with check (retail.es_lider());

-- ---------- ordenes_compra (Líder; ve su sede destino) ----------
create table if not exists retail.ordenes_compra (
  id uuid primary key default gen_random_uuid(),
  proveedor text not null,
  estado text not null default 'pendiente',
  sede_destino_id uuid not null references public.sedes (id),
  fecha date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  proveedor_id uuid references retail.proveedores (id),
  monto_estimado numeric(12, 2),
  fecha_estimada date,
  nota text
);
alter table retail.ordenes_compra enable row level security;
drop policy if exists ordenes_compra_lider on retail.ordenes_compra;
create policy ordenes_compra_lider on retail.ordenes_compra for all using (retail.es_lider()) with check (retail.es_lider());
drop policy if exists ordenes_compra_select_sede on retail.ordenes_compra;
create policy ordenes_compra_select_sede on retail.ordenes_compra for select using (sede_destino_id = retail.mi_sede());
drop trigger if exists ordenes_compra_updated on retail.ordenes_compra;
create trigger ordenes_compra_updated before update on retail.ordenes_compra for each row execute function retail.set_updated_at();

-- ---------- ordenes_compra_items ----------
create table if not exists retail.ordenes_compra_items (
  id uuid primary key default gen_random_uuid(),
  orden_id uuid not null references retail.ordenes_compra (id) on delete cascade,
  variante_id uuid not null references retail.variantes (id),
  cantidad integer not null,
  costo_unitario numeric(12, 2) not null
);
alter table retail.ordenes_compra_items enable row level security;
drop policy if exists ordenes_compra_items_lider on retail.ordenes_compra_items;
create policy ordenes_compra_items_lider on retail.ordenes_compra_items for all using (retail.es_lider()) with check (retail.es_lider());

-- ---------- lotes ----------
create table if not exists retail.lotes (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  origen text not null check (origen in ('taller', 'proveedor')),
  proveedor text,
  numero_guia text,
  fecha_recepcion date not null default current_date,
  recibido_por uuid references public.personas (id),
  nota text,
  created_at timestamptz not null default now(),
  proveedor_id uuid references retail.proveedores (id),
  orden_compra_id uuid references retail.ordenes_compra (id)
);
alter table retail.lotes enable row level security;
drop policy if exists lotes_select on retail.lotes;
create policy lotes_select on retail.lotes for select using (retail.puede_operar_sede(sede_id));
drop policy if exists lotes_insert on retail.lotes;
create policy lotes_insert on retail.lotes for insert with check (retail.puede_operar_sede(sede_id));

-- ---------- stock (se escribe vía RPC; acá solo lectura por sede) ----------
create table if not exists retail.stock (
  variante_id uuid not null references retail.variantes (id) on delete cascade,
  sede_id uuid not null references public.sedes (id),
  cantidad integer not null default 0,
  ultima_entrada timestamptz,
  ultima_salida timestamptz,
  ultima_venta timestamptz,
  contenedor_id uuid references retail.contenedores (id),
  stock_minimo integer,
  updated_at timestamptz not null default now(),
  primary key (variante_id, sede_id)
);
alter table retail.stock enable row level security;
drop policy if exists stock_select on retail.stock;
create policy stock_select on retail.stock for select using (retail.puede_operar_sede(sede_id));

-- ---------- movimientos (append-only; se escribe vía RPC) ----------
create table if not exists retail.movimientos (
  id uuid primary key default gen_random_uuid(),
  variante_id uuid not null references retail.variantes (id),
  sede_id uuid not null references public.sedes (id),
  tipo text not null check (tipo in ('entrada', 'salida', 'ajuste', 'traslado')),
  cantidad integer not null,
  motivo text,
  canal text check (canal in ('tienda', 'online')),
  sede_destino_id uuid references public.sedes (id),
  monto numeric(12, 2),
  venta_id uuid,
  usuario_id uuid references public.personas (id),
  nota text,
  created_at timestamptz not null default now(),
  contenedor_id uuid references retail.contenedores (id),
  lote_id uuid references retail.lotes (id)
);
create index if not exists movimientos_variante_sede_idx on retail.movimientos (variante_id, sede_id);
create index if not exists movimientos_created_at_idx on retail.movimientos (created_at);
alter table retail.movimientos enable row level security;
drop policy if exists movimientos_select on retail.movimientos;
create policy movimientos_select on retail.movimientos for select
  using (retail.puede_operar_sede(sede_id) or sede_destino_id = retail.mi_sede());
drop policy if exists movimientos_insert on retail.movimientos;
create policy movimientos_insert on retail.movimientos for insert with check (retail.puede_operar_sede(sede_id));
