-- ============================================================================
-- 0049_grati_cts_en_planilla.sql — Grati y CTS calculadas en su periodo
-- ============================================================================
-- Felipe (2026-07-20): que la gratificación y la CTS se calculen automáticamente
-- en el periodo de planilla que les corresponde, y se puedan agregar desde el
-- panel +/- (junto a Bono/Descuento/Vacaciones/Otros), confirmando con un clic.
--
-- Diseño acordado:
--   · El MONTO lo calcula el sistema (reusa fn_provisiones, no recalcula nada).
--   · SUMA al total del periodo, como un bono (CAYLA lleva el sistema interno
--     junto; la CTS al banco se separa en el sistema formal, aparte de este).
--   · Cae en el periodo que CONTIENE la fecha de pago legal: grati 15/07 y 15/12,
--     CTS 15/05 y 15/11.
--   · No se paga solo: el usuario confirma. Aquí solo se provee el cálculo + el
--     candado anti-doble-pago.

-- 1) Categorías nuevas para etiquetar el movimiento (siguen siendo tipo 'bono').
alter table movimientos_planilla drop constraint if exists movimientos_categoria_valida;
alter table movimientos_planilla add constraint movimientos_categoria_valida
  check (categoria is null or categoria in ('vacaciones', 'otros', 'gratificacion', 'cts'));

-- 2) fn_agregar_movimiento con CANDADO anti-doble-pago para grati/cts: no puede
--    haber dos del mismo tipo para la misma persona en el mismo periodo (un
--    estado imposible por definición: la grati de un semestre se paga una vez).
create or replace function fn_agregar_movimiento(
  p_periodo_id uuid, p_persona_id uuid, p_tipo text,
  p_concepto text, p_monto numeric, p_categoria text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare v_estado text;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede registrar movimientos.';
  end if;
  select estado into v_estado from periodos_planilla where id = p_periodo_id;
  if not found then raise exception 'Periodo inexistente.'; end if;
  if v_estado = 'pagado' then
    raise exception 'Este periodo ya está PAGADO: reábrelo para modificarlo.';
  end if;
  if p_tipo is null or p_tipo not in ('bono', 'descuento') then
    raise exception 'Tipo inválido (bono o descuento).';
  end if;
  if p_categoria is not null and p_categoria not in ('vacaciones','otros','gratificacion','cts') then
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
  if p_categoria in ('gratificacion','cts') and exists (
    select 1 from movimientos_planilla
    where periodo_id = p_periodo_id and persona_id = p_persona_id and categoria = p_categoria
  ) then
    raise exception 'Esta persona ya tiene % en este periodo. Quítalo antes de volver a agregarlo.', p_categoria;
  end if;

  insert into movimientos_planilla (periodo_id, persona_id, tipo, concepto, monto, categoria, creado_por)
  values (p_periodo_id, p_persona_id, p_tipo, trim(p_concepto), round(p_monto, 2),
          nullif(trim(coalesce(p_categoria, '')), ''), fn_persona_actual_id());
end;
$$;

grant execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text) to authenticated;
revoke execute on function fn_agregar_movimiento(uuid, uuid, text, text, numeric, text) from public, anon;

-- 3) fn_grati_cts_periodo: cuánto de grati y CTS toca en ESTE periodo, por persona.
--    Reusa fn_provisiones (calculada al fin del periodo) y elige la ventana cuya
--    fecha de pago cae dentro del periodo. Fuera de esas fechas, devuelve 0.
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
  if    v_g1 between v_ini and v_fin then v_gkey := 'grati_s1'; v_gtxt := 'Gratificación ene–jun ' || v_y;
  elsif v_g2 between v_ini and v_fin then v_gkey := 'grati_s2'; v_gtxt := 'Gratificación jul–dic ' || v_y;
  end if;
  -- ventana de CTS
  if    v_c1 between v_ini and v_fin then v_ckey := 'cts_may'; v_ctxt := 'CTS nov' || (v_y-1) || '–abr ' || v_y;
  elsif v_c2 between v_ini and v_fin then v_ckey := 'cts_nov'; v_ctxt := 'CTS may–oct ' || v_y;
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
