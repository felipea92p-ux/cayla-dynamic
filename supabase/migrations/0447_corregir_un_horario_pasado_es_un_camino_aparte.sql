-- ============================================================================
-- 0447 — Corregir un horario pasado es un camino aparte
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: dos funciones nuevas para cuando el cambio de horario de
-- verdad ocurrió hace días y recién se registra hoy — el caso que la 0444
-- deja de aceptar por el camino normal:
--
--   · fn_horario_retroactivo_preview — de solo lectura. Dado un horario
--     candidato y una fecha de inicio pasada, dice EXACTAMENTE qué cambiaría,
--     día por día, entre el cálculo actual y el que resultaría — sin guardar
--     nada. Usa fn_calcular_metricas_jornada (0445), la misma fórmula que usa
--     el cálculo real, para no reimplementarla una segunda vez.
--   · fn_corregir_horario_retroactivo — la que sí guarda. Exige motivo,
--     aplica el mismo candado de periodo pagado que fn_set_horario_semanal
--     (0380), BLOQUEA si algún día del rango ya tiene un expediente
--     disciplinario firmado o entregado (fn_dia_con_expediente_formal, 0437 —
--     decisión tomada con Felipe el 2026-09-14: igual que las otras seis
--     puertas que ya cierran ese mismo hueco), y deja rastro en
--     `correcciones_auditoria`.
--
-- QUÉ ASUME:
--   · Que puede usarlas quien hoy ya edita horarios — admin, DO (lider_do) y
--     encargada de sede (supervisor_sede), vía fn_verificar_corrector — misma
--     decisión que Felipe tomó el 2026-09-14: no restringir más de lo que ya
--     hay para editar horarios en general.
--   · Que el rango a revisar es CADA DÍA entre `p_vigente_desde` y ayer,
--     exista o no una fila en `jornadas` ese día — no solo los días con
--     jornada. Un día sin marcaje (posible falta) puede tener igual un
--     expediente disciplinario firmado citándolo, y ese caso tiene que
--     bloquear y aparecer en el preview igual que uno con tardanza. Por eso
--     las dos funciones recorren `generate_series(p_vigente_desde, hoy-1)`
--     con `left join jornadas`, no `from jornadas`.
--   · Que horas_trabajadas NUNCA cambia entre "antes" y "después": no
--     depende del horario (sale solo de entrada/salida real menos ausencias,
--     ver 0445), así que el preview la muestra igual en las dos columnas a
--     propósito — no es un error de la vista previa, es que de verdad no hay
--     nada que simular ahí.
--   · Que el origen/estado_revisión de la salida final de un día (para saber
--     si el auto-cierre sigue "pendiente de revisión", que excluye salida
--     anticipada y tiempo adicional — ver 0445) se lee de `marcajes` con la
--     MISMA selección que usa el bucle de fn_recalcular_jornada: el último
--     `salida_final` no anulado de ese día. Si ese criterio de selección
--     cambia alguna vez en el bucle, este query tiene que cambiar con él —
--     es la única pieza que no viene de una función compartida, porque
--     extraer el bucle entero de marcajes era un refactor mucho más grande
--     que lo que esta migración necesita.
--
-- POR QUÉ SE ELIGIÓ ASÍ: separar "cambiar el horario hacia adelante" (0444,
-- nunca toca el pasado) de "corregir el pasado" (acá, aparte, auditada, con
-- preview) es el mismo criterio que ya usa este repo para un campo sensible:
-- una función guardián que valida y dice qué pasó, no un `UPDATE` directo con
-- la confianza de que nadie se va a equivocar (fn_cambiar_regimen_pension,
-- fn_set_rol, fn_set_sede_base). Bloquear sin más el pasado no habría
-- bastado: cuando el cambio de horario ocurrió DE VERDAD hace unos días,
-- juzgar esos días con el horario viejo genera la misma clase de tardanza
-- falsa, solo que al revés — por eso esta migración abre la puerta que la
-- 0444 cerró, pero por un pasillo con vista previa, motivo y auditoría.
--
-- QUÉ NO CAMBIA: fn_set_horario_semanal (0444), fn_recalcular_jornada (0446),
-- fn_calcular_metricas_jornada (0445) y fn_dia_con_expediente_formal (0437)
-- se usan tal cual, sin tocarlas.
--
-- CÓMO SE REVIERTE: `drop function fn_horario_retroactivo_preview(...)` y
-- `drop function fn_corregir_horario_retroactivo(...)`. No deja nada más
-- enganchado: ninguna otra función las llama todavía.
--
-- AUDITADO EMPÍRICAMENTE el 2026-09-14, en BEGIN…ROLLBACK, con datos de
-- prueba sembrados en la misma transacción (la base compartida no tenía
-- personas ni jornadas reales). Se probaron los cuatro casos y los tres
-- pasaron a la primera después de corregir dos bugs reales que este mismo
-- ejercicio encontró en fn_horario_retroactivo_preview (un `d.dia` sin
-- castear a `::date` en dos sitios — la prueba jamás habría pasado sin
-- arreglarlos, que es exactamente para lo que sirve auditar antes de
-- entregar):
--   (a) una corrección que SÍ bloqueó por expediente disciplinario formal;
--   (b) una que SÍ bloqueó por periodo ya pagado;
--   (c) una corrección legítima de punta a punta: una jornada con 20 min de
--       tardanza bajo el horario viejo quedó en 0 tras corregir con un
--       horario candidato que la habría hecho puntual, con
--       correcciones_auditoria +1 y horario_aplicado (0446) reflejando la
--       entrada nueva;
--   (d) el preview, para el MISMO horario candidato y el mismo rango, dio
--       EXACTAMENTE los mismos números (20 → 0) que la corrección real
--       confirmó después — la garantía central de esta migración.
-- La transacción de prueba se revirtió: la base compartida quedó exactamente
-- como estaba (confirmado: max(numero) volvió a 368, personas volvió a 0).
--
-- Dos bugs más, que la prueba en SQL no podía ver, salieron recién al
-- probar la PANTALLA en el navegador con una sesión real:
--
-- TERCERO: las dos funciones nacían SIN ejecución para `authenticated`
-- (0076: `alter default privileges revoke execute on functions from
-- public` — toda función nueva nace cerrada, y hay que abrirla a mano).
-- `fn_dia_con_expediente_formal` (0437) nunca necesitó ese grant porque
-- nada la llama por RPC directo, solo otras funciones SECURITY DEFINER —
-- pero estas dos SÍ las llama el navegador directo, y sin el grant
-- PostgREST devolvía 403 antes de que el cuerpo de la función corriera.
--
-- CUARTO, ya con el grant puesto: el preview marcaba como "cambia" TODO día
-- del rango sin jornada (13 de 13, en la prueba visual), no solo el que de
-- verdad tenía una tardanza. Causa: un día sin jornada no tiene fila, así
-- que `j.horas_extra_detectadas` sale `null` del `left join` — pero
-- `fn_calcular_metricas_jornada` nunca devuelve `null` para ese campo,
-- siempre `0`. El frontend comparaba `null` contra `0` y los veía distintos.
-- Se corrige con un `coalesce(j.horas_extra_detectadas, 0)` en el preview.
--
-- Los cuatro (permiso, coalesce, y los dos de arriba) se repitieron en el
-- navegador con una sesión real hasta que el flujo completo —preview con
-- solo el día real marcado, confirmar, jornada recalculada, historial
-- visible— salió limpio.
-- ============================================================================

