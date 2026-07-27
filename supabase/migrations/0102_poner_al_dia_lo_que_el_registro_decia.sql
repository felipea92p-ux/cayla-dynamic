-- ============================================================================
-- 0102 — Poner al día lo que el registro decía que ya estaba
-- ----------------------------------------------------------------------------
-- CÓMO SE DESCUBRIÓ ESTO
--
-- El registro `migraciones_aplicadas` decía que la 0089 estaba aplicada. Su
-- contenido no estaba en la base. Un hueco en el registro se ve —así apareció
-- que faltaba la 0083—; una migración registrada que nunca corrió, no.
--
-- Se midió comparando la huella del texto de las 155 funciones de producción
-- contra una base construida desde cero con las 101 migraciones en orden
-- (`scripts/sql-manual/comparar_funciones.sql`), y cruzando cada huella distinta
-- contra el texto de esa misma función después de CADA migración. Eso dice, sin
-- interpretación posible, en qué punto se quedó cada una.
--
-- QUÉ ARREGLA ESTA MIGRACIÓN, Y SOLO ESTO
--
-- Cinco funciones donde producción tiene una versión anterior del repositorio.
-- Son las únicas del grupo «producción atrasada» que tocan dinero o asistencia:
--
--   fn_trg_marcajes_recalcular_jornada  se quedó en la 0002 · le falta la 0083
--   fn_confirmar_auto_cierre            se quedó en la 0082 · le faltan 0083 y 0089
--   fn_anular_marcaje                   se quedó en la 0088 · le falta la 0089
--   fn_corregir_marca                   se quedó en la 0088 · le falta la 0089
--   fn_reactivar_marcaje                se quedó en la 0088 · le falta la 0089
--
-- EL FALLO QUE ESTÁ VIVO AHORA MISMO, y es el motivo de urgencia
--
-- El trigger de producción es el original: cuando una marca cambia de día, solo
-- recalcula el día NUEVO. El día que la marca abandona se queda con las horas
-- que ya no le corresponden. Medido: día 20 con entrada 08:00 y salida 16:30 =
-- 8.50 h; se mueve la entrada al 21; el día 20 sigue diciendo 8.50 h sin
-- ninguna entrada que las sostenga. Ocho horas y media que la planilla paga y
-- que no existieron — y las produce la corrección, no el error original.
--
-- POR QUÉ NO SE PEGA LA 0083 NI LA 0089 DIRECTAMENTE
--
-- Porque pegarlas HOY haría retroceder. La 0083 también redefine anular,
-- corregir y reactivar, y esas las mejoraron después la 0084 y la 0089: pegar
-- la 0083 devolvería tres funciones a su versión vieja. Es el mismo error que
-- se cometió al escribir la 0100 —copiar un cuerpo correcto pero antiguo— y que
-- costó el guard de seguridad de la 0090.
--
-- Por eso los cinco cuerpos de abajo NO se copiaron de una migración: se
-- extrajeron con `pg_get_functiondef` de la base de referencia, la que aplica
-- las 101 migraciones en orden y sobre la que pasan las 253 aserciones. Son
-- byte a byte lo que está probado.
--
-- QUÉ NO TOCA, A PROPÓSITO
--
--   · Cuatro funciones donde la ÚNICA diferencia es texto corrompido en los
--     mensajes de error (se pegaron alguna vez con la codificación de Mac:
--     «l√≠der» en vez de «líder»). La lógica es idéntica. Molesta, no rompe.
--   · Tres funciones donde producción está ADELANTADA: fn_agregar_marcaje,
--     fn_corregir_marcaje y fn_eliminar_marcaje tienen mejoras que el
--     repositorio no conoce, y una función entera —fn_resellar_dia— que no
--     existe en el repo. Pisarlas borraría trabajo real. Están rescatadas en
--     `docs/rescatado-de-produccion.sql` y hay que reconciliarlas a mano.
--   · fn_crear_periodo y fn_eliminar_periodo, donde el repositorio tiene más
--     código que producción y hay que mirar qué añadió antes de aplicarlo.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar el cuerpo de fn_trg_marcajes_recalcular_jornada de la 0002
--   y los de las otras cuatro de la 0088. No hay pérdida de datos: esta
--   migración solo reemplaza código.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_anular_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
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

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
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
$function$
;

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

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;

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
$function$
;

CREATE OR REPLACE FUNCTION public.fn_corregir_marca(p_marcaje_id uuid, p_nuevo_tipo tipo_marca DEFAULT NULL::tipo_marca, p_nuevo_ts timestamp with time zone DEFAULT NULL::timestamp with time zone, p_motivo text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_tipo tipo_marca; v_ts timestamptz; v_fecha date;
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
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
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
$function$
;

CREATE OR REPLACE FUNCTION public.fn_reactivar_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha date;
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

  perform 1 from periodos_planilla
   where v_fecha between fecha_ini and fecha_fin for share;
  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
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
$function$
;

CREATE OR REPLACE FUNCTION public.fn_trg_marcajes_recalcular_jornada()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare v_fecha_vieja date; v_fecha_nueva date;
begin
  v_fecha_nueva := (new.timestamp_marca at time zone 'America/Lima')::date;

  if tg_op = 'UPDATE' then
    v_fecha_vieja := (old.timestamp_marca at time zone 'America/Lima')::date;
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


insert into migraciones_aplicadas (numero, nombre)
values (102, 'poner_al_dia_lo_que_el_registro_decia_que_ya_estaba')
on conflict (numero) do nothing;

-- La 0083 nunca corrió y ya no debe correr: su contenido útil está arriba y el
-- resto haría retroceder. Se registra para que no vuelva a aparecer como hueco
-- y para que quede dicho por qué.
insert into migraciones_aplicadas (numero, nombre)
values (83, 'candado_al_confirmar_y_dia_abandonado (aplicada via 0102, NO pegar la 0083)')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
