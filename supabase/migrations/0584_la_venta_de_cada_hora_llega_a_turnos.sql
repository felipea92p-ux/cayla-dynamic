-- ============================================================================
-- 0584 · LA VENTA DE CADA HORA LLEGA A TURNOS
-- ============================================================================
--
-- QUÉ PROMETE
--   1. `fn_compras_por_hora(sede, desde, hasta)` dice cuántas compras hubo en
--      cada hora de cada día en una tienda: una compra es un ticket completado
--      de retail (`retail.ventas`, estado «completada», sin las de prueba). Solo
--      cuenta tickets: ni montos, ni prendas, ni quién compró.
--   2. Dos números por tienda, en Parámetros, para pasar de compras a personas:
--      el RITMO (compras por hora que atiende una persona en piso, 1,5) y el
--      MÍNIMO (personas en piso aunque no haya venta, 3). Viven en
--      `configuracion.cobertura_por_venta`, uno por tienda, y DO los cambia con
--      motivo desde /admin/parametros (0552).
--   3. `fn_cobertura_por_venta(sede)` devuelve esos dos números para una sede,
--      con el valor de partida si la tienda todavía no tiene los suyos.
--   Con eso, la vista Día de Turnos reproduce un día cerrado contra lo que
--   pedía la venta de cada hora, y la sugerencia de turnos (PR siguiente) sabe
--   cuánta gente hace falta.
--
-- DE DÓNDE SALE (Felipe, 2026-11-03)
--   · La repetición de un día cerrado va dentro de la vista Día.
--   · El ritmo y el mínimo van a Parámetros, uno por tienda.
--   · Una compra es un ticket completado (no cada prenda).
--   · La lectura vive en Dynamic: las dos bases son la misma, y así es un solo
--     PR y un solo SQL. El precio de eso está en «SE ROMPE SI».
--
-- QUÉ ASUME
--   · La 0552 y la 0571 pegadas: `parametros_catalogo` con `roles_cambia`, y su
--     trigger sobre `configuracion` (esta migración escribe la clave nueva como
--     `postgres`, que el trigger deja pasar y anota con origen «base»).
--   · La forma de `retail.ventas` y `retail.ubicaciones` que tiene PRODUCCIÓN,
--     que NO es la que construyen las migraciones de este repo (0220 creó una
--     `retail.ventas` vieja, con `sede_id`; la de verdad la escribe el repo de
--     retail): `ventas(ubicacion_id, estado, es_prueba, created_at)` y
--     `ubicaciones(id, sede_dynamic_id)`. Medido en producción el 2026-11-03:
--     TRU 1 228 completadas desde el 30-sep, AQP 536, la tienda de Lima 28.
--   · Por eso la función es plpgsql: Postgres no revisa las columnas al crearla,
--     solo al correrla. En el CI de este repo existe con la tabla vieja y su
--     prueba (474) le arma la forma de producción dentro de la transacción.
--
-- POR QUÉ ASÍ
--   · Un ticket y no una prenda: es lo que mide el ritmo de 1,5 (una clienta que
--     lleva cinco prendas se atiende una vez). Lo decidió Felipe.
--   · Se cuentan TODOS los tickets completados, también los de marcas en
--     concesión: para atender, una clienta es una clienta. El «panel comercial»
--     de retail las saca porque mide plata, no gente.
--   · Las horas son las de Lima (`at time zone 'America/Lima'`), igual que
--     `fn_hoy_lima`: el corte del día no puede tener dos versiones.
--   · El tope de 62 días por consulta es para que nadie pida un año entero desde
--     el navegador. La pantalla pide una semana.
--   · Si la consulta a retail falla (una columna que cambió de nombre), la
--     función FALLA: no devuelve cero. Una sugerencia de turnos que creyera que
--     no hubo venta es peor que no tener sugerencia, y la pantalla lo dice con
--     palabras («No se pudieron leer las compras de retail»).
--   · Los parámetros por tienda se arman desde `sedes` (tipo tienda, activa), no
--     desde una lista escrita a mano. Una tienda que abra después usa el valor
--     de partida hasta que DO le ponga los suyos (sumarla al catálogo es una
--     migración: el catálogo nombra cada parámetro).
--
-- ESTADOS QUE NUNCA
--   · Nunca un ritmo en cero (dividiría por cero): mínimo 0,5 en el catálogo.
--   · Nunca un número de compras de otra sede: la lectura filtra por
--     `ubicaciones.sede_dynamic_id`.
--   · Nunca lee compras quien no es admin, Líder DO o la líder de equipo de
--     ESA sede.
--
-- SE ROMPE SI
--   · Retail renombra `estado`, `es_prueba`, `ubicacion_id` o
--     `sede_dynamic_id`. Falla ruidoso (ver arriba) y se arregla aquí. Queda
--     anotado del lado de retail que Turnos lee esas columnas.
--
-- CÓMO SE REVIERTE
--   drop function if exists fn_compras_por_hora(uuid, date, date);
--   drop function if exists fn_cobertura_por_venta(uuid);
--   delete from parametros_catalogo where parametro like 'cobertura\_%';
--   (la clave de `configuracion` puede quedarse: nadie más la lee)
--
-- CÓMO SE COMPRUEBA
--   La consulta del final: los dos números de cada tienda, las dos funciones y
--   el registro. Y, de solo lectura, las compras de ayer en TRU:
--     select * from fn_compras_por_hora(
--       (select id from sedes where codigo = 'TRU'), fn_hoy_lima() - 1, fn_hoy_lima() - 1);
--   (desde el SQL Editor no hay sesión: el guardia lo deja pasar como postgres).
-- ============================================================================