-- ── 1 · La vista previa, sin guardar nada ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_horario_retroactivo_preview(
  p_persona_id uuid, p_horario jsonb, p_vigente_desde date
)
 RETURNS TABLE (
   fecha date,
   minutos_tarde_actual int, minutos_tarde_nuevo int,
   minutos_salida_temprana_actual int, minutos_salida_temprana_nuevo int,
   horas_trabajadas_actual numeric, horas_trabajadas_nuevo numeric,
   horas_extra_actual numeric, horas_extra_nuevo numeric,
   tiene_expediente_formal boolean
 )
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sujeta_a_horario boolean;
begin
  perform fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción

  if p_vigente_desde >= fn_hoy_lima() then
    raise exception 'La corrección retroactiva es solo para fechas que ya pasaron. Para hoy o el futuro, usa el cambio de horario normal.';
  end if;

  if p_horario is null or jsonb_typeof(p_horario) <> 'object'
     or (select count(*) from jsonb_object_keys(p_horario)) = 0 then
    raise exception 'Debe trabajar al menos un día a la semana.';
  end if;

  -- Mismo candado de periodo pagado que fn_set_horario_semanal (0380/0444) y
  -- fn_corregir_horario_retroactivo (más abajo) — que el preview lo muestre
  -- ANTES de que alguien arme todo el formulario para nada.
  if exists (
    select 1 from periodos_planilla pp
    where pp.fecha_fin >= p_vigente_desde
      and (
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or exists (
          select 1 from periodo_grupo_pago g
          join personas pe on pe.id = p_persona_id
          where g.periodo_id = pp.id
            and g.grupo = pe.tipo_vinculo
            and g.estado = 'pagado'
        )
      )
  ) then
    raise exception 'Ese rango tocaría un periodo ya PAGADO. Reabre el periodo primero.';
  end if;

  select p.en_planilla or p.tipo_vinculo = 'practicante' into v_sujeta_a_horario
  from personas p where p.id = p_persona_id;

  return query
  select
    d.dia::date,
    j.minutos_tarde, met.minutos_tarde,
    j.minutos_salida_temprana, met.minutos_salida_temprana,
    j.horas_trabajadas, j.horas_trabajadas, -- invariante: no depende del horario (0445)
    -- coalesce a 0: un día SIN jornada no tiene fila, así que j.horas_extra_detectadas
    -- sale null del left join — pero fn_calcular_metricas_jornada nunca devuelve
    -- null para este campo (siempre 0 cuando no hay nada que medir). Sin este
    -- coalesce, todo día sin jornada se veía como "cambia" (null contra 0) aunque
    -- de verdad no hubiera nada que recalcular.
    coalesce(j.horas_extra_detectadas, 0), met.horas_extra_detectadas,
    fn_dia_con_expediente_formal(p_persona_id, d.dia::date)
  from generate_series(p_vigente_desde::timestamp, (fn_hoy_lima() - 1)::timestamp, interval '1 day') as d(dia)
  left join jornadas j on j.persona_id = p_persona_id and j.fecha = d.dia::date
  -- El último `salida_final` no anulado de ese día — misma selección que usa
  -- el bucle de fn_recalcular_jornada (ver "QUÉ ASUME" arriba).
  left join lateral (
    select m.origen, m.estado_revision
    from marcajes m
    where m.persona_id = p_persona_id
      and coalesce(m.fecha_jornada, (m.timestamp_marca at time zone 'America/Lima')::date) = d.dia::date
      and m.tipo = 'salida_final'
      and m.anulada_at is null
    order by m.timestamp_marca desc
    limit 1
  ) sf on true
  cross join lateral fn_calcular_metricas_jornada(
    v_sujeta_a_horario,
    j.entrada_ts, j.salida_final_ts, sf.origen, sf.estado_revision,
    j.horas_trabajadas,
    d.dia::date,
    (p_horario -> extract(dow from d.dia::date)::int::text ->> 'e')::time,
    (p_horario -> extract(dow from d.dia::date)::int::text ->> 's')::time,
    coalesce((p_horario -> extract(dow from d.dia::date)::int::text ->> 'r')::int, 0)
  ) met
  order by d.dia;
