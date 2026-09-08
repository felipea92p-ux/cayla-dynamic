-- ============================================================================
-- 0396 · Las faltas dejan de contarse después de que el contrato terminó
-- ============================================================================
-- QUÉ PROMETE
--
--   Que `fn_faltas`, `fn_faltas_resumen` y `fn_falta_contadores` dejen de
--   contar como inasistencia injustificada cada día posterior a
--   `personas.fecha_fin_contrato`, para quien correctamente dejó de venir
--   porque su contrato terminó — SALVO que haya seguido marcando después,
--   porque entonces la relación sigue viva de hecho (art. 77 LPCL) y no hay
--   ninguna fecha que la corte.
--
-- EL DEFECTO, YA MEDIDO EN `auditoria/CAYLA_CORP_RPT_202608_Auditoria.md`
--
--   Ninguna de las tres funciones mira `fecha_fin_contrato`:
--   `select proname from pg_proc where prosrc ilike '%fecha_fin_contrato%'`
--   devuelve `fn_contratos_desnaturalizados`, `fn_contratos_por_vencer`,
--   `fn_documentos_tablero`, `fn_set_fin_contrato` — ninguna del motor de
--   faltas. Como `fn_cesar_persona` prohíbe una fecha de cese futura, siempre
--   hay un tramo entre el último día de contrato y el día en que alguien
--   registra la baja a mano. En ese tramo la persona ya no viene —cumplió—, y
--   el sistema la cuenta como si hubiera faltado, día tras día, sin tope.
--
--   Reproducido en la auditoría: persona con `fecha_fin_contrato` el 07-ago,
--   sin marcajes después, evaluada el 17-ago. `fn_faltas` listó CINCO
--   inasistencias injustificadas (10 al 14 de agosto) que no eran suyas, y
--   `fn_expediente_generar_falta()` no rebotó: generó el borrador con esos
--   cinco hechos, listo para convertirse en un memo real.
--
-- QUÉ ASUME
--
--   Que «siguió marcando después de vencido» es la MISMA pregunta que ya
--   responde `fn_contratos_desnaturalizados` (0231) para el tablero de
--   Contratos: si existe una marca (no anulada) con fecha posterior a
--   `fecha_fin_contrato`, esa persona sigue trabajando de hecho y no hay
--   fecha de corte que valga — se sigue midiendo su asistencia normal, sin
--   límite, exactamente como a cualquiera sin fecha de fin.
--
--   No se llama a `fn_contratos_desnaturalizados()` directamente: esa función
--   filtra por `fn_es_admin_o_lider() is true` porque es para el tablero que
--   solo ve DO — y `fn_faltas` la puede llamar una integrante mirando SUS
--   PROPIAS faltas (0256). Filtrando ahí, la respuesta le saldría siempre
--   "no hay corte" y el defecto seguiría entero para cualquiera que no sea
--   admin/líder. Por eso `fn_fecha_limite_asistencia` repite la misma
--   pregunta sin ese candado — es un cálculo interno de una función
--   `SECURITY DEFINER`, no una pantalla.
--
--   `fn_fecha_limite_asistencia` NO se le concede a `authenticated`, a
--   propósito: es un auxiliar de uso interno, igual que `fn_dia_suspendido`
--   desde la 0292 — las tres funciones que la llaman son `SECURITY DEFINER`,
--   así que la llamada corre como su dueño (postgres) sin necesitar el grant.
--   Concedérselo a `authenticated` la dejaría en `/rest/v1/rpc/…` para
--   cualquiera con sesión, exactamente el patrón de las nueve funciones que
--   la 0292 tuvo que cerrar.
--
--   Y por la misma razón, esta migración NO toca ningún permiso de
--   `fn_falta_contadores`. La 0292 le revocó el `execute` a `authenticated`
--   a propósito (hallazgo: cualquier cuenta podía pedir por RPC directo las
--   fechas exactas de falta de cualquier otra persona) — un
--   `create or replace function` conserva los permisos tal como están, y
--   agregar aquí un `grant … to authenticated` habría reabierto ese agujero
--   en silencio. La comprobación del final se niega a aplicarse si eso pasó.
--
--   No toca el tope de 12 meses de una practicante (0336). Son preguntas
--   distintas: el tope de 12 meses es un riesgo LEGAL mientras la practicante
--   sigue viniendo todos los días — ahí cortar la ventana de asistencia sería
--   dejar de registrar presencia real. `fecha_fin_contrato` es sobre alguien
--   que YA NO VIENE porque su vínculo terminó. Confundirlas haría que una
--   practicante activa, presente, deje de contar sus tardanzas el día que
--   cruza el tope — el error contrario al que esta migración corrige.
--
-- POR QUÉ UNA FUNCIÓN NUEVA Y NO TRES COPIAS DEL MISMO CASE
--
--   Las tres funciones ya duplican por separado la pregunta «qué es un día
--   que cuenta» (lo señala el propio encabezado de la 0094). Agregar el
--   mismo `case … exists (…) …` tres veces habría sido una cuarta copia de
--   algo que se puede decir una sola vez. `fn_fecha_limite_asistencia` es la
--   fecha (o `infinity`) hasta la que a esta persona se le puede pedir
--   asistencia; las tres funciones solo la usan para acotar su ventana.
--
-- QUÉ NO HACE
--
--   No cambia ni una fila para nadie con `fecha_fin_contrato` en blanco (la
--   inmensa mayoría, planilla indefinida): `fn_fecha_limite_asistencia`
--   devuelve `infinity` y `least(…, infinity)` no mueve nada.
--
--   No corrige la duplicación de las seis exclusiones de calendario
--   (feriados, vacaciones, suspensión…) entre las tres funciones — ese es
--   otro hallazgo de la misma auditoría, con su propio costo y su propia
--   migración; mezclarlo aquí habría hecho esto imposible de revisar de una
--   pasada.
--
-- CÓMO SE REVIERTE
--   `drop function fn_fecha_limite_asistencia(uuid);` y volver a pegar el
--   cuerpo vigente de cada una de las tres funciones tal como estaba antes:
--   `fn_faltas` desde la 0256, `fn_faltas_resumen` desde la 0091,
--   `fn_falta_contadores` desde la 0094.
-- ============================================================================

