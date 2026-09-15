-- ============================================================================
-- 0449 — OBJETIVOS RECUERDAN QUIÉN LOS TOCÓ (autor + fecha, sin motivo)
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: objetivos_items gana quién creó cada objetivo, quién lo editó
-- o marcó cumplido por última vez, y quién lo eliminó — sin pedir motivo en
-- ningún caso. Decisión de Felipe por AskUserQuestion durante la auditoría
-- UX/UI del módulo (2026-09-14): "Autor + fecha, sin motivo" sobre las otras
-- dos alternativas evaluadas — motivo obligatorio solo al eliminar/desmarcar,
-- o un historial completo tipo línea de tiempo. El checklist es la evidencia
-- que sostiene un cambio de categoría (política salarial firmada, 0141); hoy
-- objetivos_items solo tiene created_at/updated_at sin autor, y
-- fn_objetivo_eliminar hace un `delete` físico sin dejar rastro — quien
-- disputara un cumplimiento borrado antes de una evaluación no tenía cómo
-- probarlo.
--
-- QUÉ ASUME: "eliminar" deja de ser un `delete` físico y pasa a ser un
-- marcado blando (eliminado_at/eliminado_por) — el mismo principio que ya usa
-- el resto de la casa para todo lo demás ("las personas nunca se borran, se
-- marcan inactivas", CLAUDE.md). Las siete funciones de la 0032/0335/0361 que
-- leen o escriben objetivos_items se reescriben para filtrar
-- `eliminado_at is null` en cada lectura; ninguna cambia su firma (mismos
-- parámetros; el jsonb de salida de fn_objetivos_checklist/fn_objetivo_agregar
-- gana dos claves, creado_por/actualizado_por, no pierde ninguna). El tope de
-- 20 objetivos y el "máximo de orden" dejan de contar los eliminados: borrar
-- abre sitio para agregar de nuevo, igual que antes con el delete físico. No
-- se pide motivo en ningún caso — se evaluó y se descartó a propósito, porque
-- a esta escala (~30 personas, el checklist arrancó recién en septiembre de
-- 2026) el costo de escribir un motivo en cada acción no se justifica todavía.
--
-- POR QUÉ SE ELIGIÓ ASÍ: cuatro columnas nullable en la misma tabla, no una
-- tabla de auditoría aparte — el molde de "historial completo" (una fila por
-- cambio) se evaluó y se descartó explícitamente por ser el de mayor costo de
-- construir y mantener, sin que hoy haya una necesidad concreta que lo pida.
-- `eliminado_at is null` como filtro repetido en cada lectura, en vez de
-- sobrecargar una columna que ya existe (por ejemplo, `cumplido = null` para
-- decir "borrado") — una columna nunca dice dos cosas distintas en este repo.
--
-- CÓMO SE REVIERTE:
--   alter table objetivos_items
--     drop column creado_por, drop column actualizado_por,
--     drop column eliminado_at, drop column eliminado_por;
--   Y volver los cuerpos de fn_objetivos_sync_mes, fn_objetivos_checklist,
--   fn_objetivo_agregar, fn_objetivo_marcar, fn_objetivo_editar,
--   fn_objetivo_eliminar, fn_objetivos_copiar_mes_anterior y
--   fn_objetivos_resumen a los de la 0032/0335/0361 (fn_objetivo_eliminar
--   volvería a hacer `delete` físico).
--
-- md5 DE PARTIDA (Postgres LOCAL, 2026-09-14 — este repo lo pide siempre a
-- PRODUCCIÓN con ./scripts/donde-vive.sh justo antes de pegar, no al escribir;
-- los de abajo son el punto de partida de ESTA Mac, no un sustituto de eso):
--   fn_objetivos_sync_mes              fa33e9e21044daabec1586bd4b544a65
--   fn_objetivos_checklist             67015e0215108829be2cde7a01e2df11
--   fn_objetivo_agregar                bb1b414c3c95cae5ef92de5a2b99a344
--   fn_objetivo_marcar                 ea9efea843c782d9e0e5118df5707aa5
--   fn_objetivo_editar                 57f396cb0f57b3512689c101005d3ceb
--   fn_objetivo_eliminar               8831f1382677f2a7741824161a226504
--   fn_objetivos_copiar_mes_anterior   5941a518d8445665183fc876d8d07b4a
--   fn_objetivos_resumen               de85e39f25c4e9873625b06dfa99962b
-- ============================================================================

alter table objetivos_items
  add column if not exists creado_por uuid references personas(id),
  add column if not exists actualizado_por uuid references personas(id),
  add column if not exists eliminado_at timestamptz,
  add column if not exists eliminado_por uuid references personas(id);

-- ---------------------------------------------------------------------------
-- Sync checklist → objetivos_mensuales: ahora solo cuenta lo NO eliminado.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_sync_mes(p_persona_id uuid, p_anio int, p_mes int)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_total int;
  v_cumplidos int;
begin
  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ ignora los ítems con borrado blando.
  select count(*), count(*) filter (where cumplido)
    into v_total, v_cumplidos
  from objetivos_items
  where persona_id = p_persona_id and anio = p_anio and mes = p_mes
    and eliminado_at is null;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧

  if v_total = 0 then
    delete from objetivos_mensuales
    where persona_id = p_persona_id and anio = p_anio and mes = p_mes;
  else
    insert into objetivos_mensuales (persona_id, anio, mes, cumplidos, total)
    values (p_persona_id, p_anio, p_mes, v_cumplidos, v_total)
    on conflict (persona_id, anio, mes) do update set
      cumplidos = excluded.cumplidos,
      total = excluded.total,
      updated_at = now();
  end if;
end;
$$;

-- Interna: la llaman las RPC de mutación; SIN grant a authenticated (igual que la 0032).
revoke execute on function fn_objetivos_sync_mes(uuid, int, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Lectura del checklist: deja fuera lo eliminado y agrega autor.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_checklist(p_anio int, p_mes int, p_persona_id uuid default null)
returns jsonb
language sql stable security definer set search_path = public
as $$
  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ filtro de borrado blando + autor y fecha.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', oi.id,
           'persona_id', oi.persona_id,
           'descripcion', oi.descripcion,
           'indicaciones', oi.indicaciones,
           'cumplido', oi.cumplido,
           'orden', oi.orden,
           'creado_por', oi.creado_por,
           'creado_at', oi.created_at,
           'actualizado_por', oi.actualizado_por,
           'actualizado_at', oi.updated_at
         ) order by oi.orden, oi.created_at), '[]'::jsonb)
  from objetivos_items oi
  where oi.anio = p_anio and oi.mes = p_mes
    and oi.eliminado_at is null
    and (p_persona_id is null or oi.persona_id = p_persona_id)
    and (
      fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and exists (
            select 1 from personas p
            where p.id = oi.persona_id
              and p.sede_base_id = fn_sede_actual_persona()))
      or oi.persona_id = fn_persona_actual_id()
    );
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧
$$;