end;
$function$;

comment on function fn_horario_retroactivo_preview(uuid, jsonb, date) is
  '0447 — simula, sin guardar nada, qué cambiaría para cada jornada entre p_vigente_desde y ayer si se aplicara p_horario. Antes de fn_corregir_horario_retroactivo.';

-- Sin este grant, la base nace SIN ejecución para nadie más que postgres/
-- service_role (0076: `alter default privileges revoke execute on functions
-- from public`) — y esta función SÍ la llama el navegador por RPC directo, a
-- diferencia de fn_dia_con_expediente_formal (0437), que solo se llama desde
-- dentro de otras funciones SECURITY DEFINER y por eso nunca necesitó uno.
grant execute on function fn_horario_retroactivo_preview(uuid, jsonb, date) to authenticated;

-- ── 2 · La corrección de verdad ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_corregir_horario_retroactivo(
  p_persona_id uuid, p_horario jsonb, p_vigente_desde date, p_motivo text
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
  v_horario_anterior jsonb;
  v_dia_bloqueado date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección retroactiva es obligatorio.';
  end if;

  v_editor := fn_verificar_corrector(p_persona_id); -- valida permiso o lanza excepción

  -- Mismo candado que fn_set_horario_semanal (0380): serializa dos llamadas
  -- casi simultáneas para la MISMA persona.
  perform pg_advisory_xact_lock(hashtext('horario_semanal:' || p_persona_id::text));

  if p_vigente_desde >= fn_hoy_lima() then
    raise exception 'Esa fecha no es del pasado: usa el cambio de horario normal, no la corrección retroactiva.';
  end if;

  -- ── NO SE TOCA UN DÍA CON UN EXPEDIENTE YA FORMAL (mismo criterio que 0437/0438) ──
  -- Recorre CADA día del rango, no solo los que tienen fila en `jornadas`: un
  -- día sin marcaje puede tener igual una falta ya sancionada citándolo.
  select min(d::date) into v_dia_bloqueado
  from generate_series(p_vigente_desde::timestamp, (fn_hoy_lima() - 1)::timestamp, interval '1 day') as d
  where fn_dia_con_expediente_formal(p_persona_id, d::date);

  if v_dia_bloqueado is not null then
    raise exception 'El % ya tiene un expediente disciplinario firmado o entregado construido sobre el horario de entonces: corregirlo retroactivamente cambiaría el hecho sobre el que ya se construyó ese expediente. Resuelve o anula el expediente en Disciplina antes de continuar.',
      to_char(v_dia_bloqueado, 'DD/MM/YYYY');
  end if;

  -- Mismo candado de periodo pagado que fn_set_horario_semanal (0380/0444).
  if exists (
    select 1 from periodos_planilla pp
    where pp.fecha_fin >= p_vigente_desde
      and (
        (pp.estado = 'pagado' and not exists (
           select 1 from periodo_grupo_pago g where g.periodo_id = pp.id
         ))
        or exists (
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
  for k, v in select * from jsonb_each(p_horario) loop
    if k !~ '^[0-6]$' then raise exception 'Día de la semana inválido: %', k; end if;
    if coalesce(v->>'e', '') = '' then raise exception 'Falta la hora de entrada del día %.', k; end if;
  end loop;

  select array_agg((t.k)::int order by (t.k)::int),
         min((t.v->>'e')::time),
         max(coalesce(nullif(t.v->>'s', '')::time, (t.v->>'e')::time)),
         min(coalesce((t.v->>'r')::int, 0)),
         max(coalesce((t.v->>'r')::int, 0))
    into v_dias, v_min_entrada, v_max_salida, v_refri_min, v_refri_max
  from jsonb_each(p_horario) as t(k, v);

  -- Lo que queda desplazado, para dejarlo en la auditoría antes de tocarlo.
  select jsonb_agg(jsonb_build_object(
           'vigente_desde', vigente_desde, 'vigente_hasta', vigente_hasta,
           'horario_por_dia', horario_por_dia
         ) order by vigente_desde)
    into v_horario_anterior
  from horarios_asignados
  where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;

  -- Mismo mecanismo de reemplazo que fn_set_horario_semanal (0380/0360):
  -- reemplaza los tramos que empiezan en/después de la fecha, recorta el
  -- anterior, inserta el nuevo.
  delete from horarios_asignados where persona_id = p_persona_id and vigente_desde >= p_vigente_desde;

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

  -- 'horarios_asignados' — mismo campo_modificado que usa fn_set_horario_semanal
  -- desde la 0440, para que las dos puertas queden bajo la misma etiqueta en
  -- el historial de correcciones (Correcciones ya sabe describir ese valor).
  insert into correcciones_auditoria (persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (
    p_persona_id, 'horarios_asignados',
    coalesce(v_horario_anterior::text, '(sin horario previo en ese rango)'),
    p_horario::text, v_editor, trim(p_motivo)
  );

  -- Recalcula desde la fecha de vigencia — igual que fn_set_horario_semanal,
  -- solo que acá esa fecha es del pasado a propósito.
  for r in select fecha from jornadas where persona_id = p_persona_id and fecha >= p_vigente_desde loop
    perform fn_recalcular_jornada(p_persona_id, r.fecha);
  end loop;
end;
$function$;

comment on function fn_corregir_horario_retroactivo(uuid, jsonb, date, text) is
  '0447 — corrige el horario de una persona con vigencia en el PASADO, cuando el cambio real ocurrió hace días y recién se registra hoy. A diferencia de fn_set_horario_semanal (0444, que ya no acepta fechas pasadas), exige motivo, bloquea si algún día del rango tiene un expediente disciplinario firmado/entregado, y deja rastro en correcciones_auditoria.';

-- Mismo motivo que el grant de arriba: esta función la llama el navegador
-- por RPC directo.
grant execute on function fn_corregir_horario_retroactivo(uuid, jsonb, date, text) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (447, 'corregir_un_horario_pasado_es_un_camino_aparte')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from pg_proc where proname = 'fn_horario_retroactivo_preview') as una_sola_version_preview,
  (select count(*) from pg_proc where proname = 'fn_corregir_horario_retroactivo') as una_sola_version_corregir;
