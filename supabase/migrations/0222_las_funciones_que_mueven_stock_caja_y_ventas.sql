-- ============================================================================
-- 0222 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/07_funciones_operacion.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 7 · FUNCIONES bloque 1 (operación)
-- Correr en cayla-DYNAMIC. Funciones del día a día: mover stock, vender, caja,
-- gasto. Van en el cajón `retail` (search_path retail, public). Reusan los
-- candados de retail; las personas se leen de public.personas (dynamic).
-- ============================================================================

-- ---------- aplicar movimiento al stock (con bloqueo por concurrencia) ----------
create or replace function retail.fn_aplicar_movimiento(p_movimiento_id uuid)
returns void language plpgsql security definer set search_path = retail, public
as $$
declare
  m movimientos%rowtype;
  v_actual integer;
begin
  select * into m from movimientos where id = p_movimiento_id;
  if not found then raise exception 'Movimiento % no existe', p_movimiento_id; end if;

  if m.tipo = 'salida' or m.tipo = 'traslado' then
    select coalesce(cantidad, 0) into v_actual from stock
      where variante_id = m.variante_id and sede_id = m.sede_id for update;
    if coalesce(v_actual, 0) < m.cantidad then
      raise exception 'Stock insuficiente en sede % (hay %, se pidió %)', m.sede_id, coalesce(v_actual, 0), m.cantidad;
    end if;
  end if;

  if m.tipo = 'entrada' then
    insert into stock (variante_id, sede_id, cantidad, ultima_entrada, contenedor_id)
      values (m.variante_id, m.sede_id, m.cantidad, m.created_at, m.contenedor_id)
      on conflict (variante_id, sede_id) do update
        set cantidad = stock.cantidad + excluded.cantidad, ultima_entrada = excluded.ultima_entrada,
            contenedor_id = coalesce(excluded.contenedor_id, stock.contenedor_id), updated_at = now();
  elsif m.tipo = 'salida' then
    update stock set cantidad = cantidad - m.cantidad, ultima_salida = m.created_at, updated_at = now()
      where variante_id = m.variante_id and sede_id = m.sede_id;
  elsif m.tipo = 'ajuste' then
    insert into stock (variante_id, sede_id, cantidad)
      values (m.variante_id, m.sede_id, m.cantidad)
      on conflict (variante_id, sede_id) do update
        set cantidad = stock.cantidad + excluded.cantidad, updated_at = now();
  elsif m.tipo = 'traslado' then
    if m.sede_destino_id is null then raise exception 'Traslado requiere sede_destino_id'; end if;
    update stock set cantidad = cantidad - m.cantidad, ultima_salida = m.created_at, updated_at = now()
      where variante_id = m.variante_id and sede_id = m.sede_id;
    insert into stock (variante_id, sede_id, cantidad, ultima_entrada, contenedor_id)
      values (m.variante_id, m.sede_destino_id, m.cantidad, m.created_at, m.contenedor_id)
      on conflict (variante_id, sede_id) do update
        set cantidad = stock.cantidad + excluded.cantidad, ultima_entrada = excluded.ultima_entrada,
            contenedor_id = coalesce(excluded.contenedor_id, stock.contenedor_id), updated_at = now();
  end if;
end;
$$;

-- ---------- registrar un movimiento (valida sede) ----------
create or replace function retail.registrar_movimiento(
  p_variante_id uuid, p_sede_id uuid, p_tipo text, p_cantidad integer,
  p_motivo text default null, p_canal text default null, p_sede_destino_id uuid default null,
  p_monto numeric default null, p_venta_id uuid default null, p_nota text default null,
  p_contenedor_id uuid default null, p_lote_id uuid default null
)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare v_id uuid; v_persona_id uuid;
begin
  if not retail.puede_operar_sede(p_sede_id) then
    raise exception 'No tienes permiso para registrar movimientos en esa sede';
  end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  insert into movimientos (variante_id, sede_id, tipo, cantidad, motivo, canal, sede_destino_id,
                           monto, venta_id, usuario_id, nota, contenedor_id, lote_id)
    values (p_variante_id, p_sede_id, p_tipo, p_cantidad, p_motivo, p_canal, p_sede_destino_id,
            p_monto, p_venta_id, v_persona_id, p_nota, p_contenedor_id, p_lote_id)
    returning id into v_id;
  perform retail.fn_aplicar_movimiento(v_id);
  return v_id;