-- ── 0 · Guardia ─────────────────────────────────────────────────────────────
do $guardia$
begin
  if to_regclass('public.parametros_catalogo') is null
     or not exists (select 1 from information_schema.columns
                     where table_name = 'parametros_catalogo' and column_name = 'roles_cambia') then
    raise exception 'Falta la 0552 o la 0571 (catálogo de parámetros con roles): esta migración no entra sin ellas.';
  end if;
end
$guardia$;

-- ── 1 · Los dos números por tienda ──────────────────────────────────────────
-- La clave nace con un objeto por tienda activa: {"TRU": {"ritmo": 1.5, "minimo": 3}, …}.
-- Si ya existe, se suman solo las tiendas que falten: repegar no pisa lo que DO cambió.
insert into configuracion (clave, valor, descripcion)
select 'cobertura_por_venta',
       coalesce(jsonb_object_agg(s.codigo, jsonb_build_object('ritmo', 1.5, 'minimo', 3)), '{}'::jsonb),
       'Por tienda (código de sede): compras por hora que atiende una persona en piso (ritmo) y personas mínimas en piso (minimo). Se cambian desde Parámetros. 0584.'
  from sedes s
 where s.tipo = 'tienda' and s.activa
on conflict (clave) do update
   set valor = (select coalesce(jsonb_object_agg(s.codigo, jsonb_build_object('ritmo', 1.5, 'minimo', 3)), '{}'::jsonb)
                  from sedes s where s.tipo = 'tienda' and s.activa) || configuracion.valor;

insert into parametros_catalogo
  (parametro, nombre, descripcion, unidad, clase, tipo_valor, valor_min, valor_max, valor_defecto,
   almacen, almacen_clave, ruta, editable, base, orden, roles_cambia)
select 'cobertura_ritmo_' || lower(s.codigo),
       'Ritmo de venta por persona · ' || s.nombre,
       'Cuántas compras por hora atiende una persona en piso. Turnos lo usa para decir cuánta gente pedía la venta de cada hora: compras de la hora ÷ este número, redondeado hacia arriba. Más alto = menos gente.',
       'compras por hora', 'operativo', 'decimal', 0.5, 10, 1.5,
       'configuracion', 'cobertura_por_venta', array[s.codigo, 'ritmo'], true,
       'Medido con la venta de Tienda TRU (decisión de Felipe, 2026-11-02)', 300, array['admin', 'lider_do']
  from sedes s where s.tipo = 'tienda' and s.activa
union all
select 'cobertura_minimo_' || lower(s.codigo),
       'Mínimo en piso · ' || s.nombre,
       'Personas en piso aunque la hora no tenga venta: abrir, cerrar y cubrir el piso. La venta puede pedir más, nunca menos.',
       'personas', 'operativo', 'entero', 1, 10, 3,
       'configuracion', 'cobertura_por_venta', array[s.codigo, 'minimo'], true,
       'Apertura con 3 (decisión de Felipe, 2026-11-02)', 310, array['admin', 'lider_do']
  from sedes s where s.tipo = 'tienda' and s.activa
