-- ============================================================================
-- 0195_las_cuatro_funciones_que_el_repositorio_no_conocia.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que el repositorio diga lo mismo que producción en cuatro funciones que
--   habían crecido solo allí. **No cambia nada en producción:** los cuerpos son
--   exactamente los que ya corren, pedidos con `pg_get_functiondef` el
--   2026-08-08. Lo que cambia es el REPOSITORIO, que hasta hoy tenía una versión
--   más pobre de las cuatro.
--
-- QUÉ ASUME
--   Nada. Se pegan tal cual llegaron, sin una coma de diferencia.
--
-- ── POR QUÉ EXISTE ──────────────────────────────────────────────────────────
--
-- El 2026-08-08 se comparó el esquema entero de producción contra el del
-- repositorio. Siete funciones tenían MÁS código en producción: alguien las
-- mejoró aplicando el cambio a mano y el archivo nunca se guardó. La 0188
-- rescató tres; estas son las cuatro que quedaban, con cuántos caracteres de
-- más tenía cada una:
--
--     fn_set_sueldo_base_legal   +562
--     fn_quitar_rendimiento      +358
--     fn_set_rendimiento         +235
--     fn_set_meta_cobertura       +11
--
-- QUÉ ERA ESE «MÁS», leído de los cuerpos que llegaron: en tres de las cuatro es
-- el candado de planilla pagada del CAMBIO 0111. `fn_set_rendimiento` y
-- `fn_quitar_rendimiento` se niegan a puntuar —o a despuntuar— un mes ya pagado,
-- porque las dos cosas mueven el total; y `fn_set_sueldo_base_legal` se niega a
-- cambiar la básica de quien tenga meses pagados con puntuación menor a 100.
--
-- O sea: **el repositorio tenía versiones SIN esos candados.** Cualquier
-- migración futura que copiara de aquí los habría borrado en silencio, igual que
-- pasó con las seis puertas que la 0180 tuvo que reponer el mismo día. Esto no
-- es orden por el orden: es cerrar la puerta por la que ya entró un problema.
--
-- ── POR QUÉ NO SE ESCRIBEN A MANO «BONITAS» ─────────────────────────────────
--
-- Porque el objetivo es que el plano describa el edificio, no que lo mejore. Si
-- al copiarlas se reformatea, se renombra o se «arregla» algo, el md5 deja de
-- coincidir y no hay forma de comprobar que el rescate salió bien. Cualquier
-- mejora va después, en su propia migración y con su propia prueba.
--
-- CÓMO SE REVIERTE
--   No se revierte. Volver atrás significa devolverle al repositorio unas
--   versiones sin candado de periodo pagado.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final debe decir 4.
-- ============================================================================

-- ── fn_set_sueldo_base_legal ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_sueldo_base_legal(p_persona_id uuid, p_monto numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede fijar la remuneración básica legal.';
  end if;
  if p_monto is not null and p_monto <= 0 then
    raise exception 'La remuneración básica legal debe ser mayor que cero.';
  end if;

  -- ⇩ CAMBIO 0111 ⇩ Solo bloquea cuando el cambio movería un total ya pagado:
  -- una puntuación por debajo de 100 en un mes cerrado. Ver la cabecera.
  if exists (
    select 1
    from rendimiento_mensual r
    where r.persona_id = p_persona_id
      and r.porcentaje < 100
      and fn_mes_planilla_pagado(r.anio, r.mes)
  ) then
    raise exception 'Esta persona tiene meses ya PAGADOS con una puntuación de rendimiento menor a 100. Cambiar su básica legal alteraría el total de esos meses. Reabre el periodo si de verdad hay que corregirlo.';
  end if;

  update personas set sueldo_base_legal = p_monto where id = p_persona_id;
  if not found then
    raise exception 'No existe esa persona.';
  end if;
end;
$function$;

-- ── fn_quitar_rendimiento ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_quitar_rendimiento(p_persona_id uuid, p_anio integer, p_mes integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar una puntuación.';
  end if;

  -- ⇩ CAMBIO 0111 ⇩ Quitar la puntuación SUBE el pago (vuelve al 100% por
  -- defecto). Mover un total pagado hacia arriba es tan inválido como moverlo
  -- hacia abajo: la foto deja de cuadrar igual.
  if fn_mes_planilla_pagado(p_anio, p_mes) then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;

  delete from rendimiento_mensual
  where persona_id = p_persona_id and anio = p_anio and mes = p_mes;
end;
$function$;

-- ── fn_set_rendimiento ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_rendimiento(p_persona_id uuid, p_anio integer, p_mes integer, p_porcentaje numeric, p_etiqueta_codigo text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede puntuar el rendimiento.';
  end if;
  if p_porcentaje is null or p_porcentaje < 0 or p_porcentaje > 100 then
    raise exception 'El rendimiento debe estar entre 0 y 100.';
  end if;
  if p_mes < 1 or p_mes > 12 then
    raise exception 'Mes inválido.';
  end if;

  -- ⇩ CAMBIO 0111 ⇩ Mismo candado y mismo mensaje que fn_set_objetivos (0032).
  if fn_mes_planilla_pagado(p_anio, p_mes) then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;

  if p_etiqueta_codigo is not null
     and not exists (select 1 from etiquetas_complemento where codigo = p_etiqueta_codigo) then
    raise exception 'Esa etiqueta no está en el catálogo.';
  end if;

  insert into rendimiento_mensual (persona_id, anio, mes, porcentaje, etiqueta_codigo, puesto_por)
  values (p_persona_id, p_anio, p_mes, p_porcentaje, p_etiqueta_codigo, fn_persona_actual_id())
  on conflict (persona_id, anio, mes) do update
    set porcentaje      = excluded.porcentaje,
        etiqueta_codigo = excluded.etiqueta_codigo,
        puesto_por      = excluded.puesto_por,
        updated_at      = now();
end;
$function$;

-- ── fn_set_meta_cobertura ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_set_meta_cobertura(p_sede_id uuid, p_dia_semana integer, p_meta integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_rol_actual() not in ('admin', 'lider_do') then
    raise exception 'Solo un administrador puede definir la meta de cobertura.';
  end if;
  if p_dia_semana < 0 or p_dia_semana > 6 then raise exception 'Día de la semana inválido.'; end if;
  if p_meta < 0 then raise exception 'La meta no puede ser negativa.'; end if;
  insert into metas_cobertura (sede_id, dia_semana, meta, updated_at)
  values (p_sede_id, p_dia_semana, p_meta, now())
  on conflict (sede_id, dia_semana) do update set meta = excluded.meta, updated_at = now();
end;
$function$;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (195, 'las_cuatro_funciones_que_el_repositorio_no_conocia')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra la última consulta.
-- Debe decir 3 y 4: las tres que llevan candado de periodo pagado, y las cuatro
-- rescatadas. `PAGAD` y no `PAGADA` porque fn_set_sueldo_base_legal dice
-- «meses ya PAGADOS», en plural: buscar la palabra exacta contaba 2 de 3 y daba
-- por incompleto un rescate que estaba bien.
select
  count(*) filter (where p.prosrc ~ 'PAGAD') as con_candado_de_pagado,
  count(*) as las_cuatro
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (p.proname || '/' || p.pronargs) in (
        'fn_set_sueldo_base_legal/2', 'fn_quitar_rendimiento/3',
        'fn_set_rendimiento/5', 'fn_set_meta_cobertura/3');
