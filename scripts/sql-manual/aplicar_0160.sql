-- ############################################################################
-- ####  ESTE ES EL ARCHIVO QUE SE PEGA EN EL SQL EDITOR DE SUPABASE.      ####
-- ############################################################################
--
-- aplicar_0160.sql — Quien no devenga beneficios deja de provisionarlos
--
-- QUÉ HACE, en dos partes
--   1. La migración: Provisiones deja de acumular CTS, gratificación,
--      vacaciones y el 9% para quien no los devenga.
--   2. Marca a Catherine y a Carlos como `rxh` (recibos por honorarios), que es
--      su vínculo real. Va por `fn_set_tipo_vinculo`, la función que ya existe
--      para esto: valida, exige sesión de admin y deja rastro en auditoría. Un
--      `update` a pelo se saltaría las tres cosas.
--
-- QUÉ **NO** HACE
--   No toca boletas, ni periodos pagados, ni salarios. `fn_provisiones` solo
--   lee y calcula.
--
-- OJO CON LO QUE VAS A VER DESPUÉS
--   La provisión de Catherine pasa de S/2.841,70 a CERO, y la de Carlos de
--   S/1.029,76 a cero. No se les quita nada: nunca les correspondió. Lo que
--   cambia es que el número que va al contador deja de incluirlo.
--
-- SE PUEDE CORRER DOS VECES SIN PROBLEMA.
--
-- Fuente: supabase/migrations/0160_quien_no_devenga_no_provisiona.sql
-- Probada con 9 comprobaciones; 4 fallan contra el esquema anterior.
-- ############################################################################

begin;

