-- ============================================================================
-- 0444 — Un horario normal no puede pisar el pasado
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
-- CHOCA CON OTRA MIGRACIÓN QUE SE FUSIONÓ A MAIN MIENTRAS ESTA SE ESCRIBÍA —
-- la 0440 ("El horario también se cambia por una puerta", 2026-09-14, otra
-- sesión) le agregó a ESTA MISMA función un cuarto parámetro (`p_motivo`,
-- obligatorio), rastro en `correcciones_auditoria`, y un trigger
-- (`trg_horarios_solo_por_rpc`) que bloquea escribir `horarios_asignados`
-- por fuera de esta función. Este archivo YA NO parte del cuerpo de la 0380
-- (3 argumentos): parte del cuerpo que deja la 0440 (4 argumentos), copiado
-- tal cual de ese archivo — confirmado que es la única versión con
-- `./scripts/donde-vive.sh fn_set_horario_semanal` tras fusionar `main`. Un
-- `create or replace` con la firma vieja de 3 argumentos aquí habría creado
-- una SEGUNDA función sobrecargada sin motivo y sin auditoría — el mismo
-- accidente de la 0297/0299 que este repo ya sufrió una vez.
--
-- QUÉ ASUME:
--   · Que corregir el pasado de verdad —cuando el cambio de horario ocurrió
--     hace días y recién se registra hoy— sigue siendo necesario, y por eso
--     esta migración NO cierra esa puerta: la abre aparte, en
--     fn_corregir_horario_retroactivo (0447), auditada, con vista previa
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
-- QUÉ NO CAMBIA: el motivo obligatorio, el advisory lock (0380), el rastro en
-- correcciones_auditoria, el candado de periodo pagado, la validación del
-- jsonb, el recorte del tramo anterior, el insert del tramo nuevo, el bucle
-- de recálculo, y el trigger `trg_horarios_solo_por_rpc` — todo eso es de la
-- 0440 y sigue exactamente igual. El único bloque nuevo es el marcado
-- «CAMBIO 0444», insertado justo después de validar el motivo y antes del
-- advisory lock — no necesita el lock: es una comparación de fechas, no toca
-- ninguna tabla.
--
-- MD5 DE PARTIDA — NO SE PUDO MEDIR EN ESTA SESIÓN. El Postgres local de esta
-- Mac no llegaba a la 0440 al escribir esto. El cuerpo se copió tal cual del
-- archivo `0440_el_horario_tambien_se_cambia_por_una_puerta.sql` de `main`.
-- Como manda CLAUDE.md: antes de pegar esto, correr contra PRODUCCIÓN (no
-- contra esta Mac) la consulta de md5 de `fn_set_horario_semanal` — tal cual
-- como abajo — y confirmar que el resultado coincide con lo que declare
-- `donde-vive.sh` en el momento de pegar, no en el momento en que esto se
-- escribió. Con la 0440 recién fusionada, el md5 de PARTIDA que corresponde
-- pedir es el que deja ESA migración en producción, no el de la 0380:
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
-- CÓMO SE REVIERTE: quitar el bloque «CAMBIO 0444» y volver al cuerpo tal
-- cual de la 0440 — pero no se debería: eso reabre el agujero que costó la
-- tardanza falsa del 2026-09-13.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_set_horario_semanal(
  p_persona_id uuid, p_vigente_desde date, p_horario jsonb, p_motivo text
)
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
  v_anterior record;
  v_valor_anterior text; v_valor_nuevo text;
begin
  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción; v_editor = quien edita

  if p_motivo is null or length(btrim(p_motivo)) < 3 then
    raise exception 'Escribe el motivo del cambio de horario (mínimo 3 caracteres).';
  end if;

  -- ⇩⇩⇩ CAMBIO 0444 ⇩⇩⇩ UN HORARIO NORMAL NUNCA PISA EL PASADO.
  -- El 2026-09-13 esto no existía: una fecha pasada aquí recalculaba tardanzas
  -- de días ya correctamente juzgados con el horario que de verdad regía
  -- entonces. Corregir el pasado de verdad sigue siendo posible —
  -- fn_corregir_horario_retroactivo (0447), aparte, auditada, con preview.
  if p_vigente_desde < fn_hoy_lima() then
    raise exception 'No se puede aplicar un horario nuevo a una fecha que ya pasó (%): eso recalcularía tardanzas de días que ya deberían estar juzgados con el horario que de verdad regía entonces. Si el cambio de horario ocurrió de verdad hace unos días y recién se registra hoy, usa la corrección retroactiva de horario — muestra antes qué jornadas cambiarían y deja el motivo anotado.',
      to_char(p_vigente_desde, 'DD/MM/YYYY');
  end if;
  -- ⇧⇧⇧ CAMBIO 0444 ⇧⇧⇧

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

  -- Estado anterior, para el rastro — capturado ANTES de tocar la tabla (0440).
  select vigente_desde, horario_por_dia, dias_laborables, hora_entrada, hora_salida
    into v_anterior
    from horarios_asignados
   where persona_id = p_persona_id and vigente_hasta is null;

  v_valor_anterior := case
    when v_anterior is null then 'sin horario previo'
    else 'vigente desde ' || v_anterior.vigente_desde::text || ': ' ||
         coalesce(v_anterior.horario_por_dia::text,
                   'días ' || v_anterior.dias_laborables::text || ' ' ||
                   v_anterior.hora_entrada::text || '–' || v_anterior.hora_salida::text)
  end;
  v_valor_nuevo := 'vigente desde ' || p_vigente_desde::text || ': ' || p_horario::text;

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

  -- Rastro obligatorio (0440): quién, cuándo, qué regía, qué rige y por qué.
  insert into correcciones_auditoria
    (persona_id, campo_modificado, valor_anterior, valor_nuevo, motivo, corregido_por)
  values (p_persona_id, 'horarios_asignados', v_valor_anterior, v_valor_nuevo, btrim(p_motivo), v_editor);
end;
$function$;

comment on function fn_set_horario_semanal(uuid, date, jsonb, text) is
  'Única puerta de escritura de horarios_asignados desde la 0184. Exige motivo '
  '(mínimo 3 caracteres) y deja rastro en correcciones_auditoria — quién, cuándo, '
  'qué regía y qué rige ahora (0440). Desde la 0444, rechaza una fecha pasada — '
  'para eso está fn_corregir_horario_retroactivo (0447).';

-- Los grants no cambian: la firma (uuid, date, jsonb, text) es la misma que
-- dejó la 0440, así que sus `revoke`/`grant` para esta función siguen en pie.

insert into migraciones_aplicadas (numero, nombre)
values (444, 'un_horario_normal_no_puede_pisar_el_pasado')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  position('CAMBIO 0444' in pg_get_functiondef('fn_set_horario_semanal'::regproc)) > 0 as tiene_el_candado,
  (select count(*) from pg_proc where proname = 'fn_set_horario_semanal') as una_sola_version,
  pg_get_function_identity_arguments(
    (select oid from pg_proc where proname = 'fn_set_horario_semanal')
  ) as firma_vigente;
