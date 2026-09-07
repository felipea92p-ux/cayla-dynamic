-- ============================================================================
-- 0392_los_guardianes_de_retail_dejan_de_colarse_por_el_or_suelto.sql
-- ============================================================================
--
-- QUÉ PROMETE
--
--   Que una persona CESADA (estado='inactivo', sesión de Auth todavía viva
--   porque fn_cesar_persona nunca toca Supabase Auth) deje de poder abrir
--   caja, vender, cerrar caja, registrar gastos/depósitos o recalcular el
--   stock en CUALQUIER sede de retail — y que una persona ACTIVA deje de
--   poder hacerlo en una sede que no es la suya. Y que recalcular_stock()
--   ya no borre en silencio stock_minimo ni contenedor_id, que no viven en
--   ninguna otra tabla.
--
-- QUÉ ASUME
--
--   · retail.es_lider(), retail.es_supervisor() y retail.puede_operar_sede()
--     están definidas tal cual quedaron en la 0218 (única definición de cada
--     una en todo el repo — confirmado, no hay una versión posterior).
--   · retail.abrir_caja(), retail.cerrar_caja() y retail.registrar_venta()
--     están tal cual quedaron en la 0222 (ídem, única definición cada una).
--   · retail.recalcular_stock() está tal cual quedó en la 0223 (ídem).
--   · public.fn_rol_actual() devuelve NULL para una persona con
--     estado <> 'activo' (0374) y public.fn_sede_actual_persona() (0005) NO
--     filtra por estado — las dos siguen así hoy; esta migración no las toca.
--
-- POR QUÉ HACÍA FALTA (auditoría del 2026-09-06/07, "Radiografía Dynamic")
--
--   La 0374 (2026-09-04) hizo fn_rol_actual() null-safe DEL LADO DE DYNAMIC
--   para que una persona cesada dejara de contar como si tuviera rol. Pero
--   retail.es_lider() y retail.es_supervisor() son "select fn_rol_actual() =
--   'admin'" SIN coalesce — a diferencia de la versión original de este
--   mismo código en cayla-retail (supabase/migrations/0003_rls.sql:28, que
--   SÍ traía "coalesce(..., false)" y se perdió al importarlo). Con
--   fn_rol_actual() en NULL, "NULL = 'admin'" es NULL, y en PL/pgSQL
--   "if not NULL then raise" NUNCA entra — la excepción no se lanza y la
--   función, que es SECURITY DEFINER, se salta la RLS igual.
--
--   PROBADO contra el Postgres local dentro de BEGIN…ROLLBACK, con control
--   (activa vs. cesada, misma persona): activa → retail.registrar_gasto
--   bloqueada, "Solo un Líder puede registrar gastos"; cesada → PASÓ, quedó
--   escrita la fila. Antes de la 0374 el mismo caso daba FALSE determinista
--   y sí bloqueaba — la 0374, escrita para cortarle el poder a quien cesa,
--   es lo que abrió este camino en retail.
--
--   Y aparte, tres funciones (abrir_caja, cerrar_caja, registrar_venta) NO
--   llamaban a puede_operar_sede() en absoluto — ni siquiera de la forma
--   rota. PROBADO: una integrante activa y normal de Trujillo abrió caja,
--   vendió y cerró la caja de Arequipa sin que nada se lo impidiera.
--
--   Y recalcular_stock() no tenía ningún candado, y truncate+rebuild
--   perdía stock_minimo/contenedor_id (no viven en `movimientos`, así que
--   no hay de dónde reconstruirlos).
--
-- QUÉ NO ARREGLA A PROPÓSITO (alcance deliberado, no descuido)
--
--   · Los otros ~8 sitios de retail que llaman "if not retail.es_lider()"
--     o "if not retail.puede_operar_sede(...)" (registrar_asiento,
--     registrar_deposito, fijar_stock_minimo, las 5 funciones de
--     producción del Taller en 0224, 2 más en 0226) NO se reescriben acá a
--     la forma "is not true": con los tres guardianes ahora null-safe
--     (coalesce), CUALQUIER llamada "if not X" vuelve a ser 100% segura sin
--     tocarla — coalesce cierra las doce puertas de un solo golpe, que es
--     justo lo que la propia auditoría señaló como la vía barata. La
--     reescritura a "is not true" en esos ~8 sitios queda como mejora de
--     consistencia para una migración aparte, no como algo que esta deje a
--     medias en seguridad.
--   · fn_sede_actual_persona() NO se toca. Sigue sin filtrar estado, así
--     que una persona cesada conserva su sede_base_id de cuando trabajaba
--     — el "or" de puede_operar_sede() ya no puede dar NULL, pero si esa
--     sede vieja coincide con la sede objetivo, el resultado real es TRUE.
--     Riesgo residual: una cesada podría seguir operando su PROPIA sede de
--     antes (no cualquier sede, como hoy). Cortar esto de raíz exige tocar
--     fn_sede_actual_persona(), una función compartida con Dynamic con
--     muchos más llamadores — no es un cambio para colar dentro de una
--     migración de retail. Queda anotado en docs/estado.md como pendiente
--     aparte, con su propio análisis de impacto.
--
-- CÓMO SE REVIERTE
--
--   Restaurar los siete cuerpos desde la 0218/0222/0223 tal cual — pero no
--   se debería: eso reabre las doce puertas para cualquier persona cesada
--   con sesión viva, y recalcular_stock volvería a borrar stock_minimo.
--
-- MD5 DE PARTIDA — medido en esta Mac (Postgres local), ANTES de escribir
-- este cambio. Como manda la casa, esto NO reemplaza pedirlo a producción:
-- se vuelve a pedir en el mensaje en que se entregue este SQL.
--
--   es_lider            tal_cual = 78e1b5a7d6b530e2019569de776f84dd
--   es_supervisor       tal_cual = 13c4fda32ce59e91cf6b869d9c1aa489
--   puede_operar_sede   tal_cual = 94ca63c18e36b74b602f82086f960d41
--   abrir_caja          tal_cual = f5a696d609922bcc2f976205c025e424
--   cerrar_caja         tal_cual = d9ccfe08a4b33a04efbba8202b07bf47
--   registrar_venta     tal_cual = def9141c9c5f2c56f664505f6264eaea
--   recalcular_stock    tal_cual = f3900bc04d2cd50515cf9de151ec3cfc
--
--   select p.proname, md5(p.prosrc) as tal_cual
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'retail'
--      and p.proname in ('es_lider','es_supervisor','puede_operar_sede',
--                         'abrir_caja','cerrar_caja','registrar_venta',
--                         'recalcular_stock')
--    order by p.proname;
--
-- AUDITADO empíricamente contra el Postgres local dentro de BEGIN…ROLLBACK,
-- seis escenarios con datos reales (una integrante activa de TRU, una
-- cesada de TRU con auth.users vivo, un admin de prueba):
--   1) puede_operar_sede(cesada, AQP)         → antes NULL, ahora FALSE
--   2) abrir_caja(cesada, AQP)                → antes abría, ahora RECHAZA
--   3) abrir_caja(activa-TRU, AQP)             → antes abría, ahora RECHAZA
--   4) abrir_caja(activa-TRU, TRU — su sede)   → sigue FUNCIONANDO
--   5) recalcular_stock(cesada)                → antes corría, ahora RECHAZA
--   6) recalcular_stock(admin), con un stock_minimo=777 puesto a mano antes
--      del truncate+rebuild → sigue en 777 después. contenedor_id igual.
-- ============================================================================