-- ============================================================================
-- 0160 — Quien no devenga beneficios deja de provisionarlos
-- ============================================================================
--
-- QUÉ PROMETE
--   Provisiones deja de acumular CTS, gratificación, vacaciones y bonificación
--   del 9% para quien no los devenga: locadores (`rxh`) y no trabajadores. Su
--   fila sigue apareciendo, con todo en cero.
--
-- QUÉ ASUME
--   · `fn_devenga_beneficios(tipo_vinculo)` es la respuesta a «¿esta persona
--     devenga beneficios?». Devuelve verdadero solo para 'planilla'.
--   · `tipo_vinculo` está bien puesto en cada ficha. La función no adivina.
--
-- EL FALLO, ENCONTRADO EL 2026-08-05
--
--   La misma pregunta se contestaba de dos formas distintas en dos partes del
--   sistema:
--
--     fn_cts_trunca          consulta fn_devenga_beneficios   ✔ desde la 0085
--     fn_grati_trunca        consulta fn_devenga_beneficios   ✔
--     fn_vacaciones_truncas  consulta fn_devenga_beneficios   ✔
--     fn_provisiones         NO consultaba nada               ✘
--
--   Resultado medido en producción: Catherine Pereyra, que trabaja por recibos
--   por honorarios, figuraba con S/2.841,70 de beneficios acumulados — el monto
--   más alto de la empresa. No los devenga y nunca los devengó.
--
--   Y la incoherencia es la peor forma de este error: la provisión decía que
--   CAYLA debía ese dinero, mientras la liquidación —el día que esa persona
--   cesara— no le habría pagado ni un sol. Se guarda plata para algo que jamás
--   va a salir, y el número que va al contador queda inflado.
--
-- POR QUÉ SE FILTRA EN LA BASE Y NO EN CADA CAMPO
--   El objeto de salida tiene ONCE campos con monto (grati_s1, grati_s2,
--   grati_total, be_s1, be_s2, be_total, cts_may, cts_nov, cts_total, vac y
--   gran_total). Multiplicar los once por un factor es once oportunidades de
--   olvidarse de uno, y el que se olvide va a ser el que nadie mire.
--
--   Los once nacen del mismo sitio: el CTE `base`, que reparte el pago por día.
--   Filtrando ahí —tres ramas— los once quedan en cero solos y por construcción.
--
-- LA PERSONA NO DESAPARECE DE LA LISTA
--   Se queda con todo en cero, que es como resolvió la 0117 el mismo problema en
--   `fn_planilla_calcular`: `* (case when en_planilla then 1 else 0 end)`. Sacar
--   a alguien de la lista obliga a preguntarse si falta por error; verlo en cero
--   es una respuesta.
--
-- POR QUÉ `fn_devenga_beneficios` Y NO `en_planilla`
--   Se parecen y no son lo mismo: `en_planilla` incluye a quien está en periodo
--   de prueba y `fn_devenga_beneficios` no. Se usa el segundo porque es el que
--   usan las tres funciones de liquidación, y la provisión tiene que coincidir
--   con lo que la liquidación pagaría. Provisionar lo que no se va a liquidar es
--   exactamente el error que esta migración viene a cerrar.
--
-- CÓMO SE REVIERTE
--   Volver a aplicar la definición de `fn_provisiones` de la migración 0158.
--   No hay datos que deshacer: esta función solo lee.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_provisiones(p_as_of date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_as_of date; v_y int;
  v_prov jsonb; v_f_grati numeric; v_f_cts numeric; v_f_vac numeric;
  v_f_be numeric;   -- CAMBIO 0134
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

  -- CAMBIO 0134 — la bonificacion extraordinaria (Ley 30334), versionada.
  select pl.valor into v_f_be
  from parametros_laborales pl
  where pl.clave = 'bonificacion_extraordinaria'
    and pl.vigente_desde <= v_as_of
    and (pl.vigente_hasta is null or pl.vigente_hasta >= v_as_of)
  order by pl.vigente_desde desc
  limit 1;
  if v_f_be is null then v_f_be := 0.09; end if;
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
    -- ⇩ CAMBIO 0160 ⇩ Quien no devenga beneficios no aporta días a la base.
    join personas pp on pp.id = j.persona_id and not pp.sueldo_fijo
                    and fn_devenga_beneficios(pp.tipo_vinculo)
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

    -- ⇩⇩⇩ CAMBIO 0135 ⇩⇩⇩ 4) LOS DÍAS QUE LA LEY MANDA CONTAR AUNQUE NADIE MARQUE.
    --
    -- EL PROBLEMA QUE ARREGLA. La rama 1 exige `horas_trabajadas > 0`. Quien está
    -- de vacaciones no marca, así que esos días aportaban CERO a su gratificación:
    -- tomarse las vacaciones le bajaba la gratificación del semestre. Un mes entero
    -- de vacaciones costaba un sexto de la gratificación, a quien ejerció un derecho.
    --
    -- LO QUE MANDA LA NORMA. El D.S. 005-2002-TR art. 2 considera tiempo
    -- efectivamente laborado, para efectos de la gratificación:
    --   a) el descanso vacacional
    --   b) la licencia con goce de remuneraciones
    --   c) los descansos o licencias de la seguridad social que originan subsidio
    --      (descanso médico, maternidad)
    --   d) el descanso por accidente de trabajo remunerado o subsidiado
    --
    -- POR QUÉ `ta.paga` Y NO UNA LISTA DE CÓDIGOS ESCRITA A MANO. El catálogo
    -- `tipos_ausencia` ya distingue cuáles pagan (columna `paga`), y ese es
    -- exactamente el criterio de la norma. Con una lista escrita acá, el día que
    -- Felipe agregue un tipo pagado desde la pantalla habría que acordarse de
    -- tocar esta función — y nadie se va a acordar. Hoy `paga` es true para
    -- vacaciones, descanso_medico y maternidad, y false para duelo, permiso
    -- personal, estudios, cumpleaños, salud-sin-documento y otro. Esos seis NO
    -- deben sumar, y no suman.
    --
    -- POR QUÉ NO EXIGE APROBACIÓN. Una ausencia registrada y no anulada es un
    -- hecho. Exigir `aprobada_at` haría que un descanso médico pendiente de firma
    -- le baje la gratificación a la persona, y la regla de la casa es clara: el
    -- error que más cuesta es el que va contra quien no debía. Si la ausencia
    -- resulta falsa, se anula y deja de contar sola.
    --
    -- CUÁNTO APORTA UN DÍA. Lo mismo que aporta un día de sueldo fijo:
    -- salario / días del mes. Es el día estándar de esa persona a su salario
    -- vigente ESE día, no un promedio — mismo criterio que ya usa la rama 2.
    --
    -- SOLO PARA QUIEN COBRA POR HORAS. Quien tiene sueldo fijo ya devenga todos
    -- los días de calendario por la rama 2; sumarlo acá lo contaría dos veces.
    select p.id as persona_id, gs::date as fecha,
           tt.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from ausencias au
    join tipos_ausencia ta on ta.codigo = au.tipo and ta.paga
    -- ⇩ CAMBIO 0160 ⇩
    join personas p on p.id = au.persona_id and not p.sueldo_fijo
                   and fn_devenga_beneficios(p.tipo_vinculo)
    cross join lateral generate_series(
      greatest(au.fecha_inicio, p.fecha_ingreso)::timestamp,
      least(au.fecha_fin, v_as_of)::timestamp,
      interval '1 day') gs
    join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = p.id
        and gs::date >= a.vigente_desde
        and (a.vigente_hasta is null or gs::date <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where au.anulada_at is null
      -- Si ese día SÍ marcó, la rama 1 ya lo contó. Puede pasar: media jornada
      -- trabajada y media de permiso, o una ausencia registrada tarde sobre un
      -- día que ya tenía marcas.
      and not exists (
        select 1 from jornadas j
        where j.persona_id = p.id and j.fecha = gs::date
          and j.horas_trabajadas is not null and j.horas_trabajadas > 0
      )

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
    -- ⇩ CAMBIO 0160 ⇩ También el sueldo fijo: un socio con sueldo fijo que no
    -- está en planilla tampoco devenga CTS, gratificación ni vacaciones.
    where p.sueldo_fijo and fn_devenga_beneficios(p.tipo_vinculo)
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
        -- ⇩ CAMBIO 0134 ⇩ La bonificacion extraordinaria sale del MISMO numero
        -- que la gratificacion y se apaga con la misma bandera: si la ventana ya
        -- se desembolso, la bonificacion se fue con ella.
        'be_s1', case when pag.g1 then 0 else round(v_f_grati * coalesce(g1.pago,0) * v_f_be, 2) end,
        'be_s2', case when pag.g2 then 0 else round(v_f_grati * coalesce(g2.pago,0) * v_f_be, 2) end,
        'be_total', round(
            ((case when pag.g1 then 0 else v_f_grati * coalesce(g1.pago,0) end)
           + (case when pag.g2 then 0 else v_f_grati * coalesce(g2.pago,0) end)) * v_f_be, 2),
        'tasa_be', v_f_be,
        -- ⇩ CAMBIO 0158 ⇩ Lo que FALTA, no un sí/no. Ver la cabecera.
        'cts_may', round(v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0)
                         - greatest(case when pag.cm then v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may), 2),
        'cts_may_pagada', (greatest(case when pag.cm then v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may) > 0),
        'cts_may_monto_pagado', nullif(round(greatest(case when pag.cm then v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may), 2), 0),
        'cts_nov', round(v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0)
                         - greatest(case when pag.cn then v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov), 2),
        'cts_nov_pagada', (greatest(case when pag.cn then v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov) > 0),
        'cts_nov_monto_pagado', nullif(round(greatest(case when pag.cn then v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov), 2), 0),
        'cts_total', round(
            (case when pag.cm then 0 else v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) end)
          + (case when pag.cn then 0 else v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) end), 2),
        -- para que la pantalla pueda mostrar qué multiplicador se usó
        'sexto_cts', v_sexto_cts,
        'vac', round(v_f_vac * coalesce(vv.pago,0), 2),
        'vac_dias', round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1),
        'proximo_aniversario', va.aniv_next,
        'gran_total', round(
            (case when pag.g1 then 0 else v_f_grati * coalesce(g1.pago,0) * (1 + v_f_be) end)   -- CAMBIO 0134
          + (case when pag.g2 then 0 else v_f_grati * coalesce(g2.pago,0) * (1 + v_f_be) end)   -- CAMBIO 0134
          + (v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0)
             - greatest(case when pag.cm then v_f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end, lib.cts_may))
          + (v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0)
             - greatest(case when pag.cn then v_f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end, lib.cts_nov))
          + v_f_vac * coalesce(vv.pago,0), 2)
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    -- ⇩ CAMBIO 0158 ⇩ Lo que dice el LIBRO de desembolsos.
    -- La 0123 pregunta si hubo movimiento de planilla; eso solo ve lo que pasó
    -- POR la planilla. La CTS de mayo 2026 salió por PLAME —al banco, a la
    -- cuenta CTS de cada persona— y de eso la planilla no sabe nada.
    cross join lateral (
      select
        coalesce(sum(d.monto) filter (where d.ventana = 'cts_may' and d.anio = v_y), 0) as cts_may,
        coalesce(sum(d.monto) filter (where d.ventana = 'cts_nov' and d.anio = v_y), 0) as cts_nov
      from desembolsos_beneficios d
      where d.persona_id = p.id
    ) lib
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



