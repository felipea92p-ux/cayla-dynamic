-- ============================================================================
-- 0221 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/06_contabilidad_produccion.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 6 · BLOQUE B (contabilidad + producción)
-- Correr en cayla-DYNAMIC. Cierra las 22 tablas de retail en el cajón `retail`.
-- Contabilidad = solo Líder (con lectura de su unidad). Producción = taller/Líder.
-- El asiento es inmutable (solo se inserta vía RPC; no se edita/borra).
-- ============================================================================

-- ---------- cuentas_contables (catálogo contable) ----------
create table if not exists retail.cuentas_contables (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  elemento text not null,
  naturaleza text not null,
  es_contra boolean not null default false,
  explicacion text not null,
  orden integer not null default 0,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table retail.cuentas_contables enable row level security;
drop policy if exists cuentas_select on retail.cuentas_contables;
create policy cuentas_select on retail.cuentas_contables for select using (auth.role() = 'authenticated');
drop policy if exists cuentas_write_lider on retail.cuentas_contables;
create policy cuentas_write_lider on retail.cuentas_contables for all using (retail.es_lider()) with check (retail.es_lider());
drop trigger if exists cuentas_updated on retail.cuentas_contables;
create trigger cuentas_updated before update on retail.cuentas_contables for each row execute function retail.set_updated_at();

-- ---------- patrimonio_items (solo Líder) ----------
create table if not exists retail.patrimonio_items (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  tipo text not null,
  monto numeric(14, 2) not null default 0,
  nota text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table retail.patrimonio_items enable row level security;
drop policy if exists patrimonio_all_lider on retail.patrimonio_items;
create policy patrimonio_all_lider on retail.patrimonio_items for all using (retail.es_lider()) with check (retail.es_lider());
drop trigger if exists patrimonio_updated on retail.patrimonio_items;
create trigger patrimonio_updated before update on retail.patrimonio_items for each row execute function retail.set_updated_at();

-- ---------- ventas_historicas_mensuales (solo Líder) ----------
create table if not exists retail.ventas_historicas_mensuales (
  id uuid primary key default gen_random_uuid(),
  sede_id uuid not null references public.sedes (id),
  anio integer not null check (anio between 2020 and 2100),
  mes integer not null check (mes between 1 and 12),
  monto numeric(14, 2) not null default 0,
  unique (sede_id, anio, mes)
);
alter table retail.ventas_historicas_mensuales enable row level security;
drop policy if exists ventas_hist_all_lider on retail.ventas_historicas_mensuales;
create policy ventas_hist_all_lider on retail.ventas_historicas_mensuales for all using (retail.es_lider()) with check (retail.es_lider());

-- ---------- activos_fijos (Líder; lectura de su unidad) ----------
create table if not exists retail.activos_fijos (
  id uuid primary key default gen_random_uuid(),
  unidad_id uuid not null references public.sedes (id),
  nombre text not null,
  serie text,
  descripcion text,
  cuenta_codigo text not null,
  costo numeric(12, 2) not null,
  valor_residual numeric(12, 2) not null default 0,
  vida_util_meses integer not null,
  tasa_anual numeric(6, 4) not null,
  fecha_adquisicion date not null,
  depreciacion_apertura numeric(12, 2) not null default 0,
  estado text not null default 'activo',
  nota text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table retail.activos_fijos enable row level security;
drop policy if exists activos_all_lider on retail.activos_fijos;
create policy activos_all_lider on retail.activos_fijos for all using (retail.es_lider()) with check (retail.es_lider());
drop policy if exists activos_select_propia on retail.activos_fijos;
create policy activos_select_propia on retail.activos_fijos for select using (unidad_id = retail.mi_sede());
drop trigger if exists activos_updated on retail.activos_fijos;
create trigger activos_updated before update on retail.activos_fijos for each row execute function retail.set_updated_at();

-- ---------- asientos (libro mayor, inmutable; se inserta vía RPC) ----------
create table if not exists retail.asientos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null default current_date,
  unidad_id uuid not null references public.sedes (id),
  glosa text not null,
  origen text not null default 'manual',
  referencia_tipo text,
  referencia_id uuid,
  creado_por uuid references public.personas (id),
  created_at timestamptz not null default now()
);
alter table retail.asientos enable row level security;
drop policy if exists asientos_select_lider on retail.asientos;
create policy asientos_select_lider on retail.asientos for select using (retail.es_lider());
drop policy if exists asientos_select_propia on retail.asientos;
create policy asientos_select_propia on retail.asientos for select using (unidad_id = retail.mi_sede());

-- ---------- asiento_lineas (partida doble; inmutable) ----------
create table if not exists retail.asiento_lineas (
  id uuid primary key default gen_random_uuid(),
  asiento_id uuid not null references retail.asientos (id) on delete cascade,
  cuenta_id uuid not null references retail.cuentas_contables (id),
  debe numeric(14, 2) not null default 0,
  haber numeric(14, 2) not null default 0,
  glosa text
);
alter table retail.asiento_lineas enable row level security;
drop policy if exists lineas_select_lider on retail.asiento_lineas;
create policy lineas_select_lider on retail.asiento_lineas for select using (retail.es_lider());
drop policy if exists lineas_select_propia on retail.asiento_lineas;
create policy lineas_select_propia on retail.asiento_lineas for select using (
  exists (select 1 from retail.asientos a where a.id = asiento_lineas.asiento_id and a.unidad_id = retail.mi_sede())
);

-- ---------- bom_items (ficha de consumo; solo Líder) ----------
create table if not exists retail.bom_items (
  id uuid primary key default gen_random_uuid(),
  producto_id uuid not null references retail.productos (id) on delete cascade,
  insumo text not null,
  cantidad_requerida numeric(12, 3) not null,
  unidad text not null,
  precio_unitario numeric(12, 2),
  created_at timestamptz not null default now()
);
alter table retail.bom_items enable row level security;
drop policy if exists bom_all_lider on retail.bom_items;
create policy bom_all_lider on retail.bom_items for all using (retail.es_lider()) with check (retail.es_lider());

-- ---------- ordenes_produccion (taller/Líder; su sede) ----------
create table if not exists retail.ordenes_produccion (
  id uuid primary key default gen_random_uuid(),
  variante_id uuid not null references retail.variantes (id),
  sede_id uuid not null references public.sedes (id),
  cantidad_planeada integer not null,
  cantidad_producida integer not null default 0,
  estado text not null default 'planeada' check (estado in ('planeada', 'en_proceso', 'completada', 'cancelada')),
  fecha_inicio date,
  fecha_fin date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  etapa text default 'corte',
  destino_sede_id uuid references public.sedes (id),
  nota text
);
alter table retail.ordenes_produccion enable row level security;
drop policy if exists op_all_lider on retail.ordenes_produccion;
create policy op_all_lider on retail.ordenes_produccion for all using (retail.es_lider()) with check (retail.es_lider());
drop policy if exists op_select_sede on retail.ordenes_produccion;
create policy op_select_sede on retail.ordenes_produccion for select using (sede_id = retail.mi_sede());
drop policy if exists op_select_destino on retail.ordenes_produccion;
create policy op_select_destino on retail.ordenes_produccion for select using (destino_sede_id = retail.mi_sede());
drop policy if exists op_insert_sede on retail.ordenes_produccion;
create policy op_insert_sede on retail.ordenes_produccion for insert with check (retail.puede_operar_sede(sede_id));
drop policy if exists op_update_sede on retail.ordenes_produccion;
create policy op_update_sede on retail.ordenes_produccion for update using (retail.puede_operar_sede(sede_id));
drop trigger if exists op_updated on retail.ordenes_produccion;
create trigger op_updated before update on retail.ordenes_produccion for each row execute function retail.set_updated_at();

-- ---------- producciones (costeo; se inserta vía RPC) ----------
create table if not exists retail.producciones (
  id uuid primary key default gen_random_uuid(),
  unidad_id uuid not null references public.sedes (id),
  variante_id uuid references retail.variantes (id),
  producto_id uuid references retail.productos (id),
  fecha date not null default current_date,
  cantidad integer not null,
  costo_tela numeric(12, 2) not null default 0,
  costo_avios numeric(12, 2) not null default 0,
  costo_maquila numeric(12, 2) not null default 0,
  precio_taller numeric(12, 2) not null default 0,
  costo_unitario numeric(12, 2) generated always as (round((costo_tela + costo_avios + costo_maquila) / nullif(cantidad, 0), 2)) stored,
  es_muestra boolean not null default false,
  estado text not null default 'terminado' check (estado in ('en_proceso', 'terminado')),
  etapas jsonb not null default '{}'::jsonb,
  detalle text,
  fecha_entrega date,
  inventariado_at timestamptz,
  nota text,
  creado_por uuid references public.personas (id),
  created_at timestamptz not null default now()
);
alter table retail.producciones enable row level security;
drop policy if exists producciones_all_lider on retail.producciones;
create policy producciones_all_lider on retail.producciones for all using (retail.es_lider()) with check (retail.es_lider());
drop policy if exists producciones_select_propia on retail.producciones;
create policy producciones_select_propia on retail.producciones for select using (unidad_id = retail.mi_sede());

-- ---------- produccion_lineas (desglose por variante) ----------
create table if not exists retail.produccion_lineas (
  id uuid primary key default gen_random_uuid(),
  produccion_id uuid not null references retail.producciones (id) on delete cascade,
  variante_id uuid not null references retail.variantes (id),
  cantidad integer not null check (cantidad > 0),
  created_at timestamptz not null default now(),
  unique (produccion_id, variante_id)
);
alter table retail.produccion_lineas enable row level security;
drop policy if exists pl_select on retail.produccion_lineas;
create policy pl_select on retail.produccion_lineas for select using (
  retail.es_lider() or exists (
    select 1 from retail.producciones p where p.id = produccion_lineas.produccion_id and retail.puede_operar_sede(p.unidad_id)
  )
);
