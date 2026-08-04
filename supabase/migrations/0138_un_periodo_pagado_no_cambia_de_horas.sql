-- ============================================================================
-- 0138 — Un periodo pagado no cambia de horas por su cuenta
-- ============================================================================
--
-- QUÉ PROMETE
--   Ninguna jornada de un día que cae dentro de un periodo PAGADO se vuelve a
--   escribir. El número de horas con el que se pagó un día se queda quieto
--   hasta que alguien revierta el pago a propósito.
--
-- QUÉ ASUME
--   · `periodos_planilla` no se solapa: una fecha pertenece a lo sumo a un
--     periodo.
--   · Revertir un pago se hace por `fn_revertir_pago`, con motivo obligatorio
--     (0095). Ese es el único camino para volver a mover un día pagado.
--
-- POR QUÉ ASÍ, Y NO DE OTRA FORMA
--   Medido contra el Postgres local, en BEGIN … ROLLBACK, el 2026-08-04:
--   un día 16/06 pagado con 9.00 h pasaba a 8.00 h cuando la cola offline
--   subía tarde el par de marcas del almuerzo. La foto del pago (0096) sostenía
--   el monto, así que nadie cobraba de menos — pero `jornadas` dejaba de
--   coincidir con lo que se pagó, y esa diferencia no la explicaba nadie.
--
--   El candado NO va en `fn_registrar_marcaje`. Once funciones llaman al
--   recálculo (los dos triggers de marcajes, el auto-cierre, las cinco de
--   horarios y turnos, reabrir día y el bono de puntualidad). Poner la regla en
--   la puerta de entrada la deja fuera de las otras diez, y ese es exactamente
--   el error que este repositorio ya pagó tres veces: la misma regla escrita en
--   dos sitios y una corrección que arregla solo uno. Va en el único sitio por
--   donde pasan todas.
--
--   Y sale en silencio en vez de lanzar excepción porque quien la ejecuta es un
--   trigger de INSERT: una excepción haría que la terminal descartara la marca
--   tras seis reintentos. La marca real siempre entra. Lo que no se mueve es el
--   número ya pagado.
--
-- DE QUÉ VERSIÓN PARTE, Y POR QUÉ IMPORTA
--   Del cuerpo que dejó la **0081** (marcas que se anulan, no se borran), que es
--   el vigente — comprobado byte a byte contra `pg_get_functiondef` del Postgres
--   local. La búsqueda ingenua encuentra la 0013, 0014, 0016 y 0017 y **no** la
--   0081, porque esta la escribe como `CREATE OR REPLACE FUNCTION public.…` en
--   mayúsculas. Partir de la 0017 —64 migraciones atrás— revierte en silencio
--   toda la lógica de marcas anuladas. Las pruebas 81 y 82 lo cazan; si tocas
--   esta función, córrelas.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar la definición de `fn_recalcular_jornada` que trae la
--   migración 0081, que es esta misma sin el bloque marcado «CANDADO DE PERIODO
--   PAGADO». No hay cambio de datos ni de esquema que deshacer.
--
-- POR QUÉ ES LA 0138 Y NO LA 0136
--   Los tres números anteriores están reclamados por trabajo que no está en
--   `main`, y por eso se saltan a propósito (la convención del repo pide
--   documentar todo salto):
--
--     0133 · no existe en ningún archivo, rama ni commit. Se saltó al crear la
--            0134 el 2026-08-04. Hueco real, sin dueño.
--     0136 · la toma `origin/educacion-con-comprobante` (commit f1b1fa7,
--            empujado a GitHub) con la pantalla de educación y su comprobante.
--     0137 · **ya no es un hueco.** Era `fn_reabrir_dia`, aplicada a mano al
--            Postgres local el 2026-08-04 a las 21:04 y nunca commiteada. Se
--            recuperó verbatim desde `pg_get_functiondef` y hoy vive en
--            `0137_reabrir_el_dia_sin_dejarlo_a_medias.sql`, con su prueba 112.
--
--   Y la 0108 sigue existiendo solo en `movilidad-supeditada-a-asistencia`, sin
--   fusionar. Los huecos que quedan (0031, 0033, 0108, 0133) no se cierran acá;
--   quedan anotados para que nadie los reutilice creyéndolos libres.
--
--   Hay además dos colisiones vivas que este archivo no causa pero que conviene
--   mirar antes de fusionar nada: `origin/cuadro-de-categorias` numera 0131 y
--   0132 con contenido distinto al que `main` llama 0131 y 0132.
-- ============================================================================

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
  v_minutos_temprano int;
  v_horas_prog numeric;
  v_horas_extra numeric(6,2) := 0;
  v_horas_trabajadas numeric(6,2);
  v_estado estado_jornada;
  v_hora_entrada_esperada timestamptz;
  v_hora_salida_esperada timestamptz;
  v_n_marcajes int;
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
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and p_fecha between fecha_ini and fecha_fin
  ) then
    return;
  end if;

  select count(*) into v_n_marcajes
  from marcajes
  where persona_id = p_persona_id and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
    and anulada_at is null;

  if v_n_marcajes = 0 then
    delete from jornadas where persona_id = p_persona_id and fecha = p_fecha;
    return;
  end if;

  for v_marcaje in
    select * from marcajes
    where persona_id = p_persona_id and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
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
  v_dow := extract(dow from p_fecha)::int::text; -- 0=domingo … 6=sábado
  select hora_entrada, hora_salida, es_descanso
    into v_hora_entrada_prog, v_hora_salida_prog, v_es_descanso
  from turnos where persona_id = p_persona_id and fecha = p_fecha;
  if not found then
    select horario_por_dia, hora_entrada, hora_salida
      into v_hpd, v_hora_entrada_legacy, v_hora_salida_legacy
    from horarios_asignados
    where persona_id = p_persona_id and vigente_desde <= p_fecha
      and (vigente_hasta is null or vigente_hasta >= p_fecha)
    order by vigente_desde desc limit 1;
    if found then
      if v_hpd is not null then
        v_hora_entrada_prog := (v_hpd -> v_dow ->> 'e')::time; -- null si ese día es descanso
        v_hora_salida_prog  := (v_hpd -> v_dow ->> 's')::time;
        v_refri_prog        := coalesce((v_hpd -> v_dow ->> 'r')::int, 0);
      else
        v_hora_entrada_prog := v_hora_entrada_legacy;
        v_hora_salida_prog  := v_hora_salida_legacy;
      end if;
    end if;
  elsif v_es_descanso then
    v_hora_entrada_prog := null; -- descanso del turno: no se mide nada
    v_hora_salida_prog := null;
  end if;

  -- tardanza de entrada (SIN tolerancia, pero por MINUTO: los segundos dentro del
  -- minuto de entrada no cuentan — 07:45:00–07:45:59 es puntual, 07:46:00 es 1 min).
  v_minutos_tarde := null;
  if v_entrada_ts is not null and v_hora_entrada_prog is not null then
    v_hora_entrada_esperada := (p_fecha + v_hora_entrada_prog) at time zone 'America/Lima';
    v_minutos_tarde := greatest(0, floor(extract(epoch from (v_entrada_ts - v_hora_entrada_esperada)) / 60)::int);
    if v_minutos_tarde > 180 then v_minutos_tarde := null; end if;
  end if;

  v_horas_trabajadas := null;
  if v_entrada_ts is not null and v_salida_final_ts is not null then
    v_horas_trabajadas := round(extract(epoch from ((v_salida_final_ts - v_entrada_ts) - v_total_ausencia)) / 3600.0, 2);
  end if;

  -- salida anticipada: cerró el día antes de su hora de salida programada.
  -- Tolerancia de 15 min: dentro de 15 min de su hora no se marca (queda en 0).
  -- No se mide mientras el auto-cierre siga SIN REVISAR: esa hora la inventó el
  -- sistema y medir contra ella sería acusar con un dato falso. En cuanto una
  -- persona la confirma o la corrige, la hora es real y el día se mide entero.
  v_minutos_temprano := null;
  if v_salida_final_ts is not null and v_hora_salida_prog is not null
     and not (v_salida_final_origen = 'auto_cierre'
              and v_salida_final_revision = 'pendiente_revision') then
    v_hora_salida_esperada := (p_fecha + v_hora_salida_prog) at time zone 'America/Lima';
    v_minutos_temprano := greatest(0, round(extract(epoch from (v_hora_salida_esperada - v_salida_final_ts)) / 60)::int);
    if v_minutos_temprano > 180 then v_minutos_temprano := null; -- turno distinto / anomalía
    elsif v_minutos_temprano <= 15 then v_minutos_temprano := 0; -- dentro de la tolerancia
    end if;
  end if;

  -- tiempo adicional: trabajó más que sus horas programadas del día (neto de refrigerio).
  -- Tolerancia de 15 min (0.25 h): dentro de eso no se marca (queda en 0).
  -- Misma regla que arriba: sin revisar no se mide; revisada, sí.
  v_horas_extra := 0;
  if v_horas_trabajadas is not null and v_hora_entrada_prog is not null and v_hora_salida_prog is not null
     and not (v_salida_final_origen = 'auto_cierre'
              and v_salida_final_revision = 'pendiente_revision') then
    v_horas_prog := greatest(0, (extract(epoch from (v_hora_salida_prog - v_hora_entrada_prog)) / 3600.0) - (v_refri_prog / 60.0));
    v_horas_extra := greatest(0, round((v_horas_trabajadas - v_horas_prog)::numeric, 2));
    if v_horas_extra <= 0.25 then v_horas_extra := 0; end if; -- dentro de la tolerancia
  end if;

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
    estado, tiene_salida_no_retornada, updated_at
  ) values (
    p_persona_id, p_fecha, v_sede_id, v_entrada_ts, v_salida_final_ts,
    v_minutos_tarde, v_minutos_temprano, v_horas_trabajadas, v_horas_extra,
    v_estado, v_abierta_temporal, now()
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
    updated_at = now();
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (138, 'un_periodo_pagado_no_cambia_de_horas')
on conflict (numero) do nothing;
