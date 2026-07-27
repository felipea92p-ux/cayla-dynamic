-- ============================================================================
-- 0097 — Lo que cuesta el equipo
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE
--
-- Una sola función, `fn_costos_planilla(desde, hasta)`, que suma lo que costó
-- el equipo en un rango de fechas: total, por sede, por área y por periodo.
-- Se alimenta ÚNICAMENTE de la foto del pago (0096). No calcula nada.
--
-- QUÉ ASUME, Y ES LO IMPORTANTE
--
--   · Solo entra lo PAGADO Y CONGELADO. Un periodo abierto no aparece: su
--     número todavía se mueve, y un costo que se mueve no es un costo, es una
--     estimación. La proyección del periodo en curso sigue estando donde
--     siempre, en la pantalla de Planilla.
--   · «Costo» aquí es lo que le cuesta a CAYLA: lo que recibe la persona MÁS
--     las provisiones (gratificación, CTS y vacaciones que se van devengando
--     aunque se paguen después). Es distinto de lo que se transfiere ese mes, y
--     las dos cifras se devuelven por separado porque el contador necesita las
--     dos.
--   · La sede y el área son las que la persona tenía EN ESE PERIODO, no las de
--     hoy: eso ya venía congelado en la foto.
--
-- LA OBJECIÓN QUE HAY QUE DECIR EN PANTALLA
--
-- Los periodos de planilla de CAYLA no son meses calendario: duran entre 20 y
-- 46 días (`periodos_planilla`). Así que «el costo de julio» no existe: existe
-- «el costo del periodo que cerró en julio». La etiqueta de mes que devuelve
-- esta función sale de `fecha_fin`, igual que la que ya usa
-- `fn_planilla_calcular`, para que las dos pantallas digan lo mismo. Pero la
-- unidad real es el periodo, y así hay que rotularlo: sumar dos periodos que
-- cerraron en el mismo mes no es sumar un mes.
--
-- POR QUÉ NO SE MANDA A RETAIL TODAVÍA
--
-- Decisión de Felipe, 27-07-2026: el apartado de costos vive aquí, en Dynamic.
-- El puente con CAYLA retail (`docs/integracion-retail/`) todavía no existe;
-- cuando exista, leerá de esta misma función. Mandar el número antes de que
-- esté congelado habría sido mandar un número que cambia solo.
--
-- CÓMO SE REVIERTE
--
--   drop function if exists fn_costos_planilla(date, date);
-- ============================================================================

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
    -- Un periodo entra si CERRÓ dentro del rango. Se corta por fecha_fin y no
    -- por solape, para que un periodo no se cuente dos veces en dos consultas
    -- consecutivas: cada periodo pertenece exactamente a un rango.
    select
      f.*,
      pp.fecha_ini,
      pp.fecha_fin,
      pp.pagado_at,
      extract(year  from pp.fecha_fin)::int as anio,
      extract(month from pp.fecha_fin)::int as mes
    from v_planilla_pagada f
    join periodos_planilla pp on pp.id = f.periodo_id
    where pp.estado = 'pagado'
      and pp.fecha_fin between p_desde and p_hasta
  )
  select jsonb_build_object(
    'desde', p_desde,
    'hasta', p_hasta,

    -- Cuántos de estos periodos tienen la foto reconstruida en vez de tomada el
    -- día del pago. Si hay alguno, la pantalla tiene que decirlo.
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

    'por_sede', (
      select coalesce(jsonb_agg(x order by (x->>'costo')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'sede',        b.sede_codigo,
          'nombre',      coalesce(se.nombre, b.sede_codigo),
          'personas',    count(distinct b.persona_id),
          'neto',        round(sum(b.total), 2),
          'provisiones', round(sum(b.provision_total), 2),
          'costo',       round(sum(b.costo_total), 2)
        ) as x
        from base b
        left join sedes se on se.codigo = b.sede_codigo
        group by b.sede_codigo, se.nombre
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

comment on function fn_costos_planilla(date, date) is
  'Suma lo que costó el equipo entre dos fechas, leyendo SOLO la foto de los pagos congelados (0096). Un periodo entra si su fecha_fin cae en el rango. No calcula nada: si un número está mal, está mal desde el día del pago.';

-- Nota sobre el permiso: esta función SÍ se concede a `authenticated`, y es
-- correcto — el guard de admin/líder está DENTRO, que es la lección de la 0090.
-- Un revoke sin guard se deshace solo la próxima vez que alguien conceda en
-- masa; un guard dentro de la función no.

insert into migraciones_aplicadas (numero, nombre)
values (97, 'lo_que_cuesta_el_equipo')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
