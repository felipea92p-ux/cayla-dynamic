-- ============================================================================
-- 0335 — TEXTO DE APOYO POR OBJETIVO
-- ----------------------------------------------------------------------------
-- Qué promete: cada objetivo del checklist (0032) puede llevar, además de su
-- descripción corta, unas indicaciones más largas — el detalle que ayuda a la
-- persona a entender qué se espera exactamente de ese objetivo.
--
-- Qué asume: es opcional y no cambia nada del pago. El checklist sigue sin
-- pagar nada (0171); esto solo agrega texto de ayuda a un objetivo que ya
-- existe. No toca objetivos_mensuales ni fn_planilla_calcular.
--
-- Por qué se eligió así: una columna nueva, nullable, en la misma tabla —no
-- una tabla aparte— porque es 1:1 con el objetivo y se lee siempre junto con
-- su descripción. Límite de 2000 caracteres: más que los 300 de la
-- descripción, porque el punto de esto es poder explicarse con más detalle.
--
-- Cómo se revierte: `alter table objetivos_items drop column indicaciones;`
-- y volver fn_objetivos_checklist / fn_objetivo_agregar / fn_objetivo_editar
-- a la versión de la 0032.
--
-- md5 de partida (producción, pedido antes de escribir):
--   fn_objetivos_checklist → fea63da0b5964eb738907a26df3907c5
--   fn_objetivo_agregar    → f0f66c3da8248b752dd26a32a763fb69
--   fn_objetivo_editar     → 81143dec842bdd957d9eeda7609b2d1e
-- ============================================================================

alter table objetivos_items
  add column if not exists indicaciones text
  check (indicaciones is null or length(indicaciones) <= 2000);

-- ---------------------------------------------------------------------------
-- Lectura del checklist: agrega 'indicaciones'. Resto idéntico a la 0032.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_checklist(p_anio int, p_mes int, p_persona_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', oi.id,
           'persona_id', oi.persona_id,
           'descripcion', oi.descripcion,
           'indicaciones', oi.indicaciones,
           'cumplido', oi.cumplido,
           'orden', oi.orden
         ) order by oi.orden, oi.created_at), '[]'::jsonb)
  from objetivos_items oi
  where oi.anio = p_anio and oi.mes = p_mes
    and (p_persona_id is null or oi.persona_id = p_persona_id)
    and (
      fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and exists (
            select 1 from personas p
            where p.id = oi.persona_id
              and p.sede_base_id = fn_sede_actual_persona()))
      or oi.persona_id = fn_persona_actual_id()
    );
$$;

-- ---------------------------------------------------------------------------
-- Agregar objetivo: acepta indicaciones opcionales. Resto idéntico a la 0032.
--
-- `create or replace` NO alcanza para agregar un parámetro: dos funciones con
-- distinto número de argumentos son sobrecargas distintas, no la misma
-- reemplazada, y con el nuevo parámetro por defecto la llamada vieja de 4
-- argumentos queda ambigua entre las dos — «function ... is not unique» — el
-- mismo síntoma que la 0297/0299 dejó en producción con el aviso de
-- vacaciones. Se comprobó en la auditoría de esta migración. Por eso se borra
-- primero la firma vieja.
-- ---------------------------------------------------------------------------
drop function if exists fn_objetivo_agregar(uuid, int, int, text);

create function fn_objetivo_agregar(
  p_persona_id uuid, p_anio int, p_mes int, p_descripcion text,
  p_indicaciones text default null
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_desc text := btrim(coalesce(p_descripcion, ''));
  v_indic text := nullif(btrim(coalesce(p_indicaciones, '')), '');
  v_item objetivos_items;
begin
  if fn_puede_gestionar_objetivos(p_persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if p_persona_id is null or not exists (select 1 from personas where id = p_persona_id) then
    raise exception 'Persona inválida.';
  end if;
  if p_anio is null or p_mes is null or p_mes not between 1 and 12 or p_anio not between 2020 and 2100 then
    raise exception 'Mes inválido.';
  end if;
  if length(v_desc) < 1 or length(v_desc) > 300 then
    raise exception 'El objetivo debe tener entre 1 y 300 caracteres.';
  end if;
  if v_indic is not null and length(v_indic) > 2000 then
    raise exception 'Las indicaciones no pueden superar los 2000 caracteres.';
  end if;
  if fn_mes_planilla_pagado(p_anio, p_mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  if (select count(*) from objetivos_items
      where persona_id = p_persona_id and anio = p_anio and mes = p_mes) >= 20 then
    raise exception 'Máximo 20 objetivos por persona y mes.';
  end if;

  insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden)
  values (
    p_persona_id, p_anio, p_mes, v_desc, v_indic,
    coalesce((select max(orden) from objetivos_items
              where persona_id = p_persona_id and anio = p_anio and mes = p_mes), 0) + 1
  )
  returning * into v_item;

  perform fn_objetivos_sync_mes(p_persona_id, p_anio, p_mes);

  return jsonb_build_object(
    'id', v_item.id, 'persona_id', v_item.persona_id,
    'descripcion', v_item.descripcion, 'indicaciones', v_item.indicaciones,
    'cumplido', v_item.cumplido, 'orden', v_item.orden
  );
end;
$$;

grant execute on function fn_objetivo_agregar(uuid, int, int, text, text) to authenticated;
revoke execute on function fn_objetivo_agregar(uuid, int, int, text, text) from public, anon;

-- ---------------------------------------------------------------------------
-- Editar: acepta indicaciones opcionales. El llamador (única pantalla que usa
-- esta RPC) siempre manda el valor vigente del campo, así que un indicaciones
-- ausente aquí significa «se borró a propósito», no «no tocar».
--
-- Mismo motivo que fn_objetivo_agregar arriba: se borra la firma vieja de 2
-- argumentos antes de crear la de 3, para no dejar dos sobrecargas ambiguas.
-- ---------------------------------------------------------------------------
drop function if exists fn_objetivo_editar(uuid, text);

create function fn_objetivo_editar(p_item_id uuid, p_descripcion text, p_indicaciones text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item objetivos_items;
  v_desc text := btrim(coalesce(p_descripcion, ''));
  v_indic text := nullif(btrim(coalesce(p_indicaciones, '')), '');
begin
  select * into v_item from objetivos_items where id = p_item_id;
  if not found then raise exception 'Objetivo inexistente.'; end if;
  if fn_puede_gestionar_objetivos(v_item.persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if fn_mes_planilla_pagado(v_item.anio, v_item.mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  if length(v_desc) < 1 or length(v_desc) > 300 then
    raise exception 'El objetivo debe tener entre 1 y 300 caracteres.';
  end if;
  if v_indic is not null and length(v_indic) > 2000 then
    raise exception 'Las indicaciones no pueden superar los 2000 caracteres.';
  end if;

  update objetivos_items
     set descripcion = v_desc, indicaciones = v_indic, updated_at = now()
   where id = p_item_id;
end;
$$;

grant execute on function fn_objetivo_editar(uuid, text, text) to authenticated;
revoke execute on function fn_objetivo_editar(uuid, text, text) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (335, 'objetivos_texto_de_apoyo')
on conflict (numero) do nothing;