on conflict (parametro) do update
   set nombre = excluded.nombre, descripcion = excluded.descripcion, unidad = excluded.unidad,
       valor_min = excluded.valor_min, valor_max = excluded.valor_max, base = excluded.base, orden = excluded.orden;

-- ── 2 · Leer los dos números de una sede ────────────────────────────────────
create or replace function fn_cobertura_por_venta(p_sede_id uuid)
returns table (ritmo numeric, minimo integer)
language sql
stable
security definer
set search_path = public
as $fn$
  select coalesce(fn_parametro_numero_en(c.valor, array[s.codigo, 'ritmo']), 1.5),
         coalesce(fn_parametro_numero_en(c.valor, array[s.codigo, 'minimo']), 3)::integer
    from sedes s
    left join configuracion c on c.clave = 'cobertura_por_venta'
   where s.id = p_sede_id;
$fn$;

comment on function fn_cobertura_por_venta(uuid) is
  'El ritmo (compras por hora por persona en piso) y el mínimo en piso de una sede, de configuracion.cobertura_por_venta; 1,5 y 3 si la tienda no tiene los suyos. 0584.';

revoke all on function fn_cobertura_por_venta(uuid) from public, anon;
grant execute on function fn_cobertura_por_venta(uuid) to authenticated;

-- ── 3 · Las compras de cada hora ────────────────────────────────────────────
create or replace function fn_compras_por_hora(p_sede_id uuid, p_desde date, p_hasta date)
returns table (fecha date, hora integer, compras integer)
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  -- Desde el SQL Editor (sin sesión) se deja pasar: es Felipe midiendo.
  if auth.uid() is not null and (
       fn_es_admin_o_lider()
       or (fn_rol_actual() = 'supervisor_sede' and fn_sede_actual_persona() = p_sede_id)
     ) is not true then
    raise exception 'No autorizado.';
  end if;

  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'El rango de fechas no es válido.';
  end if;
  if p_hasta - p_desde > 62 then
    raise exception 'Se pueden pedir hasta 62 días de compras a la vez.';
  end if;

  -- plpgsql a propósito: las columnas de retail se revisan al correr, no al
  -- crear (ver «QUÉ ASUME»). Si cambiaron, esto falla y la pantalla lo dice.
  return query
  select (v.created_at at time zone 'America/Lima')::date,
         extract(hour from v.created_at at time zone 'America/Lima')::integer,
         count(*)::integer
    from retail.ventas v
    join retail.ubicaciones u on u.id = v.ubicacion_id
   where u.sede_dynamic_id = p_sede_id
     and v.estado = 'completada'
     and v.es_prueba is not true
     and v.created_at >= (p_desde::timestamp at time zone 'America/Lima')
     and v.created_at <  ((p_hasta + 1)::timestamp at time zone 'America/Lima')
   group by 1, 2
   order by 1, 2;
end
$fn$;

comment on function fn_compras_por_hora(uuid, date, date) is
  'Compras (tickets completados de retail, sin las de prueba) por día y hora de Lima en una tienda. Admin, Líder DO o la líder de equipo de esa sede; hasta 62 días. Falla —no devuelve cero— si retail cambió la forma de sus ventas. 0584.';

revoke all on function fn_compras_por_hora(uuid, date, date) from public, anon;
grant execute on function fn_compras_por_hora(uuid, date, date) to authenticated;

-- ── 4 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (584, 'la_venta_de_cada_hora_llega_a_turnos')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

select
  (select string_agg(parametro || ' = ' || coalesce(fn_parametro_numero_en(c.valor, p.ruta)::text, '—'), ' · ' order by parametro)
     from parametros_catalogo p join configuracion c on c.clave = p.almacen_clave
    where p.parametro like 'cobertura\_%')                                         as parametros,
  to_regprocedure('fn_compras_por_hora(uuid,date,date)') is not null               as lee_compras,
  to_regprocedure('fn_cobertura_por_venta(uuid)') is not null                      as lee_parametros,
  (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 584) as registro;
