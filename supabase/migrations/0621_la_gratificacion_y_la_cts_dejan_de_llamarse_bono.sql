-- ============================================================================
-- 0621 · La gratificación y la CTS dejan de llamarse «bono», esta vez de raíz
-- ============================================================================
--
-- QUÉ PROMETE
--   1. Que `fn_grati_cts_periodo` proponga los conceptos con su nombre legal:
--        «Bono Gratitud ene–jun 2026»       →  «Gratificación ene–jun 2026»
--        «Bono Comprometidos may–oct 2026»  →  «CTS may–oct 2026»
--      (y lo mismo en el concepto del 9 %, que lleva dentro el de la grati).
--   2. Que los movimientos ya registrados con el nombre viejo pasen al legal,
--      con la misma regla y el mismo alcance que la 0107.
--   Nada más: ni un monto, ni una regla de cálculo, ni una fecha.
--
-- POR QUÉ OTRA VEZ, SI LA 0107 YA LO HIZO
--   El 2026-07-28 Felipe decidió volver a los nombres legales: la gratificación
--   y la CTS son derechos de ley, y llamarlas «bono» ante SUNAFIL se lee como
--   disfrazar un pago obligatorio de liberalidad. Ese día se cambió la etiqueta
--   del desplegable (`CLASE_LABEL`) y la 0107 renombró los movimientos que ya
--   existían — pero NADIE tocó la función que ESCRIBE el concepto
--   autocompletado, que lo traía así desde la 0050. Y cada reescritura de esa
--   función (0088, 0338, 0346, 0619) copió el cuerpo de la anterior, con su
--   texto viejo incluido, que es exactamente lo que este repositorio pide hacer
--   al reescribir. La prueba 88 además EXIGÍA «Bono Gratitud»: el error estaba
--   protegido por su propia prueba.
--
--   Se notó el 2026-11-25: la CTS de noviembre (ya depositada el 14-nov) volvió
--   a aparecer en la planilla de noviembre como 17 «Bono Comprometidos may–oct
--   2026». Eso se corrigió como dato aparte (el pago pasó al libro de
--   desembolsos); esta migración corrige el nombre.
--
-- QUÉ ASUME
--   · md5 de partida de `fn_grati_cts_periodo`: el de la 0619 en el
--     repositorio, 7dd160467dd28ef4a6cd922c506e04d1 (7483 caracteres).
--     PENDIENTE DE CONFIRMAR CONTRA PRODUCCIÓN en el mensaje en que se entrega.
--   · Que la foto del pago (0096) sigue congelando montos y no textos: el
--     renombre de la parte 2 no mueve ningún total, igual que en la 0107.
--
-- POR QUÉ ASÍ
--   DECIDÍ: copiar el cuerpo de la 0619 tal cual y cambiar solo las cuatro
--     cadenas (marcadas «CAMBIO 0621»). Repetir el UPDATE de la 0107 con su
--     misma expresión, porque es la regla ya acordada para el pasado.
--   DESCARTÉ: guardar solo la categoría y decidir el nombre al mostrarlo — la
--     raíz que la 0107 ya anotó. Es el arreglo de fondo, pero toca la boleta,
--     la planilla, el CSV y la foto del pago; no cabe en una corrección de
--     nombre. Lo que sí se agrega es la prueba 506, que falla si cualquier
--     versión futura de la función vuelve a escribir «bono» en un concepto de
--     gratificación o CTS: la copia del cuerpo viejo ya no puede pasar callada.
--   SE ROMPE SI alguien reescribe `fn_grati_cts_periodo` partiendo de la 0619
--     o anterior: la 506 lo caza.
--
-- A QUIÉN LE CAMBIA
--   A nadie en plata. En papel: toda boleta con un concepto «Bono Gratitud» o
--   «Bono Comprometidos» —incluidas las de periodos ya pagados— se reimprime
--   con «Gratificación» o «CTS». Es lo mismo que la 0107 ya aceptó.
--
-- CÓMO SE REVIERTE
--   Repegar la 0619 (devuelve los textos viejos a la función). El renombre de
--   los movimientos no se revierte: el nombre viejo es el incorrecto.
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
  v_sal_g date;   -- CAMBIO 0619: la fecha del SUELDO de la gratificación (30/06 o 30/11)
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
    v_gtxt := 'Gratificación ene–jun ' || v_g_anio;   -- CAMBIO 0621
    v_asof_g := least(v_fin, make_date(v_g_anio, 6, 30));
    v_sal_g  := v_asof_g;
  else
    select y into v_g_anio
    from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
    where make_date(y, 12, 15) between v_ini and v_fin
    limit 1;
    if v_g_anio is not null then
      v_gkey := 'grati_s2';
      v_gtxt := 'Gratificación jul–dic ' || v_g_anio;   -- CAMBIO 0621
      v_asof_g := least(v_fin, make_date(v_g_anio, 12, 31));
      -- CAMBIO 0619 — los días se devengan hasta el fin del periodo, pero el
      -- SUELDO de la gratificación de diciembre es el del 30 de noviembre
      -- (D.S. 005-2002-TR art. 3.2). Antes se tomaba el de v_asof_g (28/12): un
      -- cambio de sueldo fechado en diciembre movía todo el semestre.
      v_sal_g  := least(v_fin, make_date(v_g_anio, 11, 30));
    end if;
  end if;

  select y into v_c_anio
  from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
  where make_date(y, 5, 15) between v_ini and v_fin
  limit 1;

  if v_c_anio is not null then
    v_ckey := 'cts_may';
    v_ctxt := 'CTS nov ' || (v_c_anio - 1) || '–abr ' || v_c_anio;   -- CAMBIO 0621
    v_asof_c := least(v_fin, make_date(v_c_anio, 4, 30));
  else
    select y into v_c_anio
    from generate_series(extract(year from v_ini)::int, extract(year from v_fin)::int) y
    where make_date(y, 11, 15) between v_ini and v_fin
    limit 1;
    if v_c_anio is not null then
      v_ckey := 'cts_nov';
      v_ctxt := 'CTS may–oct ' || v_c_anio;   -- CAMBIO 0621
      v_asof_c := least(v_fin, make_date(v_c_anio, 10, 31));
    end if;
  end if;

  v_asof_g := coalesce(v_asof_g, v_fin);
  v_sal_g  := coalesce(v_sal_g, v_asof_g);
  v_asof_c := coalesce(v_asof_c, v_fin);

  v_prov_g := fn_provisiones(v_asof_g);
  v_prov_c := case when v_asof_c = v_asof_g then v_prov_g else fn_provisiones(v_asof_c) end;

  v_prov_g_piso := fn_provisiones(v_asof_g, v_sal_g);
  v_prov_c_piso := case when v_asof_c = v_asof_g and v_sal_g = v_asof_c then v_prov_g_piso
                        else fn_provisiones(v_asof_c, v_asof_c) end;

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
        -- fecha de cierre: ahí la lectura del cierre devenga de menos por falta
        -- de dato, no porque no le toque. Se pregunta DIRECTO con la bandera
        -- `sin_salario_vigente` de esa lectura (0365), no deduciéndolo de un
        -- monto en cero: quien tiene hijos devenga su asignación familiar aun
        -- sin tramo, y con «devengado > 0» se le habría pagado solo eso.
        -- La segunda condición (algo DEVENGADO: celda + lo ya cobrado) cubre a
        -- quien no devenga nada al cierre por otro motivo; se mira lo devengado
        -- y no el saldo, porque un saldo en cero por estar pagado no es falta
        -- de dato.
        select g.pid,
               case when v_gkey is null then 0
                    when coalesce((gp.fila->>'sin_salario_vigente')::boolean, false)
                      then coalesce((g.fila->>v_gkey)::numeric, 0)
                    when coalesce((gp.fila->>v_gkey)::numeric, 0)
                       + coalesce((gp.fila->>(v_gkey || '_monto_pagado'))::numeric, 0) > 0
                      then coalesce((gp.fila->>v_gkey)::numeric, 0)
                    else coalesce((g.fila->>v_gkey)::numeric, 0)
               end as grati,
               case when v_ckey is null then 0
                    when coalesce((cp.fila->>'sin_salario_vigente')::boolean, false)
                      then coalesce((c.fila->>v_ckey)::numeric, 0)
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

