-- ============================================================================
-- 0213_solo_agrava_lo_que_se_entrego.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que un documento disciplinario solo cuente como antecedente desde que se
--   ENTREGÓ, y no desde que la Empresa lo firmó. Es lo que dice el artículo 56
--   del Reglamento, y hoy el sistema hace otra cosa.
--
-- QUÉ ASUME
--   Nada nuevo. Reescribe dos funciones sobre su cuerpo vigente, extraído de la
--   base con pg_get_functiondef. No toca tablas ni datos.
--
-- ── EL PROBLEMA, MEDIDO ─────────────────────────────────────────────────────
--
-- El artículo 56 del Reglamento v4.0 es explícito en los dos sentidos:
--
--     56.1  «Un antecedente disciplinario produce efecto agravante durante los
--            doce (12) meses siguientes a la fecha en que fue ENTREGADO … Ni la
--            fecha de emisión, ni la de creación del borrador, ni la de firma
--            por la Empresa inician ese plazo.»
--
--     56.2  «Un documento firmado por la Empresa y no entregado no está
--            vigente, no agrava, no habilita el escalón siguiente y no
--            constituye sanción disciplinaria previa para los efectos del
--            literal h) del artículo 25 de la LPCL.»
--
-- El sistema, hasta hoy, medía los doce meses desde `firmado_at` y aceptaba
-- como antecedente cualquier documento en estado `firmado` O `entregado`. Dos
-- consecuencias, y las dos caen del mismo lado —el que perjudica a la persona:
--
--   · Un memo firmado y guardado en un cajón empujaba a alguien al escalón
--     siguiente. La pantalla de Disciplina tiene una sección entera llamada
--     «Firmados — por entregar», así que el caso no es teórico.
--   · El plazo de doce meses empezaba a correr antes de tiempo. Entre firmar y
--     entregar pueden pasar semanas, y en ese tramo el antecedente ya agravaba
--     sin que la persona supiera siquiera que existía.
--
-- Y es justo lo que el inciso h) del art. 25 de la LPCL exige que se pueda
-- probar: que las sanciones previas se APLICARON. Una que no se notificó no se
-- aplicó, por muy firmada que esté.
--
-- ── DÓNDE ESTABA, Y POR QUÉ SOLO SON DOS SITIOS ─────────────────────────────
--
-- La 0200 centralizó la escalera de tardanzas en `fn_tardanza_escalon`, así que
-- `fn_expediente_generar_tardanza` y `fn_tardanzas_resumen` ya no deciden la
-- vigencia por su cuenta: la preguntan. Sin ese trabajo previo esta migración
-- habría tenido que tocar cuatro funciones en vez de dos, y cada una es una
-- ocasión de equivocarse.
--
--   fn_tardanza_escalon         la vigencia de las tardanzas
--   fn_expediente_generar_falta la de las inasistencias
--
-- ── QUÉ NO HACE ─────────────────────────────────────────────────────────────
--
-- No toca los documentos existentes. Los que estén firmados y sin entregar
-- simplemente dejan de agravar hasta que se entreguen — que es lo correcto y lo
-- que el Reglamento manda. Si alguno llevaba semanas contando, deja de contar.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Reponiendo los cuerpos anteriores. Revertir significa volver a agravar con
--   documentos que nadie recibió.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final. Las cuatro columnas tienen que decir SÍ.
-- ============================================================================

-- ── 1 · La escalera de tardanzas ───────────────────────────────────────────
-- md5 de partida: 4fa1ce620779c44402090cc87779abe4
-- Si en producción no coincide, PARAR: otra migración la tocó y pegar esta
-- revertiría su trabajo en silencio.
CREATE OR REPLACE FUNCTION public.fn_tardanza_escalon(p_persona_id uuid)
 RETURNS TABLE(nivel_siguiente text, minimo integer, corte date, doc_previo uuid, bloqueado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with prev as (
    select e.id, e.nivel, e.periodo_hasta, e.resuelto_at,
           (e.entregado_at >= now() - interval '12 months') as vigente
    from expediente_disciplinario e
    where e.persona_id = p_persona_id
      and e.tipo_causal = 'tardanza'
      -- ART. 56 DEL RIT: un documento firmado y NO entregado «no está vigente,
      -- no agrava, no habilita el escalón siguiente y no constituye sanción
      -- disciplinaria previa para los efectos del literal h) del artículo 25 de
      -- la LPCL». Y los doce meses corren desde la ENTREGA, no desde la firma:
      -- «ni la fecha de emisión, ni la de creación del borrador, ni la de firma
      -- por la Empresa inician ese plazo».
      and e.estado = 'entregado'
    order by e.entregado_at desc
    limit 1
  )
  select
    case
      when p.vigente and p.nivel = 'imputacion'   then 'imputacion'
      when p.vigente and p.nivel = 'suspension'   then 'imputacion'
      when p.vigente and p.nivel = 'amonestacion' then 'suspension'
      else 'amonestacion'
    end,
    -- Con una imputación SIN resolver no hay número que valga: decide Gerencia.
    -- Resuelta, la persona sigue arriba de la escalera —de ahí no se baja— así
    -- que un solo hecho nuevo vuelve a corresponder imputación.
    case
      when p.vigente and p.nivel = 'imputacion' and p.resuelto_at is null then null::int
      when p.vigente and p.nivel = 'imputacion'                           then 1
      when p.vigente and p.nivel = 'suspension'                           then 1
      when p.vigente and p.nivel = 'amonestacion'                         then 2
      else 3
    end,
    case when p.vigente then p.periodo_hasta end,
    p.id,
    coalesce(p.vigente and p.nivel = 'imputacion' and p.resuelto_at is null, false)
  from (select 1) _
  left join prev p on true;
