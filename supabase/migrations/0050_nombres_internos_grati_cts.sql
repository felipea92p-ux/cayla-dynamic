-- ============================================================================
-- 0050_nombres_internos_grati_cts.sql — Nombres discretos del sistema interno
-- ============================================================================
-- Felipe: en el sistema INTERNO la gratificación y la CTS se leen como
-- "Bono Gratitud" y "Bono Comprometidos". Los términos formales (Gratificación,
-- CTS) quedan reservados para el sistema formal de declaraciones.
--
-- SOLO cambia el texto del concepto autocompletado. Por dentro sigue siendo
-- grati/CTS: la categoría ('gratificacion'/'cts'), el cálculo y el candado
-- anti-doble-pago no se tocan. Es puramente cómo se LEE.

create or replace function fn_grati_cts_periodo(p_periodo_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_ini date; v_fin date; v_y int; v_prov jsonb;
  v_gkey text; v_ckey text; v_gtxt text; v_ctxt text;
  v_g1 date; v_g2 date; v_c1 date; v_c2 date;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver esto.';
  end if;
  select fecha_ini, fecha_fin into v_ini, v_fin from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_prov := fn_provisiones(v_fin);
  v_g1 := (v_prov->>'grati_s1_pago')::date; v_g2 := (v_prov->>'grati_s2_pago')::date;
  v_c1 := (v_prov->>'cts_may_pago')::date;  v_c2 := (v_prov->>'cts_nov_pago')::date;
  v_y := extract(year from v_fin)::int;

  -- ventana de grati cuya fecha de pago cae en el periodo
  if    v_g1 between v_ini and v_fin then v_gkey := 'grati_s1'; v_gtxt := 'Bono Gratitud ene–jun ' || v_y;
  elsif v_g2 between v_ini and v_fin then v_gkey := 'grati_s2'; v_gtxt := 'Bono Gratitud jul–dic ' || v_y;
  end if;
  -- ventana de CTS
  if    v_c1 between v_ini and v_fin then v_ckey := 'cts_may'; v_ctxt := 'Bono Comprometidos nov' || (v_y-1) || '–abr ' || v_y;
  elsif v_c2 between v_ini and v_fin then v_ckey := 'cts_nov'; v_ctxt := 'Bono Comprometidos may–oct ' || v_y;
  end if;

  return jsonb_build_object(
    'grati_aplica', v_gkey is not null, 'grati_concepto', v_gtxt,
    'cts_aplica',   v_ckey is not null, 'cts_concepto',   v_ctxt,
    'personas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'persona_id', per->>'persona_id',
        'grati', case when v_gkey is null then 0 else coalesce((per->>v_gkey)::numeric, 0) end,
        'cts',   case when v_ckey is null then 0 else coalesce((per->>v_ckey)::numeric, 0) end
      )), '[]'::jsonb)
      from jsonb_array_elements(v_prov->'personas') per
    )
  );
end;
$$;

grant execute on function fn_grati_cts_periodo(uuid) to authenticated;
