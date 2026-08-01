-- ============================================================================
-- 0123 — Lo que ya se pagó deja de acumularse.
--
-- EL ERROR, VISTO EN PRODUCCIÓN EL 2026-08-01
--
-- La pantalla de Provisiones mostraba, al 1 de agosto, la gratificación de
-- enero–junio todavía acumulando — cuando esa gratificación se pagó el 15 de
-- julio y está registrada como movimiento en la planilla de ese periodo.
--
-- Chiara Flores lo dejaba ver de un vistazo: su fila decía
--
--     Gratificación · Julio (ene-jun)      S/ 706.54
--
-- y en su boleta de julio, entre los movimientos, había un bono
--
--     Gratificación ene–jun 2026           S/ 706.54
--
-- El mismo monto, contado dos veces. Y como esa columna entra en el «Gran
-- total», todos los totales de la pantalla estaban inflados: Chiara S/1,502.45
-- cuando lo realmente pendiente eran S/795.91.
--
-- POR QUÉ PASABA
--
-- `fn_provisiones` calcula cada ventana legal —grati ene-jun, grati jul-dic,
-- CTS nov-abr, CTS may-oct— sumando lo devengado dentro de sus fechas. Nunca
-- preguntaba si el desembolso de esa ventana ya había salido. Devengar y
-- desembolsar eran dos hechos que el cálculo no relacionaba.
--
-- QUÉ HACE ESTA MIGRACIÓN
--
-- Pregunta, por persona y por ventana, si existe un movimiento con
-- `categoria = 'gratificacion'` o `'cts'` dentro del periodo de planilla que
-- CONTIENE la fecha de pago legal. Si existe, esa ventana vale 0 en el total y
-- viaja con dos claves nuevas —`..._pagada` y `..._monto_pagado`— para que la
-- pantalla escriba «pagado el 15/07» en vez de un cero sin explicación.
--
-- POR QUÉ ESE CRITERIO Y NO UNA FECHA A MANO
--
-- Es exactamente el mismo con el que la 0049 decide en qué periodo cae un pago
-- de grati o CTS, y el mismo que usa su candado anti-doble-pago. Si las dos
-- preguntas —«¿dónde va el pago?» y «¿ya se pagó?»— se responden con la misma
-- regla, no pueden contradecirse. Una fecha de corte en configuración habría
-- sido más simple y habría vuelto a mentir el día que alguien pagara tarde.
--
-- LAS VACACIONES NO SE TOCAN, Y ES DELIBERADO
--
-- No tienen fecha de desembolso legal: se gozan cuando toca o se pagan al
-- cesar. Apagarlas por «ya se pagó» no tendría contra qué compararse. El
-- generador de esta migración lo verifica: si alguien mete `vv` en el apagado,
-- el script falla en vez de emitir SQL.
--
-- NO MUEVE NINGÚN PAGO. `fn_provisiones` es de solo lectura y alimenta una
-- pantalla de gestión; no entra en `fn_planilla_calcular` ni en ninguna boleta.
-- Lo que cambia es qué se muestra como pendiente.
--
-- SI UN PAGO NO SE REGISTRÓ EN EL SISTEMA, esta migración no puede saberlo y esa
-- ventana seguirá apareciendo pendiente. Es el comportamiento correcto: el
-- sistema no debe adivinar desembolsos que nadie anotó. Para arreglarlo se
-- carga el movimiento con el panel +/− y la fila se apaga sola.
--
-- CÓMO SE REVIERTE: restaurar fn_provisiones desde la 0122.
-- ============================================================================

-- Reemitida desde la 0122 con cuatro cambios marcados «CAMBIO 0123». El resto es
-- byte por byte lo que ya estaba: se extrajo y se parcheó con un script.

