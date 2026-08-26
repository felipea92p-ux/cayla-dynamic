-- ============================================================================
-- 0307 · EL CANDADO DEL MES PAGADO MIDE LA JORNADA, NO EL RELOJ
-- ============================================================================
--
-- QUÉ PROMETE
--   Que las seis puertas que impiden tocar un marcaje de un periodo YA PAGADO
--   midan el día al que ese marcaje pertenece PARA LA PLANILLA, y no el día
--   del calendario en que cayó su hora.
--
-- EL DEFECTO, MEDIDO
--   El periodo va del 29 al 28. Un turno del día 28 que cierra a las 00:30 del
--   29 deja una salida cuyo `timestamp_marca` cae en el 29 —día del periodo
--   siguiente, todavía abierto— mientras su `fecha_jornada` dice 28, que es el
--   día que ya se pagó. Las seis funciones derivaban la fecha con
--   `(timestamp_marca at time zone 'America/Lima')::date`, así que veían el 29
--   y dejaban pasar.
--
--   Comprobado contra la base, mismo periodo pagado (29-jul al 28-ago), misma
--   persona, misma jornada del 28, dentro de BEGIN … ROLLBACK:
--
--     entrada 20:00 del 28 ................ frenada, «cae en un periodo ya PAGADO»
--     salida 00:30 del 29 (jornada del 28) ... BORRADA, quedan 0 filas
--
--   `fn_eliminar_marcaje` hace `delete` duro. El monto pagado no se mueve
--   —eso lo protege `fn_recalcular_jornada`, que sí conoce `fecha_jornada`
--   desde la 0240—, pero el registro de control de asistencia que lo sustenta
--   queda contradiciendo la planilla, sin aviso. TRU es donde más ocurre:
--   trabaja domingo y cierra tarde.
--
-- POR QUÉ UNA FUNCIÓN Y NO LA EXPRESIÓN COPIADA SEIS VECES
--   `fn_fecha_de_jornada` dice la regla una sola vez. La expresión ya vivía
--   —correcta— en `fn_recalcular_jornada` y en `fn_trg_marcajes_recalcular_
--   jornada` desde la 0240; esta migración no inventa nada, le pone nombre a
--   lo que ya era la verdad y lo lleva a donde faltaba.
--
-- LO QUE **NO** SE TOCA, Y ES DELIBERADO
--   Solo cambian de vara las seis comprobaciones de «periodo ya PAGADO». El
--   resellado del día, la búsqueda de la sede del día, `fn_dia_incoherente`,
--   `fn_dias_por_revisar` y los mensajes al usuario SIGUEN midiendo por el
--   reloj. Son otros 14 usos en otras 6 funciones, están medidos, y van en su
--   propia migración DESPUÉS del cierre del 28 — decidido así el 2026-08-25
--   para no mover funciones que sostienen el cierre a tres días de usarlo.
--
--   ⚠️ La trampa que eso evita, y que hay que recordar antes de escribir esa
--   segunda migración: `fn_corregir_marca` tiene un guard que dice «aquí solo
--   se corrige la hora dentro de su mismo día», comparando contra `v_fecha`.
--   Si `v_fecha` pasara a ser la fecha de jornada, ese guard saltaría SIEMPRE
--   para una marca de madrugada —jornada 28, reloj 29— y esa marca quedaría
--   imposible de corregir. Ahí hacen falta dos variables, no una.
--
--   Tampoco se toca `fn_agregar_marcaje`: la marca que crea nace sin
--   `fecha_jornada`, así que el día del reloj ES su día efectivo y el candado
--   ya era consistente. Queda abierto que una encargada no pueda agregar a
--   mano una marca de madrugada que cierre el turno del día anterior — es una
--   capacidad que falta, no un candado que falle.
--
-- MD5 DE PARTIDA — pedidos al SQL Editor de PRODUCCIÓN el 2026-08-25.
--   Las seis coincidieron `tal_cual` con el repositorio, comentarios incluidos:
--     fn_anular_marcaje ......... fca64b89294b950ad0e2d2c782a144fc   1499
--     fn_confirmar_auto_cierre .. bb55fc2a3ef9f63af0f5edcbd1e154be   1614
--     fn_corregir_marca ......... 1ef15c4480eea7f095b505d92aa5f598   3210
--     fn_corregir_marcaje ....... 9208e26d60f2a6c9e4d1fcf4d892ea57   1507
--     fn_eliminar_marcaje ....... 94eda7b8b1cb750d6a3a50aaab78ab98   1114
--     fn_reactivar_marcaje ...... 0d2fc7ac6ba6d79ddfe94aa600d65654   2083
--   Y las seis devolvieron `position('fecha_jornada' in prosrc) = 0`: producción
--   no conocía la columna en ninguna. Cuerpos copiados de esas versiones
--   vigentes — 0102 (anular, corregir_marca, reactivar, confirmar) y 0188
--   (eliminar, corregir_marcaje), según `donde-vive.sh`.
--
-- CÓMO SE REVIERTE
--   Volver a pegar los cuerpos de la 0102 y la 0188 tal cual, y
--   `drop function fn_fecha_de_jornada(timestamptz, date);`. No hay datos que
--   deshacer: esta migración no escribe ni una fila.
--
-- CÓMO SE COMPRUEBA QUE ENTRÓ
--   El `select` del final: las seis tienen que decir que ya saben de la jornada.
-- ============================================================================

