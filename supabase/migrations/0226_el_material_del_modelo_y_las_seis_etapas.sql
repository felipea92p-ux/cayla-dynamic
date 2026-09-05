-- ============================================================================
-- 0226 — IMPORTADA DEL REPOSITORIO cayla-retail
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
--    Origen: `cayla-retail/supabase/unificacion/11_produccion_material_etapas.sql`
--    Decisión completa: `cayla-retail/docs/adr/0003-unificacion-retail-dynamic.md`
--
-- Debajo de esta línea empieza el archivo original, sin una sola modificación.
-- ============================================================================

-- ============================================================================
-- UNIFICACIÓN retail → dynamic · PASO 11 · Producción: material + 6 etapas
-- Correr en cayla-DYNAMIC. Aditivo — no borra ni rompe nada existente.
-- ----------------------------------------------------------------------------
-- Qué hace:
--   1) 'material' del modelo (qué tela es: Lino, Drill...) — dato del MODELO,
--      no una variante. Mismo diseño en otra tela = otro modelo (agrupados por
--      familia). Así el costo queda limpio por modelo.
--   2) set_etapa_produccion acepta las 6 etapas (antes solo 3). El proceso se
--      parte en dos tipos de orden: MUESTRA = desarrollo (patronaje, muestra,
--      escalado) · PRODUCCIÓN = fabricar (corte, confección, acabados).
--   3) registrar_produccion guarda el material cuando se crea un modelo nuevo.
-- ============================================================================

-- 1) Material del modelo.
alter table retail.productos add column if not exists material text;

-- 2) Etapas válidas: las 6 (desarrollo + producción).
create or replace function retail.set_etapa_produccion(p_produccion_id uuid, p_etapa text, p_estado text)
returns void language plpgsql security definer set search_path = retail, public
as $$
declare v_unidad uuid;
begin
  select unidad_id into v_unidad from producciones where id = p_produccion_id;
  if v_unidad is null then raise exception 'La orden no existe'; end if;
  if not retail.puede_operar_sede(v_unidad) then raise exception 'No tienes permiso sobre esta orden'; end if;
  if p_etapa not in ('patronaje', 'muestra', 'escalado', 'corte', 'confeccion', 'acabado')
    then raise exception 'Etapa inválida'; end if;
  if p_estado not in ('pendiente', 'hecho', 'tercerizado') then raise exception 'Estado de etapa inválido'; end if;
  update producciones set etapas = etapas || jsonb_build_object(p_etapa, p_estado) where id = p_produccion_id;
end;
$$;

-- 3) registrar_produccion + p_material. Se re-crea con un parámetro más al final;
--    primero borramos la firma vieja de 15 params para no dejar dos versiones.
drop function if exists retail.registrar_produccion(
  uuid, integer, numeric, numeric, numeric, numeric, jsonb, uuid, text, uuid, text, boolean, date, boolean, text
);

create or replace function retail.registrar_produccion(
  p_unidad_id uuid, p_cantidad integer, p_costo_tela numeric, p_costo_avios numeric, p_costo_maquila numeric,
  p_precio_taller numeric, p_variantes jsonb default '[]'::jsonb, p_producto_id uuid default null,
  p_referencia text default null, p_categoria_id uuid default null, p_detalle text default null,
  p_es_muestra boolean default false, p_fecha_entrega date default null,
  p_marcar_terminado boolean default false, p_nota text default null, p_material text default null
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
    insert into productos (sku_padre, referencia, categoria_id, material)
      values ('T' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 9), p_referencia, p_categoria_id,
              nullif(trim(p_material), ''))
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
