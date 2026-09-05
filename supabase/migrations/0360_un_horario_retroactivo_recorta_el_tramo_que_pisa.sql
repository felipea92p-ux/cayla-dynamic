-- ============================================================================
-- 0360 — Un horario retroactivo recorta el tramo que pisa, no solo el abierto
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que corregir el horario de alguien con una fecha de vigencia
-- que cae DENTRO de un tramo ya cerrado deje de reventar con
--   ERROR: conflicting key value violates exclusion constraint "horarios_sin_solape"
-- y haga lo que la persona esperaba: el tramo que estaba vigente ese día se
-- recorta hasta la víspera, y el nuevo rige desde la fecha elegida.
--
-- EL DEFECTO (hallazgo 14 de la auditoría del 2026-09-03/04): la 0309 puso
-- bien el candado `horarios_sin_solape`, pero `fn_set_horario_semanal` nunca
-- se ajustó a él. Su cierre de tramos era:
--
--   delete ... where vigente_desde >= p_vigente_desde;
--   update ... set vigente_hasta = p_vigente_desde - 1
--     where vigente_hasta is null and vigente_desde < p_vigente_desde;
--
-- Es decir, SOLO cerraba el tramo abierto. Con dos tramos —A del 1 al 14 de
-- agosto (cerrado) y B desde el 15 (abierto)— corregir desde el 5 de agosto
-- borraba B, insertaba el nuevo desde el 5, y dejaba A intacto del 1 al 14:
-- dos tramos cubriendo del 5 al 14. El candado lo rechazaba —correcto— con un
-- mensaje en inglés que `mensaje-error.ts` tampoco traducía. Quien lo veía era
-- una encargada, y ese texto no le decía ni qué hizo ni qué hacer.
--
-- EL ARREGLO: el `update` se generaliza a CUALQUIER tramo que empiece antes de
-- la fecha nueva y siga vigente ese día —abierto o cerrado—:
--
--   where vigente_desde < p_vigente_desde
--     and (vigente_hasta is null or vigente_hasta >= p_vigente_desde)
--
-- Un tramo cerrado que terminó ANTES de la fecha nueva no se toca (no pisa
-- nada). El `delete` de los que empiezan en o después de la fecha queda igual:
-- es la semántica de siempre —"el horario desde X reemplaza todo lo que venga
-- después"— y la auditoría no la discutió.
--
-- QUÉ NO CAMBIA: ni un carácter más del cuerpo. Mismo candado de periodo
-- pagado por grupo (0327), misma validación del jsonb, mismas columnas legacy,
-- mismo recálculo de jornadas desde la fecha. El bloque viejo se deja
-- comentado justo encima del nuevo para que la diferencia se lea sin abrir
-- el `git diff`.
--
-- Y en el panel, `mensaje-error.ts` aprende a traducir `horarios_sin_solape`
-- para el caso que este cambio no cubre —una escritura directa, o un solape
-- que llegue por otra puerta— y para el tiempo que pase entre fusionar esto
-- y pegarlo en producción.
--
-- SE REVIERTE: `create or replace` con el cuerpo de la 0327 (sección 18).
--
-- VIGENTE EN: 0327_el_candado_de_horas_pasa_a_ser_por_grupo.sql (sección 18),
-- confirmado con donde-vive.sh el 2026-09-04. md5 de partida (Postgres LOCAL,
-- no producción): tal cual dd0da86c6da97551c5824865bb621b58 · sin comentarios
-- b093a8d95fce9982d8dbf4ade6107c16. Antes de pegar en el SQL Editor, vuelve a
-- pedir el md5 a PRODUCCIÓN con donde-vive.sh — varias sesiones trabajan sobre
-- el mismo árbol y esta función ya tiene 5 versiones.
-- ============================================================================

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
    select 1 from periodos_planilla pp
    where pp.fecha_fin >= p_vigente_desde
      and (
        -- Compatibilidad: un periodo con estado='pagado' pero SIN ninguna fila
        -- en periodo_grupo_pago es de antes de la 0323 (el bucket único de
        -- siempre) — se sigue leyendo por el agregado.
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or
        -- El caso normal desde la 0323: el GRUPO de esta persona, no el
        -- periodo entero.
        exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = p_persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
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

  -- ⇩⇩⇩ CAMBIO 0360 ⇩⇩⇩ SE RECORTA EL TRAMO QUE PISA, NO SOLO EL ABIERTO.
  --
  -- Decía:
  --   update horarios_asignados set vigente_hasta = p_vigente_desde - 1
  --     where persona_id = p_persona_id and vigente_hasta is null and vigente_desde < p_vigente_desde;
  --
  -- Con eso, una fecha que caía DENTRO de un tramo ya cerrado dejaba ese
  -- tramo intacto, y el candado `horarios_sin_solape` (0309) rechazaba el
  -- insert de abajo con un error que nadie entendía. Ahora se recorta
  -- cualquier tramo que empiece antes de la fecha y siga vigente ese día —
  -- abierto (`vigente_hasta is null`) o cerrado pero con fin en o después de
  -- la fecha—. Un tramo que ya terminó antes no se toca: no pisa nada.
  update horarios_asignados set vigente_hasta = p_vigente_desde - 1
    where persona_id = p_persona_id
      and vigente_desde < p_vigente_desde
      and (vigente_hasta is null or vigente_hasta >= p_vigente_desde);

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

insert into migraciones_aplicadas (numero, nombre)
values (360, 'un_horario_retroactivo_recorta_el_tramo_que_pisa')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- El cuerpo nuevo lleva el marcador; el viejo no lo tenía.
select
  position('CAMBIO 0360' in pg_get_functiondef('fn_set_horario_semanal'::regproc)) > 0 as tiene_el_cambio,
  (select count(*) from pg_proc where proname = 'fn_set_horario_semanal') as una_sola_version;
