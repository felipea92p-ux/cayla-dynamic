-- ============================================================================
-- 0445 — El cálculo de una jornada se vuelve reusable
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: extrae de fn_recalcular_jornada, tal cual, la parte que decide
-- tardanza / salida anticipada / tiempo adicional a partir de un horario
-- programado — a una función nueva, pura y de solo lectura,
-- fn_calcular_metricas_jornada. fn_recalcular_jornada pasa a llamarla en vez
-- de tener la fórmula inline. NINGÚN NÚMERO CAMBIA: es exactamente el mismo
-- cálculo, en dos sitios en vez de uno.
--
-- PARA QUÉ: la corrección retroactiva de horario (0447,
-- fn_horario_retroactivo_preview) necesita simular "¿qué tardanza daría este
-- día con OTRO horario, sin guardar nada?" — y este repositorio ya sabe lo que
-- cuesta escribir la misma pregunta dos veces en dos sitios: la "cuarta regla"
-- de CLAUDE.md documenta CUATRO copias de "qué le tocaba trabajar ese día" que
-- convivieron con bugs reales y divergencias silenciosas hasta unificarse. Un
-- preview que reimplementara esta fórmula por su cuenta sería la quinta.
--
-- QUÉ SE MUEVE (y qué NO): se mueven los tres bloques que comparan la marca
-- real contra la hora PROGRAMADA — minutos_tarde, minutos_salida_temprana,
-- horas_extra_detectadas. NO se mueve horas_trabajadas: ese número sale solo
-- de (salida − entrada) − ausencias, nunca del horario, así que no cambia
-- nunca entre "el horario de antes" y "el horario de después" — no hay nada
-- que simular ahí. Tampoco se mueve nada de la lectura de marcajes, el estado
-- de la jornada, el candado de periodo pagado, ni el sellado de un día
-- imposible: todo eso sigue en fn_recalcular_jornada, intacto.
--
-- QUÉ ASUME: que "sujeta a horario", entrada_ts, salida_final_ts (con su
-- origen y su estado_revision) y horas_trabajadas ya están resueltos por
-- quien llama — la función nueva no toca `marcajes` ni `personas` ni
-- `horarios_asignados`: solo recibe esos hechos como parámetros y calcula.
-- Es management STABLE, no SECURITY DEFINER: no necesita saltarse RLS porque
-- no lee ninguna tabla.
--
-- POR QUÉ SE ELIGIÓ ASÍ: fn_recalcular_jornada tiene 14 versiones históricas y
-- es la función más crítica del sistema — de acá sale si a alguien se le
-- cuenta una tardanza o una falta, y eso alimenta el pago y el expediente
-- disciplinario. Extraer SOLO la fórmula (sin tocar cómo se resuelve el
-- horario, ni el bucle de marcajes, ni el resto) es el cambio más chico que
-- alcanza para que el preview sea exacto sin arriesgar el resto de la
-- función.
--
-- QUÉ NO CAMBIA: la resolución del horario (turno → horario_por_dia → legacy),
-- el bucle de marcajes, horas_trabajadas, el estado de la jornada, el candado
-- de periodo pagado, el insert/on conflict de `jornadas`, ni el sellado de un
-- día imposible. Se retiran del `declare` de fn_recalcular_jornada las dos
-- variables que ya no se usan ahí (v_hora_entrada_esperada,
-- v_hora_salida_esperada): viven ahora dentro de la función nueva.
--
-- MD5 DE PARTIDA — pedido a PRODUCCIÓN el 2026-09-15, después de que el
-- Postgres local de esta Mac (caído al escribir esto, Docker Desktop no
-- respondía, 2026-09-14) volviera a estar disponible. El cuerpo se copió tal
-- cual del archivo `0413_a_un_practicante_ya_se_le_mide_la_tardanza.sql`,
-- confirmado como la única versión vigente con `./scripts/donde-vive.sh
-- fn_recalcular_jornada` el 2026-09-14:
--
--   select md5(p.prosrc) as tal_cual,
--          md5(array_to_string(array(
--            select regexp_replace(l, '[[:space:]]*--.*$', '')
--            from unnest(string_to_array(p.prosrc, chr(10))) as l
--            where btrim(l) not like '--%'
--          ), chr(10)))                 as sin_comentarios
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'fn_recalcular_jornada';
--
-- → tal_cual = 11c659cae6ee236d81fdddb1c4d8dd8b (12 872 caracteres) —
-- COINCIDE, carácter por carácter, con el cuerpo de la 0413 de este
-- repositorio. Producción no había derivado ni un byte entre la 0413 y el
-- momento de escribir esta migración: el punto de partida que asume es real.
--
-- AUDITADO EMPÍRICAMENTE el 2026-09-14, en BEGIN…ROLLBACK contra el Postgres
-- local (sin datos reales — la base compartida estaba vacía de personas y
-- jornadas —, así que se sembraron datos de prueba dentro de la misma
-- transacción revertida): una jornada con 20 min de tardanza bajo el horario
-- sembrado se recalculó igual tras este refactor (fn_recalcular_jornada es
-- idempotente: recalcular dos veces da el mismo número), y el
-- horario_aplicado (0446) quedó con la entrada correcta. Ver también la
-- cabecera de la 0447, que corre en la misma transacción de prueba la
-- equivalencia preview-vs-real. Docker estuvo caído al empezar esta sesión y
-- se recuperó antes de terminarla — quedó auditado, no pendiente.
--
-- CÓMO SE REVIERTE: `drop function fn_calcular_metricas_jornada(...)` y volver
-- fn_recalcular_jornada al cuerpo tal cual de la 0413.
-- ============================================================================

