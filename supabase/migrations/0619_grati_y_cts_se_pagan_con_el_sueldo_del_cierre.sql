-- ============================================================================
-- 0619 · La gratificación y la CTS se pagan con el sueldo del cierre, no con la mayor de dos cuentas
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `fn_grati_cts_periodo` —la que autocompleta el pago de gratificación y
--   CTS— devuelva, por persona, el monto calculado con el sueldo vigente al
--   CIERRE del semestre aplicado a todo el semestre. Nada más.
--
-- QUÉ HABÍA (0338)
--   La función leía `fn_provisiones` dos veces —día por día y con el sueldo del
--   cierre— y se quedaba con la MAYOR. La 0338 lo eligió para que un aumento a
--   mitad de semestre no dejara el pago por debajo de la ley, y de paso «para
--   no quitarle nada a nadie» cuando el sueldo bajaba.
--
-- POR QUÉ CAMBIA (decisión de Felipe, 2026-11-14)
--   Esa segunda mitad regala plata. Hasta el 28/07/2026 el tramo de salario
--   guardaba el rango completo (1,320 / 1,450 / 1,650), del que en planilla se
--   declaraban S/ 1,130; el 29/07 el tramo bajó a la base declarada. Para la CTS
--   de noviembre de 2026, el día por día sumaba mayo–julio con el rango viejo y
--   le ganaba a la lectura legal en siete personas: S/ 142.24 de más sobre
--   S/ 4,251.42. La ley no pide eso: la remuneración computable de la CTS es la
--   de abril u octubre (D.S. 001-97-TR art. 10) y la de la gratificación la del
--   30 de junio o 30 de noviembre (Ley 27735 art. 2 y su reglamento), aplicada a
--   los meses y días del semestre (art. 21 / art. 50 del D.S. 013-2013-PRODUCE).
--   Sus palabras: «no regales dinero, CAYLA ya es demasiado generosa, paga lo
--   legal».
--
-- QUÉ ASUME
--   · Que `fn_provisiones(as_of, salario_asof)` (0338, vigente la 0491) sigue
--     aplicando el sueldo de `salario_asof` a todos los días del periodo. Esta
--     migración NO la toca.
--   · md5 de partida de `fn_grati_cts_periodo`, pedido a PRODUCCIÓN el
--     2026-11-14: 029c534ff79b6e60d7a5a760be659053 (5311 caracteres, sin \r),
--     idéntico al de la 0346 en el repositorio.
--
-- POR QUÉ ASÍ
--   DECIDÍ: cambiar solo la elección entre las dos lecturas, dentro de la misma
--     función, y dejar el día por día como respaldo de quien no tiene tramo de
--     salario al cierre.
--   DESCARTÉ: quitar la lectura día por día del todo, porque a quien le falta el
--     tramo a la fecha de cierre la lectura legal le devenga cero por falta de
--     dato, y el pago le saldría en cero sin que nadie lo note. Y descarté
--     cambiar `fn_provisiones` para que siempre use el sueldo del cierre: la
--     reserva de un semestre en curso todavía no tiene «sueldo del cierre».
--   SE ROMPE SI la pantalla de Provisiones (`aplicarPisoLegal`) no cambia a la
--     misma regla: prometería un monto y la planilla pagaría otro. Cambian
--     juntas, en el mismo PR.
--
-- A QUIÉN LE CAMBIA
--   A quien le BAJÓ el sueldo registrado dentro del semestre: cobra menos que
--   con la 0338 (lo legal, no la mayor). A quien le subió, igual que antes. A
--   quien no le cambió, igual que antes. Auditado contra producción el
--   2026-11-14 para la CTS de noviembre: siete personas bajan, diez quedan igual.
--
-- CÓMO SE REVIERTE
--   Repegar la 0346 (devuelve el `greatest`).
--
-- Idempotente: se puede pegar dos veces.
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
        -- resuelto con el sueldo del cierre desde la 0619), nunca de una
        -- base propia: ver el comentario de cabecera.
        'be',    round(x.grati * v_f_be, 2)
      )), '[]'::jsonb)
      from (
        -- ⇩⇩⇩ CAMBIO 0619 ⇩⇩⇩ SOLO EL SUELDO DEL CIERRE. Decía, en las dos columnas:
        --     greatest( día por día , sueldo del cierre )
        -- Ahora manda la lectura con el sueldo del cierre. La del día por día
        -- queda solo como respaldo para quien NO tiene tramo de salario a la
        -- fecha de cierre: ahí la lectura del cierre devenga cero por falta de
        -- dato, no porque no le toque, y pagarle cero sería pagar de menos.
        -- Se compara lo DEVENGADO (celda + lo ya cobrado), no el saldo: un saldo
        -- en cero porque ya se pagó no es «falta de dato».
        select g.pid,
               case when v_gkey is null then 0
                    when coalesce((gp.fila->>v_gkey)::numeric, 0)
                       + coalesce((gp.fila->>(v_gkey || '_monto_pagado'))::numeric, 0) > 0
                      then coalesce((gp.fila->>v_gkey)::numeric, 0)
                    else coalesce((g.fila->>v_gkey)::numeric, 0)
               end as grati,
               case when v_ckey is null then 0
                    when coalesce((cp.fila->>v_ckey)::numeric, 0)
                       + coalesce((cp.fila->>(v_ckey || '_monto_pagado'))::numeric, 0) > 0
                      then coalesce((cp.fila->>v_ckey)::numeric, 0)
                    else coalesce((c.fila->>v_ckey)::numeric, 0)
               end as cts
        -- ⇧⇧⇧ FIN CAMBIO 0619 ⇧⇧⇧
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

insert into migraciones_aplicadas (numero, nombre) values (619, 'grati_y_cts_se_pagan_con_el_sueldo_del_cierre')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