grant execute on function fn_objetivos_checklist(int, int, uuid) to authenticated;
revoke execute on function fn_objetivos_checklist(int, int, uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Agregar objetivo: sella creado_por/actualizado_por; el tope de 20 y el
-- máximo de "orden" dejan de contar lo eliminado.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_agregar(
  p_persona_id uuid, p_anio int, p_mes int, p_descripcion text,
  p_indicaciones text default null
)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_desc text := btrim(coalesce(p_descripcion, ''));
  v_indic text := nullif(btrim(coalesce(p_indicaciones, '')), '');
  v_actor uuid := fn_persona_actual_id();
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
  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ el tope de 20 no cuenta lo eliminado.
  if (select count(*) from objetivos_items
      where persona_id = p_persona_id and anio = p_anio and mes = p_mes
        and eliminado_at is null) >= 20 then
    raise exception 'Máximo 20 objetivos por persona y mes.';
  end if;

  insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden, creado_por, actualizado_por)
  values (
    p_persona_id, p_anio, p_mes, v_desc, v_indic,
    coalesce((select max(orden) from objetivos_items
              where persona_id = p_persona_id and anio = p_anio and mes = p_mes
                and eliminado_at is null), 0) + 1,
    v_actor, v_actor
  )
  returning * into v_item;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧

  perform fn_objetivos_sync_mes(p_persona_id, p_anio, p_mes);

  return jsonb_build_object(
    'id', v_item.id, 'persona_id', v_item.persona_id,
    'descripcion', v_item.descripcion, 'indicaciones', v_item.indicaciones,
    'cumplido', v_item.cumplido, 'orden', v_item.orden,
    'creado_por', v_item.creado_por, 'actualizado_por', v_item.actualizado_por
  );