end;
$$;

-- ---------- abrir caja ----------
create or replace function retail.abrir_caja(p_sede_id uuid, p_monto_apertura numeric)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare v_persona_id uuid; v_caja_id uuid;
begin
  if exists (select 1 from cajas where sede_id = p_sede_id and estado = 'abierta') then
    raise exception 'Ya hay una caja abierta en esta sede — ciérrala antes de abrir otra';
  end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  insert into cajas (sede_id, monto_apertura, abierta_por)
    values (p_sede_id, p_monto_apertura, v_persona_id) returning id into v_caja_id;
  return v_caja_id;
end;
$$;

-- ---------- cerrar caja ----------
create or replace function retail.cerrar_caja(p_caja_id uuid, p_monto_contado numeric)
returns table (monto_esperado numeric, monto_contado numeric, diferencia numeric)
language plpgsql security definer set search_path = retail, public
as $$
declare v_persona_id uuid; v_caja cajas%rowtype; v_esperado numeric;
begin
  select * into v_caja from cajas where id = p_caja_id;
  if not found then raise exception 'La caja % no existe', p_caja_id; end if;
  if v_caja.estado <> 'abierta' then raise exception 'Esta caja ya está cerrada'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  select v_caja.monto_apertura + coalesce(sum(monto_total), 0) into v_esperado
    from ventas where caja_id = p_caja_id and metodo_pago = 'efectivo';
  update cajas set monto_cierre_contado = p_monto_contado, monto_cierre_esperado = v_esperado,
    diferencia = p_monto_contado - v_esperado, cerrada_por = v_persona_id,
    cerrada_en = now(), estado = 'cerrada' where id = p_caja_id;
  return query select v_esperado, p_monto_contado, p_monto_contado - v_esperado;
end;
$$;

-- ---------- registrar venta ----------
create or replace function retail.registrar_venta(
  p_caja_id uuid, p_metodo_pago text, p_items jsonb, p_nota text default null
)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare
  v_caja cajas%rowtype; v_persona_id uuid; v_venta_id uuid; v_movimiento_id uuid;
  v_monto_total numeric := 0; v_linea_total numeric; v_item jsonb;
begin
  select * into v_caja from cajas where id = p_caja_id;
  if not found then raise exception 'La caja % no existe', p_caja_id; end if;
  if v_caja.estado <> 'abierta' then raise exception 'Esta caja ya está cerrada — no se pueden registrar más ventas ahí'; end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then raise exception 'El carrito está vacío'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_monto_total := v_monto_total + (v_item ->> 'monto')::numeric * (v_item ->> 'cantidad')::numeric;
  end loop;

  insert into ventas (sede_id, caja_id, metodo_pago, monto_total, usuario_id, nota)
    values (v_caja.sede_id, p_caja_id, p_metodo_pago, v_monto_total, v_persona_id, p_nota)
    returning id into v_venta_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_linea_total := (v_item ->> 'monto')::numeric * (v_item ->> 'cantidad')::numeric;
    insert into movimientos (variante_id, sede_id, tipo, cantidad, motivo, canal, monto, venta_id, usuario_id)
      values ((v_item ->> 'variante_id')::uuid, v_caja.sede_id, 'salida',
              (v_item ->> 'cantidad')::integer, 'venta', 'tienda', v_linea_total, v_venta_id, v_persona_id)
      returning id into v_movimiento_id;
    perform retail.fn_aplicar_movimiento(v_movimiento_id);
  end loop;

  return v_venta_id;
end;
$$;

-- ---------- registrar gasto (solo Líder) ----------
create or replace function retail.registrar_gasto(
  p_sede_id uuid, p_categoria text, p_subtotal numeric, p_igv numeric, p_total numeric,
  p_especificacion text default null
)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare v_persona_id uuid; v_gasto_id uuid;
begin
  if not retail.es_lider() then raise exception 'Solo un Líder puede registrar gastos'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  insert into gastos (sede_id, categoria, subtotal, igv, total, especificacion, usuario_id)
    values (p_sede_id, p_categoria, p_subtotal, p_igv, p_total, p_especificacion, v_persona_id)
    returning id into v_gasto_id;
  return v_gasto_id;
end;
$$;
