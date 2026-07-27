-- ============================================================================
-- 0092 — Una falta no se sanciona dos veces, tampoco por el art. 25-h
-- ----------------------------------------------------------------------------
-- PROMETE: que ningún documento disciplinario reproche hechos que ya fueron
--   reprochados en un documento anterior.
--
-- ASUME: 0060 (fn_expediente_generar_falta), 0070 y 0079 (las dos correcciones
--   anteriores de non bis in idem) y la 0091.
--
-- EL DEFECTO. fn_expediente_generar_falta tiene dos caminos:
--
--   · ESCALACIÓN (amonestación → suspensión → imputación), que mira solo las
--     faltas NUEVAS —posteriores al documento anterior— y comprueba antes si ya
--     hay una imputación vigente.
--   · ART. 25-h, que se dispara al superar los umbrales legales (4 consecutivas,
--     6 en 30 días, 16 en 180) y mira TODO el histórico de 180 días «hayan sido
--     o no sancionadas».
--
--   El candado de «ya hay una imputación vigente» vivía dentro del `else`, o sea
--   solo en la rama de escalación. La del art. 25-h no lo veía nunca, y tampoco
--   comprobaba si esos hechos ya estaban cubiertos.
--
--   Consecuencia: una vez superado el umbral, cada pulsación de «Generar
--   borrador» producía otra imputación idéntica sobre exactamente las mismas
--   faltas. Y seguía funcionando indefinidamente, porque esas faltas continúan
--   dentro de la ventana de 180 días. El único freno era el chequeo de borrador
--   pendiente, que se levanta en cuanto se firma el anterior.
--
--   Sobre una persona real eso son dos, tres o diez cartas de preaviso de
--   despido por los mismos hechos. El D.S. 003-97-TR exige reiteración y
--   progresión documentada; repetir el mismo reproche no es ninguna de las dos.
--
-- QUÉ SE AÑADE, dentro de la rama del art. 25-h:
--   1. Que exista al menos una falta POSTERIOR a lo que cubrió el documento
--      anterior. Mirar el histórico completo para probar el umbral es legítimo;
--      volver a imputar el mismo hecho, no.
--   2. El mismo candado de imputación vigente que ya tenía la otra rama.
--
-- NO CAMBIA el caso legítimo: con una falta nueva y el umbral superado, el
--   documento se genera igual que antes.
--
-- CÓMO SE REVIERTE: restaurar la función desde la 0091.
-- ============================================================================

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

  select id, nivel, periodo_hasta, firmado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'falta' and estado in ('firmado','entregado')
  order by firmado_at desc limit 1;
  v_has_prev := found;
  if v_has_prev then
    v_vigente := v_prev.firmado_at >= now() - interval '12 months';
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

insert into migraciones_aplicadas (numero, nombre)
values (92, 'una_falta_no_se_sanciona_dos_veces')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
