-- ============================================================================
-- 0189_una_tardanza_de_tres_horas_deja_de_desaparecer.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que ninguna tardanza se borre por ser grande. El número se guarda siempre;
--   quién puede usarlo para sancionar lo decide una sola función.
--
-- QUÉ ASUME
--   Nada nuevo. Ni una tabla, ni una columna, ni un permiso cambian.
--
-- ── EL PROBLEMA, Y DE DÓNDE VIENE ───────────────────────────────────────────
--
-- Desde el 2026-07-11, con la migración 0013 —«Turnos rotativos por día
-- (Trujillo)»— `fn_recalcular_jornada` lleva esta línea:
--
--     if v_minutos_tarde > 180 then v_minutos_tarde := null; end if;
--                                   -- implausible: turno distinto, no medible
--
-- La intención era buena y sigue siendo buena. Con turnos rotativos, si el
-- sistema tiene cargado el turno equivocado para ese día, la «tardanza» sale de
-- cinco horas y no significa nada. Guardarla sería acusar a alguien por un error
-- de configuración — el falso positivo que este proyecto define como su peor
-- error.
--
-- EL DEFECTO NO ES LA INTENCIÓN: ES QUE `NULL` QUEDÓ SIGNIFICANDO DOS COSAS.
--
--     null  =  «no había horario, no aplica»          → correcto ignorarlo
--     null  =  «llegó más de tres horas tarde»        → NO es lo mismo
--
-- Y los tres consumidores filtran `minutos_tarde is not null`, así que leen el
-- segundo caso como el primero. Resultado, tal cual: quien llega 20 minutos
-- tarde queda registrado en el semáforo y en su expediente; quien llega tres
-- horas y media desaparece de los dos. Cuanto más tarde llega una persona,
-- menos la ve el sistema.
--
-- SON DOS LÍNEAS, NO UNA. La misma destrucción existe para la salida temprana
-- (`v_minutos_temprano`), desde la 0017. El hallazgo original solo nombraba la
-- de la entrada: arreglar esa sola habría dejado la mitad del daño en pie y con
-- el ticket cerrado, que es peor que no haberlo tocado.
--
-- ── CÓMO SE ARREGLA, Y POR QUÉ ASÍ ──────────────────────────────────────────
--
-- Se desenredan las dos cosas que hoy viajan en el mismo campo:
--
--   · GUARDAR es medir. `fn_recalcular_jornada` anota el número real, siempre.
--   · SANCIONAR es decidir. `fn_tardanza_es_medible(minutos)` dice si esa
--     medición es lo bastante creíble para actuar sobre ella, y vive en UN solo
--     sitio — hasta hoy el 180 estaba escrito dentro de la función que lo
--     destruía, y al dejar de destruirlo hacía falta en tres funciones más.
--
-- QUÉ CAMBIA PARA CADA QUIEN, medido y no supuesto:
--
--   fn_expediente_generar_tardanza — NADA. Sigue sin imputar sobre una medición
--     dudosa. Antes por accidente (era null), ahora dicho.
--   fn_calcular_bono_puntualidad   — NADA, y a propósito. Al guardar el número
--     real, esos días habrían pasado a descontar el bono de alguien cuyo turno
--     estaba mal cargado. Se conserva el comportamiento de hoy, escrito.
--   fn_tardanzas_resumen           — devuelve una columna nueva, `sin_medir`:
--     los días de más de tres horas. NO suman al umbral legal del D.S.
--     003-97-TR —no se sanciona con una medición dudosa— pero dejan de ser
--     invisibles, y quien tiene cero tardanzas medibles y tres días sin medir
--     ahora aparece en la pantalla, cuando antes no salía en absoluto.
--
-- Ese es el punto entero: el sistema deja de decidir por su cuenta que un caso
-- raro no existe, y pasa a mostrárselo a una persona. «Dynamic avisa, nunca
-- sanciona solo» — hasta hoy, en este caso, ni avisaba.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ───────────────────────────────────────────
--
-- No corrige el pasado. Las jornadas ya calculadas conservan su `null`, y no hay
-- forma de distinguir retroactivamente «no había horario» de «llegó tardísimo»:
-- esa información se destruyó cuando se guardó. Se arregla sola en cuanto un
-- día se recalcula, y los periodos ya pagados no se recalculan nunca (0138).
-- Para saber cuántos días hay así en producción, la consulta está al final.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Devolviendo las dos líneas `:= null` a fn_recalcular_jornada y quitando
--   `sin_medir` de fn_tardanzas_resumen. Revertir significa aceptar que llegar
--   tres horas tarde sea invisible.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final devuelve el reparto real de producción.
-- ============================================================================

