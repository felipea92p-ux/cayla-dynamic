-- ============================================================================
-- 0188 — El resellado del día entra al repositorio
-- ============================================================================
--
-- QUÉ PROMETE
--   Que las cuatro funciones que hoy solo existen en producción queden también
--   en el repositorio, **byte por byte iguales**. Después de esta migración,
--   `supabase db reset` reproduce lo que de verdad corre, y ningún repegado
--   puede borrarlas sin que se note.
--
-- QUÉ ASUME
--   Que producción no las ha tocado desde el 2026-07-27. Comprobado el
--   2026-08-08 comparando md5: las tres del rescate coinciden exactamente con
--   las de producción hoy (2ccd19ee · 9208e26d · 94eda7b8). No se movieron.
--
-- ── POR QUÉ ESTA MIGRACIÓN NO CAMBIA NADA, Y AUN ASÍ HACE FALTA ─────────────
--
-- Producción ya tiene las cuatro. Aplicar esto en producción es un no-op: se
-- reemplaza cada función por sí misma. Lo que cambia es el REPOSITORIO.
--
-- Hasta hoy este código vivía en un solo lugar del mundo. La migración 0102
-- (27 de julio) lo detectó, lo rescató en `docs/rescatado-de-produccion.sql` y
-- escribió «hay que reconciliarlas a mano». Doce días después seguía pendiente,
-- y el aviso vivía dentro del comentario de una migración que nadie vuelve a
-- abrir: `docs/estado.md` no lo listaba. **Lo que no está en la lista de
-- pendientes no existe.**
--
-- El riesgo concreto de dejarlo así: `dame-el-sql.sh 37` entrega la 0037, que
-- redefine las tres SIN estas mejoras. Pegarla para reparar otra cosa las
-- borraría en silencio — exactamente lo que le pasó a la 0177 el 2026-08-07.
--
-- ── QUÉ TRAE, QUE EL REPOSITORIO NO TENÍA ──────────────────────────────────
--
--   1. `fn_resellar_dia` — no existía. Reevalúa el sello de «día por revisar»
--      DESPUÉS de cada corrección, en los dos sentidos: lo pone si el día quedó
--      roto y lo quita si volvió a cuadrar.
--
--   2. Las tres funciones de corrección la llaman. Sin eso, corregir un marcaje
--      podía dejar el día sellado para siempre aunque ya cuadrara — el defecto
--      que la 0084 arregló para OTRA familia de funciones y que aquí seguía
--      abierto.
--
--   3. `fn_agregar_marcaje`: **la sede la manda el DÍA, no el escritorio.** Si
--      la persona ya marcó ese día en otra tienda, la corrección se graba en esa
--      misma sede. Antes caía siempre a su sede base, y la jornada quedaba
--      partida entre dos sedes.
--
-- ── LA DECISIÓN QUE SIGUE ABIERTA, AHORA CON DATOS ─────────────────────────
--
-- `docs/rescatado-de-produccion.sql` dice que `fn_resellar_dia` y
-- `fn_levantar_sello_si_el_dia_cuadra` «hacen LO MISMO con dos nombres
-- distintos». **Medido el 2026-08-08, eso no es exacto** — y la diferencia
-- importa para decidir cómo unificarlas:
--
--   | situación          | fn_resellar_dia        | fn_levantar_sello_si_el_dia_cuadra |
--   |--------------------|------------------------|------------------------------------|
--   | el día está roto   | PONE el sello          | no hace nada, devuelve 0           |
--   | el día cuadra      | lo quita → 'normal'    | lo quita → 'revisada'              |
--   | marcas anuladas    | NO las excluye         | exige `anulada_at is null`         |
--   | devuelve           | void                   | cuántas filas tocó                 |
--
-- Son dos comportamientos distintos, no dos nombres de uno. Unificarlas exige
-- decidir tres cosas —si el sello se pone solo, en qué estado queda un día que
-- vuelve a cuadrar, y si una marca anulada cuenta— y eso es diseño, no copiar y
-- pegar. **Esta migración NO lo decide**: trae lo que hay, para que la decisión
-- se tome con las dos versiones dentro del repositorio y con pruebas alrededor.
--
-- La tercera fila es la que más pesa: la 0081 y la 0082 enseñaron a todo el
-- sistema a ignorar las marcas anuladas, y `fn_resellar_dia` se quedó fuera de
-- ese barrido. No se corrige aquí a propósito — cambiarla mientras se la trae
-- haría imposible saber si un fallo posterior vino del rescate o del arreglo.
--
-- CÓMO SE REVIERTE
--   En el repositorio: borrar este archivo. En producción no hay nada que
--   revertir — ya tenía estas cuatro versiones antes de aplicarla.
-- ============================================================================


-- ── 1 · fn_resellar_dia — la que no existía en el repositorio ───────────────
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

grant  execute on function fn_resellar_dia(uuid, date) to authenticated;
revoke execute on function fn_resellar_dia(uuid, date) from public, anon;


-- ── 2 · fn_agregar_marcaje — la sede del DÍA, y el resellado ────────────────
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


insert into migraciones_aplicadas (numero, nombre)
values (188, 'el_resellado_del_dia_entra_al_repositorio')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── La comprobación que dice si el rescate quedó fiel ───────────────────────
-- Los md5 son los MEDIDOS en producción el 2026-08-08. Si alguno no coincide,
-- el cuerpo se copió mal y hay que parar: no sirve traer al repositorio una
-- versión que no es la que corre.
do $mig$
declare
  v_mal text := '';
  r record;
begin
  for r in
    select * from (values
      ('fn_agregar_marcaje',  '2ccd19ee'),
      ('fn_corregir_marcaje', '9208e26d'),
      ('fn_eliminar_marcaje', '94eda7b8'),
      ('fn_resellar_dia',     'ba93483f')
    ) as t(fn, esperado)
  loop
    if (select left(md5(prosrc), 8) from pg_proc where proname = r.fn limit 1)
       is distinct from r.esperado then
      v_mal := v_mal || ' ' || r.fn;
    end if;
  end loop;

  if v_mal <> '' then
    raise warning '0188 · OJO: estas NO quedaron como en produccion:%', v_mal;
    raise warning '0188 · el cuerpo se copio mal. No des la migracion por buena.';
  else
    raise notice '0188 · las cuatro coinciden con produccion, byte por byte.';
  end if;
end $mig$;
