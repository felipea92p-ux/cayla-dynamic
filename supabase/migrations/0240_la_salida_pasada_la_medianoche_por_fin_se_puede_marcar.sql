-- ============================================================================
-- 0240_la_salida_pasada_la_medianoche_por_fin_se_puede_marcar.sql
-- ============================================================================
-- QUÉ PROMETE
--   1. Que quien cierra tienda pasada la medianoche PUEDA marcar su salida.
--   2. Que esa salida cuente en la jornada en que entró, no en el día nuevo.
--   3. Que nada de esto cambie para quien no cruza la medianoche.
--
-- QUÉ ASUME
--   · `fn_registrar_marcaje` vigente en la 0207 y `fn_recalcular_jornada` en la
--     0191 — confirmado con donde-vive.sh antes de copiar. Ojo con esto: hasta
--     esta mañana la vigente de registrar era la 0082, y copiar de ahí habría
--     revertido en silencio el sellado de marcas en periodo pagado de la 0207.
--   · Que `jornadas.estado` distingue 'abierta' y 'en_pausa' (0001).
--
-- POR QUÉ EXISTE — C4, MEDIDO
--
--   Alguien entra a las 15:00 del martes y cierra tienda a las 00:30. Al marcar
--   su salida, el sistema mira el MIÉRCOLES, no encuentra ninguna entrada y
--   espera una `entrada`. Reproducido literal contra el Postgres local:
--
--       ERROR: tipo salida_final no válido en el estado actual (se esperaba entrada)
--
--   La salida real NO SE PUEDE REGISTRAR. Y de ahí salen dos errores de signo
--   contrario en la misma noche, los dos medidos con salario S/1500:
--
--       lo que pasó         15:00 → 00:30      9.50 h    S/ 70.72
--       martes registrado   15:00 → 23:00*     8.00 h    S/ 59.55   (*la inventó el cron)
--       miércoles fantasma  00:30 → 23:00*    22.50 h    S/167.49
--                                             ───────    ─────────
--       total registrado                      30.50 h    S/227.04
--
--   30.5 horas donde hubo 9.5. Y lo peor no es el sobrepago de S/156: es que el
--   terminal, que solo le ofrece «Entrada» porque mira las marcas de hoy, la
--   empuja a abrir el día fantasma con sus propias manos.
--
--   Este repositorio dice que los marcajes son la fuente de verdad y son
--   append-only. Aquí se rechazaba en la puerta el registro de un hecho que
--   ocurrió — que es la forma más cara de perder un dato.
--
-- LA DECISIÓN DE FONDO (Felipe, 2026-08-13): LAS HORAS VAN AL DÍA EN QUE ENTRÓ
--
--   Se evaluó partirlas por la medianoche —8 h al martes, 0.5 al miércoles— y se
--   descartó por una razón que no es de gusto: PARTIR OBLIGA A INVENTAR DOS
--   MARCAS que nadie hizo, una salida a las 23:59:59 y una entrada a las
--   00:00:00. El problema de C4 es justamente que el sistema inventa una hora;
--   arreglarlo inventando dos más sería cambiar un dato falso por otros dos.
--
--   La opción elegida no inventa nada: toma las dos marcas reales y dice que son
--   del mismo turno. Es como lo cuenta una persona — «anoche salí tarde».
--
--   Lo que se pierde con esta elección, medido para no esconderlo: si el martes
--   es feriado, la media hora ya del miércoles se trata como feriado. Son unos
--   S/3.70 y a favor de la persona.
--
-- CÓMO SE HACE, Y POR QUÉ ES UN CAMBIO PEQUEÑO
--
--   Una columna, `marcajes.fecha_jornada`, que solo lleva valor cuando la marca
--   pertenece a la jornada de OTRO día. Null en el 99 % de los casos: así la
--   columna dice «esto es una excepción» en vez de repetir lo que el timestamp
--   ya sabe, y todo lo que hoy agrupa por fecha de calendario sigue funcionando
--   igual mientras no la mire.
--
--   En `fn_registrar_marcaje` basta con REASIGNAR `v_fecha` a la jornada abierta:
--   el candado de periodo pagado, la detección de marca atrasada y la validación
--   de secuencia se acomodan solos, porque todos ya trabajan sobre `v_fecha`.
--
--   Y en `fn_recalcular_jornada`, dos predicados pasan de mirar la fecha del
--   timestamp a mirar `coalesce(fecha_jornada, esa fecha)`.
--
-- QUÉ NO SE TOCA
--   Ni el cálculo de horas, ni la tardanza, ni el auto-cierre, ni la planilla.
--   Y una `entrada` de madrugada sigue abriendo un día nuevo: puede ser alguien
--   empezando su turno, y confundir eso sería cambiar un error por otro.
--
-- CÓMO SE REVIERTE
--   Restaurar las dos funciones desde la 0207 y la 0191. La columna puede
--   quedarse: sin nadie que la escriba, es null y no cambia nada.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve una fila con tres `true`.
-- ============================================================================