-- ── El umbral, en un solo sitio ──────────────────────────────────────────────
-- Hasta hoy el 180 vivía escrito dentro de fn_recalcular_jornada y en ningún
-- otro lado, porque el número se destruía ahí mismo. Al dejar de destruirlo hace
-- falta en tres funciones más, y tres copias de un número es cómo se arregla una
-- y se olvidan dos. Vive acá.
create or replace function public.fn_tardanza_es_medible(p_minutos int)
returns boolean
language sql immutable
as $function$
  -- Por encima de tres horas la medición no es creíble como tardanza: casi
  -- siempre significa que ese día la persona tenía OTRO turno y el sistema
  -- comparó contra el equivocado. No es un número falso — es un número que no
  -- se puede usar para sancionar sin que alguien lo mire.
  select p_minutos is not null and p_minutos <= 180;
$function$;

-- ── fn_recalcular_jornada · deja de destruir el número ──────────────────────
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
  if v_salida_final_ts is not null and v_hora_salida_prog is not null
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

-- ── fn_expediente_generar_tardanza · no imputa sobre una medición dudosa ────
CREATE OR REPLACE FUNCTION public.fn_expediente_generar_tardanza(p_persona_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prev      record;
  v_has_prev  boolean := false;
  v_vigente   boolean := false;
  v_cutoff    date := date '2000-01-01';
  v_nivel     text;
  v_n         int;
  v_hechos    jsonb;
  v_desde     date;
  v_hasta     date;
  v_id        uuid;
begin
  if not fn_expediente_puede_actuar(p_persona_id, 'amonestacion') then
    raise exception 'Sin permiso para generar sanciones de tardanza para esta persona.';
  end if;

  if exists (select 1 from expediente_disciplinario
             where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado = 'borrador') then
    raise exception 'Ya hay un borrador de tardanza pendiente para esta persona; revísalo o anúlalo antes de generar otro.';
  end if;

  -- último documento de tardanza firmado (o entregado)
  select id, nivel, periodo_hasta, firmado_at into v_prev
  from expediente_disciplinario
  where persona_id = p_persona_id and tipo_causal = 'tardanza' and estado in ('firmado','entregado')
  order by firmado_at desc limit 1;
  v_has_prev := found;

  if v_has_prev then
    v_vigente := v_prev.firmado_at >= now() - interval '12 months';
    if v_vigente and v_prev.periodo_hasta is not null then v_cutoff := v_prev.periodo_hasta; end if;
  end if;

  -- tardanzas del MES en curso, POSTERIORES al cutoff, no levantadas (non bis in idem)
  select jsonb_agg(jsonb_build_object('fecha', fecha, 'minutos', minutos_tarde) order by fecha),
         count(*), min(fecha), max(fecha)
    into v_hechos, v_n, v_desde, v_hasta
  from (
    select j.fecha, j.minutos_tarde
    from jornadas j
    where j.persona_id = p_persona_id
      and j.fecha >= greatest(date_trunc('month', fn_hoy_lima())::date, v_cutoff + 1)
      and j.fecha <= fn_hoy_lima()
      -- `fn_tardanza_es_medible` reemplaza al viejo `is not null`: el papel
      -- disciplinario NUNCA se arma con una medición dudosa.
      and fn_tardanza_es_medible(j.minutos_tarde) and j.minutos_tarde > 0
      and not exists (select 1 from tardanzas_justificadas tj
                      where tj.persona_id = p_persona_id and tj.fecha = j.fecha)
  ) t;
  v_n := coalesce(v_n, 0);

  -- decidir el nivel según el historial (RIT art. 7 b/c/d)
  if v_vigente and v_prev.nivel = 'imputacion' then
    raise exception 'Ya hay una imputación de cargos vigente; el despido se genera tras evaluar los descargos (paso manual de Gerencia).';
  elsif v_vigente and v_prev.nivel = 'suspension' then
    if v_n < 1 then raise exception 'No corresponde: no hay tardanzas nuevas tras la suspensión.'; end if;
    v_nivel := 'imputacion';                                    -- umbral d
  elsif v_vigente and v_prev.nivel = 'amonestacion' then
    if v_n < 2 then raise exception 'Aún no corresponde suspensión: necesita 2 tardanzas nuevas tras la amonestación (lleva %).', v_n; end if;
    v_nivel := 'suspension';                                    -- umbral c
  else
    if v_n < 3 then raise exception 'Aún no corresponde amonestación: necesita 3 tardanzas en el mes (lleva %).', v_n; end if;
    v_nivel := 'amonestacion';                                  -- umbral b
  end if;

  v_id := fn_expediente_crear_borrador(
    p_persona_id, 'tardanza', v_nivel, v_hechos, v_desde, v_hasta,
    case when v_has_prev then v_prev.id else null end,
    -- suspensión: default 1 día al día siguiente, EDITABLE antes de firmar
    case when v_nivel = 'suspension' then 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    case when v_nivel = 'suspension' then fn_hoy_lima() + 1 else null end,
    null);

  return v_id;
end;
$function$;

-- ── fn_tardanzas_resumen · los días sin medir dejan de ser invisibles ───────
-- Devuelve TABLE, y Postgres no deja agregarle una columna con `create or
-- replace`: hay que borrarla y volver a crearla. Es la segunda forma de
-- definir que documenta donde-vive.sh.
drop function if exists public.fn_tardanzas_resumen(date);
CREATE OR REPLACE FUNCTION public.fn_tardanzas_resumen(p_as_of date DEFAULT NULL::date)
 RETURNS TABLE(persona_id uuid, nombre text, sede text, tardanzas_mes integer, umbral text, ultima_fecha date, sin_medir integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with medibles as (
    select pe.id, pe.nombres || ' ' || pe.apellidos as nombre, s.codigo as sede,
      -- Corte: el periodo del último memo de tardanza YA firmado/entregado, vigente
      -- 12 meses. Las tardanzas de esa fecha o antes NO se vuelven a alertar.
      (select e.periodo_hasta
       from expediente_disciplinario e
       where e.persona_id = pe.id and e.tipo_causal = 'tardanza'
         and e.estado in ('firmado', 'entregado')
         and e.firmado_at >= now() - interval '12 months'
       order by e.firmado_at desc
       limit 1) as corte
    from personas pe join sedes s on s.id = pe.sede_base_id
    where pe.estado = 'activo' and pe.en_planilla = true and pe.sueldo_fijo = false
      and (fn_es_admin_o_lider()
           or (fn_rol_actual() = 'supervisor_sede' and pe.sede_base_id = fn_sede_actual_persona()))
  ),
  conteo as (
    select m.id as pid,
           count(distinct j.fecha) filter (
             where fn_tardanza_es_medible(j.minutos_tarde)) as n,
           -- Lo que hasta hoy no existía para nadie: los días cuya tardanza pasa
           -- de tres horas. No suman al umbral legal —no se puede sancionar con
           -- una medición dudosa— pero dejan de ser invisibles.
           count(distinct j.fecha) filter (
             where not fn_tardanza_es_medible(j.minutos_tarde)) as sm,
           max(j.fecha) filter (
             where fn_tardanza_es_medible(j.minutos_tarde)) as ult
    from medibles m
    join jornadas j on j.persona_id = m.id
      and j.fecha >= date_trunc('month', coalesce(p_as_of, fn_hoy_lima()))::date
      and j.fecha <= coalesce(p_as_of, fn_hoy_lima())
      and (m.corte is null or j.fecha > m.corte)   -- no cuenta lo ya sancionado
      and j.minutos_tarde is not null and j.minutos_tarde > 0
      and not exists (
        select 1 from tardanzas_justificadas tj
        where tj.persona_id = m.id and tj.fecha = j.fecha)
    group by m.id
  )
  select m.id, m.nombre, m.sede, c.n::int,
    case when c.n >= 3 then 'amonestacion' else 'aviso' end as umbral,
    c.ult, c.sm::int
  from medibles m join conteo c on c.pid = m.id
  -- El `or c.sm > 0` es el que hace visible el caso: alguien con cero tardanzas
  -- medibles y tres días sin medir no aparecía en esta pantalla en absoluto.
  where c.n >= 2 or c.sm > 0
  order by c.n desc, c.sm desc, m.nombre;
$function$;

-- ── fn_calcular_bono_puntualidad · el día dudoso sigue fuera, ahora dicho ──
-- Hoy esos días quedaban fuera por accidente: eran NULL. Al guardar el número
-- real pasarían a contar como tardanza y le quitarían el bono a alguien cuyo
-- turno estaba mal cargado — el falso positivo que este proyecto considera el
-- peor error. Se mantiene el comportamiento de hoy, pero escrito a propósito.
CREATE OR REPLACE FUNCTION public.fn_calcular_bono_puntualidad(p_periodo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_estado text; v_ini date; v_fin date; v_dias_periodo int;
  v_cfg jsonb; v_monto numeric; v_asistencia_min numeric;
  v_poblacion int; v_puntuales int;
  v_personas jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular el bono de puntualidad.';
  end if;

  select estado, fecha_ini, fecha_fin into v_estado, v_ini, v_fin
  from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  -- Mientras el periodo sigue corriendo, el 51% se mide contra los días que
  -- YA PASARON, no contra el periodo completo — si no, nadie podría llegar al
  -- umbral hasta el último día, aunque tenga asistencia perfecta hasta hoy.
  -- ¡OJO zona horaria! current_date usa UTC (el servidor de Supabase), NO Lima
  -- (UTC-5) — después de las 7pm hora Lima, UTC ya cree que es el día
  -- siguiente y cuenta un día de más. Se usa la fecha real de Lima.
  v_dias_periodo := least(v_fin, (now() at time zone 'America/Lima')::date) - v_ini + 1;

  select valor into v_cfg from configuracion where clave = 'bono_puntualidad';
  if v_cfg is null then
    v_cfg := '{"monto": 60, "asistencia_minima": 0.51}'::jsonb;
  end if;
  v_monto := coalesce((v_cfg->>'monto')::numeric, 0);
  v_asistencia_min := coalesce((v_cfg->>'asistencia_minima')::numeric, 0.51);

  -- Un día "cuenta" solo si minutos_tarde no es NULL — fn_recalcular_jornada ya
  -- lo deja NULL cuando no hubo hora esperada con qué comparar (sin turno/
  -- horario vigente para esa fecha, o día de descanso trabajado). Los días sin
  -- medir se ignoran por completo: no entran en dias_medidos ni en tarde_total.
  with dias_trabajo as (
    -- Tardanza LEVANTADA (fuerza mayor) cuenta como 0 (puntual) para el bono.
    select j.persona_id,
           case when exists (select 1 from tardanzas_justificadas tj
                             where tj.persona_id = j.persona_id and tj.fecha = j.fecha)
                then 0 else j.minutos_tarde end as minutos_tarde
    from jornadas j
    where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
  ),
  por_persona as (
    select persona_id,
           count(*) filter (where fn_tardanza_es_medible(minutos_tarde)) as dias_medidos,
           sum(minutos_tarde) filter (where fn_tardanza_es_medible(minutos_tarde)) as tarde_total
    from dias_trabajo
    group by persona_id
  )
  select count(*), count(*) filter (
    where coalesce(tarde_total, 0) = 0
      and dias_medidos::numeric / v_dias_periodo >= v_asistencia_min
  )
  into v_poblacion, v_puntuales
  from por_persona;

  -- recalculable sin duplicar: borra solo las filas AUTO-generadas de este periodo
  delete from movimientos_planilla
  where periodo_id = p_periodo_id
    and concepto = 'Bono puntualidad'
    and creado_por is null;

  if v_monto > 0 and v_puntuales > 0 then
    with dias_trabajo as (
      -- Tardanza LEVANTADA (fuerza mayor) cuenta como 0 (puntual) para el bono.
      select j.persona_id,
             case when exists (select 1 from tardanzas_justificadas tj
                               where tj.persona_id = j.persona_id and tj.fecha = j.fecha)
                  then 0 else j.minutos_tarde end as minutos_tarde
      from jornadas j
      where j.fecha between v_ini and v_fin and j.horas_trabajadas > 0
    ),
    por_persona as (
      select persona_id,
             count(*) filter (where fn_tardanza_es_medible(minutos_tarde)) as dias_medidos,
             sum(minutos_tarde) filter (where fn_tardanza_es_medible(minutos_tarde)) as tarde_total
      from dias_trabajo
      group by persona_id
    )
    insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
    select p_periodo_id, pp.persona_id, 'bono', 'Bono puntualidad', v_monto, null
    from por_persona pp
    where coalesce(pp.tarde_total, 0) = 0
      and pp.dias_medidos::numeric / v_dias_periodo >= v_asistencia_min;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', pe.id, 'nombre', pe.nombres || ' ' || pe.apellidos
         ) order by pe.nombres), '[]'::jsonb)
    into v_personas
  from movimientos_planilla m
  join personas pe on pe.id = m.persona_id
  where m.periodo_id = p_periodo_id and m.concepto = 'Bono puntualidad' and m.creado_por is null;

  return jsonb_build_object(
    'poblacion', v_poblacion,
    'puntuales', v_puntuales,
    'monto_por_persona', v_monto,
    'personas', v_personas
  );
end;
$function$;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (189, 'una_tardanza_de_tres_horas_deja_de_desaparecer')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado de la
-- última consulta.
--
-- `sin_medir_historicos` son los días que YA estaban en la base con el número
-- destruido: tienen horas trabajadas y horario programado, y aun así la tardanza
-- quedó en null. Cada uno es un día que pudo ser una tardanza grande y nadie vio.
-- No se pueden recuperar; se arreglarán solos cuando ese día se recalcule.
select
  (select count(*) from jornadas where minutos_tarde is not null) as con_tardanza_medida,
  (select count(*) from jornadas j
     where j.minutos_tarde is null
       and coalesce(j.horas_trabajadas, 0) > 0
       and exists (select 1 from horarios_asignados h
                    where h.persona_id = j.persona_id
                      and j.fecha >= h.vigente_desde
                      and (h.vigente_hasta is null or j.fecha <= h.vigente_hasta)))
    as sin_medir_historicos,
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'fn_tardanza_es_medible') as umbral_en_un_solo_sitio;