$function$;

grant  execute on function fn_tardanza_escalon(uuid) to authenticated;
revoke execute on function fn_tardanza_escalon(uuid) from public, anon;

-- ── 2 · La escalera de inasistencias ───────────────────────────────────────
-- md5 de partida: de232c1bddeb768e2f67f3894db8bd22
CREATE OR REPLACE FUNCTION public.fn_expediente_generar_falta(p_persona_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prev     record; v_has_prev boolean := false; v_vigente boolean := false;
  v_cutoff   date := date '2000-01-01';
  v_full     record; v_new record;
  v_nivel    text; v_hechos jsonb; v_desde date; v_hasta date;
  v_id       uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de falta para esta persona.';
  end if;
  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'falta' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de falta pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- ART. 56 DEL RIT: solo agrava lo ENTREGADO, y los doce meses corren desde
  -- la entrega. Un documento firmado y guardado en un cajón no es antecedente.
  select id, nivel, periodo_hasta, entregado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'falta' and estado = 'entregado'
  order by entregado_at desc limit 1;
  v_has_prev := found;
  if v_has_prev then
    v_vigente := v_prev.entregado_at >= now() - interval '12 months';
    if v_vigente and v_prev.periodo_hasta is not null then v_cutoff := v_prev.periodo_hasta; end if;
  end if;

  -- art. 25-h sobre TODO el histórico (hayan sido o no sancionadas)
  select * into v_full from fn_falta_contadores(p_persona_id, fn_hoy_lima() - 180);

  if coalesce(v_full.consecutivas,0) >= 4 or coalesce(v_full.en_30,0) >= 6 or coalesce(v_full.en_180,0) >= 16 then
    -- NON BIS IN IDEM, también aquí.
    -- La ley deja MIRAR todo el histórico para probar que se alcanzó el umbral,
    -- pero no deja volver a reprochar un hecho ya reprochado. Sin esto, una vez
    -- superado el umbral cada pulsación de "Generar borrador" producía otra
    -- imputación idéntica sobre exactamente las mismas faltas — indefinidamente,
    -- porque esas faltas siguen dentro de la ventana de 180 días. El único freno
    -- era el chequeo de borrador pendiente, que se levanta al firmar el anterior.
    if (select count(*) from unnest(v_full.fechas) as f where f > v_cutoff) = 0 then
      raise exception 'No corresponde: todas esas faltas ya quedaron cubiertas por el documento anterior (hasta el %). Para volver a sancionar hace falta al menos una falta nueva.',
        to_char(v_cutoff, 'DD/MM/YYYY');
    end if;
    -- Y el candado que ya existía, que vivía solo en la rama de escalación y por
    -- eso esta nunca lo veía.
    if v_vigente and v_has_prev and v_prev.nivel = 'imputacion' then
      raise exception 'Ya hay una imputación vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
    end if;
    v_nivel  := 'imputacion';
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_full.fechas) as f);
    v_desde  := (select min(f) from unnest(v_full.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_full.fechas) as f);
  else
    -- escalación sobre faltas NUEVAS (non bis in idem)
    select * into v_new from fn_falta_contadores(p_persona_id, v_cutoff + 1);
    if coalesce(v_new.en_180,0) < 1 then
      raise exception 'No corresponde: sin faltas injustificadas nuevas.';
    end if;
    if v_vigente and v_prev.nivel = 'imputacion' then
      raise exception 'Ya hay una imputación vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
    elsif v_vigente and v_prev.nivel = 'suspension' then
      v_nivel := 'imputacion';                              -- reincidencia sobre suspensión
    elsif v_vigente and v_prev.nivel = 'amonestacion' then
      v_nivel := 'suspension';                              -- reincidencia sobre amonestación
    else
      v_nivel := 'amonestacion';                            -- 1ª falta injustificada
    end if;
    v_hechos := (select jsonb_agg(jsonb_build_object('fecha', f) order by f) from unnest(v_new.fechas) as f);
    v_desde  := (select min(f) from unnest(v_new.fechas) as f);
    v_hasta  := (select max(f) from unnest(v_new.fechas) as f);
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'falta', v_nivel, v_hechos, v_desde, v_hasta,
    case when v_has_prev then v_prev.id else null end,
    case when v_nivel = 'suspension' then 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    null);
  return v_id;
end;
$function$;

grant  execute on function fn_expediente_generar_falta(uuid) to authenticated;
revoke execute on function fn_expediente_generar_falta(uuid) from public, anon;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (213, 'solo_agrava_lo_que_se_entrego')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
select
  -- Ninguna de las dos puede seguir mirando la fecha de firma.
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_tardanza_escalon', 'fn_expediente_generar_falta')
      and p.prosrc like '%firmado_at >= now()%') = 0
    as ya_no_agrava_desde_la_firma,
  -- Y las dos tienen que mirar la de entrega.
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_tardanza_escalon', 'fn_expediente_generar_falta')
      and p.prosrc like '%entregado_at >= now()%') = 2
    as ahora_agrava_desde_la_entrega,
  -- Un documento solo firmado ya no puede entrar como antecedente.
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_tardanza_escalon', 'fn_expediente_generar_falta')
      and p.prosrc like '%estado in (''firmado''%') = 0
    as lo_firmado_sin_entregar_no_cuenta,
  (select bool_and(has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('fn_tardanza_escalon', 'fn_expediente_generar_falta'))
    as el_navegador_las_puede_ejecutar;
