-- ============================================================================
-- 0224 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/09_funciones_produccion.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 9 · FUNCIONES bloque 2b (producción)
-- Correr en cayla-DYNAMIC. ÚLTIMA pieza de base de datos.
-- Registrar/cerrar orden, etapas, eliminar, revertir. En el cajón `retail`.
-- ============================================================================

create or replace function retail.set_etapa_produccion(p_produccion_id uuid, p_etapa text, p_estado text)
returns void language plpgsql security definer set search_path = retail, public
as $$
declare v_unidad uuid;
begin
  select unidad_id into v_unidad from producciones where id = p_produccion_id;
  if v_unidad is null then raise exception 'La orden no existe'; end if;
  if not retail.puede_operar_sede(v_unidad) then raise exception 'No tienes permiso sobre esta orden'; end if;
  if p_etapa not in ('corte', 'confeccion', 'acabado') then raise exception 'Etapa inválida'; end if;
  if p_estado not in ('pendiente', 'hecho', 'tercerizado') then raise exception 'Estado de etapa inválido'; end if;
  update producciones set etapas = etapas || jsonb_build_object(p_etapa, p_estado) where id = p_produccion_id;
end;
$$;

create or replace function retail.eliminar_produccion(p_produccion_id uuid)
returns void language plpgsql security definer set search_path = retail, public
as $$
declare v_prod producciones%rowtype;
begin
  select * into v_prod from producciones where id = p_produccion_id;
  if not found then raise exception 'La producción no existe'; end if;
  if not retail.puede_operar_sede(v_prod.unidad_id) then raise exception 'No tienes permiso sobre esta producción'; end if;
  if v_prod.inventariado_at is not null then
    raise exception 'Esta producción ya está en el inventario. Usa "Revertir" para sacarla, y luego elimínala.';
  end if;
  delete from producciones where id = p_produccion_id;
end;
$$;

create or replace function retail.revertir_produccion_inventario(p_produccion_id uuid)
returns void language plpgsql security definer set search_path = retail, public
as $$
declare v_prod producciones%rowtype; v_persona_id uuid; v_linea record; v_mov_id uuid;
begin
  select * into v_prod from producciones where id = p_produccion_id;
  if not found then raise exception 'La producción no existe'; end if;
  if not retail.puede_operar_sede(v_prod.unidad_id) then raise exception 'No tienes permiso sobre esta producción'; end if;
  if v_prod.inventariado_at is null then raise exception 'Esta producción no está en el inventario'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  for v_linea in select * from produccion_lineas where produccion_id = p_produccion_id loop
    insert into movimientos (variante_id, sede_id, tipo, cantidad, motivo, usuario_id, nota)
      values (v_linea.variante_id, v_prod.unidad_id, 'salida', v_linea.cantidad,
              'Reversa de producción', v_persona_id, 'Reversa ' || left(p_produccion_id::text, 8))
      returning id into v_mov_id;
    perform retail.fn_aplicar_movimiento(v_mov_id);
  end loop;
  update producciones set estado = 'en_proceso', inventariado_at = null where id = p_produccion_id;
end;
$$;

create or replace function retail.cerrar_produccion(
  p_produccion_id uuid, p_costo_tela numeric, p_costo_avios numeric, p_costo_maquila numeric, p_buenas jsonb
)
returns void language plpgsql security definer set search_path = retail, public
as $$
declare
  v_prod producciones%rowtype; v_persona_id uuid; v_total integer;
  v_item jsonb; v_linea record; v_variante_id uuid; v_cant integer; v_mov_id uuid;
begin
  select * into v_prod from producciones where id = p_produccion_id;
  if not found then raise exception 'La orden no existe'; end if;
  if not retail.puede_operar_sede(v_prod.unidad_id) then raise exception 'No tienes permiso sobre esta orden'; end if;
  if v_prod.inventariado_at is not null then raise exception 'Esta orden ya está cerrada en el inventario'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();

  if v_prod.es_muestra then
    update producciones set costo_tela = coalesce(p_costo_tela, 0), costo_avios = coalesce(p_costo_avios, 0),
      costo_maquila = coalesce(p_costo_maquila, 0), estado = 'terminado' where id = p_produccion_id;
    return;
  end if;

  v_total := 0;
  for v_item in select * from jsonb_array_elements(p_buenas) loop
    v_variante_id := (v_item->>'variante_id')::uuid;
    v_cant := coalesce((v_item->>'cantidad')::int, 0);
    if v_cant <= 0 then
      delete from produccion_lineas where produccion_id = p_produccion_id and variante_id = v_variante_id;
    else
      update produccion_lineas set cantidad = v_cant where produccion_id = p_produccion_id and variante_id = v_variante_id;
      v_total := v_total + v_cant;
    end if;
  end loop;
  if v_total <= 0 then raise exception 'No hay prendas buenas para mandar al inventario'; end if;

  update producciones set costo_tela = coalesce(p_costo_tela, 0), costo_avios = coalesce(p_costo_avios, 0),
    costo_maquila = coalesce(p_costo_maquila, 0), cantidad = v_total, estado = 'terminado', inventariado_at = now()
    where id = p_produccion_id;

  for v_linea in select * from produccion_lineas where produccion_id = p_produccion_id loop
    insert into movimientos (variante_id, sede_id, tipo, cantidad, motivo, usuario_id, nota)
      values (v_linea.variante_id, v_prod.unidad_id, 'entrada', v_linea.cantidad,
              'Producción del taller', v_persona_id, 'Orden ' || left(p_produccion_id::text, 8))
      returning id into v_mov_id;
    perform retail.fn_aplicar_movimiento(v_mov_id);
  end loop;
