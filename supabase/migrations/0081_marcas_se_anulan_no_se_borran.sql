-- ============================================================================
-- 0081 — Una marca se anula, no se borra
-- ----------------------------------------------------------------------------
-- PROMETE:
--   1. Que quitar una marca deje rastro: se anula (queda visible, tachada, con
--      quién y por qué) en vez de desaparecer de la base. Y que se pueda
--      reactivar si la anulación fue un error.
--   2. Que se pueda corregir el TIPO de una marca, no solo su hora — el error
--      real del 25/07/2026: a una persona le marcaron "salida a almuerzo"
--      cuando en realidad se iba a su casa.
--   3. Que un auto-cierre se pueda CONFIRMAR de un clic cuando su hora resulta
--      ser la correcta, y que a partir de ahí ese día se mida como cualquier
--      otro.
--
-- ASUME: marcajes, jornadas, correcciones_auditoria, fn_verificar_corrector
--   (0009/0010), periodos_planilla y el candado de periodo pagado (0037).
--
-- POR QUÉ ANULAR Y NO BORRAR. El principio del sistema es que los marcajes son
--   la fuente de verdad y son append-only: la jornada es un resumen derivado que
--   se recalcula, nunca se corrige por debajo. `fn_eliminar_marcaje` (0009) hacía
--   un DELETE de verdad, y eso contradecía ese principio: el día quedaba bien
--   pero nadie podía saber después qué se quitó ni por qué. Decisión de Cayla el
--   26/07/2026: anular. `fn_eliminar_marcaje` se mantiene por compatibilidad pero
--   la pantalla deja de usarla.
--
-- CÓMO SE REVIERTE: `scripts/sql-manual/reverso_0081.sql` — restaura la versión
--   anterior de fn_recalcular_jornada, borra las funciones nuevas y deja las tres
--   columnas (vacías no molestan, y borrarlas perdería el historial de lo anulado).
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · Las tres columnas de la anulación
-- ════════════════════════════════════════════════════════════════════════════
alter table marcajes add column if not exists anulada_at     timestamptz;
alter table marcajes add column if not exists anulada_por    uuid references personas(id);
alter table marcajes add column if not exists anulada_motivo text;

-- Estado imposible (Lamport): una marca anulada sin saber quién ni por qué. El
-- constraint lo hace imposible en el esquema, que vale más que diez validaciones
-- repartidas por el código.
alter table marcajes drop constraint if exists chk_anulacion_completa;
alter table marcajes add constraint chk_anulacion_completa check (
  (anulada_at is null and anulada_por is null and anulada_motivo is null)
  or (anulada_at is not null and anulada_por is not null
      and anulada_motivo is not null and length(trim(anulada_motivo)) >= 3)
);

-- El recálculo solo mira marcas vivas, y corre en cada insert/update de marcajes:
-- el índice parcial evita que crezca el coste según se acumulen anuladas.
create index if not exists idx_marcajes_vivas
  on marcajes (persona_id, timestamp_marca) where anulada_at is null;

comment on column marcajes.anulada_at is
  'Cuándo se anuló. NULL = marca viva. Una marca anulada no cuenta para la jornada pero sigue en el historial.';


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · El recálculo ignora las anuladas, y mide el auto-cierre ya revisado
-- ════════════════════════════════════════════════════════════════════════════
-- Dos cambios sobre la versión de 0017, ambos pequeños y ambos con consecuencias
-- en el dinero, así que van con pruebas (supabase/tests/80_recalcular_jornada):
--
--   a) Las marcas anuladas quedan fuera del conteo y del recorrido. Si se anulan
--      TODAS las de un día, el día se queda sin marcas y la jornada se borra
--      sola, igual que si nunca hubiera existido.
--
--   b) Salida anticipada y tiempo adicional dejaban de medirse SIEMPRE que la
--      salida final viniera del auto-cierre. Ahora dejan de medirse solo mientras
--      ese auto-cierre siga sin revisar. En cuanto alguien confirma la hora o la
--      corrige, deja de ser un dato inventado y el día se mide entero.
--      Decisión de Cayla el 26/07/2026.

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


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Anular y reactivar
-- ════════════════════════════════════════════════════════════════════════════
create or replace function fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la anulación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca ya está anulada.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes
     set anulada_at = now(), anulada_por = v_corr, anulada_motivo = trim(p_motivo)
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_anulado',
          v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, 'anulada', v_corr, trim(p_motivo));

  return v_nuevo;
end;
$fn$;
grant execute on function fn_anular_marcaje(uuid, text) to authenticated;
revoke execute on function fn_anular_marcaje(uuid, text) from public, anon;

