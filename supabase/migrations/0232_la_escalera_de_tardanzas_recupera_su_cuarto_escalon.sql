-- ============================================================================
-- 0232 — La escalera de tardanzas recupera su cuarto escalón
-- ============================================================================
--
-- QUÉ PROMETE
--
-- Que el semáforo de tardanzas proponga los CUATRO escalones del artículo 19.2
-- del Reglamento, y no tres:
--
--   b) amonestación escrita        3 tardanzas en el periodo mensual
--   c) primera suspensión          2 o más, con amonestación vigente     1 a 2 días
--   d) SEGUNDA suspensión          1 o más, con suspensión vigente       2 a 3 días,
--                                                                        y mayor que la primera
--   e) imputación de cargos        1 o más, tras la segunda suspensión
--
-- ── QUÉ ESTABA MAL, Y POR QUÉ CUESTA CARO ───────────────────────────────────
--
-- `fn_tardanza_escalon` saltaba de la primera suspensión directamente a la
-- imputación: `when p.vigente and p.nivel = 'suspension' then 'imputacion'`.
-- El escalón d) no existía.
--
-- El daño no es saltarse un paso. Es que el literal h) del artículo 25 de la
-- LPCL —la causal de despido por impuntualidad reiterada— exige que se hayan
-- aplicado antes «sanciones disciplinarias previas de amonestaciones escritas y
-- SUSPENSIONES», en plural. Con una sola suspensión en el legajo, el expediente
-- de despido por tardanzas NO SE SOSTIENE: el sistema empujaba a Gerencia hacia
-- una imputación que la ley no respalda todavía.
--
-- Y sobre la persona, el efecto es el contrario y también malo: se le propone
-- un procedimiento de despido cuando lo que correspondía era una suspensión de
-- dos o tres días.
--
-- ── LA SEGUNDA SUSPENSIÓN TIENE QUE SER MÁS LARGA, Y NADIE LO SABÍA ─────────
--
-- El numeral 19.2 d) exige que la segunda suspensión sea «de mayor duración que
-- la primera». `fn_expediente_generar_tardanza` creaba TODA suspensión con
-- `suspension_dias = 1`, escrito literal. Una segunda de un día habría
-- incumplido el Reglamento en el propio documento que lo invoca.
--
-- Por eso el escalón ahora devuelve `suspension_previa_dias`: el generador lo
-- lee y propone un día más, dentro del tope de tres del numeral 54.5. Con la
-- primera en 1 → la segunda sale 2; con la primera en 2 → sale 3.
--
-- ── QUÉ NO ENTRA AQUÍ, Y POR QUÉ ────────────────────────────────────────────
--
-- El supuesto ii del literal e): «cinco (5) o más tardanzas en treinta (30) días
-- corridos» con suspensión vigente. Es la ÚNICA ventana móvil del artículo y
-- convive con la mensual de los demás escalones.
--
-- No se implementa acá porque esta función no cuenta tardanzas: recibe una
-- persona y mira su expediente. Contarlas exigiría repetir dentro las
-- exclusiones que ya viven en `fn_tardanzas_resumen` —justificadas, sin medir,
-- sueldo fijo, sin horario—, y dos versiones de qué cuenta como tardanza es
-- exactamente la clase de duplicado que este repositorio prohíbe. Va a su
-- propia migración, con la cuenta hecha donde ya se hace.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
-- Restaurando las dos funciones de la 0213. `fn_tardanza_escalon` devuelve una
-- columna más, así que se recrea con drop + create: Postgres no deja agregar
-- una columna a una función que devuelve TABLE con `create or replace`.
--
-- md5 de partida (pedirlos a PRODUCCIÓN, no al Postgres local):
--   fn_tardanza_escalon            ebc200d14794e865cd80c8a9c5702095  (0213)
--   fn_expediente_generar_tardanza 9b82122a03b9284ef3dda3e5b5278bb8  (0200)
-- ============================================================================

drop function if exists fn_tardanza_escalon(uuid);

create function fn_tardanza_escalon(p_persona_id uuid)
returns table(
  nivel_siguiente        text,
  minimo                 integer,
  corte                  date,
  doc_previo             uuid,
  bloqueado              boolean,
  -- Días de la suspensión vigente más larga. Lo necesita el generador para que
  -- la segunda salga más larga que la primera (numeral 19.2 d).
  suspension_previa_dias integer
)
language sql stable security definer set search_path = public as $$
  with docs as (
    select e.id, e.nivel, e.periodo_hasta, e.resuelto_at, e.entregado_at,
           e.suspension_dias,
           (e.entregado_at >= now() - interval '12 months') as vigente
    from expediente_disciplinario e
    where e.persona_id = p_persona_id
      and e.tipo_causal = 'tardanza'
      -- ART. 56 DEL RIT: un documento firmado y NO entregado «no está vigente,
      -- no agrava, no habilita el escalón siguiente y no constituye sanción
      -- disciplinaria previa para los efectos del literal h) del artículo 25 de
      -- la LPCL». Y los doce meses corren desde la ENTREGA, no desde la firma.
      and e.estado = 'entregado'
  ),
  vig as (select * from docs where vigente),
  cuenta as (
    -- El escalón NO se decide por «cuál fue el último documento», sino por CON
    -- QUÉ CUENTA la persona. Es lo que dice el Reglamento —«cuando la
    -- colaboradora cuenta con una amonestación escrita vigente», «con una
    -- suspensión vigente»— y además no depende de ningún orden: dos documentos
    -- entregados el mismo día dejaban la escalera echándolo a suertes.
    select
      count(*) filter (where nivel = 'imputacion')                      as n_imp,
      count(*) filter (where nivel = 'suspension')                      as n_susp,
      count(*) filter (where nivel = 'amonestacion')                    as n_amon,
      max(suspension_dias) filter (where nivel = 'suspension')          as dias_susp,
      bool_or(nivel = 'imputacion' and resuelto_at is null)             as imp_abierta,
      max(periodo_hasta)                                                as corte
    from vig
  ),
  ultimo as (
    -- Solo para enlazar el documento nuevo con el anterior. El desempate por
    -- `periodo_hasta` e `id` lo hace determinista.
    select id from docs order by entregado_at desc, periodo_hasta desc, id desc limit 1
  )
  select
    case
      when c.n_imp > 0                    then 'imputacion'
      -- Dos suspensiones vigentes son las «suspensiones» en plural que exige el
      -- literal h) del art. 25 de la LPCL. Con una sola, todavía falta la
      -- segunda del numeral 19.2 d).
      when c.n_susp >= 2                  then 'imputacion'
      when c.n_susp = 1                   then 'suspension'
      when c.n_amon > 0                   then 'suspension'
      else                                     'amonestacion'
    end,
    -- Cuántas tardanzas nuevas exige ese escalón (numerales 19.2 b, c, d, e).
    -- Con una imputación SIN resolver no hay número que valga: decide Gerencia.
    case
      when c.imp_abierta                  then null::int
      when c.n_imp > 0                    then 1
      when c.n_susp >= 1                  then 1
      when c.n_amon > 0                   then 2
      else                                     3
    end,
    c.corte,
    (select id from ultimo),
    coalesce(c.imp_abierta, false),
    c.dias_susp::int
  from cuenta c;
