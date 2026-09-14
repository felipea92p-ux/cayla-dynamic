-- ============================================================================
-- 0441 — Cada jornada guarda el horario con que se midió
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: `jornadas` gana una columna, `horario_aplicado jsonb`, que
-- fn_recalcular_jornada llena CADA VEZ que corre, con el horario que de
-- verdad usó para calcular esa jornada (de dónde salió — turno puntual u
-- horario base —, y la entrada/salida/refrigerio/descanso que resolvió). Así
-- una tardanza se puede auditar mirando la propia jornada, sin tener que
-- reconstruir a mano el historial de `horarios_asignados` — que además puede
-- haber cambiado de forma desde entonces (un tramo se recorta o se reemplaza
-- con cada cambio de horario posterior).
--
-- QUÉ ASUME: que `horarios_asignados` puede reescribirse hacia atrás (0442,
-- corrección retroactiva) o simplemente seguir acumulando tramos nuevos, y que
-- ninguna de las dos cosas debe poder borrar la respuesta a "¿con qué horario
-- se juzgó ESTE día, en el momento en que se juzgó?". Guardar la referencia
-- (`horario_id`) no habría bastado: si ese tramo se recorta o se borra más
-- adelante, la referencia queda huérfana o apunta a algo distinto. Por eso es
-- una FOTO (jsonb con los valores ya resueltos), no un id.
--
-- POR QUÉ SE ELIGIÓ ASÍ: aditivo puro. No cambia ningún número que ya se
-- calculaba (minutos_tarde, horas_trabajadas, etc. — todo sigue exactamente
-- igual, ver 0440); solo agrega un dato nuevo, opcional, que no participa en
-- ningún cálculo aguas abajo (planilla, disciplina, provisiones). Una columna
-- jsonb nullable sobre una tabla existente no requiere backfill para que el
-- sistema siga funcionando — las jornadas viejas se quedan con
-- `horario_aplicado = null` hasta que algo dispare su próximo recálculo.
--
-- QUÉ NO CAMBIA: ni un número calculado, ni la resolución del horario (turno →
-- horario_por_dia → legacy) más allá de anotar DE DÓNDE salió cada vez que ya
-- lo hacía. El único cambio de forma es que el `if not found / elsif
-- v_es_descanso` de 0413 se reescribe como `if found / else` para poder anotar
-- "vino de turnos" en los dos subcasos (con y sin descanso) sin repetir la
-- asignación — es la misma lógica, reordenada; ver la comprobación de abajo
-- para el caso "turno con descanso", que es el que más cambia de forma.
--
-- MD5 DE PARTIDA — NO SE PUDO MEDIR EN ESTA SESIÓN. Docker Desktop no
-- respondía en esta Mac al escribir esto (2026-09-14), así que no hay ni
-- Postgres local para consultar. Este archivo parte del cuerpo que deja la
-- 0440 en este mismo commit (no de producción, todavía sin desplegar): antes
-- de pegar 0440 y 0441 en producción, correr la consulta de md5 estándar de
-- fn_recalcular_jornada contra PRODUCCIÓN inmediatamente antes de pegar 0440
-- (no antes), y de nuevo antes de pegar esta.
--
-- CÓMO SE REVIERTE: `alter table jornadas drop column horario_aplicado;` y
-- volver fn_recalcular_jornada al cuerpo tal cual de la 0440.
-- ============================================================================

alter table jornadas add column if not exists horario_aplicado jsonb;

comment on column jornadas.horario_aplicado is
  '0441 — foto del horario con que fn_recalcular_jornada calculó ESTA jornada: {"fuente": "turnos"|"horarios_asignados", "horario_id": uuid|null, "entrada": time|null, "salida": time|null, "refrigerio_min": int, "es_descanso": bool}. null en jornadas calculadas antes de esta migración, hasta su próximo recálculo. No participa en ningún cálculo — es solo para auditar "¿con qué se midió esto?" sin reconstruir el historial de horarios_asignados a mano.';