end;
$$;

create or replace function retail.registrar_produccion(
  p_unidad_id uuid, p_cantidad integer, p_costo_tela numeric, p_costo_avios numeric, p_costo_maquila numeric,
  p_precio_taller numeric, p_variantes jsonb default '[]'::jsonb, p_producto_id uuid default null,
  p_referencia text default null, p_categoria_id uuid default null, p_detalle text default null,
  p_es_muestra boolean default false, p_fecha_entrega date default null,
  p_marcar_terminado boolean default false, p_nota text default null
)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare
  v_persona_id uuid; v_producto_id uuid := p_producto_id; v_prod_id uuid;
  v_variantes jsonb := coalesce(p_variantes, '[]'::jsonb); v_total integer; v_costo_unit numeric(12,2);
  v_item jsonb; v_talla text; v_color text; v_cant integer; v_variante_id uuid; v_buenas jsonb := '[]'::jsonb;
begin
  if not retail.puede_operar_sede(p_unidad_id) then raise exception 'No tienes permiso para registrar producción en esa unidad'; end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();

  if jsonb_array_length(v_variantes) = 0 then
    if p_cantidad is null or p_cantidad <= 0 then raise exception 'La cantidad debe ser mayor a 0'; end if;
    v_variantes := jsonb_build_array(jsonb_build_object('talla', null, 'color', null, 'cantidad', p_cantidad));
  end if;

  select coalesce(sum((elem->>'cantidad')::int), 0) into v_total from jsonb_array_elements(v_variantes) elem;
  if v_total <= 0 then raise exception 'La cantidad total debe ser mayor a 0'; end if;
  v_costo_unit := round((coalesce(p_costo_tela,0)+coalesce(p_costo_avios,0)+coalesce(p_costo_maquila,0))/v_total, 2);

  if v_producto_id is null then
    if coalesce(trim(p_referencia), '') = '' then raise exception 'Falta el nombre del modelo'; end if;
    insert into productos (sku_padre, referencia, categoria_id)
      values ('T' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), p_referencia, p_categoria_id)
      returning id into v_producto_id;
  end if;

  insert into producciones (unidad_id, producto_id, cantidad, costo_tela, costo_avios, costo_maquila,
                            precio_taller, detalle, es_muestra, fecha_entrega, estado, nota, creado_por)
    values (p_unidad_id, v_producto_id, v_total, coalesce(p_costo_tela,0), coalesce(p_costo_avios,0),
            coalesce(p_costo_maquila,0), coalesce(p_precio_taller,0), p_detalle, coalesce(p_es_muestra,false),
            p_fecha_entrega, 'en_proceso', p_nota, v_persona_id)
    returning id into v_prod_id;

  for v_item in select * from jsonb_array_elements(v_variantes) loop
    v_talla := nullif(trim(v_item->>'talla'), ''); v_color := nullif(trim(v_item->>'color'), '');
    v_cant := (v_item->>'cantidad')::int;
    if v_cant is null or v_cant <= 0 then continue; end if;
    select id into v_variante_id from variantes
      where producto_id = v_producto_id and talla is not distinct from v_talla and color is not distinct from v_color limit 1;
    if v_variante_id is null then
      insert into variantes (producto_id, sku, talla, color, costo, precio, precio_taller)
        values (v_producto_id, 'T' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 11),
                v_talla, v_color, v_costo_unit, 0, coalesce(p_precio_taller,0))
        returning id into v_variante_id;
    else
      update variantes set costo = v_costo_unit, precio_taller = coalesce(p_precio_taller, precio_taller), updated_at = now()
        where id = v_variante_id;
    end if;
    insert into produccion_lineas (produccion_id, variante_id, cantidad) values (v_prod_id, v_variante_id, v_cant)
      on conflict (produccion_id, variante_id) do update set cantidad = excluded.cantidad;
    v_buenas := v_buenas || jsonb_build_array(jsonb_build_object('variante_id', v_variante_id, 'cantidad', v_cant));
  end loop;

  if coalesce(p_marcar_terminado, false) then
    perform retail.cerrar_produccion(v_prod_id, coalesce(p_costo_tela,0), coalesce(p_costo_avios,0), coalesce(p_costo_maquila,0), v_buenas);
  end if;

  return v_prod_id;
end;
$$;
