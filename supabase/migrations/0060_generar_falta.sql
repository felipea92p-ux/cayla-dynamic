-- ============================================================================
-- 0060_generar_falta.sql — El CEREBRO: autodetección de sanción por FALTA
-- ============================================================================
-- PROMETE: dado p_persona_id, decide qué nivel corresponde por inasistencias
--   injustificadas (RIT art. 8 v3.1 / art. 25-h LPCL) y crea el borrador.
-- ASUME: 0056/0058 (legajo + crear_borrador), la lógica de detección de faltas.
--
-- DOS conteos, distinción legal fina:
--   · Umbrales del art. 25-h (abandono 4 consec / 6 en 30d / 16 en 180d) → sobre
--     TODAS las faltas del histórico de 180 días, "hayan sido o no sancionadas"
--     (art. 25-h literal). Si cruza → imputación directa.
--   · Escalación (1ª → amonestación; reincidencia → sube un nivel) → solo sobre
--     faltas NUEVAS posteriores a la última sanción firmada (non bis in idem).
-- El despido (tras imputación) NO se autogenera: va tras evaluar descargos.

-- ── Helper: contadores de falta de UNA persona desde una fecha (sin filtro rol) ─
-- Reusa la misma cascada turno→horario y exclusiones ya validadas de fn_faltas.
create or replace function fn_falta_contadores(p_persona_id uuid, p_desde date)
returns table(consecutivas int, en_30 int, en_180 int, fechas date[])
language sql stable security definer set search_path = public as $$
  with rango as (
    select greatest(p_desde, coalesce((select fecha_ingreso from personas where id = p_persona_id), date '2026-01-01'), date '2026-01-01') as ini,
           current_date - 1 as fin
  ),
  dias as (
    select gs::date as fecha
    from generate_series((select ini from rango), (select fin from rango), interval '1 day') gs
  ),
  ev as (
    select d.fecha, (t.persona_id is not null) as hay_turno, coalesce(t.es_descanso, false) as turno_desc,
           tr.horario_por_dia as hpd, tr.dias_laborables as dl
    from dias d
    left join turnos t on t.persona_id = p_persona_id and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables from horarios_asignados h
      where h.persona_id = p_persona_id and h.vigente_desde <= d.fecha and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  sched as (
    select ev.fecha,
      case
        when exists (select 1 from jornadas j where j.persona_id = p_persona_id and j.fecha = ev.fecha and j.entrada_ts is not null) then 'presente'
        when exists (select 1 from vacaciones v where v.persona_id = p_persona_id and ev.fecha between v.fecha_inicio and v.fecha_fin)
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = p_persona_id and ju.fecha = ev.fecha) then 'just'
        else 'falta'
      end as estado
    from ev
    where (case when ev.hay_turno then not ev.turno_desc
                when ev.hpd is not null then (ev.hpd ? (extract(dow from ev.fecha)::int::text))
                when ev.dl is not null then (extract(dow from ev.fecha)::int = any(ev.dl))
                else false end)
      and not (exists (select 1 from feriados f where f.fecha = ev.fecha) and not ev.hay_turno)
  ),
  fd as (select fecha from sched where estado = 'falta'),
  c30 as (select coalesce(max(cnt),0) as n from (
    select a.fecha, count(*) as cnt from fd a join fd b on b.fecha between a.fecha - 29 and a.fecha group by a.fecha) w),
  rn as (select estado, row_number() over (order by fecha desc) as rk from sched)
  select
    (coalesce((select min(rk) from rn where estado <> 'falta'), (select coalesce(max(rk),0) from rn) + 1) - 1)::int,
    (select n from c30)::int,
    (select count(*) from fd)::int,
    (select array_agg(fecha order by fecha) from fd);
$$;

-- ── El generador de faltas ───────────────────────────────────────────────────
create or replace function fn_expediente_generar_falta(p_persona_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
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
  select * into v_full from fn_falta_contadores(p_persona_id, current_date - 180);

  if coalesce(v_full.consecutivas,0) >= 4 or coalesce(v_full.en_30,0) >= 6 or coalesce(v_full.en_180,0) >= 16 then
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
    case when v_nivel = 'suspension' then current_date + 1 else null end,
    case when v_nivel = 'suspension' then current_date + 1 else null end,
    null);
  return v_id;
end;
$$;

grant execute on function fn_falta_contadores(uuid, date) to authenticated;
grant execute on function fn_expediente_generar_falta(uuid) to authenticated;