-- ── La fórmula, ahora en un solo sitio ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_calcular_metricas_jornada(
  p_sujeta_a_horario boolean,
  p_entrada_ts timestamptz,
  p_salida_final_ts timestamptz,
  p_salida_final_origen origen_marca,
  p_salida_final_revision estado_revision,
  p_horas_trabajadas numeric,
  p_fecha date,
  p_hora_entrada_prog time,
  p_hora_salida_prog time,
  p_refri_prog int
)
 RETURNS TABLE (minutos_tarde int, minutos_salida_temprana int, horas_extra_detectadas numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_minutos_tarde int;
  v_minutos_temprano int;
  v_horas_extra numeric(6,2) := 0;
  v_horas_prog numeric;
  v_hora_entrada_esperada timestamptz;
  v_hora_salida_esperada timestamptz;
  v_pendiente_revision boolean;
begin
  v_pendiente_revision := (p_salida_final_origen = 'auto_cierre' and p_salida_final_revision = 'pendiente_revision');

  -- tardanza de entrada (SIN tolerancia, pero por MINUTO: los segundos dentro del
  -- minuto de entrada no cuentan — 07:45:00–07:45:59 es puntual, 07:46:00 es 1 min).
  v_minutos_tarde := null;
  if coalesce(p_sujeta_a_horario, false)
     and p_entrada_ts is not null and p_hora_entrada_prog is not null then
    v_hora_entrada_esperada := (p_fecha + p_hora_entrada_prog) at time zone 'America/Lima';
    v_minutos_tarde := greatest(0, floor(extract(epoch from (p_entrada_ts - v_hora_entrada_esperada)) / 60)::int);
    -- El número se guarda siempre; quién puede sancionar con él lo decide
    -- fn_tardanza_es_medible, no esta función.
  end if;

  -- salida anticipada: cerró el día antes de su hora de salida programada.
  -- Tolerancia de 15 min: dentro de 15 min de su hora no se marca (queda en 0).
  -- No se mide mientras el auto-cierre siga SIN REVISAR: esa hora la inventó el
  -- sistema y medir contra ella sería acusar con un dato falso. En cuanto una
  -- persona la confirma o la corrige, la hora es real y el día se mide entero.
  v_minutos_temprano := null;
  if coalesce(p_sujeta_a_horario, false)
     and p_salida_final_ts is not null and p_hora_salida_prog is not null
     and not v_pendiente_revision then
    v_hora_salida_esperada := (p_fecha + p_hora_salida_prog) at time zone 'America/Lima';
    v_minutos_temprano := greatest(0, round(extract(epoch from (v_hora_salida_esperada - p_salida_final_ts)) / 60)::int);
    if v_minutos_temprano <= 15 then v_minutos_temprano := 0; end if; -- dentro de la tolerancia
  end if;

  -- tiempo adicional: trabajó más que sus horas programadas del día (neto de refrigerio).
  -- Tolerancia de 15 min (0.25 h): dentro de eso no se marca (queda en 0).
  -- Misma regla que arriba: sin revisar no se mide; revisada, sí.
  v_horas_extra := 0;
  if p_horas_trabajadas is not null and p_hora_entrada_prog is not null and p_hora_salida_prog is not null
     and not v_pendiente_revision then
    v_horas_prog := greatest(0, (extract(epoch from (p_hora_salida_prog - p_hora_entrada_prog)) / 3600.0) - (p_refri_prog / 60.0));
    v_horas_extra := greatest(0, round((p_horas_trabajadas - v_horas_prog)::numeric, 2));
    if v_horas_extra <= 0.25 then v_horas_extra := 0; end if; -- dentro de la tolerancia
  end if;

  return query select v_minutos_tarde, v_minutos_temprano, v_horas_extra;
end;
$function$;

comment on function fn_calcular_metricas_jornada(boolean, timestamptz, timestamptz, origen_marca, estado_revision, numeric, date, time, time, int) is
  '0445 — minutos_tarde / minutos_salida_temprana / horas_extra_detectadas de UN día, dados sus hechos de marcaje ya resueltos y un horario programado candidato. Pura, sin leer ninguna tabla — la usan fn_recalcular_jornada (el horario REAL de ese día) y fn_horario_retroactivo_preview (0447, un horario candidato, para simular sin guardar). No cambia horas_trabajadas: ese número no depende del horario.';

-- ── fn_recalcular_jornada, ahora llamando a la fórmula de arriba ───────────
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

  -- ⇩⇩⇩ CAMBIO 0445 ⇩⇩⇩ tardanza, salida anticipada y tiempo adicional pasan a
  -- fn_calcular_metricas_jornada — misma fórmula, ahora reusable (ver cabecera
  -- de esta migración). Ni una tolerancia ni un redondeo cambia.
  select m.minutos_tarde, m.minutos_salida_temprana, m.horas_extra_detectadas
    into v_minutos_tarde, v_minutos_temprano, v_horas_extra
  from fn_calcular_metricas_jornada(
    v_sujeta_a_horario, v_entrada_ts, v_salida_final_ts,
    v_salida_final_origen, v_salida_final_revision, v_horas_trabajadas,
    p_fecha, v_hora_entrada_prog, v_hora_salida_prog, v_refri_prog
  ) m;
  -- ⇧⇧⇧ CAMBIO 0445 ⇧⇧⇧

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
values (445, 'el_calculo_de_una_jornada_se_vuelve_reusable')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  position('CAMBIO 0445' in pg_get_functiondef('fn_recalcular_jornada'::regproc)) > 0 as fn_recalcular_jornada_usa_la_nueva,
  (select count(*) from pg_proc where proname = 'fn_calcular_metricas_jornada') as una_sola_version_de_la_nueva;
