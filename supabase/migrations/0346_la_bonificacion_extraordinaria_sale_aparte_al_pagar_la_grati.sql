-- ============================================================================
-- 0346 — La bonificación extraordinaria (Ley 30334) sale en su PROPIA línea
--         también al pagar la gratificación real de julio/diciembre.
--
-- QUÉ PROMETE
--
--   Que al cerrar el periodo de julio o diciembre, el desplegable de
--   movimientos ofrezca «Bonificación extraordinaria (9%)» como una opción
--   propia —igual que ya ofrece «Gratificación» y «CTS»— con su monto
--   autocalculado, para registrarse como un movimiento SEPARADO del de la
--   gratificación.
--
-- POR QUÉ AHORA
--
--   Lo pidió el contador de CAYLA: quiere el 9% en su propia línea al
--   momento de pagar, no mezclado a mano dentro del monto de «Gratificación»
--   — es la misma separación que ya declara con el código 0312 del PLAME.
--
--   La provisión mensual (0134), la reserva acumulada de Provisiones/Costos
--   y la liquidación por cese (`fn_grati_trunca_bruta`, 0163/0343) YA
--   calculan y muestran el 9% en su propio campo. El único hueco era el pago
--   real del ciclo normal: `fn_grati_cts_periodo` —la función que autocompleta
--   el monto al elegir «Gratificación» en Planilla— nunca calculó el 9%, y el
--   desplegable de Planilla no tenía la opción. Quien quisiera pagarlo tenía
--   que sumarlo a mano dentro del mismo monto de «Gratificación», sin que
--   quedara registrado como su propio concepto.
--
-- CÓMO SE CALCULA
--
--   be = grati (el monto que la 0338 YA eligió como el mayor entre el día a
--        día y el piso legal del sueldo vigente al cierre) × la tasa
--        vigente en parametros_laborales.clave='bonificacion_extraordinaria'
--        a la fecha de corte del semestre — la MISMA tasa versionada que usa
--        fn_planilla_calcular y fn_provisiones desde la 0134. Del mismo
--        número que la gratificación, nunca de una base propia: si mañana
--        cambia la fórmula de la gratificación, la bonificación la sigue
--        sola, sin tocar esta función.
--
--   No aplica a la CTS: la Ley 30334 es específica de la gratificación
--   (art. 3), así que no se agrega un campo análogo para 'cts'.
--
-- LA CATEGORÍA NUEVA NECESITA TRES PUERTAS, NO UNA
--
--   `movimientos_planilla.categoria` es TEXT con un CHECK de lista blanca
--   (`movimientos_categoria_valida`, 0049) y `fn_agregar_movimiento` —la
--   ÚNICA función que el cliente puede llamar para insertar un movimiento—
--   repite esa misma lista blanca A MANO en dos sitios: la validación general
--   y el candado de «no dos veces en el mismo periodo». Sin las tres, la
--   opción nueva del desplegable moriría en el primer intento de guardar con
--   «Categoría inválida.». Las tres se actualizan juntas acá.
--
--   El candado de una sola vez por periodo (línea `p_categoria in
--   ('gratificacion','cts')`) se extiende a la bonificación por la misma
--   razón que ya protege a las otras dos: evitar que un doble clic la
--   duplique.
--
-- QUÉ ASUME
--
--   Que la tasa correcta para TODOS es la general (9%), no la de EPS
--   (6.75%) — la misma suposición que ya hace 0134 en toda la planilla,
--   documentada ahí: hoy el sistema no tiene el campo de afiliación a EPS.
--
--   Que la categoría nueva NO debe entrar a `fn_remuneracion_computable`
--   (la base de la liquidación por cese, 0278): su función usa una LISTA
--   BLANCA —`categoria is null or categoria = 'otros'`— así que cualquier
--   categoría nueva queda excluida por default, igual que ya lo están
--   'gratificacion', 'cts' y 'vacaciones'. Es lo correcto: la bonificación es
--   la misma plata de la gratificación bajo otra etiqueta, y esa ya está
--   excluida — contarla también sería el mismo doble conteo que la 0278
--   cerró. La prueba 215 (aserción 11) es el centinela que fuerza a decidir
--   esto a propósito en vez de en silencio: se actualiza en este mismo commit.
--
-- QUÉ NO TOCA
--
--   · Los periodos YA PAGADOS. Esto solo agrega una opción nueva al
--     desplegable — no reclasifica ni recalcula ningún movimiento existente.
--     Si alguien ya sumó el 9% a mano dentro del monto de «Gratificación» de
--     un periodo cerrado, esa fila sigue exactamente como está.
--   · `fn_grati_trunca_bruta` (liquidación por cese), que ya separaba el 9%
--     desde antes de esta migración.
--   · `fn_remuneracion_computable`: no se toca su cuerpo, solo se confirma
--     (arriba y con la prueba 215) que su lista blanca ya excluye la
--     categoría nueva sin cambiar una línea.
--   · La firma de `fn_grati_cts_periodo` ni la de `fn_agregar_movimiento`
--     (siguen igual): no hace falta `drop function` en ninguna de las dos.
--
-- CÓMO SE REVIERTE
--   Restaurar fn_grati_cts_periodo desde la 0338 y fn_agregar_movimiento
--   desde la 0327; luego:
--     alter table movimientos_planilla drop constraint movimientos_categoria_valida;
--     alter table movimientos_planilla add constraint movimientos_categoria_valida
--       check (categoria is null or categoria in ('vacaciones', 'otros', 'gratificacion', 'cts'));
--
-- MD5 DE PARTIDA (pedido a producción antes de escribir, no antes de entregar)
--   fn_grati_cts_periodo:     tal_cual 2051d2fc838ca0514a75f32791aef614
--   fn_agregar_movimiento:    tal_cual 8989424ec9d01ea635ac8aef7bf82e68
--   Los dos, confirmar contra producción antes de pegar — ver docs/estado.md.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_grati_cts_periodo(p_periodo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
declare
  v_ini date; v_fin date;
  v_gkey text; v_ckey text; v_gtxt text; v_ctxt text;
  v_g_anio int; v_c_anio int;
  v_asof_g date; v_asof_c date;
  v_prov_g jsonb; v_prov_c jsonb;
  v_prov_g_piso jsonb; v_prov_c_piso jsonb;
  v_f_be numeric;   -- CAMBIO 0346: tasa de la bonificacion extraordinaria
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver esto.';
  end if;
  select fecha_ini, fecha_fin into v_ini, v_fin from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  select y into v_g_anio
  from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
  where make_date(y, 7, 15) between v_ini and v_fin
  limit 1;

  if v_g_anio is not null then
    v_gkey := 'grati_s1';
    v_gtxt := 'Bono Gratitud ene–jun ' || v_g_anio;
    v_asof_g := least(v_fin, make_date(v_g_anio, 6, 30));
  else
    select y into v_g_anio
    from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
    where make_date(y, 12, 15) between v_ini and v_fin
    limit 1;
    if v_g_anio is not null then
      v_gkey := 'grati_s2';
      v_gtxt := 'Bono Gratitud jul–dic ' || v_g_anio;
      v_asof_g := least(v_fin, make_date(v_g_anio, 12, 31));
    end if;
  end if;

  select y into v_c_anio
  from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
  where make_date(y, 5, 15) between v_ini and v_fin
  limit 1;

  if v_c_anio is not null then
    v_ckey := 'cts_may';
    v_ctxt := 'Bono Comprometidos nov' || (v_c_anio - 1) || '–abr ' || v_c_anio;
    v_asof_c := least(v_fin, make_date(v_c_anio, 4, 30));
  else
    select y into v_c_anio
    from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
    where make_date(y, 11, 15) between v_ini and v_fin
    limit 1;
    if v_c_anio is not null then
      v_ckey := 'cts_nov';
      v_ctxt := 'Bono Comprometidos may–oct ' || v_c_anio;
      v_asof_c := least(v_fin, make_date(v_c_anio, 10, 31));
    end if;
  end if;

  v_asof_g := coalesce(v_asof_g, v_fin);
  v_asof_c := coalesce(v_asof_c, v_fin);

  v_prov_g := fn_provisiones(v_asof_g);
  v_prov_c := case when v_asof_c = v_asof_g then v_prov_g else fn_provisiones(v_asof_c) end;

  v_prov_g_piso := fn_provisiones(v_asof_g, v_asof_g);
  v_prov_c_piso := case when v_asof_c = v_asof_g then v_prov_g_piso else fn_provisiones(v_asof_c, v_asof_c) end;

  -- ⇩⇩⇩ CAMBIO 0346 ⇩⇩⇩ LA TASA DE LA BONIFICACIÓN EXTRAORDINARIA.
  --
  -- Versionada en parametros_laborales, igual que la lee fn_planilla_calcular
  -- desde la 0134: no clavada en el código, porque es una tasa legal y el día
  -- que cambie los periodos ya pagados no pueden moverse. Se busca a la fecha
  -- de CORTE del semestre de gratificación (v_asof_g), la misma fecha que ya
  -- decide el sueldo del piso legal (CAMBIO 0338) — es la fecha que la norma
  -- usa para fijar la remuneración computable de todo el semestre.
  select pl.valor into v_f_be
  from parametros_laborales pl
  where pl.clave = 'bonificacion_extraordinaria'
    and pl.vigente_desde <= v_asof_g
    and (pl.vigente_hasta is null or pl.vigente_hasta >= v_asof_g)
  order by pl.vigente_desde desc
  limit 1;
  if v_f_be is null then v_f_be := 0.09; end if;

  return jsonb_build_object(
    'grati_aplica', v_gkey is not null, 'grati_concepto', v_gtxt,
    'cts_aplica',   v_ckey is not null, 'cts_concepto',   v_ctxt,
    -- CAMBIO 0346 — mismo texto de la gratificación, para que el concepto
    -- autocompletado deje claro de qué semestre viene el 9%.
    'be_concepto',
      case when v_gkey is null then null
           else 'Bonificación extraordinaria 9% (Ley 30334) — ' || v_gtxt end,
    'personas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'persona_id', x.pid,
        'grati', x.grati,
        'cts',   x.cts,
        -- CAMBIO 0346 — del MISMO número que la gratificación (x.grati, ya
        -- resuelto como el mayor entre día a día y piso legal), nunca de una
        -- base propia: ver el comentario de cabecera.
        'be',    round(x.grati * v_f_be, 2)
      )), '[]'::jsonb)
      from (
        select g.pid,
               case when v_gkey is null then 0 else greatest(
                 coalesce((g.fila->>v_gkey)::numeric, 0),
                 coalesce((gp.fila->>v_gkey)::numeric, 0)
               ) end as grati,
               case when v_ckey is null then 0 else greatest(
                 coalesce((c.fila->>v_ckey)::numeric, 0),
                 coalesce((cp.fila->>v_ckey)::numeric, 0)
               ) end as cts
        from (select per->>'persona_id' as pid, per as fila
                from jsonb_array_elements(v_prov_g->'personas') per) g
        left join (select per->>'persona_id' as pid, per as fila
                     from jsonb_array_elements(v_prov_c->'personas') per) c
          on c.pid = g.pid
        left join (select per->>'persona_id' as pid, per as fila
                     from jsonb_array_elements(v_prov_g_piso->'personas') per) gp
          on gp.pid = g.pid
        left join (select per->>'persona_id' as pid, per as fila
                     from jsonb_array_elements(v_prov_c_piso->'personas') per) cp
          on cp.pid = g.pid
      ) x
    )
  );
