-- ============================================================================
-- 0546 · Reabrir un pago deja las horas de ESE grupo al día
-- ============================================================================
--
-- QUÉ PROMETE
--   `fn_revertir_pago` reabre un grupo y, además, repara las horas de su gente:
--   recalcula sus jornadas y quita los sellos de los días que cuadran. Antes solo
--   recalculaba si el periodo ENTERO estaba pagado.
--
-- EL DEFECTO (visto en producción el 2026-10-22; ver la 0545)
--   El 2026-10-21 el grupo «planilla» se marcó pagado a mitad de periodo. El
--   periodo se quedó 'abierto' —rxh y los demás no se habían pagado—, así que al
--   reabrirlo `fn_revertir_pago` NO recalculó nada: esa condición
--   (`v_estado_periodo_antes = 'pagado'`) es de la 0323, cuando el candado de
--   horas era uno solo para el periodo entero. La 0327 lo hizo por grupo y no
--   volvió sobre ella. Medido en la prueba 437 (aserción «LÍMITE ACTUAL») y
--   reproducido sin herramienta intermedia en la 438.
--
-- QUÉ CAMBIA, Y QUÉ NO
--   · Se agrega UNA llamada, al final: `fn_reparar_dias_tras_reabrir(p_grupo,
--     ini, fin)` (0545). No se quita nada de lo que ya hacía.
--   · El bucle de siempre —recalcular TODO el rango cuando el periodo entero
--     estaba pagado— queda intacto: es el caso de un periodo anterior a la 0323
--     sin ninguna fila por grupo, donde reabrir uno levanta el candado de todos.
--     Por eso la llamada nueva se SUMA y no lo reemplaza.
--   · Mismos argumentos, mismo permiso, misma reversa en `reversas_pago`.
--   · El texto de un comentario interno que ya no era verdad («si faltaba pagar
--     otro grupo, el candado nunca se encendió») se corrige.
--
-- QUÉ ASUME
--   · Que la 0545 ya está pegada. Se comprueba al principio: si no, PARA.
--   · Que `fn_revertir_pago` en producción es la de la 0323. También se comprueba
--     al principio (md5, con las variantes que documenta CLAUDE.md): si no
--     coincide, no se aplica NADA.
--
-- COSTO
--   Reabrir planilla repara unos 800 días (25 personas × 31). Cada uno lee ~6
--   marcas por índice de persona y fecha. Es una acción que se hace pocas veces
--   al año y dentro de una sola transacción: uno o dos segundos, sin medir en
--   producción.
--
-- CÓMO SE REVIERTE
--   Volver a pegar el cuerpo de la 0323 (`fn_revertir_pago`, líneas 681-770). Lo
--   que ya reparó no se «des-repara»: las jornadas son derivadas.
--
-- md5 de partida (fn_revertir_pago, cuerpo de la 0323), medido en el Postgres
-- desechable con las 520 migraciones de esta rama. La confirmación contra
-- producción la hace el bloque de abajo AL PEGAR, no una persona de memoria:
--   tal cual              ac66bb056d28898f209ec7e17b9511af · 4472 caracteres
--   sin comentarios       8a28101cbcfafe2e35665224815a70f4
--   crlf tal cual         be0b00a5fa5b27e056ae3639fed9eab8
-- ============================================================================

do $$
declare
  v_md5 text;
  v_len integer;
  v_pelada text;