-- ── La regla, dicha una sola vez ────────────────────────────────────────────
-- `fecha_jornada` solo trae valor cuando la marca cierra una jornada abierta
-- del día anterior. Cuando es null —el caso normal, y todas las marcas
-- anteriores a la 0240— el día es el del reloj de Lima, como siempre.
create or replace function fn_fecha_de_jornada(
  p_timestamp_marca timestamptz,
  p_fecha_jornada   date
) returns date
language sql
stable
as $function$
  select coalesce(p_fecha_jornada, (p_timestamp_marca at time zone 'America/Lima')::date);
$function$;

comment on function fn_fecha_de_jornada(timestamptz, date) is
  'El día al que pertenece un marcaje PARA LA PLANILLA. Espeja lo que hacen fn_recalcular_jornada y el trigger de marcajes desde la 0240.';


CREATE OR REPLACE FUNCTION public.fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la anulación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca ya está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha_jornada between fecha_ini and fecha_fin   -- CAMBIO 0307
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: anularla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes
     set anulada_at = now(), anulada_por = v_corr, anulada_motivo = trim(p_motivo)
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_anulado',
          v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, 'anulada', v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_confirmar_auto_cierre(p_marcaje_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.origen <> 'auto_cierre' then
    raise exception 'Solo se confirma una marca puesta por el auto-cierre.';
  end if;
  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada.';
  end if;
  if v_ant.estado_revision = 'revisada' then
    raise exception 'Ese auto-cierre ya está confirmado.';
  end if;

  -- CAMBIO 0307 · Acá `v_fecha` no lo usa nadie más que el candado, así que
  -- pasa a ser directamente la fecha de la JORNADA: una marca de madrugada
  -- pertenece al turno que cierra, no al día del calendario en que cae.
  v_fecha := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: confirmarla haría que ese día empiece a medir salida anticipada y tiempo adicional, cambiando una planilla ya pagada. Reabre el periodo primero.';
  end if;

  update marcajes set estado_revision = 'revisada'
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'auto_cierre_confirmado',
          'pendiente_revision', 'revisada', v_corr,
          coalesce(nullif(trim(coalesce(p_motivo, '')), ''), 'Confirmado: esa es su salida final.'));

  return v_nuevo;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_corregir_marca(p_marcaje_id uuid, p_nuevo_tipo tipo_marca DEFAULT NULL::tipo_marca, p_nuevo_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_tipo tipo_marca; v_ts timestamptz; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is not null then
    raise exception 'Esa marca está anulada: reactívala antes de corregirla.';
  end if;

  v_tipo := coalesce(p_nuevo_tipo, v_ant.tipo);
  v_ts   := coalesce(p_nuevo_ts,   v_ant.timestamp_marca);
  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  if v_tipo = v_ant.tipo and v_ts = v_ant.timestamp_marca then
    raise exception 'No hay nada que cambiar en esa marca.';
  end if;

  if fn_familia_marca(v_tipo) is distinct from fn_familia_marca(v_ant.tipo) then
    raise exception 'No se puede convertir % en %: una salida solo puede pasar a ser otra salida, y un retorno a otro retorno.',
      v_ant.tipo, v_tipo;
  end if;

  if (v_ts at time zone 'America/Lima')::date is distinct from v_fecha then
    raise exception 'Esa corrección movería la marca al %, y aquí solo se corrige la hora dentro de su mismo día. Si de verdad pertenece a otro día: anúlala y agrégala en el día correcto.',
      to_char((v_ts at time zone 'America/Lima')::date, 'DD/MM/YYYY');
  end if;

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha_jornada between fecha_ini and fecha_fin   -- CAMBIO 0307
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: corregirla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

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

  -- ¿La corrección dejó el día imposible? Se sella, igual que hace el terminal.
  -- Avisa sin impedir: el flujo normal pasa por aquí a mitad de camino.
  if fn_dia_incoherente(v_ant.persona_id, v_fecha) then
    update marcajes
       set estado_revision = 'pendiente_revision'
     where persona_id = v_ant.persona_id
       and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
       and anulada_at is null
       and estado_revision = 'normal';
  else
    perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  end if;

  return v_nuevo;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamp with time zone, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha_ant date; v_fecha_nueva date;
        v_jornada_ant date; v_jornada_nueva date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_fecha_ant := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  v_fecha_nueva := (p_nuevo_ts at time zone 'America/Lima')::date;

  -- CAMBIO 0307 · El candado mide la JORNADA. El `update` de abajo no toca
  -- `fecha_jornada`, así que la marca conserva la suya tanto antes como
  -- después de moverle la hora: las dos fechas salen de ese mismo valor.
  v_jornada_ant   := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);
  v_jornada_nueva := fn_fecha_de_jornada(p_nuevo_ts,            v_ant.fecha_jornada);

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_jornada_ant between fecha_ini and fecha_fin      -- CAMBIO 0307
           or v_jornada_nueva between fecha_ini and fecha_fin)   -- CAMBIO 0307
  ) then
    raise exception 'Ese marcaje cae en un periodo ya PAGADO: corregirlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  update marcajes set timestamp_marca = p_nuevo_ts, estado_revision = 'revisada'
  where id = p_marcaje_id returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'timestamp_marca', v_ant.timestamp_marca::text, p_nuevo_ts::text, v_corr, trim(p_motivo));

  perform fn_resellar_dia(v_ant.persona_id, v_fecha_ant);
  if v_fecha_nueva <> v_fecha_ant then
    perform fn_resellar_dia(v_ant.persona_id, v_fecha_nueva);
  end if;

  return v_nuevo;
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha_jornada between fecha_ini and fecha_fin   -- CAMBIO 0307
  ) then
    raise exception 'Ese marcaje cae en un periodo ya PAGADO: eliminarlo alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(v_ant.persona_id);

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (null, v_ant.persona_id, 'marcaje_eliminado', v_ant.tipo::text || ' @ ' || v_ant.timestamp_marca::text, null, v_corr, trim(p_motivo));

  delete from marcajes where id = p_marcaje_id;

  perform fn_resellar_dia(v_ant.persona_id, v_fecha);
