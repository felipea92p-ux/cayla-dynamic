-- ============================================================================
-- 0099 — Una tienda no es una oficina
-- ----------------------------------------------------------------------------
-- EL PROBLEMA
--
-- `sedes` guarda código, nombre y si está activa. Nada más. Así que el sistema
-- no sabe que **Central (CCO)** es administración y Desarrollo Organizacional
-- —no vende nada—, que **LIM** es un taller de producción, y que **AQP** y
-- **TRU** son tiendas que atienden clientas.
--
-- Sin esa distinción, el resumen de costos pone a Central al lado de AQP como
-- si fueran comparables, y la conclusión sale al revés de la realidad: Central
-- parece una tienda carísima que no factura nada. Quien mire ese cuadro sin
-- conocer el negocio va a concluir que hay que recortar en Central, que es
-- justo donde no se recorta.
--
-- Y el problema de fondo es peor que el cuadro: comparar el costo de dos sedes
-- por su TOTAL tampoco sirve aunque las dos sean tiendas. AQP con 4 personas y
-- TRU con 9 no se comparan por el total; se comparan por lo que cuesta cada
-- persona y cada hora trabajada.
--
-- QUÉ PROMETE
--
--   1. `sedes.tipo` con tres valores: 'central', 'taller', 'tienda'.
--   2. `fn_costos_planilla` devuelve, además del total por sede, el costo por
--      persona y el costo por hora — y agrupa también por tipo, para poder
--      leer «operar las tiendas cuesta X, administrar cuesta Y».
--   3. `fn_guardar_sede` acepta el tipo, para poder cambiarlo desde la
--      pantalla de Sedes sin tocar la base.
--
-- QUÉ ASUME
--
--   · Que una sede es de un solo tipo. Si algún día abres un local que es
--     tienda y taller a la vez, habrá que elegir uno y aceptar que el reporte
--     lo cuenta entero ahí. Se prefirió eso a una lista de tipos: sumar por una
--     sede que pertenece a dos categorías hace que los totales no cuadren con
--     el total general, y un cuadro de costos que no cuadra no se usa.
--   · Que el valor por defecto es 'tienda'. Es el caso mayoritario y el menos
--     dañino si alguien olvida ponerlo: una sede administrativa mal marcada
--     como tienda se nota enseguida (aparece con costo y sin ventas); una
--     tienda mal marcada como central desaparece del cuadro de tiendas y nadie
--     la echa de menos.
--
-- POR QUÉ NO SE DEDUJO DEL ÁREA DE CADA PERSONA
--
-- `areas.operativa` ya existe y era tentador. Pero una tienda también tiene
-- gente administrativa, y una persona de Central puede estar en un área
-- operativa. Deducir el tipo de la sede a partir de quién trabaja ahí clasifica
-- mal en cuanto la plantilla cambia — y cambia todos los meses. El tipo es una
-- propiedad del local, no de quien esté ese mes.
--
-- LA ASIGNACIÓN INICIAL
--
-- Se marca CCO como 'central' y LIM como 'taller' por su código, porque son las
-- sedes que existen hoy y esa es su realidad. Cualquier otra queda 'tienda'.
-- Esto se hace UNA vez, con `where tipo is null` implícito por el default: si
-- Felipe lo cambia después desde la pantalla, volver a pegar esta migración no
-- le pisa la decisión.
--
-- CÓMO SE REVIERTE
--
--   alter table sedes drop column if exists tipo;
--   -- y restaurar fn_costos_planilla con el cuerpo de la 0097
--   -- y fn_guardar_sede con el cuerpo de dos argumentos de la 0063.
-- ============================================================================

alter table sedes add column if not exists tipo text;

-- La asignación inicial va ANTES de poner el default y el not null, para que
-- se aplique solo a las filas que aún no tienen tipo — es decir, solo la
-- primera vez. Pegar esto dos veces no revierte un cambio hecho a mano.
update sedes set tipo = 'central' where tipo is null and codigo = 'CCO';
update sedes set tipo = 'taller'  where tipo is null and codigo = 'LIM';
update sedes set tipo = 'tienda'  where tipo is null;

alter table sedes alter column tipo set default 'tienda';
alter table sedes alter column tipo set not null;

alter table sedes drop constraint if exists chk_sede_tipo;
alter table sedes add constraint chk_sede_tipo
  check (tipo in ('central', 'taller', 'tienda'));

comment on column sedes.tipo is
  'Qué es este local: ''central'' (administración y Desarrollo Organizacional, no vende), ''taller'' (producción) o ''tienda'' (atiende clientas). Propiedad del local, no de quien trabaje ahí este mes. Sirve para no comparar el costo de una oficina con el de una tienda.';

-- ── Que se pueda cambiar desde la pantalla ──────────────────────────────────
-- Se EXTIENDE la función que ya existe (0063) en vez de crear una nueva: dos
-- puertas para guardar una sede acabarían divergiendo, que es el error que este
-- repositorio ya pagó tres veces esta semana.
create or replace function fn_guardar_sede(p_codigo text, p_nombre text, p_tipo text default null)
returns void
language plpgsql security definer set search_path = public
as $fn$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar sedes.';
  end if;
  if p_codigo is null or upper(trim(p_codigo)) !~ '^[A-Z0-9]{2,8}$' then
    raise exception 'Código inválido (2 a 8 letras/números, ej. LIMT): %', coalesce(p_codigo, '(vacío)');
  end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre de la sede es obligatorio.';
  end if;
  if p_tipo is not null and p_tipo not in ('central', 'taller', 'tienda') then
    raise exception 'El tipo de sede tiene que ser central, taller o tienda.';
  end if;

  insert into sedes (codigo, nombre, tipo)
  values (upper(trim(p_codigo)), trim(p_nombre), coalesce(p_tipo, 'tienda'))
  on conflict (codigo) do update
    set nombre = excluded.nombre,
        -- null = «no lo toques». Así una pantalla que todavía no manda el tipo
        -- no lo borra sin querer al guardar el nombre.
        tipo = coalesce(p_tipo, sedes.tipo);
