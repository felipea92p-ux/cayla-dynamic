-- ============================================================================
-- 0223 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/08_funciones_finanzas.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 8 · FUNCIONES bloque 2a (contab. + finanzas)
-- Correr en cayla-DYNAMIC. Asientos (con cuadre forzado), depósitos, mínimos,
-- recalcular stock y recibir mercadería. En el cajón `retail`.
-- ============================================================================

-- ---------- disparador que fuerza el cuadre del asiento (deferido) ----------
create or replace function retail.fn_asiento_cuadra()
returns trigger language plpgsql set search_path = retail, public
as $$
declare v_asiento uuid; v_debe numeric(14,2); v_haber numeric(14,2);
begin
  v_asiento := coalesce(new.asiento_id, old.asiento_id);
  select coalesce(sum(debe), 0), coalesce(sum(haber), 0) into v_debe, v_haber
    from asiento_lineas where asiento_id = v_asiento;
  if round(v_debe, 2) <> round(v_haber, 2) then
    raise exception 'Asiento % descuadrado: debe=% ≠ haber=%', v_asiento, v_debe, v_haber;
  end if;
  return null;
end;
$$;
drop trigger if exists asiento_lineas_cuadra on retail.asiento_lineas;
create constraint trigger asiento_lineas_cuadra
  after insert or update or delete on retail.asiento_lineas
  deferrable initially deferred
  for each row execute function retail.fn_asiento_cuadra();

-- ---------- registrar asiento (valida cuadre; inmutable) ----------
create or replace function retail.registrar_asiento(
  p_unidad_id uuid, p_glosa text, p_origen text, p_lineas jsonb,
  p_fecha date default current_date, p_referencia_tipo text default null, p_referencia_id uuid default null
)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare
  v_persona_id uuid; v_asiento_id uuid; v_item jsonb; v_cuenta_id uuid;
  v_debe numeric(14,2); v_haber numeric(14,2); v_sum_debe numeric(14,2) := 0; v_sum_haber numeric(14,2) := 0;
begin
  if not retail.puede_operar_sede(p_unidad_id) then raise exception 'No tienes permiso para registrar en esa unidad'; end if;
  if p_lineas is null or jsonb_array_length(p_lineas) < 2 then raise exception 'Un asiento necesita al menos dos líneas (debe y haber)'; end if;

  for v_item in select * from jsonb_array_elements(p_lineas) loop
    v_sum_debe := v_sum_debe + coalesce((v_item ->> 'debe')::numeric, 0);
    v_sum_haber := v_sum_haber + coalesce((v_item ->> 'haber')::numeric, 0);
  end loop;
  if round(v_sum_debe, 2) <> round(v_sum_haber, 2) then raise exception 'El asiento no cuadra: debe % ≠ haber %', v_sum_debe, v_sum_haber; end if;
  if v_sum_debe = 0 then raise exception 'El asiento está en cero'; end if;

  select id into v_persona_id from public.personas where auth_user_id = auth.uid();

  insert into asientos (fecha, unidad_id, glosa, origen, referencia_tipo, referencia_id, creado_por)
    values (p_fecha, p_unidad_id, p_glosa, coalesce(p_origen, 'manual'), p_referencia_tipo, p_referencia_id, v_persona_id)
    returning id into v_asiento_id;

  for v_item in select * from jsonb_array_elements(p_lineas) loop
    v_debe := coalesce((v_item ->> 'debe')::numeric, 0);
    v_haber := coalesce((v_item ->> 'haber')::numeric, 0);
    if v_debe = 0 and v_haber = 0 then continue; end if;
    select id into v_cuenta_id from cuentas_contables where codigo = (v_item ->> 'cuenta');
    if v_cuenta_id is null then raise exception 'La cuenta % no existe en el plan de cuentas', (v_item ->> 'cuenta'); end if;
    insert into asiento_lineas (asiento_id, cuenta_id, debe, haber, glosa)
      values (v_asiento_id, v_cuenta_id, v_debe, v_haber, v_item ->> 'glosa');
  end loop;

  return v_asiento_id;
end;
$$;

-- ---------- registrar depósito bancario ----------
create or replace function retail.registrar_deposito(
  p_sede_id uuid, p_monto numeric, p_nota text default null, p_fecha date default current_date
)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare v_persona_id uuid; v_id uuid;
begin
  if not retail.puede_operar_sede(p_sede_id) then raise exception 'No tienes permiso para registrar depósitos de esa sede'; end if;
  if p_monto is null or p_monto <= 0 then raise exception 'El monto del depósito debe ser mayor a 0'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  insert into depositos_bancarios (sede_id, fecha, monto, nota, usuario_id)
    values (p_sede_id, p_fecha, p_monto, p_nota, v_persona_id) returning id into v_id;
  return v_id;
end;
$$;

