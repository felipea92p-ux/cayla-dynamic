-- ============================================================================
-- 0085 — La gratificación se paga aunque el periodo cruce el año
-- ----------------------------------------------------------------------------
-- PROMETE: que un periodo de planilla que contenga el 15 de julio o el 15 de
--   diciembre pague su gratificación, sin importar en qué año caiga su cierre.
--
-- ASUME: fn_provisiones y fn_grati_cts_periodo (0025/0049/0050), y que las
--   fechas de pago son el 15 de julio (semestre ene–jun) y el 15 de diciembre
--   (semestre jul–dic).
--
-- EL DEFECTO, con números. Dos periodos idénticos salvo el día de cierre:
--     10-dic-2026 → 31-dic-2026   ⇒ paga "Bono Gratitud jul–dic 2026"
--     10-dic-2026 → 08-ene-2027   ⇒ NO PAGA NADA
--   El mismo 15 de diciembre está dentro de los dos. Reproducido en laboratorio.
--
--   La causa son DOS errores encadenados, los dos por tomar el año del cierre:
--
--   1. QUÉ SE PAGA. La función tomaba el año de fecha_fin y con él construía la
--      fecha de pago. Con cierre el 08-ene-2027 buscaba el pago del 15-dic-2027
--      —un año en el futuro— y no encontraba nada. El 15-dic-2026, que sí cae
--      dentro del periodo, no se miraba nunca.
--
--   2. CUÁNTO SE PAGA. Los montos salen de fn_provisiones(fecha), que acumula el
--      semestre del año de esa fecha. Con el 08-ene-2027 acumularía jul–dic 2027,
--      un semestre que aún no ha ocurrido: el monto habría salido en cero incluso
--      arreglando el punto 1.
--
--   Y lo que lo vuelve definitivo en vez de un retraso: fn_crear_periodo solo
--   admite un periodo por mes de cierre. Si el periodo que contiene el 15 de
--   diciembre cierra en enero, ese periodo ES el de enero — y entonces no existe
--   ningún periodo de diciembre que pueda pagar esa gratificación después. El
--   dinero no se traslada al siguiente: desaparece.
--
-- POR QUÉ PASA DE VERDAD. fn_crear_periodo permite periodos de 20 a 46 días con
--   el cierre a elección. Cerrar diciembre a primeros de enero —porque el pago se
--   hace pasado Año Nuevo— cae justo en el caso roto.
--
-- QUÉ NO CAMBIA. En un periodo que no cruza el año, el resultado es idéntico al
--   de antes, montos incluidos: el `least` deja el as_of en fecha_fin igual que
--   hasta ahora. Verificado en las pruebas 85.
--
-- CÓMO SE REVIERTE: restaurar fn_grati_cts_periodo desde la 0050.
-- ============================================================================

create or replace function fn_grati_cts_periodo(p_periodo_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $fn$
declare
  v_ini date; v_fin date;
  v_gkey text; v_ckey text; v_gtxt text; v_ctxt text;
  v_g_anio int; v_c_anio int;
  v_asof_g date; v_asof_c date;
  v_prov_g jsonb; v_prov_c jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver esto.';
  end if;
  select fecha_ini, fecha_fin into v_ini, v_fin from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  -- ── Qué gratificación cae dentro del periodo ────────────────────────────────
  -- Se recorren los años de las DOS puntas del periodo, no solo el del cierre:
  -- un periodo puede empezar en diciembre y cerrar en enero, y entonces el año
  -- del cierre no es el año de la gratificación que contiene.
  select y into v_g_anio
  from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
  where make_date(y, 7, 15) between v_ini and v_fin
  limit 1;

  if v_g_anio is not null then
    v_gkey := 'grati_s1';
    v_gtxt := 'Bono Gratitud ene–jun ' || v_g_anio;
    -- El monto es el acumulado del semestre que se paga. `least` mantiene el
    -- comportamiento de siempre cuando el periodo no cruza el año.
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

  -- ── Qué CTS cae dentro del periodo ──────────────────────────────────────────
  -- Mismo criterio. Hoy un cruce de año no coincide con ninguna fecha de pago de
  -- CTS (15 de mayo y 15 de noviembre), pero se arregla igual: la lógica no debe
  -- depender de que las fechas nunca se muevan.
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

  -- Cuando no aplica nada, se consulta con la fecha de cierre igual que antes:
  -- así la respuesta sigue trayendo la lista de personas con ceros.
  v_asof_g := coalesce(v_asof_g, v_fin);
  v_asof_c := coalesce(v_asof_c, v_fin);

  v_prov_g := fn_provisiones(v_asof_g);
  -- Una sola pasada cuando ambas fechas coinciden, que es el caso normal:
  -- fn_provisiones recorre las jornadas de todo el semestre y no es gratis.
  v_prov_c := case when v_asof_c = v_asof_g then v_prov_g else fn_provisiones(v_asof_c) end;

  return jsonb_build_object(
    'grati_aplica', v_gkey is not null, 'grati_concepto', v_gtxt,
    'cts_aplica',   v_ckey is not null, 'cts_concepto',   v_ctxt,
    'personas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'persona_id', g.pid,
        'grati', case when v_gkey is null then 0 else coalesce((g.fila->>v_gkey)::numeric, 0) end,
        'cts',   case when v_ckey is null then 0 else coalesce((c.fila->>v_ckey)::numeric, 0) end
      )), '[]'::jsonb)
      from (select per->>'persona_id' as pid, per as fila
              from jsonb_array_elements(v_prov_g->'personas') per) g
      left join (select per->>'persona_id' as pid, per as fila
                   from jsonb_array_elements(v_prov_c->'personas') per) c
        on c.pid = g.pid
    )
  );
end;
$fn$;
grant execute on function fn_grati_cts_periodo(uuid) to authenticated;
revoke execute on function fn_grati_cts_periodo(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (85, 'grati_en_periodos_que_cruzan_el_ano')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
