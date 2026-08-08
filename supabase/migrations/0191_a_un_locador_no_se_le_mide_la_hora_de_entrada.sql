-- ============================================================================
-- 0191_a_un_locador_no_se_le_mide_la_hora_de_entrada.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el sistema no le mida tardanza ni salida anticipada a quien no está
--   sujeto a un horario. Sus marcajes se guardan igual, sus horas se calculan
--   igual y su pago no cambia: lo único que desaparece es un número que nunca
--   debió existir.
--
-- QUÉ ASUME
--   Que `personas.en_planilla` distingue a quien cumple una jornada de quien
--   no. Es una columna generada: `tipo_vinculo in ('planilla','prueba')`. Un
--   `rxh` —recibo por honorarios— queda fuera, y un `no_trabajador` también.
--
-- ── POR QUÉ, Y ES LO IMPORTANTE ─────────────────────────────────────────────
--
-- Un locador presta un servicio; no cumple una jornada. La ley no le fija hora
-- de entrada, y por eso su horario en el sistema está cargado «solo como
-- referencia» (Felipe, 2026-08-08). Medirle una tardanza contra esa referencia
-- no es un número inexacto: es un número que no significa nada.
--
-- Y NO ES INOCUO. Cargo de mando, área, sede, rango de la escala y monto fijo
-- mensual son los indicios que convierten una locación de servicios en un
-- contrato de trabajo. `docs/estado.md` lo tiene anotado como frente abierto —
-- tres personas cobran por honorarios y el sistema las retrata como personal
-- subordinado. Un registro de tardanzas es de esa misma familia, y peor: es
-- **control de jornada**, el indicio más directo de subordinación que existe.
--
-- El agravante que este repositorio ya se escribió a sí mismo: el expediente lo
-- arma el propio sistema. Es prueba escrita, generada por CAYLA, en su contra.
--
-- ── DÓNDE ESTABA EL HUECO, MEDIDO ───────────────────────────────────────────
--
-- El semáforo disciplinario SÍ los excluye desde hace tiempo — `fn_faltas`,
-- `fn_faltas_resumen` y `fn_tardanzas_resumen` filtran por `en_planilla`. Pero
-- el hueco no estaba ahí:
--
--   fn_recalcular_jornada           NO lo miraba  → medía y GUARDABA el número
--   fn_expediente_generar_tardanza  NO lo mira    → puede citarlo en un memo
--   fn_expediente_generar_falta     NO lo mira    → ídem
--   fn_calcular_bono_puntualidad    NO lo mira
--   Horas · Reporte-sede · espejo   NO lo miran   → lo cuentan crudo en pantalla
--
-- SE ARREGLA EN LA RAÍZ Y NO EN LOS SIETE SITIOS. Si el número no se guarda, no
-- hay nada que citar, que contar ni que imprimir: los siete consumidores quedan
-- correctos sin tocar ninguno. Copiar `en_planilla` a siete funciones habría
-- creado siete copias de una regla, y la próxima corrección se habría aplicado
-- a una y no a las otras — que es el defecto que este repositorio persigue.
--
-- ── QUÉ PASA CON LO YA GUARDADO ─────────────────────────────────────────────
--
-- Se limpia. No es un borrado de datos: `jornadas` es un derivado, y estos dos
-- campos se reconstruyen desde `marcajes` —que es la fuente de verdad y es
-- append-only— con la consulta `scripts/sql-manual/los_21_dias_que_nadie_vio.sql`.
-- Lo que se borra es una medición que no debió calcularse; el hecho sigue
-- intacto.
--
-- No se hace recalculando, a propósito: `fn_recalcular_jornada` se niega a tocar
-- un periodo ya pagado (0138), así que un recálculo dejaría el número viejo
-- justo en los meses que ya se cerraron. El UPDATE directo alcanza a todos, y
-- ninguno de los dos campos interviene en el pago.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--   Quitando las cuatro apariciones de `v_sujeta_a_horario`. Los números
--   borrados se recuperan recalculando los días de esas personas. Revertir
--   significa volver a fabricar la prueba de subordinación.
--
-- ── CÓMO SE COMPRUEBA QUE QUEDÓ BIEN ────────────────────────────────────────
--   La consulta del final debe devolver 0 en la primera columna.
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

-- ── Limpiar lo que nunca debió medirse ──────────────────────────────────────
update jornadas j
   set minutos_tarde = null,
       minutos_salida_temprana = null
 where exists (select 1 from personas p
                where p.id = j.persona_id and p.en_planilla is not true)
   and (j.minutos_tarde is not null or j.minutos_salida_temprana is not null);

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (191, 'a_un_locador_no_se_le_mide_la_hora_de_entrada')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- La primera columna debe decir 0. La segunda es cuánta gente hay en esa
-- situación, para que el 0 signifique algo y no sea «no había a quién medir».
select
  (select count(*) from jornadas j
     join personas p on p.id = j.persona_id
    where p.en_planilla is not true
      and (j.minutos_tarde is not null or j.minutos_salida_temprana is not null))
    as mediciones_que_sobran,
  (select count(*) from personas where en_planilla is not true and estado = 'activo')
    as personas_no_sujetas_a_horario,
  (select count(*) from jornadas j
     join personas p on p.id = j.persona_id
    where p.en_planilla is not true) as sus_jornadas_registradas;