-- ── La fecha (o infinito) hasta la que se le puede pedir asistencia ─────────
create or replace function fn_fecha_limite_asistencia(p_persona_id uuid)
returns date
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    case
      when p.fecha_fin_contrato is null then null
      -- Siguió marcando DESPUÉS de vencido: la relación sigue viva de hecho
      -- (art. 77 LPCL, misma pregunta que fn_contratos_desnaturalizados) y no
      -- hay fecha que corte su asistencia.
      when exists (
        select 1 from marcajes m
        where m.persona_id = p.id
          and m.anulada_at is null
          and coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date)
              > p.fecha_fin_contrato
      ) then null
      else p.fecha_fin_contrato
    end,
    'infinity'::date
  )
  from personas p
  where p.id = p_persona_id;
$$;

comment on function fn_fecha_limite_asistencia(uuid) is
  'Hasta qué fecha se le puede pedir asistencia a esta persona — infinity si no aplica límite, '
  'o si siguió marcando después de fecha_fin_contrato (desnaturalizado de hecho, art. 77 LPCL). '
  'Usada por fn_faltas, fn_faltas_resumen y fn_falta_contadores para no contar como falta lo que '
  'pasó después de que el vínculo terminó de verdad. Desde la 0396.';

-- Sin grant a `authenticated` — ver «QUÉ ASUME» arriba. `postgres` y
-- `service_role` la ejecutan igual, por ser dueños/superusuario.
revoke execute on function fn_fecha_limite_asistencia(uuid) from public, anon, authenticated;