-- Deshacer una anulación. Existe porque anular es reversible por diseño: si no
-- lo fuera, quien duda no anula, y los días se quedan mal por miedo a tocarlos.
create or replace function fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la reactivación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.anulada_at is null then
    raise exception 'Esa marca no está anulada.';
  end if;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: reactivarla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes
     set anulada_at = null, anulada_por = null, anulada_motivo = null
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_reactivado',
          'anulada: ' || coalesce(v_ant.anulada_motivo, ''), v_ant.tipo::text, v_corr, trim(p_motivo));

  return v_nuevo;
end;
$fn$;
grant execute on function fn_reactivar_marcaje(uuid, text) to authenticated;
revoke execute on function fn_reactivar_marcaje(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 4 · Corregir el tipo (y la hora) de una marca
-- ════════════════════════════════════════════════════════════════════════════
-- A qué familia pertenece cada tipo. Una salida solo puede pasar a ser otra
-- salida, y un retorno a otro retorno: convertir una entrada en salida dejaría
-- el día con dos salidas y sin entrada, que es un destrozo difícil de deshacer.
create or replace function fn_familia_marca(p_tipo tipo_marca)
returns text language sql immutable set search_path = public as $fn$
  select case
           when p_tipo::text = 'entrada'        then 'entrada'
           when p_tipo::text like 'salida\_%'   then 'salida'
           when p_tipo::text like 'retorno\_%'  then 'retorno'
           when p_tipo::text = 'salida_final'   then 'salida'
         end;
$fn$;
grant execute on function fn_familia_marca(tipo_marca) to authenticated;
revoke execute on function fn_familia_marca(tipo_marca) from public, anon;

-- Corrige tipo y hora a la vez, en un solo registro de auditoría. Pasar null en
-- cualquiera de los dos deja ese campo como está.
create or replace function fn_corregir_marca(
  p_marcaje_id uuid,
  p_nuevo_tipo tipo_marca default null,
  p_nuevo_ts   timestamptz default null,
  p_motivo     text default null)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_tipo tipo_marca; v_ts timestamptz;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada: reactívala antes de corregirla.';
  end if;

  v_tipo := coalesce(p_nuevo_tipo, v_ant.tipo);
  v_ts   := coalesce(p_nuevo_ts,   v_ant.timestamp_marca);

  if v_tipo = v_ant.tipo and v_ts = v_ant.timestamp_marca then
    raise exception 'No hay nada que cambiar en esa marca.';
  end if;

  if fn_familia_marca(v_tipo) is distinct from fn_familia_marca(v_ant.tipo) then
    raise exception 'No se puede convertir % en %: una salida solo puede pasar a ser otra salida, y un retorno a otro retorno.',
      v_ant.tipo, v_tipo;
  end if;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (
        (v_ant.timestamp_marca at time zone 'America/Lima')::date between fecha_ini and fecha_fin
        or (v_ts at time zone 'America/Lima')::date between fecha_ini and fecha_fin
      )
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: corregirla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes
     set tipo = v_tipo, timestamp_marca = v_ts, estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  if v_tipo is distinct from v_ant.tipo then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'tipo', v_ant.tipo::text, v_tipo::text, v_corr, trim(p_motivo));
  end if;
  if v_ts is distinct from v_ant.timestamp_marca then
    insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
    values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, v_ts::text, v_corr, trim(p_motivo));
  end if;

  return v_nuevo;
end;
$fn$;
grant execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) to authenticated;
revoke execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 5 · Confirmar un auto-cierre
-- ════════════════════════════════════════════════════════════════════════════
-- "Esa es su salida final." No cambia la hora ni el origen: la marca sigue
-- mostrando que la puso el sistema. Lo que cambia es que deja de estar pendiente,
-- y a partir de ahí el día se mide entero (ver el bloque 2b).
create or replace function fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text default null)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;
  if v_ant.origen <> 'auto_cierre' then
    raise exception 'Solo se confirma una marca puesta por el auto-cierre.';
  end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada.';
  end if;
  if v_ant.estado_revision = 'revisada' then
    raise exception 'Ese auto-cierre ya está confirmado.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes set estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'auto_cierre_confirmado',
          'pendiente_revision', 'revisada', v_corr,
          coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Confirmado: esa es su salida final.'));

  return v_nuevo;
end;
$fn$;
grant execute on function fn_confirmar_auto_cierre(uuid, text) to authenticated;
revoke execute on function fn_confirmar_auto_cierre(uuid, text) from public, anon;


insert into migraciones_aplicadas (numero, nombre)
values (81, 'marcas_se_anulan_no_se_borran')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