end;
$fn$;
grant execute on function fn_grati_cts_periodo(uuid) to authenticated;
revoke execute on function fn_grati_cts_periodo(uuid) from public, anon;

-- ────────────────────────────────────────────────────────────────────────────
-- La lista blanca de la tabla, ampliada. Idempotente por naturaleza: un
-- drop/add de la misma restricción se puede pegar dos veces sin duplicar nada.
-- ────────────────────────────────────────────────────────────────────────────
alter table movimientos_planilla drop constraint if exists movimientos_categoria_valida;
alter table movimientos_planilla add constraint movimientos_categoria_valida
  check (categoria is null or categoria in ('vacaciones', 'otros', 'gratificacion', 'cts', 'bonificacion_extraordinaria'));

-- ────────────────────────────────────────────────────────────────────────────
-- fn_agregar_movimiento — la ÚNICA puerta de escritura, copiada tal cual de
-- la 0327 (vigente) con la categoría nueva en sus dos listas: la validación
-- general y el candado de una vez por periodo. Misma firma de siempre.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_agregar_movimiento(p_periodo_id uuid, p_persona_id uuid, p_tipo text, p_concepto text, p_monto numeric, p_categoria text DEFAULT NULL::text, p_periodo_origen_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_estado text;
  v_ini    date;
  v_org    record;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar movimientos.';
  end if;
  select estado, fecha_ini into v_estado, v_ini from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if fn_fecha_en_periodo_pagado(v_ini, p_persona_id) then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  if p_tipo is null or p_tipo not in ('bono', 'descuento') then
    raise exception 'Tipo inválido (bono o descuento).';
  end if;
  -- CAMBIO 0346 — bonificacion_extraordinaria se suma a la lista blanca.
  if p_categoria is not null and p_categoria not in ('vacaciones','otros','gratificacion','cts','bonificacion_extraordinaria') then
    raise exception 'Categoría inválida.';
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
  -- CAMBIO 0346 — el candado de «una vez por periodo» cubre también la
  -- bonificación, por la misma razón que ya cubre grati y CTS.
  if p_categoria in ('gratificacion','cts','bonificacion_extraordinaria') and exists (
    select 1 from movimientos_planilla
    where periodo_id = p_periodo_id and persona_id = p_persona_id and categoria = p_categoria
  ) then
    raise exception 'Esta persona ya tiene % en este periodo. Quítalo antes de volver a agregarlo.', p_categoria;
  end if;

  -- ── CAMBIO 0305 · el origen, si lo hay ────────────────────────────────────
  -- Un origen mal puesto es peor que ninguno: haría creer que una diferencia
  -- quedó saldada cuando vino de otro sitio. Por eso las tres comprobaciones.
  if p_periodo_origen_id is not null then
    if p_periodo_origen_id = p_periodo_id then
      raise exception 'El periodo de origen no puede ser este mismo: eso no es un retroactivo, es un movimiento normal de este periodo. Déjalo en blanco.';
    end if;
    select estado, fecha_fin into v_org
      from periodos_planilla where id = p_periodo_origen_id;
    if not found then
      raise exception 'El periodo de origen no existe.';
    end if;
    if v_org.estado <> 'pagado' then
      raise exception 'El periodo del que dices que viene todavía no está PAGADO. Si sigue abierto, la corrección va ahí y no acá: se arregla en su mes, no se arrastra a este.';
    end if;
    if v_org.fecha_fin >= v_ini then
      raise exception 'El periodo de origen tiene que ser ANTERIOR a este. Un retroactivo corrige un mes que ya se cerró.';
    end if;
  end if;

  insert into movimientos_planilla
    (periodo_id, persona_id, tipo, concepto, monto, categoria, creado_por, periodo_origen_id)
  values (p_periodo_id, p_persona_id, p_tipo, trim(p_concepto), round(p_monto, 2),
          nullif(trim(coalesce(p_categoria, '')), ''), fn_persona_actual_id(),
          p_periodo_origen_id);
end;
$function$;

comment on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text, uuid) is
  'Única puerta para agregar un bono o descuento a un periodo. Desde la 0346 '
  'admite tambien categoria=bonificacion_extraordinaria. Antes había DOS firmas '
  '—la de la 0025 sin categoría y la de la 0181 con ella— y agregar un '
  'parámetro con default sobre la segunda habría hecho ambigua la llamada de '
  'seis argumentos, que es el fallo que la 0301 tuvo que arreglar en '
  'fn_vacaciones_por_vencer.';

revoke all on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text, uuid) from public, anon;
grant execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text, uuid) to authenticated;

insert into migraciones_aplicadas (numero, nombre)
values (346, 'la_bonificacion_extraordinaria_sale_aparte_al_pagar_la_grati')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── Comprobación ─────────────────────────────────────────────────────────
do $$
declare
  v_ok boolean;
begin
  select (select count(*) from pg_proc where proname = 'fn_grati_cts_periodo' and prosrc like '%CAMBIO 0346%') = 1
    into v_ok;
  if not v_ok then
    raise exception 'fn_grati_cts_periodo no quedó con el cambio 0346.';
  end if;
  select (select count(*) from pg_proc where proname = 'fn_agregar_movimiento' and prosrc like '%CAMBIO 0346%') = 1
    into v_ok;
  if not v_ok then
    raise exception 'fn_agregar_movimiento no quedó con el cambio 0346.';
  end if;
end $$;

select
  (select md5(prosrc) from pg_proc where proname = 'fn_grati_cts_periodo') as md5_grati_cts,
  (select md5(prosrc) from pg_proc where proname = 'fn_agregar_movimiento') as md5_agregar_movimiento;
