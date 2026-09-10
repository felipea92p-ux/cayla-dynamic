-- 0413_a_un_practicante_ya_se_le_mide_la_tardanza.sql
--
-- QUÉ PROMETE: a un practicante (tipo_vinculo = 'practicante') se le calcula
--   minutos_tarde y minutos_salida_temprana como a cualquiera de planilla,
--   para que Desempeño, el exportador y el espejo a Google Sheets puedan
--   mostrar su asistencia real. Lo que NO promete es que eso dispare
--   disciplina: fn_expediente_generar_tardanza gana su propio candado, y
--   fn_tardanzas_resumen —el semáforo de Disciplina, que ya filtra
--   en_planilla=true— sigue sin ver a ningún practicante, porque en_planilla
--   se queda en false para él (0085: columna generada desde tipo_vinculo).
--
-- QUÉ ASUME:
--   · Que un practicante SÍ debe tener su llegada registrada de forma
--     informativa: la Ley 28518 (art. 41.3) lo obliga a "observar las normas
--     y reglamentos que rijan en el centro de trabajo", y el propio convenio
--     fija una jornada (art. 44). Medir esa jornada no es lo mismo que
--     disciplinarla — eso último sigue prohibido, por lo mismo que ya
--     protege a un RxH (0119, 0191): "generar tardanzas y expedientes es
--     fiscalizar una conducta, y eso es prueba de subordinación (art. 9 del
--     D.S. 003-97-TR)". Un RxH sigue completamente fuera: no tiene jornada
--     que la ley le fije, así que a él no se le mide nada.
--   · Que un RxH y un no_trabajador siguen sin medirse — nada cambia para
--     ellos.
--   · Que el dinero de planilla no se toca: fn_planilla_calcular no
--     referencia minutos_tarde ni minutos_salida_temprana en ninguna
--     migración (confirmado por auditoría del repo completo). CTS,
--     gratificación, vacaciones y AFP de un practicante siguen en cero
--     porque dependen de en_planilla, que esta migración NO toca.
--   · Que Incidencias es la única superficie que convierte el número en una
--     decisión automática del sistema ("incidencia alta" con 3+ tardanzas en
--     30 días) — el tipo de fiscalización activa que si es más riesgosa que
--     mostrar el dato. Por eso esa pantalla gana su propio filtro en el
--     mismo commit (apps/web/app/(admin)/admin/incidencias/page.tsx), para
--     que el aviso automático se quede exclusivo de quien sí está en_planilla.
--
-- POR QUÉ SE ELIGIÓ ASÍ: separar "medir" (informativo) de "disciplinar"
--   (formal) en vez de encender en_planilla para practicante. Encender
--   en_planilla habría arrastrado CTS/gratificación/vacaciones/AFP —
--   beneficios que la Ley 28518 le niega expresamente a un practicante
--   (arts. 3, 47) — y habría revertido en silencio ocho migraciones que ya
--   construyeron excepciones puntuales para él (0322, 0333, 0336, 0397,
--   entre otras) siguiendo el patrón `en_planilla or tipo_vinculo =
--   'practicante'`. Esta migración usa exactamente ese mismo patrón, en el
--   escritor y en ningún otro lado.
--
--   Auditoría previa a escribir esto: se revisaron TODOS los consumidores de
--   minutos_tarde/minutos_salida_temprana (SQL y frontend). Los que ya
--   filtran por en_planilla=true (fn_tardanzas_resumen, dashboard,
--   reporte-sede) siguen protegidos sin tocarlos. fn_jornadas_extra no
--   filtra por en_planilla pero tampoco decide nada por sí sola: solo
--   alimenta pantallas, y la única que convertía su número en una decisión
--   automática (Incidencias) se cierra en esta misma migración.
--
-- CÓMO SE REVIERTE: volver a `select p.en_planilla into v_sujeta_a_horario`
--   en fn_recalcular_jornada (sin el `or tipo_vinculo = 'practicante'`),
--   quitar el candado nuevo de fn_expediente_generar_tardanza, y revertir el
--   filtro de Incidencias. El backfill de abajo no hace falta deshacerlo: un
--   recálculo de más no daña nada, y los días de un practicante volverían a
--   dar minutos_tarde = null la próxima vez que algo dispare su recálculo.
--
-- ── fn_recalcular_jornada ────────────────────────────────────────────────
-- VIGENTE EN: 0327_el_candado_de_horas_pasa_a_ser_por_grupo.sql (confirmado
--   con ./scripts/donde-vive.sh fn_recalcular_jornada). Cuerpo copiado con
--   pg_get_functiondef del Postgres local, que coincide byte a byte con
--   producción: md5 tal cual 3ec58d5f268e784705b3fa2048d0610c, sin
--   comentarios 0dc7e74e370e2189ceded8669c31a8c1 (confirmado contra
--   producción el 2026-09-10). Un solo cambio real: la línea que arma
--   v_sujeta_a_horario, marcada CAMBIO 0413 abajo. Los comentarios de
--   alrededor se actualizan para que sigan explicando lo que el código
--   realmente hace.
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
  -- ⇩⇩⇩ CAMBIO 0413 ⇩⇩⇩
  select p.en_planilla or p.tipo_vinculo = 'practicante' into v_sujeta_a_horario
  from personas p where p.id = p_persona_id;
  -- ⇧⇧⇧ CAMBIO 0413 ⇧⇧⇧

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

