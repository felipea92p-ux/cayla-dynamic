-- ============================================================================
-- Una persona puede ver SUS PROPIAS faltas
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que `fn_faltas` le responda a la persona por sí misma, además de
--   a admin/líder (todo el mundo) y a la encargada (su sede). Ni una fila más:
--   la rama nueva es `pe.id = fn_persona_actual_id()`, así que quien la llame
--   sin ser ninguna de las tres sigue recibiendo cero filas.
--
-- QUÉ ASUME: que `fn_persona_actual_id()` devuelve null cuando quien pregunta no
--   tiene fila en `personas`. Con null, `pe.id = null` es NULL —nunca true—, así
--   que el OR no abre nada. Es la forma null-safe que este repositorio exige.
--
-- POR QUÉ: hoy una integrante entra a «Lo mío», ve un día sin marcaje en gris y
--   no sabe si el sistema le contó una falta. Se entera cuando ya hay una
--   conversación encima, que es exactamente cuando ya no se puede arreglar el
--   marcaje. Y buena parte de las faltas que este sistema detecta no son faltas:
--   son días sin turno cargado o sin horario vigente. La persona es la única que
--   sabe qué pasó ese día — dejarla verlo es el canal de corrección más barato
--   que tiene CAYLA, y encaja con «Dynamic avisa, nunca sanciona solo».
--
--   No le da ninguna capacidad nueva: no puede justificar nada, solo mirar. Lo
--   que ve de sí misma ya lo ven su encargada y DO.
--
-- CÓMO SE REVIERTE: volver a aplicar el cuerpo de la 0079 tal cual. Esta
--   migración cambia UNA línea de la cláusula de visibilidad; todo lo demás es
--   copia literal de la versión vigente.
--
-- MD5 DE PARTIDA (pedido a PRODUCCIÓN el 2026-08-15, no copiado del local):
--   8887c5d18d8893bdf5b6383afdf1ff40 · 3488 caracteres · 3497 bytes
--   Es la versión de la 0079 — el repositorio y producción coinciden.
--   Si al pegar esto el md5 de partida no era ese, PARA: se estaría
--   sobrescribiendo una versión que nadie sabe de dónde salió.
--
-- Idempotente: `create or replace`, se puede pegar dos veces sin efecto.
-- ============================================================================

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
           -- ⇩ CAMBIO 0256: cada quien se ve a sí misma. Con
           -- `fn_persona_actual_id()` en null esto es NULL, nunca true.
           or pe.id = fn_persona_actual_id())
  ),
  dias as (
    select m.id as persona_id, m.nombre, m.sede, gs::date as fecha
    from medibles m
    cross join lateral generate_series(
      greatest(p_desde, m.fecha_ingreso),
      least(p_hasta, (now() at time zone 'America/Lima')::date - 1),
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
        when e.hay_turno then not e.turno_descanso                       -- el turno del día manda
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
      -- La suspensión manda sobre cualquier otro motivo: es un hecho de la
      -- empresa, no una situación de la persona.
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
  -- ⇩ CAMBIO 0079: el día que se cumple una sanción no es una falta
  left join lateral (
    select 1 as es where fn_dia_suspendido(tb.persona_id, tb.fecha)
  ) sus on true
  left join lateral (
    select 1 as es from feriados f where f.fecha = tb.fecha limit 1
  ) fer on true
  where tb.trabaja
    and presente.persona_id is null                       -- no marcó = ausente
    and not (fer.es is not null and not tb.hay_turno)     -- feriado sin turno explícito: no cuenta
  order by tb.fecha desc, tb.nombre;
$$;

-- El `create or replace` conserva los permisos, así que este grant es de más.
-- Va igual: la 0189 dejó dos pantallas caídas en producción durante dos días
-- porque un `drop function` se llevó por delante un grant que nadie repuso, y
-- desde entonces en este repositorio toda migración que toca una función deja
-- su permiso escrito. Cuesta una línea.
grant execute on function fn_faltas(date, date) to authenticated;
revoke execute on function fn_faltas(date, date) from public, anon;

-- ----------------------------------------------------------------------------
-- LO QUE ESTA MIGRACIÓN **NO** HACE, Y ESTÁ DECIDIDO
--
-- · No abre las vacaciones: no hacía falta. `vacaciones` no es una tabla, es una
--   vista sobre `ausencias` (tipo = 'vacaciones', no anuladas) declarada con
--   `security_invoker=true`, así que la RLS que manda es la de `ausencias` — y
--   `ausencias_select_propia` ya existe. Cada quien ya podía leer las suyas.
--
-- · No muestra un SALDO de vacaciones. Ese número sale de un cálculo que acaba
--   de tener un defecto de doble cobro en la trunca; publicárselo a treinta
--   personas antes de que asiente sería comprometerse con una cifra que todavía
--   se mueve. Lo registrado es un hecho; el saldo es una promesa.
--
-- · No abre el expediente disciplinario. `exp_select_propia` ya lo permite, pero
--   esa policy no filtra por estado: incluiría los BORRADORES, o sea documentos
--   que nadie decidió entregar. Avisarle a alguien de una sanción que aún no
--   existe es peor que no avisarle de nada.
-- ----------------------------------------------------------------------------

-- El rastro. Sin esta fila, `que_falta_pegar.sql` no puede decir si esta
-- migración llegó a producción, y la prueba 122 —que corre en cada push— falla
-- a propósito para que nadie se olvide.
insert into migraciones_aplicadas (numero, nombre)
values (256, 'una_persona_puede_ver_sus_propias_faltas')
on conflict (numero) do nothing;