begin
  if to_regprocedure('public.fn_reparar_dias_tras_reabrir(text,date,date)') is null then
    raise exception '0546 · PARA. Falta pegar la 0545 (fn_reparar_dias_tras_reabrir). No se aplicó nada.';
  end if;

  select md5(p.prosrc), length(p.prosrc),
         md5(array_to_string(array(
           select regexp_replace(l, '[[:space:]]*--.*$', '')
             from unnest(string_to_array(p.prosrc, chr(10))) as l
            where btrim(l) not like '--%'), chr(10)))
    into v_md5, v_len, v_pelada
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_revertir_pago' and p.pronargs = 3;

  if v_md5 is null then
    raise exception '0546 · PARA. fn_revertir_pago(uuid,text,text) no existe en esta base. No se aplicó nada.';
  end if;

  -- Mismo código, tres formas de llegar a producción (CLAUDE.md): tal cual, sin
  -- comentarios, o con \r\n si se pegó desde Windows. NO cubre «desde Windows Y sin
  -- comentarios a la vez» (CLAUDE.md lo dice): ahí PARA, y la salida es medir.
  if v_md5 not in ('ac66bb056d28898f209ec7e17b9511af', 'be0b00a5fa5b27e056ae3639fed9eab8')
     and v_pelada <> '8a28101cbcfafe2e35665224815a70f4'
  then
    raise exception '0546 · PARA. fn_revertir_pago en esta base es % (% caracteres; sin comentarios %), y no es ninguna de las formas esperadas. Producción tiene otra versión: no se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_revertir_pago.', v_md5, v_len, v_pelada;
  end if;
end
$$;