CREATE OR REPLACE FUNCTION public.fn_recalcular_jornada(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
  v_marcaje record;
  v_entrada_ts timestamptz;
  v_salida_final_ts timestamptz;
  v_salida_final_origen origen_marca;
  v_salida_final_revision estado_revision;
  v_ausencia_inicio timestamptz;
  v_total_ausencia interval := interval '0';
  v_horas_imposibles boolean := false;   -- 0249: la resta dio negativo
  v_abierta_temporal boolean := false;
  v_sede_id uuid;
  v_hora_entrada_prog time;
  v_hora_salida_prog time;
  v_refri_prog int := 0;
  v_es_descanso boolean := false;
  v_hpd jsonb;
  v_hora_entrada_legacy time;
  v_hora_salida_legacy time;
  v_dow text;
  v_minutos_tarde int;
  v_sujeta_a_horario boolean;   -- 0191/0413: un RxH no tiene jornada que medir; un practicante sí
  v_minutos_temprano int;
  v_horas_extra numeric(6,2) := 0;
  v_horas_trabajadas numeric(6,2);
  v_estado estado_jornada;
  v_n_marcajes int;
  v_fuente_horario text;        -- CAMBIO 0441: de dónde salió el horario de este día
  v_horario_id uuid;             -- CAMBIO 0441: id del tramo de horarios_asignados, si aplica
begin
  -- ── CANDADO DE PERIODO PAGADO ──────────────────────────────────────────────
  -- Un día que cae dentro de un periodo con estado 'pagado' NO se vuelve a
  -- calcular. Ni por una marca que sube tarde desde la cola offline, ni porque
  -- alguien cambie un horario que abarca meses hacia atrás.
  --
  -- Se SALE en silencio en vez de lanzar excepción, y es a propósito: este
  -- cuerpo lo ejecuta un trigger sobre `marcajes`. Lanzar aquí abortaría el
  -- INSERT, la terminal reintentaría seis veces y acabaría descartando una
  -- marca REAL de una persona que sí estuvo. Perder el registro de un hecho es
  -- peor que tener un día pagado que no coincide con él: los marcajes son la
  -- fuente de verdad y son append-only. La marca entra; lo que no se mueve es
  -- el número que ya se pagó.
  --
  -- El día no queda mudo: la marca atrasada rompe la secuencia del día,
  -- fn_dia_incoherente lo sella y aparece en Correcciones. Probado en la 110.
  --
  -- El candado se levanta solo: lee el estado del periodo en cada llamada, así
  -- que revertir el pago (fn_revertir_pago, con motivo obligatorio) devuelve el
  -- recálculo sin tocar nada más.
  if fn_fecha_en_periodo_pagado(p_fecha, p_persona_id) then
    return;
  end if;

  select count(*) into v_n_marcajes
  from marcajes
  where persona_id = p_persona_id
    -- 0240 · La jornada manda, no el calendario. `fecha_jornada` solo trae
    -- valor cuando una marca cierra una jornada abierta del día anterior —
    -- alguien que cruzó la medianoche—; en todo lo demás es null y esto se
    -- comporta exactamente igual que antes.
    and coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) = p_fecha
    and anulada_at is null;

  if v_n_marcajes = 0 then
    delete from jornadas where persona_id = p_persona_id and fecha = p_fecha;
    return;
  end if;

  for v_marcaje in
    select * from marcajes
    where persona_id = p_persona_id
    -- 0240 · La jornada manda, no el calendario. `fecha_jornada` solo trae
    -- valor cuando una marca cierra una jornada abierta del día anterior —
    -- alguien que cruzó la medianoche—; en todo lo demás es null y esto se
    -- comporta exactamente igual que antes.
    and coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) = p_fecha
      and anulada_at is null
    order by timestamp_marca asc
  loop
    v_sede_id := coalesce(v_sede_id, v_marcaje.sede_id);
    if v_marcaje.tipo = 'entrada' then
      v_entrada_ts := coalesce(v_entrada_ts, v_marcaje.timestamp_marca);
    elsif v_marcaje.tipo = 'salida_final' then
      v_salida_final_ts := v_marcaje.timestamp_marca;
      v_salida_final_origen := v_marcaje.origen;
      v_salida_final_revision := v_marcaje.estado_revision;
    elsif v_marcaje.tipo::text like 'salida\_%' escape '\' then
      v_ausencia_inicio := v_marcaje.timestamp_marca;
      v_abierta_temporal := true;
    elsif v_marcaje.tipo::text like 'retorno\_%' escape '\' then
      if v_abierta_temporal and v_ausencia_inicio is not null then
        v_total_ausencia := v_total_ausencia + (v_marcaje.timestamp_marca - v_ausencia_inicio);
      end if;
      v_abierta_temporal := false;
      v_ausencia_inicio := null;
    end if;
  end loop;

  -- horario programado del día: turno → horario por día (jsonb) → hora única legacy.
  -- ¿Esta persona está sujeta a un horario? Un locador (rxh) presta un
  -- servicio, no cumple una jornada: la ley no le fija hora de entrada, y el
  -- sistema tampoco debe medírsela (0191). Un practicante SÍ tiene jornada
  -- fijada por su convenio (Ley 28518 art. 44), así que a él sí se le mide —
  -- lo que no se le hace es disciplinarlo con eso: ese candado vive en
  -- fn_expediente_generar_tardanza y en el filtro en_planilla=true que ya
  -- usa fn_tardanzas_resumen, no acá (0413).
  select p.en_planilla or p.tipo_vinculo = 'practicante' into v_sujeta_a_horario
  from personas p where p.id = p_persona_id;

  v_dow := extract(dow from p_fecha)::int::text; -- 0=domingo … 6=sábado
  select hora_entrada, hora_salida, es_descanso
    into v_hora_entrada_prog, v_hora_salida_prog, v_es_descanso
  from turnos where persona_id = p_persona_id and fecha = p_fecha;
  -- ⇩⇩⇩ CAMBIO 0441 ⇩⇩⇩ mismo `if/else` de siempre, reescrito de `if not
  -- found / elsif v_es_descanso` a `if found / else` para poder anotar
  -- v_fuente_horario en los dos subcasos de turno (con y sin descanso) sin
  -- repetir la asignación. El comportamiento no cambia: un turno con
  -- descanso sigue anulando entrada/salida; uno sin descanso sigue dejando lo
  -- que trajo el SELECT; y "no hay turno" sigue cayendo al horario base.
  if found then
    v_fuente_horario := 'turnos';
    if v_es_descanso then
      v_hora_entrada_prog := null; -- descanso del turno: no se mide nada
      v_hora_salida_prog := null;
    end if;
  else
    select id, horario_por_dia, hora_entrada, hora_salida
      into v_horario_id, v_hpd, v_hora_entrada_legacy, v_hora_salida_legacy
    from horarios_asignados
    where persona_id = p_persona_id and vigente_desde <= p_fecha
      and (vigente_hasta is null or vigente_hasta >= p_fecha)
    order by vigente_desde desc limit 1;
    if found then
      v_fuente_horario := 'horarios_asignados';
      if v_hpd is not null then
        v_hora_entrada_prog := (v_hpd -> v_dow ->> 'e')::time; -- null si ese día es descanso
        v_hora_salida_prog  := (v_hpd -> v_dow ->> 's')::time;
        v_refri_prog        := coalesce((v_hpd -> v_dow ->> 'r')::int, 0);
      else
        v_hora_entrada_prog := v_hora_entrada_legacy;
        v_hora_salida_prog  := v_hora_salida_legacy;
      end if;
    end if;
  end if;
  -- ⇧⇧⇧ CAMBIO 0441 ⇧⇧⇧

  v_horas_trabajadas := null;
  if v_entrada_ts is not null and v_salida_final_ts is not null then
    v_horas_trabajadas := round(extract(epoch from ((v_salida_final_ts - v_entrada_ts) - v_total_ausencia)) / 3600.0, 2);

    -- ⇩⇩⇩ CAMBIO 0249 ⇩⇩⇩ UN NEGATIVO NO SE GUARDA, PERO TAMPOCO TUMBA LA MARCA.
    --
    -- Hasta acá, un negativo llegaba al `insert` de abajo y `chk_horas_no_negativas`
    -- (0095) lo rechazaba. Pero el `insert` de la jornada NO va solo: cuelga del
    -- trigger de `marcajes`, así que la excepción sube y se lleva por delante EL
    -- MARCAJE ENTERO. O sea que un día con las pausas descuadradas hacía que la
    -- salida de esa persona fuera IMPOSIBLE de registrar — el terminal le seguía
    -- ofreciendo «Salida» toda la noche y cada intento se iba a la cola hasta
    -- apartarse. Medido el 2026-08-14 contra el Postgres local, y visto antes en
    -- producción: dos salidas apartadas con este mismo error.
    --
    -- Es la regla que la 0068 ya dejó escrita y que la 0207 repite: perder el
    -- registro de alguien que sí estuvo es peor que un día que no cuadra.
    --
    -- NULL Y NO CERO, y la diferencia importa: cero dice «no trabajó», null dice
    -- «no se sabe cuánto». Es lo mismo que hizo la 0095 al limpiar los negativos
    -- que ya existían. La planilla lee `coalesce(horas_trabajadas, 0)`, así que
    -- de momento paga igual — por eso el día NO puede quedarse callado, y de eso
    -- se encarga el sello del final.
    if v_horas_trabajadas < 0 then
      v_horas_imposibles := true;
      v_horas_trabajadas := null;
    end if;
  end if;

  -- tardanza, salida anticipada y tiempo adicional: fn_calcular_metricas_jornada (0440).
  select m.minutos_tarde, m.minutos_salida_temprana, m.horas_extra_detectadas
    into v_minutos_tarde, v_minutos_temprano, v_horas_extra
  from fn_calcular_metricas_jornada(
    v_sujeta_a_horario, v_entrada_ts, v_salida_final_ts,
    v_salida_final_origen, v_salida_final_revision, v_horas_trabajadas,
    p_fecha, v_hora_entrada_prog, v_hora_salida_prog, v_refri_prog
  ) m;

  if v_salida_final_ts is not null then
    if v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'pendiente_revision' then
      v_estado := 'auto_cerrada_pendiente';
    elsif v_salida_final_origen = 'auto_cierre' and v_salida_final_revision = 'revisada' then
      v_estado := 'revisada';
    else
      v_estado := 'cerrada';
    end if;
  elsif v_abierta_temporal then
    v_estado := 'en_pausa';
  else
    v_estado := 'abierta';
  end if;

  insert into jornadas (
    persona_id, fecha, sede_id, entrada_ts, salida_final_ts,
    minutos_tarde, minutos_salida_temprana, horas_trabajadas, horas_extra_detectadas,
    estado, tiene_salida_no_retornada, horario_aplicado, updated_at
  ) values (
    p_persona_id, p_fecha, v_sede_id, v_entrada_ts, v_salida_final_ts,
    v_minutos_tarde, v_minutos_temprano, v_horas_trabajadas, v_horas_extra,
    v_estado, v_abierta_temporal,
    -- CAMBIO 0441 — null si ni turno ni horario base cubrían este día (nada
    -- que fotografiar); si no, la foto de lo que de verdad se usó.
    case when v_fuente_horario is null then null else
      jsonb_build_object(
        'fuente', v_fuente_horario, 'horario_id', v_horario_id,
        'entrada', v_hora_entrada_prog, 'salida', v_hora_salida_prog,
        'refrigerio_min', v_refri_prog, 'es_descanso', v_es_descanso
      )
    end,
    now()
  )
  on conflict (persona_id, fecha) do update set
    sede_id = excluded.sede_id,
    entrada_ts = excluded.entrada_ts,
    salida_final_ts = excluded.salida_final_ts,
    minutos_tarde = excluded.minutos_tarde,
    minutos_salida_temprana = excluded.minutos_salida_temprana,
    horas_trabajadas = excluded.horas_trabajadas,
    horas_extra_detectadas = excluded.horas_extra_detectadas,
    estado = excluded.estado,
    tiene_salida_no_retornada = excluded.tiene_salida_no_retornada,
    horario_aplicado = excluded.horario_aplicado,
    updated_at = now();

  -- ── 0249 · Y el día imposible se señala, en vez de pagarse como cero ───────
  -- Sin esto el arreglo de arriba sería peor que el problema: la marca entraría,
  -- la jornada quedaría sin horas y la planilla la pagaría como 0 h sin que nadie
  -- se entere. Un descuento silencioso es exactamente lo que este sistema no
  -- puede hacer.
  --
  -- Se usa el mismo sello que ya existe para el día incoherente (0068), así que
  -- el día aparece en Correcciones sin pantalla nueva ni concepto nuevo.
  --
  -- `estado_revision = 'normal'` NO es un filtro de cortesía: es lo que corta la
  -- recursión. Este update dispara el trigger de `marcajes`, que vuelve a llamar
  -- a esta función; en esa segunda vuelta las marcas ya están selladas, el update
  -- toca 0 filas y no hay tercera. La profundidad es 2, siempre.
  if v_horas_imposibles then
    update marcajes
      set estado_revision = 'pendiente_revision'
    where persona_id = p_persona_id
      and coalesce(fecha_jornada, (timestamp_marca at time zone 'America/Lima')::date) = p_fecha
      and anulada_at is null
      and estado_revision = 'normal';
  end if;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (441, 'cada_jornada_guarda_el_horario_con_que_se_midio')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  position('CAMBIO 0441' in pg_get_functiondef('fn_recalcular_jornada'::regproc)) > 0 as tiene_el_snapshot,
  exists (
    select 1 from information_schema.columns
    where table_name = 'jornadas' and column_name = 'horario_aplicado'
  ) as tiene_la_columna;