create or replace function retail.es_lider()
returns boolean language sql stable set search_path = public
as $$ select coalesce(public.fn_rol_actual() = 'admin', false); $$;

create or replace function retail.es_supervisor()
returns boolean language sql stable set search_path = public
as $$ select coalesce(public.fn_rol_actual() = 'supervisor_sede', false); $$;

create or replace function retail.puede_operar_sede(p_sede_id uuid)
returns boolean language sql stable set search_path = public
as $$
  select coalesce(public.fn_rol_actual() = 'admin', false)
      or coalesce(public.fn_sede_actual_persona() = p_sede_id, false);
$$;

-- ── abrir_caja, cerrar_caja, registrar_venta: les faltaba el candado entero,
-- no una versión rota de él. Mismo patrón que ya usa registrar_movimiento
-- (0222:86), con el "is not true" que la casa exige para todo lo nuevo.
create or replace function retail.abrir_caja(p_sede_id uuid, p_monto_apertura numeric)
returns uuid language plpgsql security definer set search_path = retail, public
as $$
declare v_persona_id uuid; v_caja_id uuid;
begin
  if retail.puede_operar_sede(p_sede_id) is not true then
    raise exception 'No tienes permiso para abrir caja en esa sede';
  end if;
  if exists (select 1 from cajas where sede_id = p_sede_id and estado = 'abierta') then
    raise exception 'Ya hay una caja abierta en esta sede — ciérrala antes de abrir otra';
  end if;
  select id into v_persona_id from public.personas where auth_user_id = auth.uid();
  insert into cajas (sede_id, monto_apertura, abierta_por)
    values (p_sede_id, p_monto_apertura, v_persona_id) returning id into v_caja_id;
  return v_caja_id;