$function$;

insert into migraciones_aplicadas (numero, nombre)
values (160, 'quien_no_devenga_no_provisiona')
on conflict (numero) do nothing;

-- ── Los dos vínculos, por la puerta que corresponde ─────────────────────────
-- `fn_set_tipo_vinculo` exige sesión de admin para saber quién hace el cambio y
-- poder auditarlo. El SQL Editor no la trae, así que se le presta una.
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and auth_user_id is not null limit 1), true) as _sesion_prestada;

do $vinc$
declare
  r record;
begin
  for r in
    select p.id, p.apellidos || ', ' || p.nombres as quien, p.tipo_vinculo
    from personas p
    where (p.nombres ilike '%catherine%' or p.nombres ilike '%carlos%')
      and p.estado = 'activo'
  loop
    if r.tipo_vinculo = 'rxh' then
      raise notice '· % ya estaba como rxh. No se toca.', r.quien;
    else
      perform fn_set_tipo_vinculo(r.id, 'rxh');
      raise notice '· % pasó de % a rxh.', r.quien, r.tipo_vinculo;
    end if;
  end loop;
end
$vinc$;

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
select 'La función ya respeta el tipo de vínculo' as comprobacion,
       case when (select prosrc from pg_proc where proname='fn_provisiones' limit 1)
                 ilike '%CAMBIO 0160%'
            then 'OK' else 'REVISAR' end as resultado
union all
select 'Quedó anotada como aplicada',
       case when exists (select 1 from migraciones_aplicadas where numero = 160)
            then 'OK' else 'REVISAR' end
union all
select 'Catherine y Carlos figuran como rxh',
       case when (select count(*) from personas
                   where (nombres ilike '%catherine%' or nombres ilike '%carlos%')
                     and estado = 'activo' and tipo_vinculo <> 'rxh') = 0
            then 'OK' else 'REVISAR — mira el detalle de abajo' end;

commit;

-- ############################################################################
-- Después del commit: cómo quedaron. Si algo fallara al leer, ya no puede
-- deshacer el cambio.
-- ############################################################################
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol='admin' and auth_user_id is not null limit 1), true) as _sesion_prestada;

select prov.fila ->> 'nombre'                                      as persona,
       p.tipo_vinculo                                              as vinculo,
       to_char((prov.fila -> 'gran_total')::numeric, 'FM999999.00') as provision_ahora
from personas p
join lateral (
  select e as fila from jsonb_array_elements(fn_provisiones(current_date) -> 'personas') e
  where (e ->> 'persona_id')::uuid = p.id limit 1
) prov on true
where p.estado = 'activo' and p.tipo_vinculo <> 'planilla'
order by 1;
