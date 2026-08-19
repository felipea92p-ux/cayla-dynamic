-- ============================================================================
-- 0273 — El libro de desembolsos vale para los cinco beneficios
-- ============================================================================
--
-- QUÉ PROMETE
--   Que una gratificación o unas vacaciones pagadas POR FUERA de la planilla
--   —anotadas en `desembolsos_beneficios`— dejen de mostrarse como pendientes.
--   Hasta hoy solo se descontaban las dos ventanas de CTS.
--
-- QUÉ ASUME
--   md5 de partida, pedido al SQL Editor de PRODUCCIÓN el 2026-08-19 y
--   confirmado por Felipe tras pegar la 0271:
--     fn_provisiones   86d01fa3ab543865f7245912377d92d9
--   El cuerpo se copió de la 0271 y se cambió solo lo que dice esta cabecera.
--   Asume además que `fn_beneficio_ya_depositado` existe: la crea la 0163, que
--   figura aplicada en producción el 06/08/2026.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- El libro admite CINCO ventanas —su `check` lista grati_s1, grati_s2,
-- cts_may, cts_nov y vacaciones— y `fn_provisiones` solo leía las dos de CTS.
-- Las otras tres se podían anotar y no las restaba nadie.
--
-- Medido el 2026-08-19 contra el Postgres local, con una persona de S/1.500 y
-- un depósito de S/700 registrado en `grati_s1`:
--
--     grati_s1        749.97  →  749.97   (no se movió)
--     grati_s1_pagada false   →  false    (siguió diciendo que no se pagó)
--
-- Y NO SE QUEDA EN LA RESERVA, que es lo que lo separa del defecto de la 0271.
-- `fn_grati_cts_periodo` lee `grati_s1`/`grati_s2` para proponer el bono al
-- cerrar el mes: con una grati ya pagada por transferencia, proponía pagarla
-- otra vez. La 0271 tocaba solo un número de pantalla; esta toca una propuesta
-- de pago.
--
-- La 0158 dejó dicho en su propia cabecera que gratificación y vacaciones
-- «siguen con la regla vieja de todo-o-nada». Era deuda conocida y anotada.
-- Esta migración la paga.
--
-- ── CÓMO, Y POR QUÉ ASÍ ─────────────────────────────────────────────────────
--
-- SE PREGUNTA CON `fn_beneficio_ya_depositado`, la función de la 0163, en vez
-- del `sum` propio que la 0158 escribió aquí dentro. Ya era la respuesta a esta
-- misma pregunta para `fn_cts_trunca` y `fn_grati_trunca`; tener una segunda
-- copia equivalente es exactamente el mecanismo que produjo el defecto de la
-- 0271 —dos escrituras de una regla, una se corrige y la otra se queda vieja—.
--
-- Y CADA REGLA SE DICE UNA SOLA VEZ. Dos laterales nuevos, `devengado` y
-- `cobrado`, calculan las dos mitades por ventana; las veintitantas líneas de
-- arriba pasan a ser una resta. Antes la misma expresión aparecía hasta cinco
-- veces por ventana (celda, bandera, monto pagado, total, gran total), que es
-- lo que hizo invisible durante meses que `cts_total` se había quedado atrás.
--
-- LA BONIFICACIÓN AHORA ES PROPORCIONAL. Era todo-o-nada: «si la ventana se
-- pagó, la bonificación se fue con ella». Con un depósito PARCIAL eso deja de
-- ser cierto — sobre media gratificación pendiente queda media bonificación
-- pendiente. Sigue saliendo del mismo número que la gratificación, que es lo
-- que la 0134 decidió.
--
-- SE TOMA LA MAYOR DE LAS DOS FUENTES, NUNCA LA SUMA. Es la decisión de la
-- 0158 y la prueba 124 la defiende: un pago anotado en la planilla Y en el
-- libro se descontaría dos veces. Se conserva intacta.
--
-- ── LO QUE NO CAMBIA ────────────────────────────────────────────────────────
--
-- Sin ningún desembolso anotado, esta migración no mueve un céntimo: las cinco
-- restas valen cero y todo da lo mismo que antes. Solo cambia el resultado de
-- quien tenga algo escrito en el libro, y en ese caso el número viejo era el
-- equivocado.
--
-- CÓMO SE REVIERTE
--   Restaurar `fn_provisiones` desde la 0271, tal cual. No toca tablas, ni
--   datos, ni permisos.
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
                    and fn_devenga_algo(pp.id)   -- CAMBIO 0196
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
                   and fn_devenga_algo(p.id)   -- CAMBIO 0196
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
    where p.sueldo_fijo and fn_devenga_algo(p.id)   -- CAMBIO 0196
  )
  select coalesce(jsonb_agg(sub.fila order by sub.nombre), '[]'::jsonb) into v_out
  from (
    select (p.nombres || ' ' || p.apellidos) as nombre,
      jsonb_build_object(
        'persona_id', p.id,
        'nombre', p.nombres || ' ' || p.apellidos,
        'sede', s.codigo,
        'fecha_ingreso', p.fecha_ingreso,
        -- ⇩ CAMBIO 0123 · REESCRITO POR LA 0273 ⇩ Lo que FALTA, no un sí/no.
        --
        -- Cada celda es la misma resta: lo devengado menos lo ya cobrado. Las
        -- dos mitades se calculan una sola vez, abajo, en `devengado` y
        -- `cobrado`. Antes cada una de estas líneas repetía la fórmula entera y
        -- la gratificación se quedó sin la resta del libro durante meses.
        --
        -- El negativo SE MUESTRA. Si se depositó de más, aparece en negativo en
        -- vez de esconderse en un cero: decisión de la 0158, defendida por la
        -- prueba 124.
        'grati_s1', round(devengado.g1 - cobrado.g1, 2),
        'grati_s1_pagada', (cobrado.g1 > 0),
        'grati_s1_monto_pagado', nullif(round(cobrado.g1, 2), 0),
        'grati_s2', round(devengado.g2 - cobrado.g2, 2),
        'grati_s2_pagada', (cobrado.g2 > 0),
        'grati_s2_monto_pagado', nullif(round(cobrado.g2, 2), 0),
        'grati_total', col.grati_total,
        -- ⇩ CAMBIO 0134 · AJUSTADO POR LA 0273 ⇩ La bonificación extraordinaria
        -- sale del MISMO número que la gratificación, así que sigue lo que
        -- quede de ella. Antes era todo-o-nada («si la ventana se pagó, la
        -- bonificación se fue con ella»), y con un depósito PARCIAL eso dejaba
        -- de ser cierto: sobre media gratificación pendiente queda media
        -- bonificación pendiente, no la entera ni cero.
        'be_s1', round((devengado.g1 - cobrado.g1) * v_f_be, 2),
        'be_s2', round((devengado.g2 - cobrado.g2) * v_f_be, 2),
        'be_total', col.be_total,
        'tasa_be', v_f_be,
        -- ⇩ CAMBIO 0158 ⇩ Lo que FALTA, no un sí/no. Ver la cabecera.
        'cts_may', round(devengado.cm - cobrado.cm, 2),
        'cts_may_pagada', (cobrado.cm > 0),
        'cts_may_monto_pagado', nullif(round(cobrado.cm, 2), 0),
        'cts_nov', round(devengado.cn - cobrado.cn, 2),
        'cts_nov_pagada', (cobrado.cn > 0),
        'cts_nov_monto_pagado', nullif(round(cobrado.cn, 2), 0),
        -- ⇩ CAMBIO 0271 ⇩ El total resta EXACTAMENTE lo mismo que sus dos
        -- ventanas. Ahora eso ya no hay que cuidarlo a mano: las tres líneas
        -- leen las mismas dos columnas.
        'cts_total', col.cts_total,
        -- para que la pantalla pueda mostrar qué multiplicador se usó
        'sexto_cts', v_sexto_cts,
        -- ⇩ CAMBIO 0273 ⇩ Las vacaciones también descuentan lo depositado. Es la
        -- quinta ventana del libro y era la única que nunca se restaba.
        'vac', col.vac,
        'vac_pagada', (cobrado.vac > 0),
        'vac_monto_pagado', nullif(round(cobrado.vac, 2), 0),
        -- Los días también, no solo el monto: mostrarle «12.4 días acumulados» a
        -- quien no devenga vacaciones es prometer por escrito algo que no
        -- existe, y esa pantalla la lee una persona.
        'vac_dias', case when dev.hay_vac
                         then round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1)
                         else 0 end,
        'proximo_aniversario', va.aniv_next,
        -- El gran total es la suma de las cuatro columnas que la pantalla
        -- muestra —grati + bonificación + CTS + vacaciones— y nada más. Desde
        -- el 2026-08-19 la pantalla lo LEE de aquí en vez de rehacerlo, así que
        -- esta línea es la única definición que existe del número.
        --
        -- Suma las columnas YA REDONDEADAS, a propósito: así el total cuadra
        -- con lo que se ve, hasta el céntimo. Ver el comentario del lateral
        -- `col` para por qué eso importa más de lo que parece.
        'gran_total', col.grati_total + col.be_total + col.cts_total + col.vac
      ) as fila
    from personas p
    join sedes s on s.id = p.sede_base_id
    -- ⇩⇩⇩ CAMBIO 0196 ⇩⇩⇩ EL FACTOR SE APAGA EN ORIGEN.
    --
    -- Los tres factores se leen una vez arriba y se usan QUINCE veces en el
    -- bloque de la fila: en cada ventana, en cada total y en el gran total.
    -- Poner un `case when devenga…` en cada una de las quince es pedir un
    -- olvido — y el olvido no daría error: daría un número.
    --
    -- Acá el factor de quien no devenga ese beneficio vale CERO, y las quince
    -- expresiones dan cero solas. Una regla, un sitio, nada que sincronizar.
    cross join lateral (
      select case when fn_devenga(p.id, 'grati')      then v_f_grati else 0 end as f_grati,
             case when fn_devenga(p.id, 'cts')        then v_f_cts   else 0 end as f_cts,
             case when fn_devenga(p.id, 'vacaciones') then v_f_vac   else 0 end as f_vac,
             fn_devenga(p.id, 'vacaciones')                                     as hay_vac
    ) dev
    cross join lateral (
      select (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int))::date as aniv_ini,
             (p.fecha_ingreso + make_interval(years => extract(year from age(v_as_of, p.fecha_ingreso))::int + 1))::date as aniv_next
    ) va
    -- ⇩ CAMBIO 0158 · AMPLIADO POR LA 0273 ⇩ Lo que dice el LIBRO de desembolsos.
    -- La 0123 pregunta si hubo movimiento de planilla; eso solo ve lo que pasó
    -- POR la planilla. La CTS de mayo 2026 salió por PLAME —al banco, a la
    -- cuenta CTS de cada persona— y de eso la planilla no sabe nada.
    --
    -- ⇩⇩⇩ CAMBIO 0273 ⇩⇩⇩ LAS CINCO VENTANAS, Y POR LA PUERTA DE LA 0163.
    --
    -- La 0158 solo leyó las dos de CTS. El libro admite cinco —su `check` lista
    -- grati_s1, grati_s2, cts_may, cts_nov y vacaciones— así que una grati
    -- pagada por transferencia se anotaba y NADIE la restaba: la pantalla la
    -- seguía mostrando pendiente. Medido el 2026-08-19 con un depósito de S/700
    -- de grati_s1: `grati_s1` no se movió de S/749.97 y `pagada` siguió en
    -- false.
    --
    -- Y eso no se quedaba en la reserva: `fn_grati_cts_periodo` lee estos
    -- mismos campos para proponer el bono al cerrar el mes, así que proponía
    -- pagar otra vez lo ya pagado. La CTS no tenía el problema desde la 0158;
    -- la gratificación y las vacaciones sí.
    --
    -- SE PREGUNTA CON `fn_beneficio_ya_depositado`, no con un `sum` propio.
    -- Esa función es de la 0163 y ya era la respuesta a esta misma pregunta
    -- para `fn_cts_trunca` y `fn_grati_trunca`. Tener aquí un segundo `sum`
    -- equivalente es exactamente la forma en que nació el defecto que arregló
    -- la 0271: dos copias de una regla, una se corrige y la otra no.
    --
    -- EL AÑO ES EL DEL DEPÓSITO, no el del devengo. Lo dice el comentario de la
    -- 0163 y vale para las cuatro ventanas fijas: grati_s1 se paga el 15/07 de
    -- v_y, grati_s2 el 15/12 de v_y, cts_may el 15/05 de v_y (cubriendo desde
    -- noviembre anterior) y cts_nov el 15/11 de v_y.
    cross join lateral (
      select
        fn_beneficio_ya_depositado(p.id, 'grati_s1',   v_y) as grati_s1,
        fn_beneficio_ya_depositado(p.id, 'grati_s2',   v_y) as grati_s2,
        fn_beneficio_ya_depositado(p.id, 'cts_may',    v_y) as cts_may,
        fn_beneficio_ya_depositado(p.id, 'cts_nov',    v_y) as cts_nov,
        fn_beneficio_ya_depositado(p.id, 'vacaciones', v_y) as vacaciones
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
    -- ⇩⇩⇩ CAMBIO 0273 ⇩⇩⇩ CADA REGLA, UNA SOLA VEZ.
    --
    -- El bloque de arriba usaba la misma expresión hasta CINCO veces por
    -- ventana: en la celda, en la bandera `pagada`, en el monto pagado, en el
    -- total y en el gran total. Así nació el defecto de la 0271 — `cts_total`
    -- se quedó con la fórmula anterior a la 0158 mientras sus celdas ya
    -- restaban, y durante meses nadie pudo verlo porque había que comparar dos
    -- expresiones largas escritas en sitios distintos.
    --
    -- Acá se calcula UNA vez lo devengado y UNA vez lo ya cobrado, y todo lo de
    -- arriba es una resta. Si mañana cambia la regla, cambia en un solo sitio y
    -- no hay una segunda copia que se pueda quedar vieja.
    cross join lateral (
      select dev.f_grati * coalesce(g1.pago, 0)                     as g1,
             dev.f_grati * coalesce(g2.pago, 0)                     as g2,
             dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago, 0)   as cm,
             dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago, 0)   as cn,
             dev.f_vac * coalesce(vv.pago, 0)                       as vac
    ) devengado
    -- Lo YA COBRADO por cada ventana, por cualquiera de las dos vías.
    --
    -- SE TOMA LA MAYOR, NUNCA LA SUMA. Es la decisión de la 0158 y su prueba
    -- 124 la defiende: si un pago quedó anotado en los dos sitios —la planilla
    -- y el libro— sumarlos descontaría el doble y dejaría la provisión corta.
    -- La planilla, cuando detecta el pago, asume la ventana COMPLETA; el libro
    -- sabe el monto exacto. La mayor de las dos es la respuesta prudente.
    --
    -- Las vacaciones no tienen vía de planilla que mirar (`pag` no las trae),
    -- así que su única fuente es el libro.
    cross join lateral (
      select greatest(case when pag.g1 then devengado.g1 else 0 end, lib.grati_s1) as g1,
             greatest(case when pag.g2 then devengado.g2 else 0 end, lib.grati_s2) as g2,
             greatest(case when pag.cm then devengado.cm else 0 end, lib.cts_may)  as cm,
             greatest(case when pag.cn then devengado.cn else 0 end, lib.cts_nov)  as cn,
             lib.vacaciones                                                        as vac
    ) cobrado
    -- ⇩⇩⇩ CAMBIO 0273 ⇩⇩⇩ LAS CUATRO COLUMNAS QUE SE VEN, REDONDEADAS UNA VEZ.
    --
    -- El gran total se arma sumando ESTAS, no repitiendo el cálculo con más
    -- decimales. Parece un detalle y es la queja con la que empezó todo esto:
    -- redondear la suma da un resultado distinto de sumar los redondeos, y la
    -- diferencia —un céntimo— cae justo en la celda que la persona compara con
    -- las de al lado. Medido: columnas 1232.76 contra un total de 1232.77.
    --
    -- Un céntimo no es plata, pero un total que no cuadra con lo que se ve
    -- enseña a desconfiar de la pantalla entera. Y esta pantalla existe para
    -- que alguien pueda revisarla.
    cross join lateral (
      select round((devengado.g1 - cobrado.g1) + (devengado.g2 - cobrado.g2), 2)            as grati_total,
             round(((devengado.g1 - cobrado.g1) + (devengado.g2 - cobrado.g2)) * v_f_be, 2) as be_total,
             round((devengado.cm - cobrado.cm) + (devengado.cn - cobrado.cn), 2)            as cts_total,
             round(devengado.vac - cobrado.vac, 2)                                          as vac
    ) col
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
values (273, 'el_libro_de_desembolsos_vale_para_los_cinco_beneficios')
on conflict (numero) do nothing;
