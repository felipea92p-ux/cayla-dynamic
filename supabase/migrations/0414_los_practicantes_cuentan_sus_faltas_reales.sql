-- ============================================================================
-- 0414 · Un practicante con falta real ya no se ve "sin marca"
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `fn_faltas` cuente la inasistencia real de un practicante
--   (`personas.tipo_vinculo = 'practicante'`) como "falta". Hoy el filtro
--   `en_planilla = true` lo deja afuera del todo, y como esta función
--   alimenta /admin/horas (la cuadrícula de Desempeño) y el aviso de
--   /admin/incidencias, ese día se pinta gris ("sin marca") en vez de rojo
--   — aunque el practicante tuviera turno u horario asignado y no haya
--   venido.
--
-- EL DEFECTO
--
--   Mismo patrón que ya corrigió la 0333 en /admin/contratos (ago-2026) y
--   que el commit de ayer corrigió en el Dashboard de asistencia
--   (`apps/web/app/(admin)/admin/dashboard/page.tsx`): un practicante activo
--   es estructuralmente invisible en una pantalla que solo pregunta
--   `en_planilla = true`, aunque la pregunta real de esa pantalla no es "¿es
--   trabajador de planilla?" sino "¿vino o no vino?". Sin este cambio,
--   ningún lugar del sistema le muestra a quien lo supervisa que un
--   practicante faltó — ni siquiera para que decida hablar con él o, si se
--   repite, terminarle el convenio por incumplimiento de sus obligaciones
--   (cláusula octava del modelo de convenio del D.S. 007-2005-TR: el
--   convenio de prácticas se puede terminar por incumplimiento sin pasar
--   por el escalón disciplinario de un colaborador de planilla).
--
-- QUÉ ASUME
--
--   `tipo_vinculo = 'practicante'` explícito, nunca `not en_planilla` a
--   secas — así un RxH o un no_trabajador no entra por accidente. Mismo
--   criterio puntual que ya usaron la 0333 y el Dashboard.
--
--   NO toca `fn_faltas_resumen` ni `fn_falta_contadores`: esas dos alimentan
--   el escalón disciplinario formal (memos, D.S. 003-97-TR) y deben seguir
--   excluyendo a los practicantes a propósito — tratarlos con la misma
--   maquinaria de sanciones progresivas que a un colaborador de planilla es
--   exactamente la señal que un inspector de trabajo usa para argumentar
--   que el convenio de prácticas es una relación laboral disfrazada
--   (desnaturalización, art. 51 de la Ley 28518). `fn_faltas` es la única de
--   las tres que es puramente informativa — pinta una cuadrícula y un
--   aviso, no genera ningún memo — así que es la única que puede ensancharse
--   sin acercarse a ese riesgo.
--
-- CÓMO SE REVIERTE
--   Volver a pegar el cuerpo de `fn_faltas` tal como quedó en la 0396:
--   `pe.en_planilla = true`, sin el `or pe.tipo_vinculo = 'practicante'`.
-- ============================================================================

create or replace function fn_faltas(p_desde date, p_hasta date)
returns table (persona_id uuid, nombre text, sede text, fecha date, justificada boolean, motivo text)
language sql stable security definer set search_path = public
as $$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede, pe.fecha_ingreso
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo'
      -- ⇩ CAMBIO 0414: un practicante cuenta sus faltas reales, igual que ya
      -- cuenta su presencia en el Dashboard desde ayer.
      and (pe.en_planilla = true or pe.tipo_vinculo = 'practicante')
      and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona())
           or pe.id = fn_persona_actual_id())
  ),
  dias as (
    select m.id as persona_id, m.nombre, m.sede, gs::date as fecha
    from medibles m
    cross join lateral generate_series(
      greatest(p_desde, m.fecha_ingreso),
      least(p_hasta, (now() at time zone 'America/Lima')::date - 1, fn_fecha_limite_asistencia(m.id)),
      interval '1 day') gs
  ),
  evaluado as (
    select d.*,
      (t.persona_id is not null) as hay_turno,
      coalesce(t.es_descanso, false) as turno_descanso,
      tr.horario_por_dia, tr.dias_laborables
    from dias d
    left join turnos t on t.persona_id = d.persona_id and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables
      from horarios_asignados h
      where h.persona_id = d.persona_id and h.vigente_desde <= d.fecha
        and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  tocaba as (
    select e.*,
      case
        when e.hay_turno then not e.turno_descanso
        when e.horario_por_dia is not null then (e.horario_por_dia ? (extract(dow from e.fecha)::int::text))
        when e.dias_laborables is not null then (extract(dow from e.fecha)::int = any(e.dias_laborables))
        else false
      end as trabaja
    from evaluado e
  )
  select tb.persona_id, tb.nombre, tb.sede, tb.fecha,
    (v.persona_id is not null or ju.motivo is not null or ds.persona_id is not null
     or sus.es is not null) as justificada,
    coalesce(
      case when sus.es is not null then 'suspension' end,
      ju.motivo,
      case when v.persona_id is not null then 'vacaciones' end,
      case when ds.persona_id is not null then 'descanso_sustitutorio' end
    ) as motivo
  from tocaba tb
  left join lateral (
    select 1 as persona_id from jornadas j
    where j.persona_id = tb.persona_id and j.fecha = tb.fecha and j.entrada_ts is not null limit 1
  ) presente on true
  left join lateral (
    select 1 as persona_id from vacaciones vc
    where vc.persona_id = tb.persona_id and tb.fecha between vc.fecha_inicio and vc.fecha_fin limit 1
  ) v on true
  left join justificaciones_asistencia ju on ju.persona_id = tb.persona_id and ju.fecha = tb.fecha
  left join lateral (
    select 1 as persona_id from feriados_descanso_sustitutorio d
    where d.persona_id = tb.persona_id
      and d.fecha_descanso_sustitutorio = tb.fecha
      and d.estado in ('PENDIENTE', 'OTORGADO') limit 1
  ) ds on true
  left join lateral (
    select 1 as es where fn_dia_suspendido(tb.persona_id, tb.fecha)
  ) sus on true
  left join lateral (
    select 1 as es from feriados f where f.fecha = tb.fecha limit 1
  ) fer on true
  where tb.trabaja
    and presente.persona_id is null
    and not (fer.es is not null and not tb.hay_turno)
  order by tb.fecha desc, tb.nombre;
$$;

grant execute on function fn_faltas(date, date) to authenticated;
revoke execute on function fn_faltas(date, date) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (414, 'los_practicantes_cuentan_sus_faltas_reales')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

do $$
begin
  raise notice '0414 · fn_faltas ya cuenta las faltas reales de un practicante; fn_faltas_resumen y fn_falta_contadores siguen intactas.';
end $$;
