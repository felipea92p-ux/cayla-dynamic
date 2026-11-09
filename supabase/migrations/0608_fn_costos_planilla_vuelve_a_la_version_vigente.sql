-- ============================================================================
-- 0608 — fn_costos_planilla vuelve a la versión vigente
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_costos_planilla` de producción sea la del repositorio: la de la
--   0323, que ya trae lo de la 0260. No escribe ni una línea nueva: el cuerpo
--   de abajo es el de la 0323 copiado byte por byte.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
--   Felipe, en el SQL Editor de producción, el 2026-11-09:
--
--     fn_costos_planilla   2e960fc4db713c4fc4dad10f6c42a67b · 5603
--
--   Ese md5 es, carácter por carácter, el de la 0099 (una_tienda_no_es_una_
--   oficina). Producción tiene la función DOS versiones atrás, aunque la 0260
--   y la 0323 figuran las dos en `migraciones_aplicadas`. Las otras siete
--   funciones que tocó la 0323 —las que congelan, marcan pagado, revierten y
--   repagan— coinciden exacto con el repositorio: lo que se quedó atrás es
--   solo este reporte, no el pago.
--
--   No se sabe cómo pasó. La 0323 tenía un freno que la paraba entera si esta
--   función no era la de la 0260, así que o se pegó por partes sin ese bloque,
--   o algo volvió a pegar la 0099 después.
--
-- ── QUÉ CAMBIA EN PANTALLA AL PEGARLA ──────────────────────────────────────
--
--   En Costos y en el «Costo de planilla» de Inicio → Tendencias:
--     1. Aparece «Salió del banco» (0260): lo transferido más la pensión, el
--        EsSalud y la retención de 4ta que CAYLA paga por cada persona.
--     2. Un periodo cuenta en cuanto SU grupo se paga (0323). Hasta hoy, un
--        periodo con planilla pagada y RxH pendiente no aparecía en ninguna
--        de las dos pantallas hasta que se pagaran los dos.
--   «Se transfirió» y «Costo real» de los periodos ya pagados enteros no se
--   mueven: la 0323 lo comprobó así, y la prueba 258 lo vigila.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--   · Que producción tiene la de la 0099 (2e960fc4 · 5603), o ya la de la 0323
--     (a25fbbc2 · 6973; repegar no cambia nada). Con cualquier otra, PARA y no
--     aplica nada: sería una versión que nadie midió.
--   · Que lo demás de la 0323 está pegado: `periodo_grupo_pago` y la columna
--     `grupo` de `v_planilla_pagada`. El bloque 0 lo comprueba.
--
-- ── CÓMO SE COMPRUEBA ───────────────────────────────────────────────────────
--   Antes de pegarla, mira Costos (el último periodo pagado y el total). Pégala.
--   La consulta del final tiene que decir `al_dia = true`. Recarga Costos: tiene
--   que aparecer «Salió del banco», y los periodos pagados enteros tienen que
--   decir lo mismo que antes.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Repegar el cuerpo de la 0099. No tiene sentido salvo que esta rompa algo:
--   es volver a perder dos migraciones ya aprobadas.
-- ============================================================================

-- ── 0 · Comprobar ANTES de tocar nada ───────────────────────────────────────
do $guardia$
declare
  v_md5 text;
  v_len int;
begin
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_costos_planilla';
  if v_md5 is distinct from '2e960fc4db713c4fc4dad10f6c42a67b'      -- la de la 0099: lo que había en producción
     and v_md5 is distinct from 'a25fbbc2a67dcc6b07f1cb2a8647c124' then  -- la de la 0323: ya al día
    raise exception '0608 · PARA. fn_costos_planilla en esta base es % (% caracteres): ni la de la 0099 (2e960fc4 · 5603) ni la de la 0323 (a25fbbc2 · 6973). No se aplicó nada.', v_md5, v_len;
  end if;
  if to_regclass('public.periodo_grupo_pago') is null then
    raise exception '0608 · PARA. Falta la tabla periodo_grupo_pago (0323). No se aplicó nada.';
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'v_planilla_pagada' and column_name = 'grupo') then
    raise exception '0608 · PARA. v_planilla_pagada no tiene la columna grupo (0323). No se aplicó nada.';
  end if;
end
$guardia$;

-- ── 1 · La función de la 0323, tal cual ─────────────────────────────────────
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
      coalesce(se.nombre, f.sede_codigo) as sede_nombre,
      coalesce((f.fila->>'descuento_afp')::numeric, 0)  as pension_remitida,
      coalesce((f.fila->>'aporte_essalud')::numeric, 0) as essalud_empresa,
      coalesce((f.fila->>'retencion_4ta')::numeric, 0)  as retencion_remitida
    from v_planilla_pagada f
    join periodos_planilla pp on pp.id = f.periodo_id
    left join sedes se on se.codigo = f.sede_codigo
    where pp.fecha_fin between p_desde and p_hasta
      -- CAMBIO 0323 · antes: pp.estado = 'pagado' (el periodo entero de una
      -- sola vez). Ahora, el grupo de ESTA fila tiene que estar pagado —
      -- planilla entra en cuanto se paga, sin esperar a que RxH también lo
      -- esté. COMPATIBILIDAD: un periodo sin ninguna fila en
      -- periodo_grupo_pago (de antes de esta migración) sigue el criterio
      -- viejo — pp.estado = 'pagado' a secas — porque ahí nunca hubo grupos
      -- que distinguir.
      and (
        exists (
          select 1 from periodo_grupo_pago g
           where g.periodo_id = f.periodo_id
             and g.grupo = f.grupo
             and g.estado = 'pagado'
        )
        or (
          pp.estado = 'pagado'
          and not exists (select 1 from periodo_grupo_pago g2 where g2.periodo_id = f.periodo_id)
        )
      )
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
        'costo',       coalesce(round(sum(costo_total), 2), 0),
        'salio_del_banco', coalesce(round(sum(total + pension_remitida + essalud_empresa + retencion_remitida), 2), 0)
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
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)
        ) as x
        from base b
        group by b.periodo_id, b.fecha_ini, b.fecha_fin, b.anio, b.mes
      ) s
    ),

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
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2),
          'costo_por_persona', round(sum(b.costo_total) / nullif(count(distinct b.persona_id), 0), 2),
          'costo_por_hora',    round(sum(b.costo_total) / nullif(sum(b.horas_mes), 0), 2)
        ) as x
        from base b
        group by b.sede_codigo, b.sede_nombre, b.sede_tipo
      ) s
    ),

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
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2),
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
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)
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
          'costo',       round(sum(b.costo_total), 2),
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2)
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
  'Costos de planilla en un rango. Cuenta una fila en cuanto SU grupo (tipo_vinculo) está pagado — 0323, antes esperaba a que TODO el periodo lo estuviera. Repuesta por la 0608: en producción había quedado la de la 0099.';

-- ── 2 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (608, 'fn_costos_planilla_vuelve_a_la_version_vigente')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── 3 · Comprobación ────────────────────────────────────────────────────────
select md5(p.prosrc) = 'a25fbbc2a67dcc6b07f1cb2a8647c124' as al_dia,
       md5(p.prosrc) as md5, length(p.prosrc) as largo,
       (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 608) as registro
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_costos_planilla';