create or replace function fn_provisiones(p_as_of date default null)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_as_of date; v_y int;
  v_prov jsonb; v_f_grati numeric; v_f_cts numeric; v_f_vac numeric;
  v_sexto_cts numeric;   -- CAMBIO 0112
  v_asig numeric;        -- CAMBIO 0113
  g1_ini date; g1_fin date; g1_pago date;
  g2_ini date; g2_fin date; g2_pago date;
  c1_ini date; c1_fin date; c1_pago date;
  c2_ini date; c2_fin date; c2_pago date;
  v_prox_fecha date; v_prox_tipo text; v_prox_ref text;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o lider puede ver las provisiones.';
  end if;
  v_as_of := coalesce(p_as_of, fn_hoy_lima());
  v_y := extract(year from v_as_of)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion":0.08333,"cts":0.04167,"vacaciones":0.04167,"sexto_cts":0}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts   := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vac   := coalesce((v_prov->>'vacaciones')::numeric, 0);
  -- ⇩⇩⇩ CAMBIO 0112 ⇩⇩⇩ EL SEXTO DE LA GRATIFICACIÓN EN LA BASE DE LA CTS.
  --
  -- El Art. 16 del D.S. 001-97-TR manda que la remuneración computable de la CTS
  -- incluya «un sexto de lo percibido» por gratificación en el semestre. Hasta
  -- ahora la CTS se calculaba solo sobre el sueldo, así que faltaba ese sexto.
  --
  -- En pequeña empresa la gratificación es MEDIA remuneración, así que el sexto
  -- vale (0.5 / 6) = 0.083333 del sueldo, y la base correcta es sueldo × 13/12.
  -- Comprobado: 1,130 × 13/12 × 15/30 = S/612.08 al año, contra los S/565 de hoy.
  -- Faltaban S/47.08 al año por persona.
  --
  -- ARRANCA EN CERO: si la clave no está en configuracion, el multiplicador es 1
  -- y la CTS sale exactamente como hoy. Se activa con un UPDATE:
  --
  --   update configuracion
  --      set valor = valor || '{"sexto_cts": 0.083333}'::jsonb
  --    where clave = 'planilla_provisiones';
  --
  -- POR QUÉ ES UN MULTIPLICADOR Y NO UN FACTOR NUEVO. Subir el factor de la CTS
  -- de 4.167% a 4.514% daría el mismo número HOY, pero se rompería en cuanto la
  -- base incluya otro concepto remunerativo (la asignación familiar, por ejemplo),
  -- porque el sexto tiene que salir de la gratificación real y no del sueldo pelado.
  -- Multiplicando la base, el sexto sigue siendo un sexto de lo que sea.
  --
  -- SI CAYLA PASARA AL RÉGIMEN GENERAL, donde la gratificación es una remuneración
  -- completa, el valor correcto sería (1 / 6) = 0.166667 y la base sueldo × 7/6.
  v_sexto_cts := coalesce((v_prov->>'sexto_cts')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0113 ⇩⇩⇩ LA ASIGNACIÓN FAMILIAR ENTRA EN LA BASE.
  -- Los S/113 de la Ley 25129 SON remuneración, así que integran la remuneración
  -- computable de gratificación, CTS y vacaciones. Hasta ahora fn_provisiones no
  -- sabía que existían: se pagaban como línea aparte en la boleta y quedaban fuera
  -- de la base. El monto sale de la misma clave que usa la planilla.
  -- ⇩ CAMBIO 0122 ⇩ Esta lectura queda solo como RESPALDO. El valor que de verdad
  -- se usa se busca DÍA POR DÍA más abajo, en la rama de la 0113: esta función
  -- acumula sobre años de historia, y aplicar el monto de hoy a un periodo de 2025
  -- reescribiría lo que ya se pagó. Ver el comentario de esa rama.
  select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
  from configuracion where clave = 'asignacion_familiar';
  if v_asig is null then v_asig := 113.00; end if;

  -- Ventanas del ano (periodos legales)
  g1_ini := make_date(v_y,1,1);    g1_fin := make_date(v_y,6,30);  g1_pago := make_date(v_y,7,15);
  g2_ini := make_date(v_y,7,1);    g2_fin := make_date(v_y,12,31); g2_pago := make_date(v_y,12,15);
  c1_ini := make_date(v_y-1,11,1); c1_fin := make_date(v_y,4,30);  c1_pago := make_date(v_y,5,15);
  c2_ini := make_date(v_y,5,1);    c2_fin := make_date(v_y,10,31); c2_pago := make_date(v_y,11,15);

  -- Proximo desembolso: la fecha de pago mas cercana que aun no pasa.
  -- Incluye tambien las ventanas del ANO SIGUIENTE: entre el 16 y el 31 de dic,
  -- tras el ultimo pago del ano (grati_s2, 15-dic), el proximo desembolso cae en
  -- el ano v_y+1 (CTS may). Sin estas filas, 'proximo' quedaria NULL esas dos
  -- semanas de cada diciembre.
  select fecha, tipo, ref into v_prox_fecha, v_prox_tipo, v_prox_ref
  from (values
    (c1_pago, 'CTS',           'cts_may'),
    (g1_pago, 'Gratificacion', 'grati_s1'),
    (c2_pago, 'CTS',           'cts_nov'),
    (g2_pago, 'Gratificacion', 'grati_s2'),
    (make_date(v_y+1, 5,15), 'CTS',           'cts_may'),
    (make_date(v_y+1, 7,15), 'Gratificacion', 'grati_s1'),
    (make_date(v_y+1,11,15), 'CTS',           'cts_nov'),
    (make_date(v_y+1,12,15), 'Gratificacion', 'grati_s2')
  ) t(fecha, tipo, ref)
  where fecha >= v_as_of
  order by fecha
  limit 1;

  with base as (
    -- 1) Sueldo regular ganado por HORAS (base mensual correcta). Excluye a quien
    --    cobra sueldo fijo: ese va por la rama 2, para no contar dos veces.
    select j.persona_id, j.fecha,
           j.horas_trabajadas * tt.salario
             / (6.5 * extract(day from (date_trunc('month', j.fecha) + interval '1 month - 1 day'))::numeric) as pago_dia
    from jornadas j
    join personas pp on pp.id = j.persona_id and not pp.sueldo_fijo
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = j.persona_id
        and j.fecha >= a.vigente_desde
        and (a.vigente_hasta is null or j.fecha <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where j.horas_trabajadas is not null and j.horas_trabajadas > 0

    union all

    -- ⇩⇩⇩ CAMBIO 0113 ⇩⇩⇩ 3) ASIGNACIÓN FAMILIAR de quien tiene hijos.
    --
    -- Es remuneración (Ley 25129), así que entra en la base de gratificación, CTS
    -- y vacaciones. La doctrina lo dice con este mismo ejemplo: «si ganas S/1,130
    -- + S/113, tu gratificación será S/1,243, no S/1,130».
    --
    -- Va por día de CALENDARIO y no por jornada marcada, igual que el sueldo fijo:
    -- la asignación se paga completa cada mes, no se recorta por asistencia. Al
    -- sumar un mes entero da los S/113 exactos, y en los bordes del periodo (mes
    -- de ingreso, primer mes de la ventana) prorratea por días, que es el mismo
    -- criterio que ya usaba la rama 2.
    --
    -- Aplica a TODOS los que tienen hijos, con sueldo fijo o por horas: la rama 1
    -- excluye a los de sueldo fijo para no contarlos dos veces, pero la asignación
    -- les corresponde igual, y esta rama no los excluye a propósito.
    -- ⇩⇩⇩ CAMBIO 0122 ⇩⇩⇩ EL MONTO SE BUSCA POR DÍA, no una vez para toda la
    -- historia. La asignación es el 10% de la RMV y sube cuando sube la RMV: si
    -- se aplicara el monto de hoy a los días de 2025, la provisión de un periodo
    -- ya pagado cambiaría al publicarse el decreto. Con la búsqueda por día, cada
    -- día aporta el monto que estaba vigente ESE día y el pasado queda fijo.
    --
    -- Es una subconsulta correlacionada por día y sí cuesta más que leer un
    -- escalar. Se acepta a propósito: la función es 'stable' y se llama a demanda,
    -- y la alternativa es un cálculo que se mueve solo. Si el volumen molesta, el
    -- arreglo es un lateral contra un rango de fechas, no volver al escalar.
    select p.id as persona_id, gs::date as fecha,
           coalesce(
             (select pl.valor
                from parametros_laborales pl
               where pl.clave = 'asignacion_familiar'
                 and pl.vigente_desde <= gs::date
                 and (pl.vigente_hasta is null or pl.vigente_hasta >= gs::date)
               order by pl.vigente_desde desc
               limit 1),
             v_asig)
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from personas p
    cross join lateral generate_series(p.fecha_ingreso::timestamp, v_as_of::timestamp, interval '1 day') gs
    where p.con_hijos

    union all

    -- 2) SUELDO FIJO: provisiona su salario completo cada mes, marque o no. Se
    --    genera un aporte diario = salario / días del mes para cada día de
    --    calendario desde su ingreso; al sumar un mes entero da el salario, y en
    --    los bordes prorratea por días. Mismo criterio que ya usa planilla.
    select p.id as persona_id, gs::date as fecha,
           sal.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from personas p
    cross join lateral generate_series(p.fecha_ingreso::timestamp, v_as_of::timestamp, interval '1 day') gs
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and gs::date >= a.vigente_desde
        and (a.vigente_hasta is null or gs::date <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) sal on true
    where p.sueldo_fijo
  )
  select coalesce(jsonb_agg(sub.fila order by sub.nombre), '[]'::jsonb) into v_out
  from (
    select (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id', p.id,
        'nombre', p.nombres || ' ' || p.apellidos,
        'sede', s.codigo,
        'fecha_ingreso', p.fecha_ingreso,
        -- ⇩ CAMBIO 0123 ⇩ Una ventana ya desembolsada vale 0: seguir sumándola
        -- contaba dos veces la misma plata. El monto original viaja aparte para
        -- que la pantalla pueda escribir «pagado el 15/07» en vez de un cero mudo.
        'grati_s1', case when pag.g1 then 0 else round(v_f_grati * coalesce(g1.pago,0), 2) end,
        'grati_s1_pagada', pag.g1,
        'grati_s1_monto_pagado', case when pag.g1 then round(v_f_grati * coalesce(g1.pago,0), 2) end,
        'grati_s2', case when pag.g2 then 0 else round(v_f_grati * coalesce(g2.pago,0), 2) end,
        'grati_s2_pagada', pag.g2,
        'grati_s2_monto_pagado', case when pag.g2 then round(v_f_grati * coalesce(g2.pago,0), 2) end,
        'grati_total', round(
            (case when pag.g1 then 0 else v_f_grati * coalesce(g1.pago,0) end)
          + (case when pag.g2 then 0 else v_f_grati * coalesce(g2.pago,0) end), 2),
        'cts_may', case when pag.cm then 0 else round(v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0), 2) end,
        'cts_may_pagada', pag.cm,
        'cts_may_monto_pagado', case when pag.cm then round(v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0), 2) end,
        'cts_nov', case when pag.cn then 0 else round(v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0), 2) end,
        'cts_nov_pagada', pag.cn,
        'cts_nov_monto_pagado', case when pag.cn then round(v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0), 2) end,
        'cts_total', round(
            (case when pag.cm then 0 else v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) end)
          + (case when pag.cn then 0 else v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) end), 2),
        -- para que la pantalla pueda mostrar qué multiplicador se usó
        'sexto_cts', v_sexto_cts,
        'vac', round(v_f_vac * coalesce(vv.pago,0), 2),
        'vac_dias', round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1),
        'proximo_aniversario', va.aniv_next,
        'gran_total', round(
            (case when pag.g1 then 0 else v_f_grati * coalesce(g1.pago,0) end)
          + (case when pag.g2 then 0 else v_f_grati * coalesce(g2.pago,0) end)
          + (case when pag.cm then 0 else v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) end)
          + (case when pag.cn then 0 else v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) end)
          + v_f_vac * coalesce(vv.pago,0), 2)
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    -- ⇩ CAMBIO 0123 ⇩ ¿Ya se desembolsó cada ventana?
    cross join lateral (
      select
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g1_pago between pp.fecha_ini and pp.fecha_fin) as g1,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'gratificacion'
                   and g2_pago between pp.fecha_ini and pp.fecha_fin) as g2,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'cts'
                   and c1_pago between pp.fecha_ini and pp.fecha_fin) as cm,
        exists (select 1 from movimientos_planilla m
                  join periodos_planilla pp on pp.id = m.periodo_id
                 where m.persona_id = p.id and m.categoria = 'cts'
                   and c2_pago between pp.fecha_ini and pp.fecha_fin) as cn
    ) pag
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g1_ini,p.fecha_ingreso) and least(v_as_of,g1_fin)) g1 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(g2_ini,p.fecha_ingreso) and least(v_as_of,g2_fin)) g2 on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c1_ini,p.fecha_ingreso) and least(v_as_of,c1_fin)) cm on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between greatest(c2_ini,p.fecha_ingreso) and least(v_as_of,c2_fin)) cn on true
    left join lateral (select sum(b.pago_dia) as pago from base b where b.persona_id=p.id and b.fecha between va.aniv_ini and v_as_of) vv on true
    where p.estado = 'activo'
  ) sub;

  return jsonb_build_object(
    'as_of', v_as_of,
    'factores', v_prov,
    'proximo', jsonb_build_object('fecha', v_prox_fecha, 'tipo', v_prox_tipo, 'ref', v_prox_ref),
    'grati_s1_pago', g1_pago, 'grati_s2_pago', g2_pago,
    'cts_may_pago', c1_pago, 'cts_nov_pago', c2_pago,
    'grati_s1_periodo', 'ene-jun', 'grati_s2_periodo', 'jul-dic',
    'cts_may_periodo', 'nov-abr', 'cts_nov_periodo', 'may-oct',
    'personas', v_out
  );
end;



$$;



insert into migraciones_aplicadas (numero, nombre)
values (123, 'lo_pagado_deja_de_acumularse')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';
