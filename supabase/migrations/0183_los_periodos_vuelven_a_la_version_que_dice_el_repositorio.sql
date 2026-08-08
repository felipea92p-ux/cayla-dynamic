-- ============================================================================
-- 0183_los_periodos_vuelven_a_la_version_que_dice_el_repositorio.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que `fn_crear_periodo` y `fn_eliminar_periodo` de producción digan lo mismo
--   que el repositorio: mensajes legibles, y un error en castellano —en vez de
--   uno crudo de Postgres— cuando alguien intenta crear dos periodos que
--   cierran el mismo mes.
--
-- QUÉ ASUME
--   Que `periodos_planilla` encadena: cada periodo empieza el día siguiente al
--   cierre del anterior. Viene de la 0025 y no ha cambiado.
--
-- CÓMO SE ENCONTRÓ — la parte útil
--   La comprobación de la 0181 no preguntaba por las cuatro funciones que esa
--   migración arreglaba: barría el esquema entero buscando el signo «√», que en
--   castellano nunca aparece dentro de un mensaje. Devolvió DOS que no estaban
--   en la lista. Una lista escrita a mano las habría dado por buenas.
--
--   Medidas, resultó que producción corre la versión ANTERIOR a la 0026 y encima
--   mal codificada. El md5 coincide exactamente con el de la 0025 pasada por
--   Mac OS Roman:
--
--       fn_crear_periodo      47530434   = 0025 con acentos rotos
--       fn_eliminar_periodo   a56927fb   = 0025 con acentos rotos
--
-- LO QUE ESTA MIGRACIÓN **NO** ARREGLA, Y CASI SE ANUNCIÓ QUE SÍ
--   La 0026 añadió a `fn_crear_periodo` un candado contra dos periodos que
--   cierren el mismo mes, con este motivo escrito en julio: «el plus de
--   objetivos se pagaría doble». Al ver que producción no lo tenía, la
--   conclusión evidente era que el plus se podía pagar dos veces.
--
--   Se probó antes de afirmarlo, y es FALSO. Con el código de producción, crear
--   el segundo periodo falla igual — lo frena el índice único
--   `periodos_etiqueta_unica`, sobre (año, mes) de la fecha de cierre. Y el
--   2026-08-07 se comprobó que los 261 candados de producción son idénticos a
--   los del repositorio, byte a byte: ese índice está.
--
--   Lo mismo con el `pg_advisory_xact_lock` que también falta: sin él, dos
--   creaciones simultáneas no dejan un hueco ni un solape, porque el constraint
--   de exclusión `periodos_sin_solape` lo impide. Lo que el lock evita es que
--   una de las dos muera con un error crudo en vez de esperar su turno.
--
--   Así que el valor real de esta migración es modesto y conviene decirlo:
--     · los mensajes dejan de leerse «entre 20 y 46 d√≠as»;
--     · quien intente el periodo repetido lee «Ya existe un periodo que cierra
--       en 10/2026…» en vez de «duplicate key value violates unique constraint»,
--       que es justo la clase de texto que `mensajeDeError` esconde y convierte
--       en un genérico inútil;
--     · producción deja de correr una versión de julio que nadie sabía viva.
--
--   La lección, que vale más que la migración: el candado que de verdad protege
--   el dinero aquí es el de la BASE, no el de la función. Un constraint vale más
--   que diez validaciones en el código — y hoy eso dejó de ser una frase.
--
-- CÓMO SE REVIERTE
--   Volviendo a los cuerpos de la 0025. No hay motivo para hacerlo.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final debe decir 0 y «ninguna». Barre el esquema entero
--   otra vez: si quedara alguna función con texto roto, sale ahí.
-- ============================================================================

-- ── fn_crear_periodo ──  md5 correcto (0026): c2f7ac69eb357d742fcbd30e3be063a9
CREATE OR REPLACE FUNCTION public.fn_crear_periodo(p_fecha_fin date, p_fecha_ini date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ini date; v_id uuid; v_ultimo date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede crear periodos.';
  end if;
  if p_fecha_fin is null then raise exception 'La fecha de cierre es obligatoria.'; end if;

  -- serializar contra otra creación/eliminación simultánea (sin huecos por carrera)
  perform pg_advisory_xact_lock(hashtext('periodos_planilla'));

  select max(fecha_fin) into v_ultimo from periodos_planilla;
  if v_ultimo is null then
    if p_fecha_ini is null then
      raise exception 'Para el primer periodo debes indicar la fecha de inicio.';
    end if;
    v_ini := p_fecha_ini;
  else
    v_ini := v_ultimo + 1;
    if p_fecha_ini is not null and p_fecha_ini <> v_ini then
      raise exception 'El inicio se encadena automáticamente al % (día siguiente al último cierre).', v_ini;
    end if;
  end if;

  if p_fecha_fin < v_ini + 19 or p_fecha_fin > v_ini + 45 then
    raise exception 'El periodo debe durar entre 20 y 46 días (inicio %, cierre propuesto %).', v_ini, p_fecha_fin;
  end if;

  -- un solo periodo por mes de cierre (el plus de objetivos se pagaría doble)
  if exists (
    select 1 from periodos_planilla
    where extract(year from fecha_fin)::int = extract(year from p_fecha_fin)::int
      and extract(month from fecha_fin)::int = extract(month from p_fecha_fin)::int
  ) then
    raise exception 'Ya existe un periodo que cierra en %/% — dos periodos con el mismo mes de cierre pagarían el plus de objetivos dos veces. Elige un cierre en otro mes.',
      extract(month from p_fecha_fin)::int, extract(year from p_fecha_fin)::int;
  end if;

  insert into periodos_planilla (fecha_ini, fecha_fin, creado_por)
  values (v_ini, p_fecha_fin, fn_persona_actual_id())
  returning id into v_id;

  return jsonb_build_object('id', v_id, 'fecha_ini', v_ini, 'fecha_fin', p_fecha_fin);
end;
$function$;

-- ── fn_eliminar_periodo ──  md5 correcto (0026): 14acc43cf164ba17e9e7e6cf0f7dc228
CREATE OR REPLACE FUNCTION public.fn_eliminar_periodo(p_periodo_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fin date; v_estado text; v_max date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede eliminar periodos.';
  end if;
  perform pg_advisory_xact_lock(hashtext('periodos_planilla'));
  select fecha_fin, estado into v_fin, v_estado from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  select max(fecha_fin) into v_max from periodos_planilla;
  if v_fin <> v_max then
    raise exception 'Solo se puede eliminar el ÚLTIMO periodo (para no romper la cadena).';
  end if;
  if v_estado = 'pagado' then
    raise exception 'Un periodo pagado no se elimina; reábrelo primero si de verdad hace falta.';
  end if;
  delete from periodos_planilla where id = p_periodo_id;
end;
$function$;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (183, 'los_periodos_vuelven_a_la_version_que_dice_el_repositorio')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado de la
-- última consulta. Debe decir 0 y «ninguna».
select count(*) as funciones_con_texto_roto,
       coalesce(string_agg(p.proname, ' ' order by p.proname), 'ninguna') as cuales
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname like 'fn\_%'
  and p.prosrc like '%' || chr(8730) || '%';