-- ── 1 · A qué jornada pertenece una marca ──────────────────────────────────
alter table marcajes
  add column if not exists fecha_jornada date;

comment on column marcajes.fecha_jornada is
  'Solo cuando la marca pertenece a la jornada de OTRO día: quien cruza la medianoche. Null en todo lo demás, y entonces manda la fecha de Lima del timestamp. Desde la 0240.';

-- El índice que el recálculo va a usar. Parcial a propósito: solo hay filas con
-- valor cuando alguien cruzó la medianoche, así que ocupa casi nada.
create index if not exists idx_marcajes_fecha_jornada
  on marcajes (persona_id, fecha_jornada)
  where fecha_jornada is not null;


-- ── 2 · La salida de madrugada encuentra su jornada ────────────────────────
-- Cuerpo de la 0207 (la vigente) copiado con script. El diff contra el original
-- son puras líneas añadidas salvo las dos del `insert`, que solo ganan una coma.
CREATE OR REPLACE FUNCTION public.fn_registrar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_timestamp_cliente timestamp with time zone, p_client_uuid uuid, p_origen origen_marca DEFAULT 'terminal'::origen_marca, p_terminal_id uuid DEFAULT NULL::uuid, p_sede_id uuid DEFAULT NULL::uuid, p_motivo_otro text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sede_id uuid;
  v_marcaje marcajes;
  v_existente marcajes;
  v_fecha date;
  v_esperado tipo_marca;
  v_caller_rol rol_usuario;
  v_terminal_auth uuid;
  v_ultimo_ts timestamptz;
  v_atrasada boolean;
  v_en_pagado boolean;     -- 0207: ¿esta marca cae dentro de un periodo ya pagado?
  v_cruzo_medianoche boolean := false;  -- 0240: ¿cierra una jornada del día anterior?
  v_jornada_abierta date;               -- 0240: y de qué día es esa jornada