end;
$fn$;

-- La versión de dos argumentos se retira para que llamar con dos no quede
-- ambiguo entre las dos firmas. Quien llame por nombre de argumento (así lo
-- hace PostgREST) sigue funcionando igual: el tercero toma su valor por defecto.
drop function if exists fn_guardar_sede(text, text);

grant execute on function fn_guardar_sede(text, text, text) to authenticated;
revoke execute on function fn_guardar_sede(text, text, text) from public, anon;

-- ── Costos: comparar sedes sin comparar peras con manzanas ──────────────────
create or replace function fn_costos_planilla(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = public
as $fn$
declare v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver los costos de planilla.';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde then
    raise exception 'El rango de fechas no es válido.';
  end if;

  with base as (
    select
      f.*,
      pp.fecha_ini,
      pp.fecha_fin,
      pp.pagado_at,
      extract(year  from pp.fecha_fin)::int as anio,
      extract(month from pp.fecha_fin)::int as mes,
      coalesce(se.tipo, 'tienda') as sede_tipo,
      coalesce(se.nombre, f.sede_codigo) as sede_nombre
    from v_planilla_pagada f
    join periodos_planilla pp on pp.id = f.periodo_id
    left join sedes se on se.codigo = f.sede_codigo
    where pp.estado = 'pagado'
      and pp.fecha_fin between p_desde and p_hasta
  )
  select jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,

    'periodos_retroactivos', (
      select count(distinct periodo_id)::int from base where origen = 'retroactivo'
    ),

    'totales', (
      select jsonb_build_object(
        'personas',    count(distinct persona_id),
        'periodos',    count(distinct periodo_id),
        'neto',        coalesce(round(sum(total), 2), 0),
        'provisiones', coalesce(round(sum(provision_total), 2), 0),
        'costo',       coalesce(round(sum(costo_total), 2), 0)
      ) from base
    ),

    'por_periodo', (
      select coalesce(jsonb_agg(x order by x->>'fecha_fin' desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'periodo_id',  b.periodo_id,
          'fecha_ini',   b.fecha_ini,
          'fecha_fin',   b.fecha_fin,
          'anio',        b.anio,
          'mes',         b.mes,
          'pagado_at',   max(b.pagado_at),
          'congelada_at', max(b.congelada_at),
          'version',     max(b.version),
          'reconstruida', bool_or(b.origen = 'retroactivo'),
          'personas',    count(*),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2)
        ) as x
        from base b
        group by b.periodo_id, b.fecha_ini, b.fecha_fin, b.anio, b.mes
      ) s
    ),

    -- ⇩ NUEVO 0099: el tipo, y las dos cifras que sí permiten comparar.
    -- El costo por persona se calcula sobre personas DISTINTAS, no sobre filas:
    -- alguien que cobró en tres periodos es una persona, no tres.
    'por_sede', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'sede',        b.sede_codigo,
          'nombre',      b.sede_nombre,
          'tipo',        b.sede_tipo,
          'personas',    count(distinct b.persona_id),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'costo_por_persona', round(sum(b.costo_total) / nullif(count(distinct b.persona_id), 0), 2),
          'costo_por_hora',    round(sum(b.costo_total) / nullif(sum(b.horas_mes), 0), 2)
        ) as x
        from base b
        group by b.sede_codigo, b.sede_nombre, b.sede_tipo
      ) s
    ),

    -- Operar las tiendas cuesta X · producir en el taller cuesta Y ·
    -- administrar cuesta Z. Es la lectura que el total por sede no da.
    'por_tipo', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'tipo',        b.sede_tipo,
          'sedes',       count(distinct b.sede_codigo),
          'personas',    count(distinct b.persona_id),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2),
          'costo_por_persona', round(sum(b.costo_total) / nullif(count(distinct b.persona_id), 0), 2),
          'costo_por_hora',    round(sum(b.costo_total) / nullif(sum(b.horas_mes), 0), 2)
        ) as x
        from base b
        group by b.sede_tipo
      ) s
    ),

    'por_area', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'area',        b.area_codigo,
          'nombre',      coalesce(ar.nombre, b.area_codigo, 'Sin área'),
          'operativa',   coalesce(ar.operativa, false),
          'personas',    count(distinct b.persona_id),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2)
        ) as x
        from base b
        left join areas ar on ar.codigo = b.area_codigo
        group by b.area_codigo, ar.nombre, ar.operativa
      ) s
    ),

    'por_persona', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'persona_id',  b.persona_id,
          'nombre',      max(b.nombre),
          'sede',        max(b.sede_codigo),
          'area',        max(b.area_codigo),
          'periodos',    count(*),
          'horas',       round(sum(b.horas_mes), 2),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2)
        ) as x
        from base b
        group by b.persona_id
      ) s
    )
  ) into v_out;

  return v_out;
end;
$fn$;

grant execute on function fn_costos_planilla(date, date) to authenticated;
revoke execute on function fn_costos_planilla(date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (99, 'una_tienda_no_es_una_oficina')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