-- ── 2 · Los movimientos que ya se registraron con el nombre viejo ──────────
-- Misma expresión que la 0107 ('gi': también «bono gratitud» escrito a mano).
-- Conserva el detalle: «Bono Gratitud ene–jun 2026» queda «Gratificación
-- ene–jun 2026», y el 9 % «… — Bono Gratitud jul–dic 2026» queda «… —
-- Gratificación jul–dic 2026».
do $$
declare
  v_grati int;
  v_cts   int;
begin
  with cambiadas as (
    update movimientos_planilla
       set concepto = regexp_replace(concepto, 'Bono\s+Gratitud', 'Gratificación', 'gi')
     where concepto ~* 'Bono\s+Gratitud'
    returning 1
  )
  select count(*) into v_grati from cambiadas;

  with cambiadas as (
    update movimientos_planilla
       set concepto = regexp_replace(concepto, 'Bono\s+Comprometidos', 'CTS', 'gi')
     where concepto ~* 'Bono\s+Comprometidos'
    returning 1
  )
  select count(*) into v_cts from cambiadas;

  raise notice '0621 · movimientos renombrados: % de gratificación, % de CTS.', v_grati, v_cts;
end $$;

insert into migraciones_aplicadas (numero, nombre) values (621, 'la_gratificacion_y_la_cts_dejan_de_llamarse_bono')
on conflict (numero) do update set nombre = excluded.nombre, aplicada_at = now();