-- ── fn_faltas (vigente: 0256) ────────────────────────────────────────────
-- Único cambio: el tope de la ventana de días también mira
-- fn_fecha_limite_asistencia(m.id). Todo lo demás es copia literal.
create or replace function fn_faltas(p_desde date, p_hasta date)
returns table (persona_id uuid, nombre text, sede text, fecha date, justificada boolean, motivo text)
language sql stable security definer set search_path = public
as $$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede, pe.fecha_ingreso
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona())
           or pe.id = fn_persona_actual_id())
  ),
  dias as (
    select m.id as persona_id, m.nombre, m.sede, gs::date as fecha
    from medibles m
    cross join lateral generate_series(
      greatest(p_desde, m.fecha_ingreso),
      -- ⇩ CAMBIO 0396: no cuenta lo que pasó después de que el vínculo terminó.
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

-- ── fn_faltas_resumen (vigente: 0091) ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_faltas_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, consecutivas integer, en_30 integer, en_180 integer, nivel text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with rango as (select greatest(coalesce(p_as_of, fn_hoy_lima()) - 180, date '2026-01-01') as ini, coalesce(p_as_of, fn_hoy_lima()) - 1 as fin),
  medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
           greatest((select ini from rango), pe.fecha_ingreso) as desde
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  dias as (
    -- ⇩ CAMBIO 0396: no cuenta lo que pasó después de que el vínculo terminó.
    select m.id as pid, gs::date as fecha
    from medibles m cross join lateral generate_series(m.desde, least((select fin from rango), fn_fecha_limite_asistencia(m.id)), interval '1 day') gs
  ),
  ev as (
    select d.pid, d.fecha,
      (t.persona_id is not null) as hay_turno, coalesce(t.es_descanso, false) as turno_desc,
      tr.horario_por_dia as hpd, tr.dias_laborables as dl
    from dias d
    left join turnos t on t.persona_id = d.pid and t.fecha = d.fecha
    left join lateral (
      select h.horario_por_dia, h.dias_laborables from horarios_asignados h
      where h.persona_id = d.pid and h.vigente_desde <= d.fecha and (h.vigente_hasta is null or h.vigente_hasta >= d.fecha)
      order by h.vigente_desde desc limit 1
    ) tr on true
  ),
  sched as (
    select ev.pid, ev.fecha,
      case
        when exists (select 1 from jornadas j where j.persona_id = ev.pid and j.fecha = ev.fecha and j.entrada_ts is not null) then 'presente'
        when fn_dia_suspendido(ev.pid, ev.fecha) then 'just'
        when exists (select 1 from vacaciones v where v.persona_id = ev.pid and ev.fecha between v.fecha_inicio and v.fecha_fin)
          or exists (select 1 from justificaciones_asistencia ju where ju.persona_id = ev.pid and ju.fecha = ev.fecha)
          or exists (select 1 from feriados_descanso_sustitutorio d
                     where d.persona_id = ev.pid and d.fecha_descanso_sustitutorio = ev.fecha
                       and d.estado in ('PENDIENTE', 'OTORGADO')) then 'just'
        else 'falta'
      end as estado
    from ev
    where (case when ev.hay_turno then not ev.turno_desc
                when ev.hpd is not null then (ev.hpd ? (extract(dow from ev.fecha)::int::text))
                when ev.dl is not null then (extract(dow from ev.fecha)::int = any(ev.dl))
                else false end)
      and not (exists (select 1 from feriados f where f.fecha = ev.fecha) and not ev.hay_turno)
  ),
  rn as (
    select pid, estado, row_number() over (partition by pid order by fecha desc) as rk from sched
  ),
  consec as (
    select pid, (coalesce(min(rk) filter (where estado <> 'falta'), max(rk) + 1) - 1) as consecutivas
    from rn group by pid
  ),
  faltas_dias as (
    select pid, fecha from sched where estado = 'falta'
  ),
  c30 as (
    select pid, max(cnt) as n
    from (
      select a.pid, a.fecha, count(*) as cnt
      from faltas_dias a
      join faltas_dias b on b.pid = a.pid and b.fecha between a.fecha - 29 and a.fecha
      group by a.pid, a.fecha
    ) w
    group by pid
  ),
  c180 as (select pid, count(*) as n from sched where estado = 'falta' group by pid)
  select m.id, m.nombre, m.sede,
    coalesce(cc.consecutivas, 0)::int, coalesce(c30.n, 0)::int, coalesce(c180.n, 0)::int,
    case
      when coalesce(cc.consecutivas,0) > 3 or coalesce(c30.n,0) > 5 or coalesce(c180.n,0) > 15 then 'rojo'
      when coalesce(cc.consecutivas,0) = 3 or coalesce(c30.n,0) >= 4 or coalesce(c180.n,0) >= 12 then 'ambar'
      else 'verde'
    end as nivel
  from medibles m
  left join consec cc on cc.pid = m.id
  left join c30  on c30.pid  = m.id
  left join c180 on c180.pid = m.id
  where coalesce(cc.consecutivas,0) >= 3 or coalesce(c30.n,0) >= 4 or coalesce(c180.n,0) >= 12
  order by (case when coalesce(cc.consecutivas,0) > 3 or coalesce(c30.n,0) > 5 or coalesce(c180.n,0) > 15 then 1 else 2 end), m.nombre;
$function$;

grant execute on function fn_faltas_resumen(date) to authenticated;
revoke execute on function fn_faltas_resumen(date) from public, anon;

-- ── fn_falta_contadores (vigente: 0094) ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_falta_contadores(p_persona_id uuid, p_desde date)
 RETURNS TABLE(consecutivas integer, en_30 integer, en_180 integer, fechas date[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with rango as (
    select greatest(p_desde, coalesce((select fecha_ingreso from personas where id = p_persona_id), date '2026-01-01'), date '2026-01-01') as ini,
           -- ⇩ CAMBIO 0396: no cuenta lo que pasó después de que el vínculo terminó.
           least(fn_hoy_lima() - 1, fn_fecha_limite_asistencia(p_persona_id)) as fin
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

-- Sin grant ni revoke: `create or replace function` conserva los permisos que
-- ya tenía (la 0292 le revocó `authenticated` a propósito). Tocarlos acá los
-- reescribiría — ver «QUÉ ASUME» arriba.

insert into migraciones_aplicadas (numero, nombre)
values (396, 'las_faltas_dejan_de_contar_despues_del_fin_de_contrato')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Se niega a quedar aplicada si reabrió el agujero de la 0292 ────────────
-- `create or replace` no debería tocar los permisos, pero esto lo comprueba
-- en vez de confiar: si `authenticated` puede ejecutar cualquiera de las tres
-- funciones internas, algo salió mal y hay que pararse a mirar antes de que
-- termine en producción.
do $$
declare
  v_falla text;
begin
  select string_agg(fn, ', ') into v_falla
  from (values
    ('fn_falta_contadores(uuid,date)'),
    ('fn_fecha_limite_asistencia(uuid)')
  ) as f(fn)
  where has_function_privilege('authenticated', f.fn, 'execute');

  if v_falla is not null then
    raise exception
      'PARA. La 0396 dejó a "authenticated" ejecutar directo: %. Eso reabre el hallazgo de la 0292 — no debe pegarse así.',
      v_falla;
  end if;
end $$;

do $$
begin
  raise notice '0396 · fn_faltas / fn_faltas_resumen / fn_falta_contadores dejan de contar despues de fecha_fin_contrato, salvo desnaturalizacion.';
end $$;
