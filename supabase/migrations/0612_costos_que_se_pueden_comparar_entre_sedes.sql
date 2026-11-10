-- ============================================================================
-- 0612 — Costos que se pueden comparar entre sedes
-- ============================================================================
--
-- QUÉ PROMETE
--   Que «por persona» y «por hora» de `fn_costos_planilla` —en cada sede
--   (`por_sede`) y en cada tipo de sede (`por_tipo`)— digan lo que cuesta una
--   persona y una hora de trabajo, y no cuánto rota la sede ni cuánta gente suya
--   no marca. Tres cambios:
--     · `personas_periodo` (nueva): cada persona cuenta una vez por cada periodo
--       en que cobró. Cuatro periodos de una misma integrante son cuatro; una
--       plaza que en esos cuatro periodos ocuparon tres personas, una tras otra,
--       también son cuatro. Con el divisor de siempre, la primera plaza contaba
--       como una persona y la segunda como tres.
--     · `costo_por_persona_periodo` (nueva): el costo real dividido entre eso. Es
--       lo que la pantalla Costos muestra como «Por persona al mes».
--     · `costo_por_hora` (CAMBIA): el costo de quien marcó horas dividido entre
--       esas horas. Lo que costó quien no marcó ninguna sale aparte, en
--       `costo_sin_horas` (nueva), para que no desaparezca de la vista.
--   `costo_por_persona` sigue saliendo igual que antes (ver «POR QUÉ ASÍ»). Los
--   totales, los periodos, las áreas y las personas no cambian.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
--   Felipe, en el SQL Editor de producción, el 2026-11-10, sobre lo pagado en
--   2026 (4 periodos):
--
--     Tienda TRU   28 personas en el año, 62 personas-periodo, 8 en preselección
--     Tienda AQP   12 personas en el año, 22 personas-periodo, 5 en preselección
--     Central       5 personas en el año, 19 personas-periodo, ninguna;
--                  el 39 % de su costo es de quien no marca horas
--
--   POR PERSONA. `costo_por_persona` divide el costo del AÑO entre las personas
--   DISTINTAS que cobraron en él. Con rotación, el divisor crece sin que crezca
--   el costo: cada persona en preselección que se fue a las semanas suma una
--   persona entera al año. Así, Central costaba 2.25 veces lo que TRU por
--   persona y AQP un 33 % menos que TRU. Por persona y por periodo, Central
--   cuesta 1.31 veces lo que TRU y AQP un 19 % menos. La diferencia no es gasto:
--   es rotación.
--
--   POR HORA. `costo_por_hora` sumaba el costo de TODOS y lo dividía entre las
--   horas de quienes marcan. El sueldo de quien no marca entraba arriba sin sus
--   horas abajo. Central salía a 1.67 veces la hora de TRU; contando solo a quien
--   marcó, prácticamente igual (1.01 veces). Las otras cuatro sedes no tenían
--   un sol sin horas, así que ahí no cambia nada.
--
--   Y la pantalla pedía exactamente esto: «Compara por persona y por hora, no
--   por el total».
--
-- ── QUÉ ASUME ───────────────────────────────────────────────────────────────
--   · Que la 0608 está pegada: la función de partida es la de la 0323
--     (a25fbbc2 · 6973). El 2026-11-10 producción todavía tenía la de la 0099
--     (2e960fc4 · 5603), con la 0608 ya fusionada. Con cualquier otra, PARA y no
--     aplica nada.
--   · Que un periodo de CAYLA es un mes de pago (del 29 al 28). Por eso la
--     pantalla dice «al mes» y la columna dice «periodo».
--   · Que `horas_mes` de la foto son las horas marcadas: cero quiere decir que
--     esa persona no marcó en ese periodo, no que no trabajó.
--
-- ── POR QUÉ ASÍ, Y NO DE OTRA FORMA ─────────────────────────────────────────
--   · Cifras NUEVAS para «por persona» y no cambiar el significado de
--     `costo_por_persona`. La migración se pega antes de fusionar el PR: en ese
--     rato la pantalla publicada sigue leyendo `costo_por_persona`, y le habría
--     puesto la cifra nueva debajo del rótulo viejo. Además la prueba 100 fija lo
--     que esa cifra significa. Se deja de dibujar; borrarla del todo es para la
--     próxima vez que alguien reescriba esta función.
--   · Para «por hora», al revés: se corrige la MISMA cifra. El rótulo no cambia
--     («Por hora») y lo que cambia es que deja de estar inflada; la pantalla
--     publicada muestra la cifra buena desde el momento en que se pega.
--   · Personas-periodo y no «plantilla promedio» (personas-periodo ÷ periodos).
--     La plantilla promedio da el costo anual por plaza: es esta misma cifra por
--     el número de periodos, así que no dice nada nuevo, y en un año a medias
--     «anual» engaña.
--   · Y no «personas equivalentes a tiempo completo» (horas ÷ jornada). Dividir
--     el costo entre eso es el costo por hora multiplicado por una constante:
--     ya está en la columna de al lado.
--   · `count(distinct (persona, periodo))` y no `count(*)`: quien pasa de
--     preselección a planilla a mitad de mes tiene DOS filas en ese periodo (una
--     por grupo, 0323), y es una sola persona ese mes.
--   · Para quien no marca, sacar su costo de la hora y no INVENTARLE horas con su
--     jornada pactada. Imputarlas daría una hora más «completa», pero con horas
--     que nadie registró; y su costo no se pierde: va en `costo_sin_horas`.
--
-- ── SE ROMPE SI ─────────────────────────────────────────────────────────────
--   · Una sede contrata en preselección por pocos días y muchas veces: cada
--     estadía corta cuenta como un periodo entero y «por persona» vuelve a bajar,
--     menos que antes pero baja. Es el caso de Oficina TRU (11 personas en el año,
--     6 en preselección, 16 personas-periodo en 2 periodos). Si eso pesa, el paso
--     siguiente es ponderar cada fila por la parte del periodo que trabajó.
--   · Alguien pasa un periodo ENTERO de vacaciones o con descanso médico: cobra
--     sin marcar, y su costo de ese periodo sale de «por hora» y va a «sin
--     horas». Medido: en 2026 eso no le pasó a nadie fuera de Central.
--
-- ── OTRA RAMA REESCRIBE ESTA FUNCIÓN ────────────────────────────────────────
--   La 0609 (rama claude/graficos-audit-resize, sin subir al 2026-11-10) agrega
--   los conceptos de cada periodo y también parte de la 0608. Si se pega esta
--   primero, el freno de la 0609 la para —bien—, y hay que rehacerla sobre esta.
--
-- ── CÓMO SE COMPRUEBA ───────────────────────────────────────────────────────
--   La consulta del final tiene que decir `al_dia = true` y el registro
--   `612 · costos_que_se_pueden_comparar_entre_sedes`. En Costos, «Por persona
--   al mes» deja de decir «—», y «Por hora» de Central baja hasta parecerse a la
--   de las tiendas, con una nota debajo que dice cuánto costó quien no marca.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Repegar la 0608. «Por persona al mes» vuelve a «—», «Por hora» vuelve a la
--   cifra inflada y la nota desaparece. Nada más cambia.
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
  if v_md5 = '2e960fc4db713c4fc4dad10f6c42a67b' then
    raise exception '0612 · PARA. fn_costos_planilla todavía es la de la 0099: pega antes la 0608. No se aplicó nada.';
  end if;
  if v_md5 is distinct from 'a25fbbc2a67dcc6b07f1cb2a8647c124'       -- la de la 0608 (= 0323): de la que parte esta
     and v_md5 is distinct from '1c34f5f88edaedb62cd99e2f49ed3ff2' then -- esta misma: repegarla no cambia nada
    raise exception '0612 · PARA. fn_costos_planilla en esta base es % (% caracteres), se esperaba la de la 0608 (a25fbbc2 · 6973). No se aplicó nada.', v_md5, v_len;
  end if;
end
$guardia$;

-- ── 1 · La función de la 0608, con las personas-periodo y la hora de quien marca
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
  'Costos de planilla en un rango. Cuenta una fila en cuanto SU grupo (tipo_vinculo) está pagado — 0323. Por sede y por tipo, el costo por persona-periodo no baja con la rotación y el costo por hora solo cuenta a quien marcó horas — 0612.';

-- ── 2 · Registro ────────────────────────────────────────────────────────────
insert into migraciones_aplicadas (numero, nombre) values (612, 'costos_que_se_pueden_comparar_entre_sedes')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── 3 · Comprobación ────────────────────────────────────────────────────────
select md5(p.prosrc) = '1c34f5f88edaedb62cd99e2f49ed3ff2' as al_dia,
       md5(p.prosrc) as md5, length(p.prosrc) as largo,
       (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 612) as registro
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'fn_costos_planilla';
