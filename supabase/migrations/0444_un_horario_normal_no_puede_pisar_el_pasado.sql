-- ============================================================================
-- 0439 — Un horario normal no puede pisar el pasado
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: fn_set_horario_semanal (el camino normal de /admin/horarios,
-- botón "Cambiar") deja de aceptar un `vigente_desde` anterior a HOY. Cambiar
-- el horario de alguien hacia adelante nunca vuelve a recalcular tardanzas de
-- días que ya pasaron.
--
-- QUÉ PASABA SIN ESTO: el 2026-09-13 Felipe cambió el horario de una persona
-- con "Vigente desde" movido a una fecha pasada (ayer). El único candado que
-- tenía esta función era contra tocar un periodo de planilla ya PAGADO — no
-- distinguía "hoy" de "hace 40 días". El guardado recorta el tramo anterior
-- (`update ... set vigente_hasta = p_vigente_desde - 1`), inserta el tramo
-- nuevo y recalcula toda jornada con `fecha >= p_vigente_desde` — así que días
-- ya correctamente juzgados con el horario que de verdad regía entonces
-- quedaron re-juzgados con el horario de hoy, generando tardanzas falsas.
-- El campo de fecha en la pantalla (admin/horarios/page.tsx) tampoco tenía un
-- `min`: cualquier fecha pasada era seleccionable.
--
-- QUÉ ASUME:
--   · Que corregir el pasado de verdad —cuando el cambio de horario ocurrió
--     hace días y recién se registra hoy— sigue siendo necesario, y por eso
--     esta migración NO cierra esa puerta: la abre aparte, en
--     fn_corregir_horario_retroactivo (0442), auditada, con vista previa
--     exacta y bloqueada si el día ya tiene un expediente disciplinario
--     firmado — bloquear sin más habría movido el problema, no cerrado el
--     agujero (decisión tomada con Felipe el 2026-09-14).
--   · `fn_hoy_lima()` (0091) es la única fuente de "qué día es hoy" — se usa
--     esa, nunca `current_date`.
--
-- POR QUÉ SE ELIGIÓ ASÍ: el candado va en el SERVIDOR, no solo en la pantalla
-- (que también gana un `min` en el campo de fecha, en el mismo commit) —
-- mismo criterio que ya usa este repo en todos lados: la pantalla puede
-- dibujar mal o quedarse desactualizada, la base no debe confiar en eso.
--
-- QUÉ NO CAMBIA: ni un carácter del resto del cuerpo — el candado de periodo
-- pagado, el advisory lock de la 0380, la validación del jsonb, el recorte del
-- tramo anterior, el insert del tramo nuevo y el bucle de recálculo siguen
-- exactamente iguales. El único bloque nuevo es el marcado «CAMBIO 0439»,
-- insertado justo después de validar el permiso y antes del advisory lock —no
-- necesita el lock: es una comparación de fechas, no toca ninguna tabla.
--
-- MD5 DE PARTIDA — NO SE PUDO MEDIR EN ESTA SESIÓN. El Postgres local de esta
-- Mac no está disponible (Docker Desktop no respondía al escribir esto,
-- 2026-09-14), así que no hay ni siquiera un md5 local que declarar. El cuerpo
-- se copió tal cual del archivo `0380_fn_set_horario_semanal_gana_el_mismo_
-- candado_que_objetivos.sql`, confirmado como la única versión vigente con
-- `./scripts/donde-vive.sh fn_set_horario_semanal` el 2026-09-14.
--
-- COMO MANDA CLAUDE.md: antes de pegar esto, correr contra PRODUCCIÓN (no
-- contra esta Mac) la consulta de md5 de `fn_set_horario_semanal` — tal cual
-- como abajo — y confirmar que el resultado coincide con lo que declare
-- `donde-vive.sh` en el momento de pegar, no en el momento en que esto se
-- escribió:
--
--   select md5(p.prosrc) as tal_cual,
--          md5(array_to_string(array(
--            select regexp_replace(l, '[[:space:]]*--.*$', '')
--            from unnest(string_to_array(p.prosrc, chr(10))) as l
--            where btrim(l) not like '--%'
--          ), chr(10)))                 as sin_comentarios
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_set_horario_semanal';
--
-- CÓMO SE REVIERTE: quitar el bloque «CAMBIO 0439» y volver al cuerpo tal
-- cual de la 0380 — pero no se debería: eso reabre el agujero que costó la
-- tardanza falsa del 2026-09-13.
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

  -- ⇩⇩⇩ CAMBIO 0439 ⇩⇩⇩ UN HORARIO NORMAL NUNCA PISA EL PASADO.
  -- El 2026-09-13 esto no existía: una fecha pasada aquí recalculaba tardanzas
  -- de días ya correctamente juzgados con el horario que de verdad regía
  -- entonces. Corregir el pasado de verdad sigue siendo posible —
  -- fn_corregir_horario_retroactivo (0442), aparte, auditada, con preview.
  if p_vigente_desde < fn_hoy_lima() then
    raise exception 'No se puede aplicar un horario nuevo a una fecha que ya pasó (%): eso recalcularía tardanzas de días que ya deberían estar juzgados con el horario que de verdad regía entonces. Si el cambio de horario ocurrió de verdad hace unos días y recién se registra hoy, usa la corrección retroactiva de horario — muestra antes qué jornadas cambiarían y deja el motivo anotado.',
      to_char(p_vigente_desde, 'DD/MM/YYYY');
  end if;
  -- ⇧⇧⇧ CAMBIO 0439 ⇧⇧⇧

  -- CAMBIO 0380 — mismo candado que la 0361 le dio a Objetivos: serializa
  -- dos llamadas casi simultáneas para la MISMA persona, en vez de dejarlas
  -- chocar contra horarios_sin_solape con un mensaje que confunde.
  perform pg_advisory_xact_lock(hashtext('horario_semanal:' || p_persona_id::text));

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

  -- SE RECORTA EL TRAMO QUE PISA, NO SOLO EL ABIERTO (0360). Un tramo que ya
  -- terminó antes de la fecha no se toca: no pisa nada.
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
values (439, 'un_horario_normal_no_puede_pisar_el_pasado')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  position('CAMBIO 0439' in pg_get_functiondef('fn_set_horario_semanal'::regproc)) > 0 as tiene_el_candado;