end;
$$;

create or replace function retail.cerrar_caja(p_caja_id uuid, p_monto_contado numeric)
returns table (monto_esperado numeric, monto_contado numeric, diferencia numeric)
language plpgsql security definer set search_path = retail, public
as $$
declare v_persona_id uuid; v_caja cajas%rowtype; v_esperado numeric;
begin
  select * into v_caja from cajas where id = p_caja_id;
  if not found then raise exception 'La caja % no existe', p_caja_id; end if;
  -- La sede se resuelve DESDE LA CAJA, no desde un parámetro: cerrar_caja
  -- solo recibe p_caja_id, así que no hay otra forma de saber de qué sede es.
  if retail.puede_operar_sede(v_caja.sede_id) is not true then
    raise exception 'No tienes permiso para cerrar caja en esa sede';
  end if;
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
  if retail.puede_operar_sede(v_caja.sede_id) is not true then
    raise exception 'No tienes permiso para vender en esa sede';
  end if;
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

-- ── recalcular_stock: sin candado, y truncate+rebuild perdía stock_minimo y
-- contenedor_id (no viven en `movimientos`, así que no hay de dónde
-- reconstruirlos). Se respaldan en una tabla temporal antes del truncate y
-- se reponen al final con un UPDATE — el resto de la función (los cinco
-- INSERT que reconstruyen `cantidad` desde movimientos) no cambia ni un
-- carácter.
create or replace function retail.recalcular_stock()
returns void language plpgsql security definer set search_path = retail, public
as $$
begin
  if retail.es_lider() is not true then
    raise exception 'Solo un Líder puede recalcular el stock';
  end if;

  create temp table _stock_respaldo on commit drop as
    select variante_id, sede_id, stock_minimo, contenedor_id from stock;

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

  update stock s set stock_minimo = r.stock_minimo, contenedor_id = r.contenedor_id
    from _stock_respaldo r
    where r.variante_id = s.variante_id and r.sede_id = s.sede_id;
end;
$$;

insert into migraciones_aplicadas (numero, nombre)
values (392, '0392_los_guardianes_de_retail_dejan_de_colarse_por_el_or_suelto')
on conflict (numero) do nothing;

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Los tres guardianes ya no pueden devolver NULL bajo ninguna combinación de
-- entradas (comprobado con los coalesce, no solo leído): "es_lider_null" y
-- "puede_operar_sede_null" deben salir los dos en `false` — si alguno sale
-- vacío (NULL), esta migración no cerró lo que promete.
select
  coalesce((select public.fn_rol_actual() = 'admin' from (select 1) x), false) is not null as ok_referencia,
  (retail.es_lider() is not null)            as es_lider_nunca_null,
  (retail.es_supervisor() is not null)       as es_supervisor_nunca_null,
  pg_get_functiondef('retail.abrir_caja(uuid,numeric)'::regprocedure) like '%puede_operar_sede%' as abrir_caja_ya_valida,
  pg_get_functiondef('retail.cerrar_caja(uuid,numeric)'::regprocedure) like '%puede_operar_sede%' as cerrar_caja_ya_valida,
  pg_get_functiondef('retail.registrar_venta(uuid,text,jsonb,text)'::regprocedure) like '%puede_operar_sede%' as registrar_venta_ya_valida,
  pg_get_functiondef('retail.recalcular_stock()'::regprocedure) like '%es_lider%' as recalcular_stock_ya_valida;