end;
$$;

grant execute on function fn_objetivo_agregar(uuid, int, int, text, text) to authenticated;
revoke execute on function fn_objetivo_agregar(uuid, int, int, text, text) from public, anon;

-- ---------------------------------------------------------------------------
-- Marcar / desmarcar: ignora lo eliminado, sella actualizado_por.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_marcar(p_item_id uuid, p_cumplido boolean)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item objetivos_items;
begin
  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ un ítem eliminado ya no se puede marcar.
  select * into v_item from objetivos_items where id = p_item_id and eliminado_at is null;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧
  if not found then raise exception 'Objetivo inexistente.'; end if;
  if fn_puede_gestionar_objetivos(v_item.persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if fn_mes_planilla_pagado(v_item.anio, v_item.mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;
  if p_cumplido is null then raise exception 'Valor inválido.'; end if;

  update objetivos_items
     set cumplido = p_cumplido, updated_at = now(), actualizado_por = fn_persona_actual_id()
   where id = p_item_id;
  perform fn_objetivos_sync_mes(v_item.persona_id, v_item.anio, v_item.mes);
end;
$$;

grant execute on function fn_objetivo_marcar(uuid, boolean) to authenticated;
revoke execute on function fn_objetivo_marcar(uuid, boolean) from public, anon;

-- ---------------------------------------------------------------------------
-- Editar el texto: ignora lo eliminado, sella actualizado_por.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_editar(p_item_id uuid, p_descripcion text, p_indicaciones text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item objetivos_items;
  v_desc text := btrim(coalesce(p_descripcion, ''));
  v_indic text := nullif(btrim(coalesce(p_indicaciones, '')), '');
begin
  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ un ítem eliminado ya no se puede editar.
  select * into v_item from objetivos_items where id = p_item_id and eliminado_at is null;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧
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
     set descripcion = v_desc, indicaciones = v_indic, updated_at = now(), actualizado_por = fn_persona_actual_id()
   where id = p_item_id;
end;
$$;

grant execute on function fn_objetivo_editar(uuid, text, text) to authenticated;
revoke execute on function fn_objetivo_editar(uuid, text, text) from public, anon;

-- ---------------------------------------------------------------------------
-- Eliminar: deja de ser un `delete` físico — marca eliminado_at/eliminado_por.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivo_eliminar(p_item_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item objetivos_items;
begin
  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ un ítem ya eliminado se trata como inexistente
  -- (mismo mensaje que antes daba un id que nunca existió — no hay un
  -- "doble eliminar" que distinguir para quien usa la pantalla).
  select * into v_item from objetivos_items where id = p_item_id and eliminado_at is null;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧
  if not found then raise exception 'Objetivo inexistente.'; end if;
  if fn_puede_gestionar_objetivos(v_item.persona_id) is not true then
    raise exception 'No puedes gestionar los objetivos de esta persona.';
  end if;
  if fn_mes_planilla_pagado(v_item.anio, v_item.mes) is true then
    raise exception 'La planilla de ese mes ya está PAGADA: reabre el periodo para corregir.';
  end if;

  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ borrado blando en vez de `delete from objetivos_items`.
  update objetivos_items
     set eliminado_at = now(), eliminado_por = fn_persona_actual_id()
   where id = p_item_id;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧
  perform fn_objetivos_sync_mes(v_item.persona_id, v_item.anio, v_item.mes);
end;
$$;

grant execute on function fn_objetivo_eliminar(uuid) to authenticated;
revoke execute on function fn_objetivo_eliminar(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- Copiar del mes anterior: ignora lo eliminado en las dos comprobaciones y en
-- el insert; las copias nuevas quedan con creado_por/actualizado_por de quien
-- copia (candado de la 0361, sin tocar).
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_copiar_mes_anterior(p_persona_id uuid, p_anio int, p_mes int)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_prev date;
  v_prev_anio int;
  v_prev_mes int;
  v_actor uuid;
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

  -- ⇩⇩⇩ CAMBIO 0361 ⇩⇩⇩ candado por persona: sin tocar. Sigue siendo la
  -- primera acción tras validar permiso/persona/mes y ANTES de preguntar si
  -- el mes está vacío — la prueba 287 verifica este marcador literal.
  perform pg_advisory_xact_lock(hashtext('objetivos:' || p_persona_id::text));
  -- ⇧⇧⇧ CAMBIO 0361 ⇧⇧⇧

  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩ "vacío" ignora lo eliminado — un mes que solo tiene
  -- ítems con borrado blando se trata igual que uno que nunca tuvo ítems.
  if exists (
    select 1 from objetivos_items
    where persona_id = p_persona_id and anio = p_anio and mes = p_mes
      and eliminado_at is null
  ) then
    raise exception 'Este mes ya tiene objetivos: solo se puede copiar hacia un mes vacío.';
  end if;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧

  v_prev := make_date(p_anio, p_mes, 1) - interval '1 month';
  v_prev_anio := extract(year from v_prev)::int;
  v_prev_mes := extract(month from v_prev)::int;

  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩
  if not exists (
    select 1 from objetivos_items
    where persona_id = p_persona_id and anio = v_prev_anio and mes = v_prev_mes
      and eliminado_at is null
  ) then
    raise exception 'No hay objetivos en % de % para copiar.', v_prev_mes, v_prev_anio;
  end if;

  v_actor := fn_persona_actual_id();

  insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden, creado_por, actualizado_por)
  select p_persona_id, p_anio, p_mes, src.descripcion, src.indicaciones, src.orden, v_actor, v_actor
  from objetivos_items src
  where src.persona_id = p_persona_id and src.anio = v_prev_anio and src.mes = v_prev_mes
    and src.eliminado_at is null
    and not exists (
      select 1 from objetivos_items d
      where d.persona_id = p_persona_id and d.anio = p_anio and d.mes = p_mes
        and d.descripcion = src.descripcion and d.eliminado_at is null
    )
  order by src.orden, src.created_at
  limit 20;
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧

  get diagnostics v_copiados = row_count;

  perform fn_objetivos_sync_mes(p_persona_id, p_anio, p_mes);

  return jsonb_build_object('copiados', v_copiados);
end;
$$;

grant execute on function fn_objetivos_copiar_mes_anterior(uuid, int, int) to authenticated;
revoke execute on function fn_objetivos_copiar_mes_anterior(uuid, int, int) from public, anon;

-- ---------------------------------------------------------------------------
-- Resumen del mes: "con_checklist" ignora lo eliminado.
-- ---------------------------------------------------------------------------
create or replace function fn_objetivos_resumen(p_anio int, p_mes int)
returns jsonb
language sql stable security definer set search_path = public
as $$
  -- ⇩⇩⇩ CAMBIO 0449 ⇩⇩⇩
  select coalesce(jsonb_agg(jsonb_build_object(
           'persona_id', om.persona_id,
           'cumplidos', om.cumplidos,
           'total', om.total,
           'con_checklist', exists (
             select 1 from objetivos_items oi
             where oi.persona_id = om.persona_id and oi.anio = om.anio and oi.mes = om.mes
               and oi.eliminado_at is null
           )
         )), '[]'::jsonb)
  from objetivos_mensuales om
  where om.anio = p_anio and om.mes = p_mes
    and (
      fn_es_admin_o_lider() is true
      or (fn_rol_actual() = 'supervisor_sede' and exists (
            select 1 from personas p
            where p.id = om.persona_id
              and p.sede_base_id = fn_sede_actual_persona()))
      or om.persona_id = fn_persona_actual_id()
    );
  -- ⇧⇧⇧ CAMBIO 0449 ⇧⇧⇧
$$;

grant execute on function fn_objetivos_resumen(int, int) to authenticated;
revoke execute on function fn_objetivos_resumen(int, int) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (449, 'objetivos_recuerdan_quien_los_toco')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
select
  (select count(*) from information_schema.columns
    where table_name = 'objetivos_items' and column_name = 'creado_por') = 1 as tiene_creado_por,
  (select count(*) from information_schema.columns
    where table_name = 'objetivos_items' and column_name = 'eliminado_at') = 1 as tiene_eliminado_at,
  position('CAMBIO 0449' in pg_get_functiondef('fn_objetivo_eliminar'::regproc)) > 0 as eliminar_es_blando,
  position('CAMBIO 0449' in pg_get_functiondef('fn_objetivos_copiar_mes_anterior'::regproc)) > 0 as copiar_ignora_eliminados,
  (select count(*) from pg_proc where proname = 'fn_objetivo_eliminar') = 1 as una_sola_version;