end;
$function$;


CREATE OR REPLACE FUNCTION public.fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date; v_fecha_jornada date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la reactivación es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id for update;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  -- Autorización primero: los mensajes de estado de abajo cuentan cosas de una
  -- marca que quien pregunta puede no tener derecho a conocer.
  v_corr := fn_verificar_corrector(v_ant.persona_id);

  if v_ant.anulada_at is null then
    raise exception 'Esa marca no está anulada.';
  end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  -- CAMBIO 0307 · El candado del mes pagado se mide contra la JORNADA, no
  -- contra el reloj. Una salida a las 00:30 del 29 que cierra el turno del 28
  -- pertenece —para la planilla— al 28. `v_fecha` sigue siendo el día del
  -- reloj porque de eso dependen el resellado y los mensajes de esta función;
  -- lo único que cambia de vara es el candado.
  v_fecha_jornada := fn_fecha_de_jornada(v_ant.timestamp_marca, v_ant.fecha_jornada);

  perform 1 from periodos_planilla
   where v_fecha_jornada between fecha_ini and fecha_fin for share;   -- CAMBIO 0307
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha_jornada between fecha_ini and fecha_fin   -- CAMBIO 0307
  ) then
    raise exception 'Esa marca cae en un periodo ya PAGADO: reactivarla alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  if v_ant.tipo = 'salida_final' and exists (
    select 1 from marcajes
    where persona_id = v_ant.persona_id
      and tipo = 'salida_final'
      and (timestamp_marca at time zone 'America/Lima')::date = v_fecha
      and anulada_at is null
      and id <> p_marcaje_id
  ) then
    raise exception 'Ese día ya tiene otra salida final activa. Anula primero la que sobra: dos salidas finales el mismo día dejan el cálculo al azar.';
  end if;

  update marcajes
     set anulada_at = null, anulada_por = null, anulada_motivo = null
   where id = p_marcaje_id
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (p_marcaje_id, v_ant.persona_id, 'marcaje_reactivado',
          'anulada: ' || coalesce(v_ant.anulada_motivo, ''), v_ant.tipo::text, v_corr, trim(p_motivo));

  perform fn_levantar_sello_si_el_dia_cuadra(v_ant.persona_id, v_fecha);
  return v_nuevo;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (307, '0307_el_candado_del_mes_pagado_mide_la_jornada')
on conflict (numero) do nothing;

-- ── COMPROBACION ────────────────────────────────────────────────────────────
select p.proname                                             as funcion,
       position('fn_fecha_de_jornada' in p.prosrc) > 0       as ya_mide_la_jornada,
       position('CAMBIO 0307' in p.prosrc) > 0               as lleva_el_marcador
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('fn_anular_marcaje','fn_confirmar_auto_cierre','fn_corregir_marca',
                     'fn_corregir_marcaje','fn_eliminar_marcaje','fn_reactivar_marcaje')
 order by p.proname;
