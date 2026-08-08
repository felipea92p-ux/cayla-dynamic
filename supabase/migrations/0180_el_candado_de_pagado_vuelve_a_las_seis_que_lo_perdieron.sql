-- ============================================================================
-- 0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que ninguna de las seis funciones de abajo deje cambiar un feriado, un
--   turno, un horario o un descanso de una fecha que cae dentro de un periodo
--   de planilla ya PAGADO. Al intentarlo, error claro y nada se toca.
--
-- QUÉ ASUME
--   Que existe `periodos_planilla` con su columna `estado`, y que el valor
--   'pagado' significa que esa planilla ya se depositó. Ambas cosas vienen de
--   la 0025 y no han cambiado desde entonces.
--
-- POR QUÉ EXISTE — Y NO ES UNA MIGRACIÓN NORMAL
--   Estas seis funciones YA tienen el candado en el repositorio: se lo pusieron
--   la 0026 y la 0037, en julio. Esta migración no cambia el repositorio: lo
--   que hace es volver a poner en PRODUCCIÓN lo que el repositorio dice desde
--   hace 150 migraciones.
--
--   El 2026-08-07 se comparó el esquema entero de producción contra el del
--   repositorio, función por función. Producción tenía 13 funciones con el
--   candado; el repositorio, 19. Las seis que faltaban son estas. Sus cuerpos
--   se pidieron y se compararon línea a línea: producción es exactamente el
--   repositorio MENOS ese bloque. Ni una línea de más — por eso sobrescribir
--   no pierde nada, y por eso se miró antes de escribir.
--
--   No se sabe cómo se perdieron. La 0026 y la 0037 figuran anotadas en
--   `migraciones_aplicadas` de producción. Una fila dice que alguien la anotó,
--   no que su contenido esté en la base — este repositorio ya pagó esa
--   diferencia con la 0089.
--
-- QUÉ SE ROMPÍA SIN ESTO
--   Cambiar el feriado de una fecha ya pagada no daba error. La jornada se
--   recalcula sola con el trigger, las horas de ese mes cambian, y la planilla
--   que se depositó deja de cuadrar con lo que el sistema dice hoy. Sin aviso,
--   sin error, sin rastro visible: el pasado deja de coincidir consigo mismo y
--   se descubre cuando alguien reclama su pago.
--
-- CÓMO SE REVIERTE
--   Volviendo a aplicar los cuerpos de la 0026 (feriados) y la 0037 (turnos,
--   horarios y descansos) sin el bloque `if exists (… estado = 'pagado' …)`.
--   Revertir esto significa aceptar que una planilla pagada pueda cambiar.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve 6. Si devuelve menos, algo no se aplicó.
-- ============================================================================