begin
  -- Idempotencia: reintentos offline con el mismo client_uuid no duplican.
  select * into v_existente from marcajes where client_uuid = p_client_uuid;
  if found then
    return v_existente;
  end if;

  if p_origen = 'terminal' then
    if p_terminal_id is null then
      raise exception 'p_terminal_id es obligatorio cuando origen = terminal';
    end if;
    select sede_id, auth_user_id into v_sede_id, v_terminal_auth
    from terminales where id = p_terminal_id and activo;
    if v_sede_id is null then
      raise exception 'terminal % no encontrado o inactivo', p_terminal_id;
    end if;
    if auth.uid() is not null and v_terminal_auth is not null and auth.uid() <> v_terminal_auth then
      raise exception 'el terminal autenticado no coincide con p_terminal_id';
    end if;
  else
    if p_sede_id is null then
      raise exception 'p_sede_id es obligatorio cuando origen != terminal';
    end if;
    select rol into v_caller_rol from personas where auth_user_id = auth.uid();
    if v_caller_rol is null or v_caller_rol not in ('admin', 'lider_do', 'supervisor_sede') then
      raise exception 'no autorizado para registrar marcajes con origen %', p_origen;
    end if;
    if v_caller_rol = 'supervisor_sede' then
      if not exists (
        select 1 from personas
        where auth_user_id = auth.uid() and sede_base_id = p_sede_id
      ) then
        raise exception 'un supervisor_sede solo puede corregir marcajes de su propia sede';
      end if;
    end if;
    v_sede_id := p_sede_id;
  end if;

  if p_tipo = 'salida_otro' and (p_motivo_otro is null or length(trim(p_motivo_otro)) < 3) then
    raise exception 'motivo_otro es obligatorio para salida_otro';
  end if;

  v_fecha := (p_timestamp_cliente at time zone 'America/Lima')::date;

  -- ⇩⇩⇩ CAMBIO 0240 ⇩⇩⇩ LA JORNADA MANDA, NO EL CALENDARIO.
  --
  -- Quien cierra tienda a las 00:30 no podía marcar su salida: el sistema miraba
  -- el día NUEVO, no encontraba ninguna entrada y esperaba una `entrada`. La
  -- salida real se rechazaba en la puerta —medido: «tipo salida_final no válido
  -- en el estado actual (se esperaba entrada)»— y de ahí salían DOS errores de
  -- signo contrario: el día anterior lo cerraba el cron con la hora programada
  -- (le faltaban 1.5 h de las que trabajó) y nacía un día fantasma que el cron
  -- cerraba en 22.5 h. En una sola noche: 30.5 h registradas donde hubo 9.5.
  --
  -- Con esto, esa marca pertenece a la JORNADA que sigue abierta, aunque el
  -- calendario ya haya cambiado de día. No se inventa nada: se usan las dos
  -- marcas reales y se dice que son del mismo turno, que es como lo cuenta una
  -- persona — «anoche salí tarde».
  --
  -- SOLO PARA SALIDAS Y RETORNOS. Una `entrada` a las 00:30 abre un día nuevo
  -- como siempre: puede ser alguien empezando su turno, y confundir eso sería
  -- cambiar un error por otro.
  --
  -- EL TOPE DE 16 HORAS es lo que impide que una jornada que alguien olvidó
  -- cerrar se coma el día siguiente. Pasado ese tope, la marca vuelve a ser del
  -- día que dice el calendario y el auto-cierre hace su trabajo.
  if p_tipo::text like 'salida\_%' escape '\' or p_tipo::text like 'retorno\_%' escape '\' then
    select j.fecha into v_jornada_abierta
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha < v_fecha
      and j.estado in ('abierta', 'en_pausa')
      and j.entrada_ts is not null
      and p_timestamp_cliente <= j.entrada_ts + interval '16 hours'
    order by j.fecha desc
    limit 1;

    if found then
      v_fecha := v_jornada_abierta;
      v_cruzo_medianoche := true;
    end if;
  end if;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ ¿Cae dentro de un periodo ya pagado?
  -- Se calcula acá arriba, una sola vez, porque hace falta en los DOS caminos
  -- por los que esta función deja una marca: el insert del final y la
  -- reconciliación del auto-cierre, que retorna antes de llegar a él.
  --
  -- Lo que NO se hace con esto es rechazar. La 0068 ya lo dejó escrito: la
  -- terminal reintenta seis veces y acaba descartando la marca. Perder el
  -- registro de alguien que sí estuvo es peor que un día pagado que no cuadra.
  select exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) into v_en_pagado;

  -- ¿LLEGA ATRASADA? Su hora es anterior a la última ya registrada de ese día:
  -- viene de la cola offline. No se le puede aplicar la validación de secuencia
  -- (se juzgaría contra un presente que no le corresponde, se rechazaría, y la
  -- terminal acabaría borrándola tras 6 reintentos). Se acepta siempre.
  select max(timestamp_marca) into v_ultimo_ts
  from marcajes
  where persona_id = p_persona_id
    and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and anulada_at is null;

  v_atrasada := v_ultimo_ts is not null and p_timestamp_cliente < v_ultimo_ts;

  -- Marcas EN VIVO: candado anti-doble-marcado de siempre, intacto.
  if p_origen = 'terminal' and not v_atrasada then
    v_esperado := fn_siguiente_tipo_esperado(p_persona_id, v_fecha);
    if v_esperado is not null and v_esperado <> p_tipo then
      raise exception 'tipo % no válido en el estado actual (se esperaba %)', p_tipo, v_esperado;
    end if;
    if v_esperado is null and p_tipo not in (
      'salida_final', 'salida_almuerzo', 'salida_personal', 'salida_tramite', 'salida_medico', 'salida_otro'
    ) then
      raise exception 'tipo % no válido: la jornada ya está cerrada o requiere elegir un tipo de salida', p_tipo;
    end if;
  end if;

  -- Reconciliación: una salida_final real que llega después de un auto-cierre
  -- sintético del mismo día reemplaza el registro sintético, no lo duplica.
  if p_tipo = 'salida_final' then
    select * into v_existente
    from marcajes
    where persona_id = p_persona_id
      and tipo = 'salida_final'
      and origen = 'auto_cierre'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null;

    if found then
      update marcajes set
        timestamp_marca = p_timestamp_cliente,
        origen = p_origen,
        -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ Este es el camino delicado, y el que se olvida:
        -- cambia la HORA de una marca que ya existía dentro del periodo pagado,
        -- y además ponía 'normal' a secas, borrando cualquier sello previo.
        estado_revision = case when v_en_pagado then 'pendiente_revision'::estado_revision
                               else 'normal'::estado_revision end,
        client_uuid = p_client_uuid,
        terminal_id = p_terminal_id,
        server_received_at = now()
      where id = v_existente.id
      returning * into v_marcaje;

      return v_marcaje;
    end if;
  end if;

  insert into marcajes (
    client_uuid, persona_id, sede_id, terminal_id, tipo, motivo_otro, timestamp_marca, origen,
    -- 0240: solo lleva valor cuando la marca pertenece a la jornada de OTRO día.
    -- Null en todo lo demás, que es el 99 % de los casos: así la columna dice
    -- «esto es una excepción» en vez de repetir lo que el timestamp ya sabe.
    fecha_jornada
  ) values (
    p_client_uuid, p_persona_id, v_sede_id, p_terminal_id, p_tipo, p_motivo_otro, p_timestamp_cliente, p_origen,
    case when v_cruzo_medianoche then v_fecha else null end
  )
  returning * into v_marcaje;

  -- ⇩⇩⇩ CAMBIO 0207 ⇩⇩⇩ La marca entra, pero no entra muda.
  -- Solo se sella ELLA y no el día entero: el día ya se pagó y su jornada es
  -- correcta como foto de lo que se pagó — lo anómalo es la recién llegada.
  if v_en_pagado then
    update marcajes set estado_revision = 'pendiente_revision' where id = v_marcaje.id;
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  -- ¿El día quedó IMPOSIBLE al ordenarlo por hora? Entonces se sella para que
  -- aparezca en Correcciones. No se pierde nada, pero deja de estar en silencio.
  -- Solo se sella si de verdad quedó roto: una marca atrasada que encaja bien
  -- en la secuencia no genera ninguna alarma.
  if fn_dia_incoherente(p_persona_id, v_fecha) then
    update marcajes
      set estado_revision = 'pendiente_revision'
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and estado_revision = 'normal';
    select * into v_marcaje from marcajes where id = v_marcaje.id;
  end if;

  return v_marcaje;
