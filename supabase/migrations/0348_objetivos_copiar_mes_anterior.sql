-- ============================================================================
-- 0348 — COPIAR OBJETIVOS DEL MES ANTERIOR
-- ----------------------------------------------------------------------------
-- Qué promete: un botón «Copiar del mes anterior» en /admin/objetivos, para
-- cuando el mes elegido no tiene checklist todavía. Duplica descripción,
-- indicaciones y orden de los objetivos del mes calendario previo de esa
-- misma persona — todos SIN marcar, porque son un objetivo nuevo que empieza
-- desde cero. Pedido pendiente desde el 2026-08-14 (docs/estado.md).
--
-- Qué asume: SOLO copia hacia un mes vacío. Si el mes destino ya tiene algún
-- objetivo, se niega — mezclar una copia con ediciones que ya existan es
-- ambiguo (¿se duplica lo que coincide? ¿se reemplaza?) y no hay pedido de
-- Felipe para resolver esa ambigüedad. Si el mes anterior no tiene ningún
-- objetivo, tampoco hay nada que copiar. No toca objetivos_mensuales
-- directamente: reusa fn_objetivos_sync_mes, igual que el resto de la 0032.
--
-- Por qué se eligió así: mismos guardas que fn_objetivo_agregar
-- (fn_puede_gestionar_objetivos, fn_mes_planilla_pagado, tope de 20) porque
-- el resultado es indistinguible de agregar los objetivos uno por uno — el
-- servidor tiene que revalidar lo mismo, no confiar en que la pantalla ya
-- filtró. El mes anterior se calcula con aritmética de fecha (restar un mes
-- al día 1), no con "if mes = 1", para no repetir a mano el caso de enero.
--
-- Cómo se revierte: `drop function fn_objetivos_copiar_mes_anterior(uuid, int, int);`
-- No hay columnas nuevas que revertir.
-- ============================================================================

create or replace function fn_objetivos_copiar_mes_anterior(p_persona_id uuid, p_anio int, p_mes int)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_prev date;
  v_prev_anio int;
  v_prev_mes int;
  v_copiados int;
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
  if fn_mes_planilla_pagado(p_anio, p_mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  if exists (
    select 1 from objetivos_items
    where persona_id = p_persona_id and anio = p_anio and mes = p_mes
  ) then
    raise exception 'Este mes ya tiene objetivos: solo se puede copiar hacia un mes vacío.';
  end if;

  v_prev := make_date(p_anio, p_mes, 1) - interval '1 month';
  v_prev_anio := extract(year from v_prev)::int;
  v_prev_mes := extract(month from v_prev)::int;

  if not exists (
    select 1 from objetivos_items
    where persona_id = p_persona_id and anio = v_prev_anio and mes = v_prev_mes
  ) then
    raise exception 'No hay objetivos en % de % para copiar.', v_prev_mes, v_prev_anio;
  end if;

  insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden)
  select p_persona_id, p_anio, p_mes, descripcion, indicaciones, orden
  from objetivos_items
  where persona_id = p_persona_id and anio = v_prev_anio and mes = v_prev_mes
  order by orden, created_at
  limit 20;

  get diagnostics v_copiados = row_count;

  perform fn_objetivos_sync_mes(p_persona_id, p_anio, p_mes);

  return jsonb_build_object('copiados', v_copiados);
end;
$$;

grant execute on function fn_objetivos_copiar_mes_anterior(uuid, int, int) to authenticated;
revoke execute on function fn_objetivos_copiar_mes_anterior(uuid, int, int) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (348, 'objetivos_copiar_mes_anterior')
on conflict (numero) do nothing;
