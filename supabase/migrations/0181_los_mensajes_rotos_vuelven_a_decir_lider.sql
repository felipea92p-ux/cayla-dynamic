-- ============================================================================
-- 0181_los_mensajes_rotos_vuelven_a_decir_lider.sql
-- ============================================================================
-- QUÉ PROMETE
--   Que los mensajes que estas cuatro funciones muestran a una persona vuelvan
--   a leerse en castellano. Hoy, en producción, dicen «l√≠der» donde deberían
--   decir «líder».
--
-- QUÉ ASUME
--   Nada nuevo. Los cuerpos son los mismos que ya están en el repositorio: no
--   cambia una coma de lógica, solo la codificación del texto.
--
-- POR QUÉ EXISTE
--   El 2026-08-07, comparando producción contra el repositorio función por
--   función, cuatro salieron distintas por muy poco: 3 y 5 caracteres. El
--   cuerpo de `fn_set_con_hijos` se pidió entero y se vio:
--
--       'Solo un administrador o l√≠der puede cambiar la asignaci√≥n familiar.'
--
--   Es MOJIBAKE: texto UTF-8 leído como Mac OS Roman. Cada acento se parte en
--   dos caracteres. Se comprobó simulando esa conversión sobre el cuerpo del
--   repositorio: sale idéntico, 313 caracteres y 324 bytes, y su md5 coincide
--   con el de producción. Las otras tres se confirmaron igual, por md5, sin
--   necesidad de pedir sus cuerpos.
--
--       fn_set_con_hijos        cfb3c0c0
--       fn_quitar_movimiento    81b5e161
--       fn_agregar_movimiento   ff25e88a
--       fn_simular_planilla     373e3c39
--
--   Los cuatro md5 de producción son exactamente los de simular la conversión
--   sobre el texto del repositorio. No hay lógica distinta: hay texto roto.
--
-- POR QUÉ NO SE VA A VOLVER A ROMPER AL APLICAR ESTO
--   Porque el canal habitual no es el culpable: si lo fuera, estarían rotas las
--   199 funciones, y están rotas cuatro. Ese daño entró una vez, por otra vía.
--   Pegar esto desde el SQL Editor devuelve el texto correcto.
--
-- QUÉ SE ROMPÍA SIN ESTO
--   Nada del cálculo — y por eso es fácil dejarlo pasar. Lo que se rompe es la
--   confianza: quien intenta cambiar la asignación familiar de alguien y recibe
--   «Solo un administrador o l√≠der puede…» no lee un permiso denegado, lee un
--   sistema averiado. Y deja de creerle al siguiente mensaje, que sí importa.
--
-- CÓMO SE REVIERTE
--   No se revierte. Volver atrás significa devolver el texto roto.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final devuelve 0. Cuenta cuántas funciones del esquema
--   llevan todavía el signo «√», que en castellano no aparece nunca dentro de
--   un mensaje: su presencia SIEMPRE es este daño.
-- ============================================================================

-- ── fn_agregar_movimiento ──  md5 correcto: ee67c18902ee72c36366505e3218886c
CREATE OR REPLACE FUNCTION public.fn_agregar_movimiento(p_periodo_id uuid, p_persona_id uuid, p_tipo text, p_concepto text, p_monto numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_estado text; v_id uuid;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar bonos o descuentos.';
  end if;
  select estado into v_estado from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  if p_tipo is null or p_tipo not in ('bono', 'descuento') then
    raise exception 'Tipo inválido (bono o descuento).';
  end if;
  if p_concepto is null or length(trim(p_concepto)) < 2 then
    raise exception 'El concepto es obligatorio.';
  end if;
  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto debe ser mayor a 0.';
  end if;
  if not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;

  insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, creado_por)
  values (p_periodo_id, p_persona_id, p_tipo, trim(p_concepto), round(p_monto, 2), fn_persona_actual_id())
  returning id into v_id;

  return jsonb_build_object('id', v_id);
end;
$function$;

-- ── fn_quitar_movimiento ──  md5 correcto: 6acec517707973b4e7c7461c8678ce28
CREATE OR REPLACE FUNCTION public.fn_quitar_movimiento(p_movimiento_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_estado text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede quitar bonos o descuentos.';
  end if;
  select pp.estado into v_estado
  from movimientos_planilla m join periodos_planilla pp on pp.id = m.periodo_id
  where m.id = p_movimiento_id;
  if not found then raise exception 'Movimiento inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  delete from movimientos_planilla where id = p_movimiento_id;
end;
$function$;

-- ── fn_set_con_hijos ──  md5 correcto: a5a5f35e8bedd9f128b2b92c05d0e1ff
CREATE OR REPLACE FUNCTION public.fn_set_con_hijos(p_persona_id uuid, p_con_hijos boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede cambiar la asignación familiar.';
  end if;
  update personas set con_hijos = coalesce(p_con_hijos, false) where id = p_persona_id;
  if not found then raise exception 'Persona inválida.'; end if;
end;
$function$;

-- ── fn_simular_planilla ──  md5 correcto: a4d5b292e6d51f4ce9f034e3890b99ff
CREATE OR REPLACE FUNCTION public.fn_simular_planilla(p_ini date, p_fin date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede simular la planilla.';
  end if;
  if p_ini is null or p_fin is null or p_fin < p_ini then
    raise exception 'Rango de fechas inválido.';
  end if;
  if (p_fin - p_ini) + 1 > 62 then
    raise exception 'La simulación admite máximo 62 días.';
  end if;
  return fn_planilla_calcular(p_ini, p_fin, null) || jsonb_build_object('simulacion', true);
end;
$function$;

-- ── El registro, y que la API recargue el esquema ───────────────────────────
insert into migraciones_aplicadas (numero, nombre)
values (181, 'los_mensajes_rotos_vuelven_a_decir_lider')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Va la ÚLTIMA a propósito: el SQL Editor solo muestra el resultado de la
-- última consulta. Debe decir 0.
--
-- No pregunta por las cuatro: barre el esquema ENTERO. Si el daño alcanzó a
-- alguna función que la comparación no señaló, aquí sale — y una lista de
-- cuatro nombres escrita a mano no lo habría visto nunca.
select count(*) as funciones_con_texto_roto,
       coalesce(string_agg(p.proname, ' ' order by p.proname), 'ninguna') as cuales
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname like 'fn\_%'
  and p.prosrc like '%' || chr(8730) || '%';
