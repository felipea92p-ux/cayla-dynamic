-- ============================================================================
-- 0084 — El sello de "día por revisar" se levanta cuando el día vuelve a cuadrar
-- ----------------------------------------------------------------------------
-- PROMETE: que un día arreglado deje de aparecer en la lista de días por revisar,
--   sin que nadie tenga que tocar marcas que ya estaban bien.
--
-- ASUME: la 0068 (fn_dia_incoherente y el sello), la 0081 (anular) y la 0082.
--
-- EL CASO REAL (Estefany, 17/07/2026). Cuando una marca llega tarde y deja el día
--   con una secuencia imposible, la 0068 SELLA todas las marcas de ese día
--   poniéndolas en 'pendiente_revision' — un sello en tinta, no una pregunta que
--   se recalcule. Ese día se arregló del todo: se agregaron tres marcas a mano y
--   se anuló la entrada duplicada. Pero su salida final de las 21:52 era del
--   terminal, era correcta, y nadie tuvo motivo para tocarla: se quedó con el
--   sello puesto. Y como la lista pregunta "¿hay alguna marca sellada?" en vez de
--   "¿sigue roto el día?", ese día no salía nunca de la lista.
--
--   El efecto es al revés de lo que uno esperaría: cuantas más marcas del día
--   estén correctas, más fácil es que el día se quede pegado ahí.
--
-- POR QUÉ NO SE TOCA EL AUTO-CIERRE. Una salida puesta por el auto-cierre también
--   está en 'pendiente_revision', pero por otro motivo y con todo el derecho: esa
--   hora la inventó el sistema y alguien tiene que decir si vale. Ese sello se
--   levanta al confirmarla o al corregirla, no aquí.
--
-- CÓMO SE REVIERTE: los sellos levantados no se pueden volver a poner uno por uno
--   (no queda registro de cuáles se levantaron), pero tampoco hace falta: el
--   siguiente marcaje que deje el día roto lo vuelve a sellar solo. Para deshacer
--   el comportamiento basta con borrar fn_levantar_sello_si_el_dia_cuadra y
--   restaurar las tres funciones desde la 0083.
-- ============================================================================


-- ════════════════════════════════════════════════════════════════════════════
-- 1 · La pieza que levanta el sello
-- ════════════════════════════════════════════════════════════════════════════
-- Devuelve cuántas marcas dejó de sellar, para poder contarlo en la limpieza.
create or replace function fn_levantar_sello_si_el_dia_cuadra(p_persona_id uuid, p_fecha date)
returns int language plpgsql security definer set search_path = public as $fn$
declare v_n int := 0;
begin
  -- Sigue roto: el sello se queda donde está.
  if fn_dia_incoherente(p_persona_id, p_fecha) then
    return 0;
  end if;

  update marcajes
     set estado_revision = 'revisada'
   where persona_id = p_persona_id
     and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
     and anulada_at is null
     and estado_revision = 'pendiente_revision'
     -- El auto-cierre conserva el suyo: es un sello por otro motivo.
     and origen <> 'auto_cierre';

  get diagnostics v_n = row_count;
  return v_n;
end;
$fn$;
grant execute on function fn_levantar_sello_si_el_dia_cuadra(uuid, date) to authenticated;
revoke execute on function fn_levantar_sello_si_el_dia_cuadra(uuid, date) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 2 · Se llama después de cada corrección
-- ════════════════════════════════════════════════════════════════════════════
-- Va en las tres funciones que pueden hacer que un día vuelva a cuadrar. No se
-- puso dentro de fn_recalcular_jornada, que sería el sitio "natural": esa función
-- la dispara un trigger sobre marcajes, y escribir en marcajes desde ahí crearía
-- una recursión (update → trigger → update → …).

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
  select * into v_ant from marcajes where id = p_marcaje_id for update;
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

  if (v_ts at time zone 'America/Lima')::date
     is distinct from (v_ant.timestamp_marca at time zone 'America/Lima')::date then
    raise exception 'Esa corrección movería la marca al %, y aquí solo se corrige la hora dentro de su mismo día. Si de verdad pertenece a otro día: anúlala y agrégala en el día correcto.',
      to_char((v_ts at time zone 'America/Lima')::date, 'DD/MM/YYYY');
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

  perform fn_levantar_sello_si_el_dia_cuadra(
    v_ant.persona_id, (v_ts at time zone 'America/Lima')::date);

  return v_nuevo;
end;
$fn$;
grant execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) to authenticated;
revoke execute on function fn_corregir_marca(uuid, tipo_marca, timestamptz, text) from public, anon;

create or replace function fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la anulación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
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

  perform fn_levantar_sello_si_el_dia_cuadra(
    v_ant.persona_id, (v_ant.timestamp_marca at time zone 'America/Lima')::date);

  return v_nuevo;
end;
$fn$;
grant execute on function fn_anular_marcaje(uuid, text) to authenticated;
revoke execute on function fn_anular_marcaje(uuid, text) from public, anon;

create or replace function fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
returns marcajes language plpgsql security definer set search_path = public as $fn$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la reactivación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
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

  -- Reactivar puede volver a ROMPER el día: por eso se vuelve a preguntar en vez
  -- de dar por hecho que sigue cuadrando.
  perform fn_levantar_sello_si_el_dia_cuadra(
    v_ant.persona_id, (v_ant.timestamp_marca at time zone 'America/Lima')::date);

  return v_nuevo;
end;
$fn$;
grant execute on function fn_reactivar_marcaje(uuid, text) to authenticated;
revoke execute on function fn_reactivar_marcaje(uuid, text) from public, anon;


-- ════════════════════════════════════════════════════════════════════════════
-- 3 · Limpieza de los días que ya estaban arreglados
-- ════════════════════════════════════════════════════════════════════════════
-- Sin esto, los días que ya se corrigieron antes de esta migración seguirían
-- pegados en la lista para siempre — empezando por el de Estefany del 17/07.
do $$
declare r record; v_dias int := 0; v_marcas int := 0; v_n int;
begin
  for r in
    select distinct persona_id,
           (timestamp_marca at time zone 'America/Lima')::date as fecha
    from marcajes
    where estado_revision = 'pendiente_revision'
      and anulada_at is null
      and origen <> 'auto_cierre'
  loop
    v_n := fn_levantar_sello_si_el_dia_cuadra(r.persona_id, r.fecha);
    if v_n > 0 then
      v_dias  := v_dias + 1;
      v_marcas := v_marcas + v_n;
    end if;
  end loop;
  raise notice 'Días que ya cuadraban y salen de la lista: % (marcas des-selladas: %)', v_dias, v_marcas;
end $$;


insert into migraciones_aplicadas (numero, nombre)
values (84, 'el_sello_se_levanta_cuando_el_dia_cuadra')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