-- ── fn_set_feriado ──  md5 esperado tras aplicar: 719d2dc02f9408322518c4b116d5775a
CREATE OR REPLACE FUNCTION public.fn_set_feriado(p_fecha date, p_nombre text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar feriados.';
  end if;
  if p_fecha is null then raise exception 'La fecha es obligatoria.'; end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre del feriado es obligatorio.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae dentro de un periodo ya PAGADO: cambiar sus feriados alteraría una planilla pagada. Reabre el periodo primero.';
  end if;
  insert into feriados (fecha, nombre) values (p_fecha, trim(p_nombre))
  on conflict (fecha) do update set nombre = excluded.nombre;
end;
$function$;

-- ── fn_quitar_feriado ──  md5 esperado tras aplicar: 78c1592506fa7abe332bcbb7c9e06f49
CREATE OR REPLACE FUNCTION public.fn_quitar_feriado(p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede gestionar feriados.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae dentro de un periodo ya PAGADO: cambiar sus feriados alteraría una planilla pagada. Reabre el periodo primero.';
  end if;
  delete from feriados where fecha = p_fecha;
  if not found then raise exception 'No hay feriado en esa fecha.'; end if;
end;
$function$;

-- ── fn_set_turno ──  md5 esperado tras aplicar: af2b07ee7a0701e8b2603d20fb413f5b
CREATE OR REPLACE FUNCTION public.fn_set_turno(p_persona_id uuid, p_fecha date, p_hora_entrada time without time zone, p_hora_salida time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción
  if p_hora_entrada is null then
    raise exception 'La hora de entrada del turno es obligatoria.';
  end if;
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: cambiar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;
  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen)
  values (p_persona_id, p_fecha, p_hora_entrada, p_hora_salida, false, 'panel')
  on conflict (persona_id, fecha) do update set
    hora_entrada = excluded.hora_entrada,
    hora_salida = excluded.hora_salida,
    es_descanso = false,
    origen = 'panel';
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;

-- ── fn_quitar_turno ──  md5 esperado tras aplicar: c0f7d21aba09ad6621148ee9945b42d5
CREATE OR REPLACE FUNCTION public.fn_quitar_turno(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: quitar el turno alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;
  delete from turnos where persona_id = p_persona_id and fecha = p_fecha;
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;

-- ── fn_set_horario_semanal ──  md5 esperado tras aplicar: 68790773c6b7e54830e02ecbdec540bf
CREATE OR REPLACE FUNCTION public.fn_set_horario_semanal(p_persona_id uuid, p_vigente_desde date, p_horario jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_editor uuid; r record;
  k text; v jsonb;
  v_dias int[]; v_min_entrada time; v_max_salida time;
  v_refri_min int; v_refri_max int;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción

  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and fecha_fin >= p_vigente_desde
  ) then
    raise exception 'Ese horario tocaría un periodo ya PAGADO (recalcula las jornadas desde esa fecha en adelante). Reabre el periodo primero.';
  end if;

  if p_horario is null or jsonb_typeof(p_horario) <> 'object'
     or (select count(*) from jsonb_object_keys(p_horario)) = 0 then
    raise exception 'Debe trabajar al menos un día a la semana.';
  end if;
  -- validar claves (0-6) y que cada día tenga hora de entrada
  for k, v in select * from jsonb_each(p_horario) loop
    if k !~ '^[0-6]$' then raise exception 'Día de la semana inválido: %', k; end if;
    if coalesce(v->>'e', '') = '' then raise exception 'Falta la hora de entrada del día %.', k; end if;
  end loop;

  -- resumen para columnas legacy: min entrada / max salida / días / refrigerio (min-max por día).
  -- nullif protege el casteo si 's' llegara vacío (cae a la hora de entrada).
  select array_agg((t.k)::int order by (t.k)::int),
         min((t.v->>'e')::time),
         max(coalesce(nullif(t.v->>'s', '')::time, (t.v->>'e')::time)),
         min(coalesce((t.v->>'r')::int, 0)),
         max(coalesce((t.v->>'r')::int, 0))
    into v_dias, v_min_entrada, v_max_salida, v_refri_min, v_refri_max
  from jsonb_each(p_horario) as t(k, v);

  -- reemplazar tramos que empiezan en/después de la fecha, cerrar el anterior
  delete from horarios_asignados where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;
  update horarios_asignados set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id and vigente_hasta is null and vigente_desde < p_vigente_desde;

  insert into horarios_asignados (
    persona_id, vigente_desde, vigente_hasta, hora_entrada, hora_salida,
    almuerzo_min_minutos, almuerzo_max_minutos, dias_laborables, horario_por_dia
  )
  values (
    p_persona_id, p_vigente_desde, null, v_min_entrada, coalesce(v_max_salida, v_min_entrada),
    v_refri_min, v_refri_max, v_dias, p_horario
  );

  -- recalcular tardanzas desde la fecha de vigencia
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$function$;

-- ── fn_set_descanso ──  md5 esperado tras aplicar: b5d0a2bfb5ee709e73ff3f8d18e3a200
CREATE OR REPLACE FUNCTION public.fn_set_descanso(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_editor uuid;
begin
  v_editor := fn_verificar_corrector(p_persona_id);
  if exists (
    select 1 from periodos_planilla where estado = 'pagado' and p_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: marcar descanso ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;
  insert into turnos (persona_id, fecha, hora_entrada, hora_salida, es_descanso, origen)
  values (p_persona_id, p_fecha, null, null, true, 'panel')
  on conflict (persona_id, fecha) do update set
    hora_entrada = null,
    hora_salida = null,
    es_descanso = true,
    origen = 'panel';
  perform fn_recalcular_jornada(p_persona_id, p_fecha);
end;
$function$;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (180, 'el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado de la
-- última consulta, así que esta es la que se ve al terminar de pegar.
-- Debe decir 6. Es la misma pregunta que destapó el problema.
select count(*) as las_seis_con_candado
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosrc like '%periodo ya PAGADO%'
  and p.proname in ('fn_set_feriado','fn_quitar_feriado','fn_set_turno',
                    'fn_quitar_turno','fn_set_horario_semanal','fn_set_descanso');
