-- ============================================================================
-- 0361 — «Copiar del mes anterior» no duplica el checklist con un doble clic
-- ----------------------------------------------------------------------------
-- QUÉ PROMETE: que dos llamadas simultáneas a fn_objetivos_copiar_mes_anterior
-- para la misma persona y el mismo mes dejen UNA copia, no dos. La primera
-- copia; la segunda espera a que la primera termine, encuentra el mes lleno y
-- se niega con el mensaje que ya existía desde la 0348:
--   «Este mes ya tiene objetivos: solo se puede copiar hacia un mes vacío.»
--
-- EL DEFECTO (hallazgo 15 de la auditoría del 2026-09-03/04): la 0348 hacía
--   1. ¿el mes destino está vacío?   → sí
--   2. insert ... select del mes anterior
-- en dos pasos sin nada que los ate. Un 1 de septiembre, con la red lenta, la
-- líder de DO pulsa «Copiar del mes anterior» dos veces: las dos peticiones
-- llegan, las dos hacen la pregunta 1 ANTES de que ninguna haya hecho el paso
-- 2, las dos ven «vacío», las dos insertan. Ocho objetivos se vuelven
-- dieciséis, ocho repetidos. Si la integrante cumple los ocho, el sistema le
-- calcula 50 % en vez de 100 % — y ese porcentaje alimenta el historial
-- mensual (0350) que se mira para conversar, observar o promover. Es la
-- condición de carrera clásica: comprobar y luego actuar sin candado
-- (time-of-check / time-of-use).
--
-- QUÉ ASUME (dos cosas, y las dos se comprobaron en el Postgres local el
-- 2026-09-04):
--   1. Que cada llamada RPC de Supabase corre dentro de su propia
--      transacción y que esa transacción termina (commit o rollback) cuando
--      la función devuelve. Es así por diseño de PostgREST: una llamada =
--      una transacción.
--   2. Que la transacción corre en READ COMMITTED, que es el valor por
--      defecto de Postgres (`default_transaction_isolation`) y el que usa
--      PostgREST; esta función no fija otro (solo `search_path`). Importa
--      porque en READ COMMITTED cada sentencia toma una foto nueva: la
--      segunda llamada, al salir de la espera del candado, pregunta «¿el mes
--      está vacío?» y VE lo que la primera acaba de commitear. Bajo
--      REPEATABLE READ o SERIALIZABLE la foto se toma al empezar la
--      transacción, y ni el `if exists` ni el `not exists` verían esos
--      ítems: el candado pondría en fila y aun así se copiaría dos veces. Si
--      algún día se cambia el aislamiento por defecto del rol, esta
--      migración hay que volver a mirarla.
--
-- MEDIDO en el Postgres local el 2026-09-04, con dos sesiones (una sostiene
-- `pg_advisory_xact_lock(hashtext('objetivos:<uuid>'))` cuatro segundos y
-- la otra llama a la función un segundo después, como admin, dentro de
-- begin/rollback):
--   · sin candado ajeno:                          3,7 ms, copia
--   · candado ajeno de la MISMA persona:      2 995 ms, espera y luego copia
--   · candado ajeno de OTRA persona:              3,0 ms, no espera
-- La espera cabe de sobra en el `statement_timeout=8s` del rol
-- `authenticated`; y si alguna vez no cupiera, el desenlace sería un error
-- visible, no un duplicado.
--
-- POR QUÉ SE ELIGIÓ ASÍ (dos defensas, no una):
--
-- a) pg_advisory_xact_lock(hashtext('objetivos:' || persona)). Un candado
--    consultivo DE TRANSACCIÓN, tomado como primera acción tras validar
--    permiso, persona y mes, y ANTES de preguntar si el mes está vacío.
--    · De transacción (xact) y no de sesión: se suelta solo cuando la
--      transacción termina, sin que nadie tenga que acordarse de soltarlo, y
--      no puede quedar colgado si la función lanza una excepción a medio
--      camino. Con PostgREST, «la transacción termina» es exactamente «la
--      llamada RPC terminó», que es lo que se quiere: la segunda llamada
--      entra cuando la primera ya commiteó, y por eso SÍ ve los ítems recién
--      insertados y se niega.
--    · Por persona y no global: dos encargadas copiando a dos integrantes
--      distintas no tienen por qué esperarse. El hash del texto
--      'objetivos:<uuid>' da una clave estable por persona, y el prefijo
--      evita chocar con cualquier otro candado que use hashtext de un uuid a
--      secas (el mismo uuid para otra cosa daría la misma clave).
--    · Consultivo y no un `lock table`: no frena a nadie que esté marcando o
--      editando un objetivo mientras tanto; solo pone en fila a quien intente
--      COPIAR hacia esa misma persona.
--
-- b) Defensa en profundidad: el insert ... select agrega `and not exists`
--    contra el mes destino por descripción. Con el candado nunca debería
--    hacer falta —cuando llega al insert, el mes está vacío—, pero si algún
--    día otra puerta escribe objetivos sin pasar por este candado, la copia
--    sigue sin duplicar por descripción. Cuesta una subconsulta sobre un
--    índice que ya existe (idx_objetivos_items_persona_mes).
--
-- QUÉ NO CAMBIA: los guards (fn_puede_gestionar_objetivos, persona, mes,
-- fn_mes_planilla_pagado), el tope de 20, el «mes anterior vacío», el sync
-- con fn_objetivos_sync_mes, el jsonb de retorno y los grants/revokes son
-- los de la 0348, carácter por carácter. La pantalla /admin/objetivos suma
-- por su lado un `if (copiando) return;` para no disparar dos veces desde el
-- mismo tick de React, pero el servidor NO confía en eso: el candado está acá.
--
-- SE REVIERTE: `create or replace` con el cuerpo de la 0348. No hay columnas
-- ni índices nuevos que revertir.
--
-- VIGENTE EN: 0348_objetivos_copiar_mes_anterior.sql (única versión),
-- confirmado con donde-vive.sh el 2026-09-04.
-- md5 de partida (Postgres LOCAL): 53845c12e88f876bf8266d2a8f8c09e0
--                 sin comentarios: 53845c12e88f876bf8266d2a8f8c09e0
-- (coinciden porque el cuerpo de la 0348 no lleva comentarios). Antes de
-- pegar en el SQL Editor, vuelve a pedir el md5 a PRODUCCIÓN con
-- ./scripts/donde-vive.sh fn_objetivos_copiar_mes_anterior — un md5 es una
-- foto, y varias sesiones trabajan sobre el mismo árbol.
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

  -- ⇩⇩⇩ CAMBIO 0361 ⇩⇩⇩ CANDADO POR PERSONA ANTES DE PREGUNTAR SI EL MES ESTÁ VACÍO.
  --
  -- La 0348 no tenía nada acá: pasaba directo al `if exists`. Dos llamadas a
  -- la vez hacían las dos esa pregunta antes de que ninguna insertara, y las
  -- dos copiaban. Este candado es de TRANSACCIÓN (se suelta solo al terminar
  -- la llamada RPC, con o sin excepción) y es POR PERSONA (copiar a otra
  -- integrante no espera). La segunda llamada se queda acá hasta que la
  -- primera commitea; cuando sigue, el `if exists` de abajo ya ve los ítems
  -- copiados y se niega con el mensaje de siempre.
  perform pg_advisory_xact_lock(hashtext('objetivos:' || p_persona_id::text));
  -- ⇧⇧⇧ CAMBIO 0361 ⇧⇧⇧

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

  -- ⇩⇩⇩ CAMBIO 0361 ⇩⇩⇩ DEFENSA EN PROFUNDIDAD: NO COPIAR LO QUE YA ESTÁ EN EL DESTINO.
  --
  -- Decía:
  --   insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden)
  --   select p_persona_id, p_anio, p_mes, descripcion, indicaciones, orden
  --   from objetivos_items
  --   where persona_id = p_persona_id and anio = v_prev_anio and mes = v_prev_mes
  --   order by orden, created_at
  --   limit 20;
  --
  -- Con el candado de arriba el destino siempre llega vacío a este punto, así
  -- que el `not exists` no filtra nada. Se deja para que, si otra puerta
  -- escribe objetivos sin pasar por el candado, la copia no duplique por
  -- descripción.
  insert into objetivos_items (persona_id, anio, mes, descripcion, indicaciones, orden)
  select p_persona_id, p_anio, p_mes, src.descripcion, src.indicaciones, src.orden
  from objetivos_items src
  where src.persona_id = p_persona_id and src.anio = v_prev_anio and src.mes = v_prev_mes
    and not exists (
      select 1 from objetivos_items d
      where d.persona_id = p_persona_id and d.anio = p_anio and d.mes = p_mes
        and d.descripcion = src.descripcion
    )
  order by src.orden, src.created_at
  limit 20;
  -- ⇧⇧⇧ CAMBIO 0361 ⇧⇧⇧

  get diagnostics v_copiados = row_count;

  perform fn_objetivos_sync_mes(p_persona_id, p_anio, p_mes);

  return jsonb_build_object('copiados', v_copiados);
end;
$$;

grant execute on function fn_objetivos_copiar_mes_anterior(uuid, int, int) to authenticated;
revoke execute on function fn_objetivos_copiar_mes_anterior(uuid, int, int) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (361, 'copiar_objetivos_no_duplica_con_doble_clic')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
-- El cuerpo nuevo lleva el candado y el marcador; el de la 0348 no tenía
-- ninguno de los dos. Y sigue habiendo UNA sola función con ese nombre.
select
  position('pg_advisory_xact_lock' in pg_get_functiondef('fn_objetivos_copiar_mes_anterior'::regproc)) > 0 as tiene_el_candado,
  position('CAMBIO 0361' in pg_get_functiondef('fn_objetivos_copiar_mes_anterior'::regproc)) > 0 as tiene_el_cambio,
  (select count(*) from pg_proc where proname = 'fn_objetivos_copiar_mes_anterior') as una_sola_version;
