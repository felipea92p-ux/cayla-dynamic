-- ============================================================================
-- 0094 — El memo no acusa por días que el propio sistema da por justificados
-- ----------------------------------------------------------------------------
-- PROMETE: que el documento disciplinario que se imprime y se ENTREGA use la
--   misma definición de «falta» que la pantalla que lo anuncia.
--
-- ASUME: 0070 (el descanso sustitutorio no es inasistencia), 0079 (los días de
--   suspensión tampoco) y la 0093.
--
-- EL DEFECTO. «Qué es una falta» está escrito DOS veces en el sistema:
--   · fn_faltas / fn_faltas_resumen — el detalle y el semáforo de la pantalla.
--   · fn_falta_contadores — lo que fn_expediente_generar_falta usa para armar
--     los hechos del documento.
--
--   La 0070 y la 0079 corrigieron las dos primeras y ninguna tocó la tercera.
--   Resultado: la pantalla dice «justificado — suspensión» y el papel que se
--   imprime lista ese mismo día como inasistencia injustificada.
--
--   Es exactamente lo que el encabezado de la 0079 se propuso impedir —«la
--   sanción que ya se cumplió se convierte en la prueba para la siguiente»—
--   sobreviviendo justo donde más daño hace: en el documento que recibe la
--   persona y que puede acabar sosteniendo un despido.
--
-- LA CAUSA DE FONDO, que esta migración NO resuelve: mientras «falta» se defina
--   en dos sitios, la próxima corrección volverá a arreglar uno solo. Lo que
--   corresponde es que fn_expediente_generar_falta consuma la misma definición
--   que el semáforo y que fn_falta_contadores desaparezca. Queda anotado en
--   docs/hallazgos-abiertos.md; aquí se cierra el agujero que ya está entregando
--   papeles equivocados.
--
-- CÓMO SE REVIERTE: restaurar la función desde la 0091.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_falta_contadores(p_persona_id uuid, p_desde date)
 RETURNS TABLE(consecutivas integer, en_30 integer, en_180 integer, fechas date[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with rango as (
    select greatest(p_desde, coalesce((select fecha_ingreso from personas where id = p_persona_id), date '2026-01-01'), date '2026-01-01') as ini,
           fn_hoy_lima() - 1 as fin
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
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = p_persona_id and ju.fecha = ev.fecha)
          -- Las dos ramas que le faltaban, y que fn_faltas sí tiene desde la 0070
          -- y la 0079. Sin ellas, el memo que se imprime y se ENTREGA listaba
          -- como inasistencia injustificada un día de suspensión ya cumplida o
          -- un día de descanso sustitutorio pactado — mientras la pantalla decía
          -- lo contrario. La sanción cumplida se convertía en la prueba para la
          -- siguiente, que es justo lo que la 0079 vino a impedir.
          or fn_dia_suspendido(p_persona_id, ev.fecha)
          or exists (select 1 from feriados_descanso_sustitutorio d
                      where d.persona_id = p_persona_id
                        and d.fecha_descanso_sustitutorio = ev.fecha
                        and d.estado in ('PENDIENTE','OTORGADO')) then 'just'
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
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (94, 'el_memo_no_acusa_por_dias_ya_justificados')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