-- ---------- fijar stock mínimo (solo Líder) ----------
create or replace function retail.fijar_stock_minimo(p_variante_id uuid, p_sede_id uuid, p_minimo integer default null)
returns void language plpgsql security definer set search_path = retail, public
as $$
begin
  if not retail.es_lider() then raise exception 'Solo un Líder puede fijar mínimos de stock'; end if;
  if p_minimo is not null and p_minimo < 0 then raise exception 'El mínimo no puede ser negativo'; end if;
  insert into stock (variante_id, sede_id, cantidad, stock_minimo)
    values (p_variante_id, p_sede_id, 0, p_minimo)
    on conflict (variante_id, sede_id) do update set stock_minimo = excluded.stock_minimo, updated_at = now();
end;
$$;

-- ---------- recalcular stock (mantenimiento) ----------
create or replace function retail.recalcular_stock()
returns void language plpgsql security definer set search_path = retail, public
as $$
begin
  truncate table stock;
  insert into stock (variante_id, sede_id, cantidad, ultima_entrada)
    select variante_id, sede_id, sum(cantidad), max(created_at) from movimientos where tipo = 'entrada'
    group by variante_id, sede_id
    on conflict (variante_id, sede_id) do update set cantidad = stock.cantidad + excluded.cantidad, ultima_entrada = excluded.ultima_entrada;
  insert into stock (variante_id, sede_id, cantidad, ultima_salida)
    select variante_id, sede_id, -sum(cantidad), max(created_at) from movimientos where tipo = 'salida'
    group by variante_id, sede_id
    on conflict (variante_id, sede_id) do update set cantidad = stock.cantidad + excluded.cantidad, ultima_salida = excluded.ultima_salida;
  insert into stock (variante_id, sede_id, cantidad)
    select variante_id, sede_id, sum(cantidad) from movimientos where tipo = 'ajuste'
    group by variante_id, sede_id
    on conflict (variante_id, sede_id) do update set cantidad = stock.cantidad + excluded.cantidad;
  insert into stock (variante_id, sede_id, cantidad, ultima_salida)
    select variante_id, sede_id, -sum(cantidad), max(created_at) from movimientos where tipo = 'traslado'
    group by variante_id, sede_id
    on conflict (variante_id, sede_id) do update set cantidad = stock.cantidad + excluded.cantidad, ultima_salida = excluded.ultima_salida;
  insert into stock (variante_id, sede_id, cantidad, ultima_entrada)
    select variante_id, sede_destino_id, sum(cantidad), max(created_at) from movimientos where tipo = 'traslado' and sede_destino_id is not null
    group by variante_id, sede_destino_id
    on conflict (variante_id, sede_id) do update set cantidad = stock.cantidad + excluded.cantidad, ultima_entrada = excluded.ultima_entrada;
end;
$$;

-- ---------- recibir lote (mercadería) ----------
create or replace function retail.recibir_lote(
  p_sede_id uuid, p_origen text, p_items jsonb,
  p_proveedor text default null, p_numero_guia text default null, p_nota text default null
)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare
  v_persona_id uuid; v_lote_id uuid; v_item jsonb; v_variante_id uuid; v_producto_id uuid;
  v_movimiento_id uuid; v_contenedor_id uuid;
begin
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'El lote no tiene ítems'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  insert into lotes (sede_id, origen, proveedor, numero_guia, recibido_por, nota)
    values (p_sede_id, p_origen, p_proveedor, p_numero_guia, v_persona_id, p_nota) returning id into v_lote_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    if (v_item ->> 'variante_id') is not null then
      v_variante_id := (v_item ->> 'variante_id')::uuid;
    else
      if (v_item ->> 'producto_id') is not null then
        v_producto_id := (v_item ->> 'producto_id')::uuid;
      else
        insert into productos (sku_padre, referencia, genero, marca, temporada)
          values (v_item ->> 'sku_padre', v_item ->> 'referencia', v_item ->> 'genero', v_item ->> 'marca', v_item ->> 'temporada')
          returning id into v_producto_id;
      end if;
      insert into variantes (producto_id, sku, talla, color, costo, precio, stock_minimo)
        values (v_producto_id, v_item ->> 'sku', v_item ->> 'talla', v_item ->> 'color',
                coalesce((v_item ->> 'costo')::numeric, 0), coalesce((v_item ->> 'precio')::numeric, 0),
                coalesce((v_item ->> 'stock_minimo')::integer, 0))
        returning id into v_variante_id;
    end if;

    v_contenedor_id := case when (v_item ->> 'contenedor_id') is not null then (v_item ->> 'contenedor_id')::uuid else null end;
    insert into movimientos (variante_id, sede_id, tipo, cantidad, motivo, usuario_id, lote_id, contenedor_id)
      values (v_variante_id, p_sede_id, 'entrada', (v_item ->> 'cantidad')::integer, 'ingreso de lote', v_persona_id, v_lote_id, v_contenedor_id)
      returning id into v_movimiento_id;
    perform retail.fn_aplicar_movimiento(v_movimiento_id);
  end loop;

  return v_lote_id;
end;
$$;
