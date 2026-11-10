-- ============================================================================
-- 0614 — El costo de cada periodo dice de qué está hecho
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_costos_planilla` devuelva, dentro de cada periodo de `por_periodo`,
--   un objeto `conceptos` con el total de cada concepto: sueldo base, descanso
--   semanal trabajado, sobretiempo, feriados, plus, bonos, asignación familiar,
--   movilidad, educación, los descuentos (pensión, retención de 4ta y otros) y
--   las cuatro provisiones. Ninguna otra cifra cambia: todo lo de la 0612 (por
--   persona-periodo, por hora solo de quien marcó, costo sin horas) sigue igual.
--
--   Lo usa el gráfico «En qué se va la planilla» de Inicio → Tendencias, que
--   explica por qué un periodo costó más que el anterior.
--
-- ── POR QUÉ 0614 Y NO 0609 ──────────────────────────────────────────────────
--   Se escribió el 2026-11-09 como 0609, sobre la 0608, y no se pegó. Mientras
--   esperaba, la 0612 reescribió esta misma función y se pegó en producción el
--   2026-11-10. Pegada tal cual, la 0609 habría devuelto la función a la de la
--   0608 y borrado en silencio la 0612 —su guardia lo habría frenado, pero
--   igual había que rehacerla—. Esta es la misma idea sobre el cuerpo de la
--   0612, y va DESPUÉS de ella: con el número 0609, un `db reset` la aplicaría
--   antes que la 0612 y la 0612 la pisaría. El 0609 queda como hueco explicado
--   en scripts/hooks/huecos-conocidos.txt; nunca llegó a producción.
--
-- ── POR QUÉ AQUÍ Y NO EN UNA FUNCIÓN APARTE ─────────────────────────────────
--   · Para que cuadre al sol con el «Costo de planilla» de al lado. Una función
--     aparte tendría que repetir qué filas cuentan (cada grupo en cuanto SU
--     grupo se paga, 0323), y el día que una de las dos cambie, habría dos
--     costos. Aquí los conceptos salen de la misma `base` que `costo`.
--   · Para no bajar sueldos al navegador. Leer `planilla_pagada_detalle` desde
--     la pantalla traería el sueldo de cada persona; esto entrega solo los
--     totales del periodo.
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--   · Que la 0612 está pegada: la función de partida es la suya
--     (1c34f5f8 · 8893), la que devolvió producción el 2026-11-10. Con
--     cualquier otra, PARA y no aplica nada.
--   · Que en cada fila pagada el neto es la suma de los conceptos menos los
--     descuentos. Medido por Felipe en producción el 2026-11-09 sobre las 402
--     filas pagadas: ninguna difiere en más de un centavo, en el neto ni en las
--     provisiones. En local, el neto cuadra exacto; las cuatro provisiones, no
--     siempre: cada una se redondea por su lado y puede diferir en 0.01 de
--     `provision_total`. Por eso el cuadre usa la cifra `provisiones` del
--     periodo, que ya existía, y las cuatro solo la detallan.
--   · Que «costo» sigue siendo lo que la 0097 definió y la 0260 dejó así: lo
--     que recibe la persona más las provisiones. Por eso la pensión aparece
--     restando y el EsSalud de la empresa no aparece. Es una decisión vigente,
--     no un olvido de esta migración.
--
-- ── CÓMO SE COMPRUEBA ───────────────────────────────────────────────────────
--   La consulta del final: `al_dia = true` y `con_conceptos = true`. En Inicio
--   → Tendencias, «En qué se va la planilla» dice el mismo total que «Costo de
--   planilla».
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Repegar la 0612. El gráfico deja de dibujarse y lo dice; nada más cambia.
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
  if v_md5 in ('2e960fc4db713c4fc4dad10f6c42a67b', 'a25fbbc2a67dcc6b07f1cb2a8647c124') then
    raise exception '0614 · PARA. fn_costos_planilla es la de la 0099 o la de la 0608: pega antes la 0612. No se aplicó nada.';
  end if;
  if v_md5 is distinct from '1c34f5f88edaedb62cd99e2f49ed3ff2'       -- la de la 0612: de la que parte esta
     and v_md5 is distinct from 'f499f51db8c698ae8b52324f4333ed7d' then -- esta misma: repegarla no cambia nada
    raise exception '0614 · PARA. fn_costos_planilla en esta base es % (% caracteres), se esperaba la de la 0612 (1c34f5f8 · 8893). No se aplicó nada.', v_md5, v_len;
  end if;
end
$guardia$;

-- ── 1 · La función de la 0612, con los conceptos de cada periodo ────────────
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
          'salio_del_banco', round(sum(b.total + b.pension_remitida + b.essalud_empresa + b.retencion_remitida), 2),
          -- CAMBIO 0614 · De qué está hecho el costo de cada periodo, por concepto. Sale
          -- de la MISMA base que 'costo':
          --   (pago_base + descanso_semanal + sobretiempo + feriados + plus + bonos
          --    + asignacion_familiar + movilidad + educacion)
          --   - (descuentos + pension + retencion_4ta)        = neto (al centavo)
          --   + 'provisiones' de arriba                       = costo (al centavo)
          -- Las cuatro provisiones de abajo DETALLAN 'provisiones' pero no la suman al
          -- centavo: cada una se redondea por su lado (19 de 42 filas locales difieren
          -- en 0.01). Para cuadrar, se usa 'provisiones'.
          -- Solo totales del periodo: nunca el sueldo de una persona.
          'conceptos', jsonb_build_object(
            'pago_base',               round(sum(coalesce(b.pago_base, 0)), 2),
            'descanso_semanal',        round(sum(coalesce(b.monto_descanso_semanal, 0)), 2),
            'sobretiempo',             round(sum(coalesce(b.monto_sobretiempo, 0)), 2),
            'feriados',                round(sum(coalesce(b.monto_feriados, 0)), 2),
            'plus',                    round(sum(coalesce(b.monto_plus, 0)), 2),
            'bonos',                   round(sum(coalesce(b.bonos, 0)), 2),
            'asignacion_familiar',     round(sum(coalesce(b.asignacion_familiar, 0)), 2),
            'movilidad',               round(sum(coalesce(b.monto_movilidad, 0)), 2),
            'educacion',               round(sum(coalesce(b.monto_educacion, 0)), 2),
            'descuentos',              round(sum(coalesce(b.descuentos, 0)), 2),
            'pension',                 round(sum(coalesce(b.descuento_pension, 0)), 2),
            'retencion_4ta',           round(sum(coalesce(b.retencion_4ta, 0)), 2),
            'provision_gratificacion', round(sum(coalesce(b.provision_gratificacion, 0)), 2),
            'provision_cts',           round(sum(coalesce(b.provision_cts, 0)), 2),
            'provision_vacaciones',    round(sum(coalesce(b.provision_vacaciones, 0)), 2),
            'provision_bonif_extraordinaria', round(sum(coalesce(b.provision_bonif_extraordinaria, 0)), 2)
          )
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
          -- CAMBIO 0612 · cada persona cuenta UNA vez por cada periodo en que cobró: una plaza que rotó entre
          -- tres personas pesa lo mismo que una que ocupó una sola. Dos filas de la misma persona en el mismo
          -- periodo (pasó de preselección a planilla a mitad de mes) son una persona-periodo, no dos.
          'personas_periodo',  count(distinct (b.persona_id, b.periodo_id)),
          'costo_por_persona_periodo', round(sum(b.costo_total) / nullif(count(distinct (b.persona_id, b.periodo_id)), 0), 2),
          -- CAMBIO 0612 · antes: sum(costo_total) / sum(horas_mes). El costo de quien no marca entraba arriba y sus
          -- horas no entraban abajo. Ahora la hora se calcula solo con quien marcó, y lo demás sale aparte.
          'costo_por_hora',    round(sum(b.costo_total) filter (where b.horas_mes > 0)
                                     / nullif(sum(b.horas_mes) filter (where b.horas_mes > 0), 0), 2),
          'costo_sin_horas',   round(coalesce(sum(b.costo_total) filter (where b.horas_mes <= 0), 0), 2)
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
          -- CAMBIO 0612 · cada persona cuenta UNA vez por cada periodo en que cobró: una plaza que rotó entre
          -- tres personas pesa lo mismo que una que ocupó una sola. Dos filas de la misma persona en el mismo
          -- periodo (pasó de preselección a planilla a mitad de mes) son una persona-periodo, no dos.
          'personas_periodo',  count(distinct (b.persona_id, b.periodo_id)),
          'costo_por_persona_periodo', round(sum(b.costo_total) / nullif(count(distinct (b.persona_id, b.periodo_id)), 0), 2),
          -- CAMBIO 0612 · antes: sum(costo_total) / sum(horas_mes). El costo de quien no marca entraba arriba y sus
          -- horas no entraban abajo. Ahora la hora se calcula solo con quien marcó, y lo demás sale aparte.
          'costo_por_hora',    round(sum(b.costo_total) filter (where b.horas_mes > 0)
                                     / nullif(sum(b.horas_mes) filter (where b.horas_mes > 0), 0), 2),
          'costo_sin_horas',   round(coalesce(sum(b.costo_total) filter (where b.horas_mes <= 0), 0), 2)
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
  'Costos de planilla en un rango. Cuenta una fila en cuanto SU grupo (tipo_vinculo) está pagado — 0323. Por sede y por tipo, el costo por persona-periodo no baja con la rotación y el costo por hora solo cuenta a quien marcó horas — 0612. Cada periodo trae además el total de cada concepto, que suma su costo al centavo — 0614.';

-- ── 2 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (614, 'el_costo_de_cada_periodo_dice_de_que_esta_hecho')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── 3 · Comprobación ────────────────────────────────────────────────────────
select md5(p.prosrc) = 'f499f51db8c698ae8b52324f4333ed7d' as al_dia,
       position('CAMBIO 0614' in p.prosrc) > 0 as con_conceptos,
       md5(p.prosrc) as md5, length(p.prosrc) as largo,
       (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 614) as registro
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_costos_planilla';