create or replace function fn_revertir_pago(p_periodo_id uuid, p_motivo text, p_grupo text default 'planilla')
returns void language plpgsql security definer set search_path = public as $$
declare
  v_estado_grupo text; v_pagado_at_grupo timestamptz;
  v_estado_periodo_antes text; v_pagado_at_periodo timestamptz;
  v_ini date; v_fin date;
  v_dia record; v_dias int := 0;
  v_reparados int := 0;      -- CAMBIO 0546
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede revertir un pago.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 4 then
    raise exception 'El motivo de la reapertura es obligatorio (mínimo 4 caracteres).';
  end if;
  if p_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'Grupo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador, practicante.', p_grupo;
  end if;

  select estado, fecha_ini, fecha_fin, pagado_at
    into v_estado_periodo_antes, v_ini, v_fin, v_pagado_at_periodo
  from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;

  select estado, pagado_at into v_estado_grupo, v_pagado_at_grupo
  from periodo_grupo_pago where periodo_id = p_periodo_id and grupo = p_grupo for update;

  -- CAMBIO 0323 · COMPATIBILIDAD: sin fila en periodo_grupo_pago (nunca se
  -- tocó por grupo) y el periodo entero dice 'pagado', es el bucket único de
  -- antes de esta migración — se trata este grupo como pagado también, con
  -- la fecha del periodo como aproximación (nunca se guardó una por grupo).
  if not found and v_estado_periodo_antes = 'pagado' then
    v_estado_grupo := 'pagado';
    v_pagado_at_grupo := v_pagado_at_periodo;
  end if;

  if coalesce(v_estado_grupo, 'abierto') <> 'pagado' then
    raise exception 'El grupo % de este periodo no está pagado (estado actual: %).', p_grupo, coalesce(v_estado_grupo, 'abierto');
  end if;

  insert into reversas_pago (periodo_id, revertido_por, motivo, pagado_at_previo, grupo)
    values (p_periodo_id, fn_persona_actual_id(), trim(p_motivo), v_pagado_at_grupo, p_grupo);

  -- Upsert, no update: la fila puede no existir todavía (el caso de
  -- compatibilidad de arriba). A partir de aquí este (periodo, grupo) ya
  -- queda con seguimiento propio.
  insert into periodo_grupo_pago (periodo_id, grupo, estado, pagado_at, pagado_por)
  values (p_periodo_id, p_grupo, 'abierto', null, null)
  on conflict (periodo_id, grupo)
  do update set estado = 'abierto', pagado_at = null, pagado_por = null;

  -- Si un grupo se reabre, el periodo deja de estar "completo" — sin importar
  -- si antes de este reabrir estaba pagado o no.
  update periodos_planilla set estado = 'abierto', pagado_at = null where id = p_periodo_id;

  -- ── Y ahora sí, se descongela ─────────────────────────────────────────────
  -- Este primer bucle es el de siempre y no cambia: si el periodo ENTERO estaba
  -- 'pagado' antes de reabrir, recalcula todo el rango.
  --
  -- ⇩ Lo que ya NO es verdad (y este comentario decía): «si todavía faltaba pagar
  -- otro grupo, el candado nunca se encendió». Desde la 0327 el candado es por
  -- GRUPO: un grupo pagado solo bloquea las horas de su gente aunque el periodo
  -- siga 'abierto'. Por eso, más abajo, el grupo que se reabre se repara SIEMPRE.
  --
  -- EL ORDEN IMPORTA Y NO ES CASUAL: los dos updates de arriba tienen que
  -- estar hechos antes de llegar aquí. `fn_recalcular_jornada` lee el estado
  -- del periodo en cada llamada, así que si se recalculara antes saldría en
  -- silencio por su propio candado y este bucle no haría absolutamente nada —
  -- sin fallar, sin avisar, y con toda la pinta de estar funcionando.
  --
  -- SOLO DÍAS CON MARCAJES. Un día sin ninguna marca es historia cargada a mano
  -- (la 0045 tiene 1.427 así, todo 2025 de siete personas) y recalcularlo la
  -- borraría, porque fn_recalcular_jornada elimina la jornada de un día que se
  -- quedó sin marcas. Las personas nunca se borran y su historial tampoco.
  --
  -- Sin filtrar por `anulada_at`: un día cuyas marcas se anularon todas SÍ tuvo
  -- marcas, su jornada es derivada, y le toca desaparecer.
  if v_estado_periodo_antes = 'pagado' then
    for v_dia in
      select distinct m.persona_id,
             (m.timestamp_marca at time zone 'America/Lima')::date as fecha
      from marcajes m
      where (m.timestamp_marca at time zone 'America/Lima')::date between v_ini and v_fin
    loop
      perform fn_recalcular_jornada(v_dia.persona_id, v_dia.fecha);
      v_dias := v_dias + 1;
    end loop;
  end if;

  -- ⇩⇩⇩ CAMBIO 0546 ⇩⇩⇩ El grupo que se reabre se repara SIEMPRE, hubiera estado
  -- pagado el periodo entero o no. Recalcula la jornada de su gente, y con ella
  -- quita los sellos que el candado les puso a marcas cuyo día cuadra (0207,
  -- «la marca entra, pero no entra muda»). Sin esto, reabrir un grupo pagado a
  -- mitad de periodo —el incidente del 2026-10-21— dejaba las jornadas
  -- «abierta», sin salida ni horas, y Correcciones diciendo «ya cuadra».
  --
  -- Va DESPUÉS de los dos updates de arriba por la misma razón que el bucle de
  -- siempre: `fn_reparar_dias_tras_reabrir` se niega si algún día de este grupo
  -- sigue pagado, y la respuesta correcta aquí es que ya no lo está.
  v_reparados := fn_reparar_dias_tras_reabrir(p_grupo, v_ini, v_fin);

  raise notice 'Grupo % reabierto: % jornadas recalculadas entre % y % · % días de ese grupo reparados.', p_grupo, v_dias, v_ini, v_fin, v_reparados;
end;
$$;

grant execute on function fn_revertir_pago(uuid, text, text) to authenticated;
revoke execute on function fn_revertir_pago(uuid, text, text) from public, anon;

comment on function fn_revertir_pago(uuid, text, text) is
  'Reabre UN grupo (tipo_vinculo) del periodo — 0323. Siempre vuelve a poner periodos_planilla.estado = abierto. Desde la 0546 repara SIEMPRE las jornadas y los sellos de la gente de ese grupo (fn_reparar_dias_tras_reabrir), hubiera estado pagado el periodo entero o no; el bucle de recálculo de todo el rango, cuando el periodo entero estaba pagado, se conserva.';

insert into migraciones_aplicadas (numero, nombre)
values (546, 'revertir_un_pago_repara_las_horas_del_grupo')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────────
select position('CAMBIO 0546' in pg_get_functiondef('public.fn_revertir_pago(uuid,text,text)'::regprocedure)) > 0 as tiene_el_cambio,
       (select numero || ' · ' || nombre from migraciones_aplicadas where numero = 546) as registro;
