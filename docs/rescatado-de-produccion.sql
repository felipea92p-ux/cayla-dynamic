-- ============================================================================
-- rescatado-de-produccion.sql — lo que existe en producción y NO en el repo
-- ----------------------------------------------------------------------------
-- ESTO NO SE PEGA EN NINGÚN SITIO. Es un rescate, no una migración.
--
-- El 27-07-2026 se comparó función por función la producción de CAYLA contra
-- una base construida desde cero con las 101 migraciones del repositorio. Doce
-- funciones tenían un texto que no coincide con NINGUNA versión del repo.
-- Al leerlas resultaron ser cuatro cosas distintas mezcladas:
--
--   1. Cuatro donde la única diferencia son los acentos de los mensajes de
--      error, pegados alguna vez con la codificación de Mac («l√≠der» por
--      «líder»). Lógica idéntica. Se corrigen solas al reaplicar el repo.
--   2. Una legado que ya nadie llama (fn_proyeccion_planilla, sustituida por
--      fn_planilla_calcular). Ninguna pantalla la usa.
--   3. Dos donde el repositorio tiene MÁS código que producción y hay que mirar
--      qué añadió antes de aplicarlo (fn_crear_periodo, fn_eliminar_periodo).
--   4. Y estas cuatro de abajo: producción está ADELANTADA. Alguien las mejoró
--      a mano y ese trabajo nunca volvió al repositorio. Se conservan aquí
--      literalmente, tal como estaban en producción, para no perderlas.
--
-- LO QUE HAY QUE DECIDIR CON ESTO DELANTE — no se hizo de paso a propósito:
--
-- `fn_resellar_dia` y `fn_levantar_sello_si_el_dia_cuadra` (migración 0084)
-- hacen LO MISMO con dos nombres distintos, y cada una está cableada a una
-- familia de funciones diferente:
--     fn_resellar_dia                  ← fn_agregar_marcaje, fn_corregir_marcaje,
--                                        fn_eliminar_marcaje  (solo producción)
--     fn_levantar_sello_si_el_dia_cuadra ← fn_corregir_marca, fn_anular_marcaje,
--                                        fn_reactivar_marcaje (repo y producción)
--
-- Es exactamente el problema que este repositorio lleva arreglando desde ayer:
-- la misma regla escrita dos veces. Arreglar una deja la otra rota y nada avisa.
-- Hay que unificarlas en una sola, y eso es una decisión de diseño, no un
-- copiar y pegar.
--
-- Además, `fn_agregar_marcaje` de producción trae algo que el repositorio no
-- tiene y que sí hace falta: la sede de una corrección la manda el DÍA, no el
-- escritorio. Si la persona ya marcó ese día en otra tienda, la corrección se
-- graba en esa misma sede. Sin eso la jornada queda partida entre dos sedes y
-- el terminal ve media verdad.
-- ============================================================================


-- ── 1 · fn_resellar_dia — no existe en el repositorio ───────────────────────
CREATE OR REPLACE FUNCTION public.fn_resellar_dia(p_persona_id uuid, p_fecha date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_dia_incoherente(p_persona_id, p_fecha) then
    update marcajes set estado_revision = 'pendiente_revision'
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and estado_revision = 'normal';
  else
    update marcajes set estado_revision = 'normal'
    where persona_id = p_persona_id
      and (timestamp_marca at time zone 'America/Lima')::date = p_fecha
      and estado_revision = 'pendiente_revision'
      and origen <> 'auto_cierre';
  end if;
end;
$function$;

-- ── 2 · fn_agregar_marcaje — producción trae la sede del DÍA y el resellado ──
CREATE OR REPLACE FUNCTION public.fn_agregar_marcaje(p_persona_id uuid, p_tipo tipo_marca, p_ts timestamp with time zone, p_motivo text, p_motivo_otro text DEFAULT NULL::text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sede uuid; v_nuevo marcajes; v_corr uuid; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;

  v_fecha := (p_ts at time zone 'America/Lima')::date;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
  ) then
    raise exception 'Esa fecha cae en un periodo ya PAGADO: agregar un marcaje ahí alteraría una planilla ya pagada. Reabre el periodo primero.';
  end if;

  v_corr := fn_verificar_corrector(p_persona_id);

  -- La sede la manda el DÍA, no el escritorio: si la persona ya marcó ese día
  -- (por ejemplo, de visita en otra tienda), la corrección se graba en esa misma
  -- sede. Solo si el día está vacío cae a su sede base. Sin esto, la jornada
  -- queda partida entre dos sedes y el terminal ve media verdad.
  select m.sede_id into v_sede
  from marcajes m
  where m.persona_id = p_persona_id
    and (m.timestamp_marca at time zone 'America/Lima')::date = v_fecha
    and m.sede_id is not null
  order by m.timestamp_marca, m.id
  limit 1;

  if v_sede is null then
    select sede_base_id into v_sede from personas where id = p_persona_id;
  end if;
  if v_sede is null then raise exception 'Persona no encontrada.'; end if;

  insert into marcajes (client_uuid, persona_id, sede_id, tipo, motivo_otro, timestamp_marca, origen, estado_revision)
  values (gen_random_uuid(), p_persona_id, v_sede, p_tipo, p_motivo_otro, p_ts, 'admin_correccion', 'revisada')
  returning * into v_nuevo;

  insert into correcciones_auditoria (marcaje_id, persona_id, campo_modificado, valor_anterior, valor_nuevo, corregido_por, motivo)
  values (v_nuevo.id, p_persona_id, 'marcaje_agregado', null, p_tipo::text || ' @ ' || p_ts::text, v_corr, trim(p_motivo));

  perform fn_resellar_dia(p_persona_id, v_fecha);

  return v_nuevo;
end;
$function$;

-- ── 3 · fn_corregir_marcaje — resella el día viejo Y el nuevo ───────────────
CREATE OR REPLACE FUNCTION public.fn_corregir_marcaje(p_marcaje_id uuid, p_nuevo_ts timestamp with time zone, p_motivo text)
 RETURNS marcajes
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_nuevo marcajes; v_corr uuid; v_fecha_ant date; v_fecha_nueva date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_fecha_ant := (v_ant.timestamp_marca at time zone 'America/Lima')::date;
  v_fecha_nueva := (p_nuevo_ts at time zone 'America/Lima')::date;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado'
      and (v_fecha_ant between fecha_ini and fecha_fin
           or v_fecha_nueva between fecha_ini and fecha_fin)
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

-- ── 4 · fn_eliminar_marcaje — resella el día tras borrar ────────────────────
CREATE OR REPLACE FUNCTION public.fn_eliminar_marcaje(p_marcaje_id uuid, p_motivo text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ant marcajes; v_corr uuid; v_fecha date;
begin
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'El motivo de la corrección es obligatorio.';
  end if;
  select * into v_ant from marcajes where id = p_marcaje_id;
  if not found then raise exception 'Marcaje no encontrado.'; end if;

  v_fecha := (v_ant.timestamp_marca at time zone 'America/Lima')::date;

  if exists (
    select 1 from periodos_planilla
    where estado = 'pagado' and v_fecha between fecha_ini and fecha_fin
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