-- ── fn_expediente_generar_tardanza ──────────────────────────────────────────
-- VIGENTE EN: 0311_el_mes_cerrado_se_puede_documentar_y_el_corte_se_suma.sql
--   (confirmado con ./scripts/donde-vive.sh fn_expediente_generar_tardanza).
--   Cuerpo copiado con pg_get_functiondef del Postgres local, que coincide
--   byte a byte con producción: md5 tal cual 0622ece0145f1914de53cb059ceeb8ba,
--   sin comentarios f71d4c56f3f81f6db66680d5358702c7 (confirmado contra
--   producción el 2026-09-10). Un solo cambio: el candado nuevo justo
--   después del chequeo de permiso, marcado CAMBIO 0413 abajo.
--
--   Por qué hace falta aunque fn_tardanzas_resumen ya filtre en_planilla:
--   esta función está `grant`eada a `authenticated` y su único llamador en
--   todo el frontend (admin/disciplina/page.tsx) la alimenta ya filtrada —
--   pero nada en la base de datos se lo exige. "No confiar en el llamador,
--   blindar en la función" es el mismo principio que ya usa este repo para
--   fn_cambiar_regimen_pension, fn_set_rol y fn_set_sede_base.
CREATE OR REPLACE FUNCTION public.fn_expediente_generar_tardanza(p_persona_id uuid, p_mes date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_esc     record;
  v_ini     date;
  v_fin     date;
  v_mes_hoy date;
  v_al      date;
  v_mes_txt text;
  v_n       int;
  v_hechos  jsonb;
  v_desde   date;
  v_hasta   date;
  v_dias    int;
  v_fechas  date[];
  v_id      uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0413 ⇩⇩⇩ CANDADO PROPIO, NO SOLO EL DE LA PANTALLA QUE LLAMA.
  -- Un RxH nunca tuvo minutos_tarde poblado, así que esto no le cambia nada.
  -- Un practicante SÍ puede tener minutos_tarde desde esta misma migración
  -- (0413) — y su convenio de modalidad formativa (Ley 28518) no es relación
  -- laboral, así que no puede recibir una sanción del RIT aunque alguien
  -- llegara a llamar a esta función con su persona_id. sueldo_fijo se suma
  -- porque su pago no depende de horas y fn_tardanzas_resumen ya lo excluye
  -- por el mismo motivo.
  if not exists (
    select 1 from personas p
    where p.id = p_persona_id and p.en_planilla = true and p.sueldo_fijo = false
  ) then
    raise exception 'Esta persona no está sujeta a disciplina por tardanzas (no está en planilla, o tiene sueldo fijo).';
  end if;
  -- ⇧⇧⇧ CAMBIO 0413 ⇧⇧⇧

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- ── EL PERIODO MENSUAL CALENDARIO (arts. 19.1 a y 19.4) ──────────────────
  -- «Del día primero al último día de cada mes», y el 19.4 dice que su cierre
  -- «no impide emitir el documento». El mes es un dato del documento, no la hora
  -- a la que alguien pulsó el botón. `least(..., hoy)` para no citar un futuro.
  v_mes_hoy := date_trunc('month', fn_hoy_lima())::date;
  v_ini     := date_trunc('month', coalesce(p_mes, fn_hoy_lima()))::date;
  v_fin     := least((v_ini + interval '1 month')::date - 1, fn_hoy_lima());
  -- `to_char(..., 'TMMonth')` NO sirve acá: `lc_time` es en_US.UTF-8 y devuelve
  -- «July». El mes se nombra en español o el mensaje no sirve para nadie.
  v_mes_txt := (array['enero','febrero','marzo','abril','mayo','junio','julio',
                      'agosto','septiembre','octubre','noviembre','diciembre'])
                 [extract(month from v_ini)::int] || ' de ' || extract(year from v_ini)::int;

  if v_ini > v_mes_hoy then
    raise exception 'No se puede emitir por %: ese mes todavía no ha empezado.', v_mes_txt;
  end if;

  -- Mes en curso → nulo: la vigencia se mide contra el reloj, como hasta hoy.
  -- Mes cerrado → contra su último día.
  v_al := case when v_ini = v_mes_hoy then null else (v_ini + interval '1 month')::date - 1 end;

  select * into v_esc from fn_tardanza_escalon_al(p_persona_id, v_al);

  if v_esc.bloqueado then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  end if;

  -- ART. 19.1 a), párrafo 2: «El literal e) del numeral 19.2 NO se cuenta por
  -- periodo mensual calendario». Su supuesto i) computa toda tardanza nueva
  -- posterior a la notificación de la segunda suspensión, y el ii) tiene ventana
  -- propia de treinta días corridos. Hoy el código lo acota al mes igual
  -- —defecto preexistente— pero acotarlo a un mes ELEGIDO sería escribirlo como
  -- si fuera la regla. Se para en vez de emitir: falla cerrado.
  --
  -- La condición mira EL MES, no la forma de la llamada. Escrita como
  -- `p_mes is not null` se disparaba también sobre el mes en curso —el mismo mes
  -- que el camino por defecto documenta sin problema— y dejaba el cuarto escalón
  -- inalcanzable desde una pantalla que siempre nombra el mes.
  if v_esc.nivel_siguiente = 'imputacion' and v_ini <> v_mes_hoy then
    raise exception
      'La imputación de cargos del numeral 19.2 e) NO se cuenta por periodo mensual calendario '
      '(numeral 19.1 a): computa toda tardanza nueva posterior a la notificación de la segunda '
      'suspensión. Genérala sobre el mes en curso, no sobre uno ya cerrado.';
  end if;

  -- ART. 56.6. Se dice aparte porque «lleva 0» deja a quien lo lee sin saber qué
  -- hacer: no es que falten tardanzas, es que ese mes ya no se documenta.
  if v_esc.corte is not null and v_esc.corte >= v_fin then
    raise exception
      'El último documento de tardanzas de esta persona cubre hasta el %, y en % ya no queda '
      'ningún hecho nuevo que reprochar (numeral 56.6). Los meses se emiten del más viejo al '
      'más nuevo: este ya no alcanza.',
      to_char(v_esc.corte, 'DD/MM/YYYY'), v_mes_txt;
  end if;

  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      -- ── 1 · LA VENTANA ES EL MES CALENDARIO que se documenta (19.1 a) ────
      and j.fecha >= v_ini
      and j.fecha <= v_fin
      -- ── 2 · Y DENTRO DE ESE MES, SOLO LO NUEVO (19.1 b, 52.5, 56.6) ──────
      -- Las dos condiciones SE SUMAN. El `greatest(inicio de mes, corte + 1)`
      -- que había acá las fundía en un solo límite: ganaba la más tardía y la
      -- otra se quedaba sin ningún trabajo que hacer. De ahí salían las dos
      -- averías: el corte por antecedente sustituía al mensual, y el día 1 el
      -- mes anterior entero desaparecía del generador.
      and (v_esc.corte is null or j.fecha > v_esc.corte)
      -- Cinturón y tirantes: el corte es una fecha y puede ser null; esto es la
      -- lista nominal de días ya citados.
      and not fn_tardanza_ya_documentada(p_persona_id, j.fecha)
      -- El papel disciplinario NUNCA se arma con una medición dudosa.
      and fn_tardanza_es_medible(j.minutos_tarde) and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  if v_n < v_esc.minimo then
    raise exception 'Aún no corresponde %: en % lleva % tardanza(s) nueva(s) y su escalón exige %.%',
      v_esc.nivel_siguiente, v_mes_txt, v_n, v_esc.minimo,
      case when v_esc.corte is null then ''
           else format(' El documento anterior cubre hasta el %s; solo cuentan las posteriores a esa fecha.',
                       to_char(v_esc.corte, 'DD/MM/YYYY')) end;
  end if;

  if v_esc.nivel_siguiente = 'suspension' then
    if v_esc.suspension_previa_dias is null then
      v_dias := 1;
    elsif v_esc.suspension_previa_dias >= 3 then
      raise exception
        'La primera suspensión se registró con % días, y el numeral 19.2 c) la topa en dos. '
        'La segunda tiene que ser mayor y caber en el tope de tres del numeral 54.5, y con esa '
        'primera no hay ningún número que cumpla las dos cosas. Revisa la primera suspensión '
        'antes de seguir con la escalera.',
        v_esc.suspension_previa_dias;
    else
      v_dias := v_esc.suspension_previa_dias + 1;
    end if;
  end if;

  if v_dias is not null then
    -- OJO: arranca MAÑANA, y no en el mes documentado. La suspensión se cumple
    -- en el futuro aunque los hechos sean de junio; fijarla sobre el mes
    -- documentado la pondría en días que ya pasaron.
    begin
      select array_agg(fecha order by fecha) into v_fechas
        from fn_dias_suspension(p_persona_id, fn_hoy_lima() + 1, v_dias);
    exception when others then
      raise exception
        'No puedo fijar los días de la suspensión: esta persona no tiene un horario vigente, '
        'y sin él no se sabe qué días son laborables. El numeral 54.5 exige comunicar «los días '
        'concretos en que se cumplirá», y no se pueden poner días de descanso. Asígnale su '
        'horario en Equipo y vuelve a intentarlo.';
    end;
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_esc.nivel_siguiente, v_hechos, v_desde, v_hasta,
    v_esc.doc_previo, v_dias,
    case when v_fechas is not null then v_fechas[1] end,
    case when v_fechas is not null then v_fechas[array_length(v_fechas, 1)] end,
    null);

  if v_fechas is not null then
    update expediente_disciplinario set suspension_fechas = v_fechas where id = v_id;
  end if;

  return v_id;
end;
$function$;

-- ── Backfill: los días de practicantes ya calculados bajo el candado viejo ──
-- Sin esto, el arreglo de arriba solo se nota hacia adelante: los días de un
-- practicante calculados ANTES de esta migración se quedarían con
-- minutos_tarde/minutos_salida_temprana en null para siempre, porque nada
-- vuelve a disparar su recálculo salvo un marcaje nuevo o una corrección.
--
-- Se hace llamando a fn_recalcular_jornada tal cual —no un UPDATE a mano—
-- porque es la única fuente de verdad de esa cuenta y porque respeta solo
-- ella el candado de periodo pagado (fn_fecha_en_periodo_pagado): un mes ya
-- pagado de un practicante se queda exactamente como está, sin que este
-- backfill lo toque. Es idempotente: si esta migración se pegara dos veces
-- por error, recalcular de más no daña nada.
do $$
declare
  r record;
begin
  for r in
    select j.persona_id, j.fecha
    from jornadas j
    join personas p on p.id = j.persona_id
    where p.tipo_vinculo = 'practicante'
  loop
    perform fn_recalcular_jornada(r.persona_id, r.fecha);
  end loop;
end $$;