$$;

comment on function fn_tardanza_escalon(uuid) is
  'Art. 19.2 del RIT: que escalon toca y cuantas tardanzas exige. Cuatro escalones: amonestacion, primera suspension, segunda suspension e imputacion.';

grant execute on function fn_tardanza_escalon(uuid) to authenticated, service_role;
revoke execute on function fn_tardanza_escalon(uuid) from public;

-- ── El generador, que ahora sabe graduar la segunda ────────────────────────
-- Copiado del cuerpo VIGENTE (0200) y cambiando solo dos cosas: los días de la
-- suspensión y el mensaje que dice cuántas tardanzas faltan. Todo lo demás
-- —el freno de borrador pendiente, `fn_tardanza_es_medible` de la 0189, la
-- ventana del mes calendario— se conserva intacto.
create or replace function fn_expediente_generar_tardanza(p_persona_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_esc       record;
  v_cutoff    date;
  v_n         int;
  v_hechos    jsonb;
  v_desde     date;
  v_hasta     date;
  v_dias      int;
  v_id        uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  select * into v_esc from fn_tardanza_escalon(p_persona_id);

  if v_esc.bloqueado then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  end if;

  v_cutoff := coalesce(v_esc.corte, date '2000-01-01');

  -- tardanzas del MES en curso, POSTERIORES al cutoff, no levantadas (non bis in idem)
  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)
      and j.fecha <= fn_hoy_lima()
      -- `fn_tardanza_es_medible` reemplaza al viejo `is not null`: el papel
      -- disciplinario NUNCA se arma con una medición dudosa.
      and fn_tardanza_es_medible(j.minutos_tarde) and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  -- El número sale del `minimo` del escalón y no escrito a mano: la PRIMERA
  -- suspensión exige dos tardanzas y la SEGUNDA una sola (numerales 19.2 c y d),
  -- y el mensaje fijo pedía siempre dos.
  if v_n < v_esc.minimo then
    raise exception '%', case v_esc.nivel_siguiente
      when 'imputacion' then 'No corresponde: no hay tardanzas nuevas tras la segunda suspensión.'
      when 'suspension' then format('Aún no corresponde suspensión: necesita %s tardanza(s) nueva(s) tras el documento anterior (lleva %s).', v_esc.minimo, v_n)
      else format('Aún no corresponde amonestación: necesita %s tardanzas en el mes (lleva %s).', v_esc.minimo, v_n)
    end;
  end if;

  -- NUMERAL 19.2 d): la segunda suspensión es «de mayor duración que la
  -- primera», dentro del tope de tres días del numeral 54.5. Antes toda
  -- suspensión se creaba con un día escrito literal, así que una segunda habría
  -- incumplido el Reglamento en el documento que lo invoca.
  v_dias := case
    when v_esc.nivel_siguiente <> 'suspension' then null
    when v_esc.suspension_previa_dias is null  then 1
    else greatest(2, least(3, v_esc.suspension_previa_dias + 1))
  end;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_esc.nivel_siguiente, v_hechos, v_desde, v_hasta,
    v_esc.doc_previo,
    -- Días propuestos, EDITABLES antes de firmar. La suspensión arranca al día
    -- siguiente y ocupa tantos días como se propongan.
    v_dias,
    case when v_dias is not null then fn_hoy_lima() + 1 end,
    case when v_dias is not null then fn_hoy_lima() + v_dias end,
    null);

  return v_id;
end;
$$;

grant  execute on function fn_expediente_generar_tardanza(uuid) to authenticated;
revoke execute on function fn_expediente_generar_tardanza(uuid) from public, anon;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (232, 'la_escalera_de_tardanzas_recupera_su_cuarto_escalon')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Las tres deben decir true.
select
  (select prosrc ilike '%c.n_susp >= 2%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_tardanza_escalon')     as hay_cuatro_escalones,
  (select prosrc ilike '%suspension_previa_dias%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_generar_tardanza')
                                                                          as el_generador_lee_los_dias_previos,
  (select prosrc ilike '%greatest(2, least(3%' from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_expediente_generar_tardanza')
                                                                          as la_segunda_sale_mas_larga;
