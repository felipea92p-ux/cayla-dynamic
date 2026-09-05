-- ============================================================================
-- 0249_una_salida_real_siempre_se_puede_registrar.sql
-- ============================================================================
-- QUÉ PROMETE
--   1. Que ninguna marca que una persona hizo de verdad sea rechazada porque
--      las horas de ese día salgan negativas.
--   2. Que ese día no se pague en silencio como cero: queda sellado para
--      revisión y aparece en Correcciones.
--   3. Que nada cambie para un día normal — ni un valor, ni una fila.
--
-- QUÉ ASUME
--   · `fn_recalcular_jornada` vigente en la 0240 — confirmado con donde-vive.sh
--     antes de copiar.
--
--     md5 DE PARTIDA: NO SE TOMÓ. Esta migración se pegó antes de pedírselo a
--     producción, y `create or replace` ya había reescrito el cuerpo cuando se
--     fue a buscar: el número anterior no existe en ningún lado. Queda escrito
--     porque una migración de este repo tiene que decir la verdad sobre cómo se
--     aplicó, y porque el de llegada NO lo sustituye — sale idéntico partas de
--     donde partas, así que no prueba de qué versión se partió.
--
--     md5 de llegada: c50fa2ed18d61ef7ad304fd554fba4cc — medido en producción
--     el 2026-08-14, idéntico al del Postgres local con esta migración puesta.
--     El local partía de la 0240 (230a121d4ab7aaa121fb0703c5bafcfa).
--
--     Lo que sostiene que producción también estaba en la 0240, a falta del
--     md5 de partida: el error que rechazaba las salidas era exactamente el
--     comportamiento de la 0240, y su bloque de comprobación devolvió sus tres
--     `true` ese mismo día. Es indicio, no garantía. La garantía era el número.
--   · `chk_horas_no_negativas` (0095), que se queda tal cual: sigue siendo
--     imposible guardar un día con horas negativas.
--   · El sello `estado_revision = 'pendiente_revision'` (0068/0082) y el trigger
--     `trg_marcajes_recalcular_jornada`, que es AFTER INSERT OR UPDATE FOR EACH ROW.
--
-- POR QUÉ EXISTE — MEDIDO EL 2026-08-14
--
--   El 13 de agosto, dos salidas del terminal quedaron apartadas en la cola de
--   una Mac con este error, repetido seis veces cada una:
--
--       new row for relation "jornadas" violates check constraint
--       "chk_horas_no_negativas"
--
--   La cuenta de las horas es (salida − entrada) − ausencia. Si las pausas de un
--   día suman más que el tramo entre la entrada y la salida —una corrección con
--   la hora mal tecleada basta—, la resta da negativo. El CHECK de la 0095 hace
--   bien su trabajo: un día no puede restar horas de la planilla.
--
--   Pero ese `insert` en `jornadas` no ocurre solo: lo dispara el trigger de
--   `marcajes`. La excepción sube por el trigger y REVIENTA EL INSERT DEL
--   MARCAJE. O sea que el efecto real no era «esta jornada no se guarda», era
--   «esta persona no puede marcar su salida». El terminal, que decide entrada o
--   salida por el estado abierto, le seguía ofreciendo «Salida» toda la noche;
--   cada intento se iba a la cola y a los seis rechazos se apartaba.
--
--   Reproducido literal contra el Postgres local, dentro de BEGIN … ROLLBACK:
--
--       entrada           2026-08-10 09:00
--       salida_almuerzo   2026-08-10 09:30
--       retorno_almuerzo  2026-08-10 23:30   ← corrección con la hora mal puesta
--       salida_final      2026-08-10 20:00   ← RECHAZADA
--
--       horas = 11.00 − 14.00 = −3.00   →   chk_horas_no_negativas
--
--   Y ahí choca con lo que este repositorio tiene escrito desde el principio:
--   los marcajes son la fuente de verdad y son append-only. La 0068 lo dejó
--   dicho y la 0207 lo repitió — «perder el registro de alguien que sí estuvo es
--   peor que un día pagado que no cuadra». La 0240 arregló este mismo choque
--   para quien cruza la medianoche; esta arregla la otra puerta.
--
-- LA DECISIÓN: NULL, NO CERO — Y NUNCA CALLADO
--
--   Un negativo deja de guardarse; en su lugar va `null`. Cero diría «no
--   trabajó», que es falso y además es un dato con el que se puede pagar. Null
--   dice «no se sabe cuánto», que es la verdad. Es lo mismo que hizo la 0095
--   cuando limpió los negativos que ya existían.
--
--   Y como la planilla lee `coalesce(horas_trabajadas, 0)`, un null SE PAGA
--   COMO CERO mientras nadie lo mire. Por eso la mitad que no se puede omitir es
--   el sello: las marcas de ese día pasan a `pendiente_revision` y el día
--   aparece en Correcciones. Arreglar el rechazo sin el sello habría cambiado
--   una marca perdida a gritos por un descuento en silencio, que es peor.
--
--   Lo que NO hace esta migración, a propósito: adivinar cuál de las marcas está
--   mal. Eso lo decide una persona mirando el día, que es la regla de siempre —
--   Dynamic avisa, nunca corrige solo lo que toca dinero.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar el cuerpo de `fn_recalcular_jornada` de la 0240. El CHECK
--   no se toca, así que no hay nada que deshacer en el esquema. Las marcas que
--   esta migración haya sellado se quedan en `pendiente_revision`: son días que
--   de verdad hay que mirar, y quitarles el sello es cosa de Correcciones.
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
  v_sujeta_a_horario boolean;   -- 0191: un locador no tiene hora de entrada
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
  -- sistema tampoco debe medírsela. Ver el encabezado de la 0191.
  select p.en_planilla into v_sujeta_a_horario from personas p where p.id = p_persona_id;

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
  if coalesce(v_sujeta_a_horario, false)
     and v_entrada_ts is not null and v_hora_entrada_prog is not null then
    v_hora_entrada_esperada := (p_fecha + v_hora_entrada_prog) at time zone 'America/Lima';
    v_minutos_tarde := greatest(0, floor(extract(epoch from (v_entrada_ts - v_hora_entrada_esperada)) / 60)::int);
    -- Acá se ponía `v_minutos_tarde := null`. Ya no: el número se guarda
    -- siempre y quién puede sancionar con él lo decide fn_tardanza_es_medible.
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

  -- salida anticipada: cerró el día antes de su hora de salida programada.
  -- Tolerancia de 15 min: dentro de 15 min de su hora no se marca (queda en 0).
  -- No se mide mientras el auto-cierre siga SIN REVISAR: esa hora la inventó el
  -- sistema y medir contra ella sería acusar con un dato falso. En cuanto una
  -- persona la confirma o la corrige, la hora es real y el día se mide entero.
  v_minutos_temprano := null;
  if coalesce(v_sujeta_a_horario, false)
     and v_salida_final_ts is not null and v_hora_salida_prog is not null
     and not (v_salida_final_origen = 'auto_cierre'
              and v_salida_final_revision = 'pendiente_revision') then
    v_hora_salida_esperada := (p_fecha + v_hora_salida_prog) at time zone 'America/Lima';
    v_minutos_temprano := greatest(0, round(extract(epoch from (v_hora_salida_esperada - v_salida_final_ts)) / 60)::int);
    -- Misma corrección en la salida temprana. Esta segunda instancia no
    -- estaba en el hallazgo: arreglar solo la de la entrada dejaba la mitad.
    if v_minutos_temprano <= 15 then v_minutos_temprano := 0; -- dentro de la tolerancia
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
values (249, 'una_salida_real_siempre_se_puede_registrar')
on conflict (numero) do nothing;


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  (select prosrc like '%v_horas_imposibles%'
     from pg_proc where proname = 'fn_recalcular_jornada')
    as el_negativo_ya_no_tumba_la_marca,
  (select prosrc like '%pendiente_revision%'
     from pg_proc where proname = 'fn_recalcular_jornada')
    as el_dia_imposible_queda_sellado,
  exists (select 1 from pg_constraint
           where conname = 'chk_horas_no_negativas'
             and conrelid = 'jornadas'::regclass)
    as el_candado_de_la_0095_sigue_puesto;