end;
$function$;


-- ── 3 · Y el recálculo agrupa por jornada, no por calendario ───────────────
-- Cuerpo de la 0191 (la vigente). Cambian DOS predicados y nada más.
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
end;
$function$;


-- ── 4 · Y el trigger recalcula la jornada correcta ─────────────────────────
-- Cuerpo de la 0102 (la vigente).
CREATE OR REPLACE FUNCTION public.fn_trg_marcajes_recalcular_jornada()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_fecha_vieja date; v_fecha_nueva date;
begin
  -- 0240 · La jornada manda. `fecha_jornada` solo trae valor cuando la marca
  -- cierra una jornada abierta del día anterior; si no, esto es idéntico a antes.
  -- Sin esta línea la marca de madrugada se guarda bien y NO SIRVE DE NADA: se
  -- recalcularía el día nuevo, y la jornada que debía cerrarse se queda abierta.
  -- Medido: la marca entraba con su fecha_jornada correcta y la jornada del
  -- martes seguía en «abierta» sin salida.
  v_fecha_nueva := coalesce(new.fecha_jornada, (new.timestamp_marca at time zone 'America/Lima')::date);

  if tg_op = 'UPDATE' then
    v_fecha_vieja := coalesce(old.fecha_jornada, (old.timestamp_marca at time zone 'America/Lima')::date);
    -- La marca cambió de día, o cambió de persona: el día que abandona también
    -- tiene que rehacerse, o se queda cobrando horas que ya no le corresponden.
    if v_fecha_vieja is distinct from v_fecha_nueva
       or old.persona_id is distinct from new.persona_id then
      perform fn_recalcular_jornada(old.persona_id, v_fecha_vieja);
    end if;
  end if;

  perform fn_recalcular_jornada(new.persona_id, v_fecha_nueva);
  return new;
end;
$function$
;

notify pgrst, 'reload schema';

insert into migraciones_aplicadas (numero, nombre)
values (240, 'la_salida_pasada_la_medianoche_por_fin_se_puede_marcar')
on conflict (numero) do nothing;


-- ── Comprobación de que la pegada llegó entera ──────────────────────────────
select
  exists (select 1 from information_schema.columns
           where table_name = 'marcajes' and column_name = 'fecha_jornada')
    as existe_la_columna,
  (select prosrc like '%v_cruzo_medianoche%'
     from pg_proc where proname = 'fn_registrar_marcaje')
    as la_salida_encuentra_su_jornada,
  (select prosrc like '%coalesce(fecha_jornada%'
     from pg_proc where proname = 'fn_recalcular_jornada')
    as el_recalculo_agrupa_por_jornada;
