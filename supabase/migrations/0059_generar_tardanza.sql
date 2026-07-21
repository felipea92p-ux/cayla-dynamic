-- ============================================================================
-- 0059_generar_tardanza.sql — El CEREBRO: autodetección de sanción por tardanza
-- ============================================================================
-- PROMETE: dado p_persona_id, decide qué nivel de sanción por tardanza corresponde
--   HOY según el RIT art. 7 y el historial del legajo, arma los hechos desde
--   Dynamic y crea el borrador. Si no corresponde nada, lo dice y no crea.
-- ASUME: 0056 (legajo), 0058 (crear_borrador), jornadas.minutos_tarde, 0053.
--
-- NON BIS IN IDEM (el candado clave): solo cuenta tardanzas POSTERIORES al
--   periodo_hasta del último documento de tardanza FIRMADO. Nunca recuenta una
--   tardanza ya sancionada. Sin esto, la suspensión se fundaría en tardanzas que
--   ya motivaron la amonestación → sanción nula.
--
-- Escala (RIT art. 7): sin antecedente vigente y 3+ en el mes → amonestación (b);
--   con amonestación vigente y 2+ nuevas → suspensión (c); con suspensión vigente
--   y 1+ nueva → imputación (d). "Vigente" = firmado hace ≤ 12 meses (art. 14.4).
--   El despido (tras imputación) NO se autogenera: va tras evaluar descargos.
--
-- El de FALTAS (art. 8 / 25-h) va en 0060, con el mismo patrón.

create or replace function fn_expediente_generar_tardanza(p_persona_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_prev      record;
  v_has_prev  boolean := false;
  v_vigente   boolean := false;
  v_cutoff    date := date '2000-01-01';
  v_nivel     text;
  v_n         int;
  v_hechos    jsonb;
  v_desde     date;
  v_hasta     date;
  v_id        uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- último documento de tardanza firmado (o entregado)
  select id, nivel, periodo_hasta, firmado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado in ('firmado','entregado')
  order by firmado_at desc limit 1;
  v_has_prev := found;

  if v_has_prev then
    v_vigente := v_prev.firmado_at >= now() - interval '12 months';
    if v_vigente and v_prev.periodo_hasta is not null then v_cutoff := v_prev.periodo_hasta; end if;
  end if;

  -- tardanzas del MES en curso, POSTERIORES al cutoff, no levantadas (non bis in idem)
  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha >= greatest(date_trunc('month', current_date)::date, v_cutoff + 1)
      and j.fecha <= current_date
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  -- decidir el nivel según el historial (RIT art. 7 b/c/d)
  if v_vigente and v_prev.nivel = 'imputacion' then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  elsif v_vigente and v_prev.nivel = 'suspension' then
    if v_n < 1 then raise exception 'No corresponde: no hay tardanzas nuevas tras la suspensión.'; end if;
    v_nivel := 'imputacion';                                    -- umbral d
  elsif v_vigente and v_prev.nivel = 'amonestacion' then
    if v_n < 2 then raise exception 'Aún no corresponde suspensión: necesita 2 tardanzas nuevas tras la amonestación (lleva %).', v_n; end if;
    v_nivel := 'suspension';                                    -- umbral c
  else
    if v_n < 3 then raise exception 'Aún no corresponde amonestación: necesita 3 tardanzas en el mes (lleva %).', v_n; end if;
    v_nivel := 'amonestacion';                                  -- umbral b
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_nivel, v_hechos, v_desde, v_hasta,
    case when v_has_prev then v_prev.id else null end,
    -- suspensión: default 1 día al día siguiente, EDITABLE antes de firmar
    case when v_nivel = 'suspension' then 1 else null end,
    case when v_nivel = 'suspension' then current_date + 1 else null end,
    case when v_nivel = 'suspension' then current_date + 1 else null end,
    null);

  return v_id;
end;
$$;

-- ── Ajustar un borrador antes de firmarlo (días de suspensión, hechos, nota) ──
create or replace function fn_expediente_editar_borrador(
  p_id uuid,
  p_suspension_dias int default null, p_suspension_desde date default null, p_suspension_hasta date default null,
  p_observacion text default null, p_hechos jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare r expediente_disciplinario%rowtype;
begin
  select * into r from expediente_disciplinario where id = p_id;
  if not found then raise exception 'El documento no existe.'; end if;
  if r.estado <> 'borrador' then raise exception 'Solo se puede editar un borrador (estado actual: %).', r.estado; end if;
  if not fn_expediente_puede_actuar(r.persona_id, r.nivel) then raise exception 'Sin permiso.'; end if;
  update expediente_disciplinario set
    suspension_dias  = coalesce(p_suspension_dias, suspension_dias),
    suspension_desde = coalesce(p_suspension_desde, suspension_desde),
    suspension_hasta = coalesce(p_suspension_hasta, suspension_hasta),
    observacion      = coalesce(p_observacion, observacion),
    hechos           = coalesce(p_hechos, hechos)
  where id = p_id;
end;
$$;

grant execute on function fn_expediente_generar_tardanza(uuid) to authenticated;
grant execute on function fn_expediente_editar_borrador(uuid,int,date,date,text,jsonb) to authenticated;
