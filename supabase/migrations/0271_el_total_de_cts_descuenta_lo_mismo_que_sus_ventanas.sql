-- ============================================================================
-- 0271 — El total de CTS descuenta lo mismo que sus ventanas
-- ============================================================================
--
-- QUÉ PROMETE
--   Que `cts_total`, en la pantalla Provisiones, reste el mismo depósito
--   directo (PLAME, fuera de planilla) que ya restan sus propias celdas
--   `cts_may` y `cts_nov`. Hoy no lo hace, y el "Gran total" de la pantalla
--   —que se arma sumando `grati_total + cts_total + vac`— hereda el error.
--
-- QUÉ ASUME
--   md5 de partida, pedido al SQL Editor de PRODUCCIÓN el 2026-08-19:
--     fn_provisiones   9b6be5fae9b82d5d1da3d7b8d1f82252   (20786 caracteres)
--
--   ⚠️ ESE md5 NO ES EL QUE DEBERÍA SER, y esta migración existe sabiéndolo.
--   Es, byte por byte, el cuerpo que escribe la **0158**. El repositorio dice
--   que la versión vigente es la 0196, y `migraciones_aplicadas` en producción
--   dice que la 0160 (05/08) y la 0196 (08/08) SÍ se aplicaron. Las dos cosas
--   no pueden ser ciertas: algo devolvió `fn_provisiones` a la 0158 después.
--   Ver la sección «EL DESVÍO» más abajo — no es una nota al margen, cambia lo
--   que esta migración tiene que hacer.
--
--   Cómo se midió, para que se pueda repetir: se aplicó en el Postgres local,
--   dentro de BEGIN…ROLLBACK, el cuerpo de CADA versión histórica de
--   `fn_provisiones` (0091, 0112, 0113, 0122, 0123, 0134, 0135, 0158, 0160,
--   0196) y se comparó su md5 contra el de producción. La 0158 coincide exacta;
--   ninguna otra se acerca. No se dedujo: se midió.
--
-- ── EL DEFECTO, ENCONTRADO A PARTIR DE UN CASO REAL ─────────────────────────
--
-- Una fila real de Provisiones mostraba, para una persona de AQP: CTS de mayo
-- "pagado 15/05" con S/94.17 ya depositado, CTS de noviembre en S/195.26, y
-- CTS total en negrita en S/436.20 — una cifra que no es la suma de lo que se
-- ve arriba (94.17 + 195.26 = 289.43), porque `cts_may` deja de mostrar un
-- número en cuanto está "pagada" y esconde el saldo real.
--
-- Reproducido en el Postgres local, dentro de BEGIN…ROLLBACK, con una persona
-- sintética y un desembolso directo de S/50 contra una CTS de mayo devengada
-- de S/375.03: `cts_may` bajó correctamente a S/325.03 (375.03 − 50), pero
-- `cts_total` dio S/598.84 — exactamente los S/50 de más, porque su fórmula
-- nunca resta `lib.cts_may`/`lib.cts_nov` (el libro de `desembolsos_beneficios`
-- que creó la 0155 y que 0158 empezó a leer).
--
-- La causa: la 0158 («Las provisiones descuentan lo depositado») corrigió
-- `cts_may` y `cts_nov` para restar ese libro, y dejó un `gran_total` correcto
-- que sí lo resta (líneas 760-767 de la 0196) — pero `cts_total` se quedó con
-- la fórmula anterior a la 0158, palabra por palabra. Nadie lo notó porque
-- `cts_total` y `gran_total` son dos campos distintos del mismo jsonb, y la
-- pantalla nunca lee `gran_total`: arma su propio "Gran total" sumando
-- `grati_total + cts_total + vac` en el cliente
-- (`apps/web/app/(admin)/admin/provisiones/page.tsx:439` y `:479`), así que el
-- error de `cts_total` se propaga ahí sin que la aritmética visible en pantalla
-- deje de "cuadrar" — cuadra con un número que ya está mal.
--
-- ── EL ARREGLO ───────────────────────────────────────────────────────────────
--
-- `cts_total` pasa a ser, literalmente, `cts_may + cts_nov` con la misma resta
-- que ya usan esas dos celdas (y que ya usa `gran_total`). No se toca ninguna
-- otra ventana, ni gratificación ni vacaciones: esas ya eran consistentes
-- entre su celda y su total.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE, Y ES DELIBERADO ──────────────────────────
--
-- No cambia la pantalla para que "Gran total" lea `gran_total` del backend en
-- vez de recalcularlo. `gran_total` incluye la bonificación extraordinaria
-- (Ley 30334, `be_total`) que la pantalla de Provisiones nunca muestra en
-- ninguna columna hoy; adoptarlo ahí sumaría un concepto nuevo sin explicarlo,
-- que es un cambio de alcance distinto y no lo que se pidió corregir acá. Con
-- este arreglo, el recálculo del cliente (`grati_total + cts_total + vac`)
-- vuelve a coincidir con la porción de gratificación + CTS + vacaciones de
-- `gran_total` — la brecha que queda es solo la bonificación extraordinaria, y
-- ya existía antes de este bug, sin empeorar.
--
-- No toca `desembolsos_beneficios` ni ningún dato histórico: el cambio es solo
-- de fórmula, no de datos, y no mueve un céntimo de lo que ya se pagó.
--
-- ── EL DESVÍO · POR QUÉ ESTA MIGRACIÓN LLEVA PRERREQUISITOS DENTRO ──────────
--
-- El cuerpo que sigue es el de la 0196 (más el arreglo de `cts_total`), y ese
-- cuerpo LLAMA a `fn_devenga()` y `fn_devenga_algo()`, que nacen en la 0196.
-- Si en producción esas funciones no existen —porque lo que allí corre es la
-- 0158—, pegar solo `fn_provisiones` la crearía sin una queja y la pantalla
-- Provisiones reventaría al ABRIRLA, no al pegarla. Un error que no aparece
-- cuando lo causas es el peor de repartir.
--
-- Por eso esta migración se asegura primero de sus propios cimientos: las tres
-- columnas y las dos funciones que necesita, copiadas de la 0196 sin cambiarles
-- una coma. Las tres formas son idempotentes a propósito (`add column if not
-- exists`, `create or replace`), así que en la base que YA las tiene no cambia
-- nada y en la que no, quedan puestas. Se pega igual en los dos mundos, y ese
-- es exactamente el punto: no hizo falta averiguar en cuál estamos.
--
-- LO QUE ESTO IMPLICA, DICHO SIN ADORNO. Al pegarla, producción recibe también
-- lo que la 0160 y la 0196 le hacían a `fn_provisiones` y que hoy no tiene:
--
--   · 0160 — quien no devenga deja de provisionar. Medido el 2026-08-05:
--     Catherine Pereyra, que trabaja por recibos por honorarios, figuraba con
--     S/2.841,70 acumulados, el monto más alto de la empresa, sin devengar
--     ninguno. Ese número desaparece, y es una corrección, no una pérdida: la
--     liquidación nunca se los habría pagado.
--   · 0196 — la excepción por persona y beneficio. No mueve un céntimo por sí
--     sola: las tres banderas nacen en blanco y en blanco significa «decide el
--     tipo de vínculo», que es lo de hoy.
--
-- Las dos son correcciones ya decididas, escritas y probadas; producción
-- debería tenerlas desde el 5 y el 8 de agosto. Esto no las inventa: las pone
-- donde el registro ya dice que están.
--
-- LO QUE ESTA MIGRACIÓN NO ARREGLA, Y HAY QUE MIRAR APARTE. La 0196 también
-- reescribe `fn_grati_trunca_bruta`, `fn_cts_trunca` y `fn_vacaciones_truncas`
-- —las tres del cálculo por cese—. Si lo que pisó `fn_provisiones` pisó también
-- alguna de esas, esta migración NO lo ve ni lo corrige: solo toca la suya. Sus
-- md5 esperados son 78cb6ac1…, 84e62261… y 0d411bdb…; conviene compararlos
-- contra producción antes de la próxima liquidación por cese. Queda dicho aquí
-- para que se lea como pendiente y no como descuido.
--
-- CÓMO SE REVIERTE
--   Restaurar `fn_provisiones` desde la 0196, tal cual. Las columnas y las dos
--   funciones auxiliares se pueden dejar: son las de la 0196 y no estorban a
--   nadie. No toca datos ni permisos.
-- ============================================================================

-- ── CIMIENTOS · lo que el cuerpo de abajo necesita para no reventar ─────────
-- Copiado de la 0196 sin cambios. Idempotente: si ya están, esto no hace nada.

alter table personas add column if not exists devenga_grati      boolean;
alter table personas add column if not exists devenga_cts        boolean;
alter table personas add column if not exists devenga_vacaciones boolean;

create or replace function public.fn_devenga(p_persona_id uuid, p_beneficio text)
returns boolean
language plpgsql stable security definer
set search_path to 'public'
as $function$
declare v_p personas%rowtype; v_flag boolean;
begin
  -- Se rechaza un beneficio desconocido en vez de devolver el defecto. Si
  -- alguien escribe 'vacacion' en singular, tiene que enterarse en el momento y
  -- no descubrir dentro de un año que esa llamada nunca filtró nada.
  if p_beneficio not in ('grati', 'cts', 'vacaciones') then
    raise exception 'Beneficio desconocido: %. Son grati, cts o vacaciones.', p_beneficio;
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then return false; end if;

  v_flag := case p_beneficio
              when 'grati'      then v_p.devenga_grati
              when 'cts'        then v_p.devenga_cts
              when 'vacaciones' then v_p.devenga_vacaciones
            end;

  return coalesce(v_flag, fn_devenga_beneficios(v_p.tipo_vinculo));
end;
$function$;

create or replace function public.fn_devenga_algo(p_persona_id uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $function$
  select fn_devenga(p_persona_id, 'grati')
      or fn_devenga(p_persona_id, 'cts')
      or fn_devenga(p_persona_id, 'vacaciones');
$function$;

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
        -- ⇩ CAMBIO 0123 ⇩ Una ventana ya desembolsada vale 0: seguir sumándola
        -- contaba dos veces la misma plata. El monto original viaja aparte para
        -- que la pantalla pueda escribir «pagado el 15/07» en vez de un cero mudo.
        'grati_s1', case when pag.g1 then 0 else round(dev.f_grati * coalesce(g1.pago,0), 2) end,
        'grati_s1_pagada', pag.g1,
        'grati_s1_monto_pagado', case when pag.g1 then round(dev.f_grati * coalesce(g1.pago,0), 2) end,
        'grati_s2', case when pag.g2 then 0 else round(dev.f_grati * coalesce(g2.pago,0), 2) end,
        'grati_s2_pagada', pag.g2,
        'grati_s2_monto_pagado', case when pag.g2 then round(dev.f_grati * coalesce(g2.pago,0), 2) end,
        'grati_total', round(
            (case when pag.g1 then 0 else dev.f_grati * coalesce(g1.pago,0) end)
          + (case when pag.g2 then 0 else dev.f_grati * coalesce(g2.pago,0) end), 2),
        -- ⇩ CAMBIO 0134 ⇩ La bonificacion extraordinaria sale del MISMO numero
        -- que la gratificacion y se apaga con la misma bandera: si la ventana ya
        -- se desembolso, la bonificacion se fue con ella.
        'be_s1', case when pag.g1 then 0 else round(dev.f_grati * coalesce(g1.pago,0) * v_f_be, 2) end,
        'be_s2', case when pag.g2 then 0 else round(dev.f_grati * coalesce(g2.pago,0) * v_f_be, 2) end,
        'be_total', round(
            ((case when pag.g1 then 0 else dev.f_grati * coalesce(g1.pago,0) end)
           + (case when pag.g2 then 0 else dev.f_grati * coalesce(g2.pago,0) end)) * v_f_be, 2),
        'tasa_be', v_f_be,
        -- ⇩ CAMBIO 0158 ⇩ Lo que FALTA, no un sí/no. Ver la cabecera.
        'cts_may', round(dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0)
                         - greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may), 2),
        'cts_may_pagada', (greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may) > 0),
        'cts_may_monto_pagado', nullif(round(greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end,
                                    lib.cts_may), 2), 0),
        'cts_nov', round(dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0)
                         - greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov), 2),
        'cts_nov_pagada', (greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov) > 0),
        'cts_nov_monto_pagado', nullif(round(greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end,
                                    lib.cts_nov), 2), 0),
        -- ⇩ CAMBIO 0271 ⇩ El total ahora resta EXACTAMENTE lo mismo que sus dos
        -- ventanas: es `cts_may + cts_nov`, ni un carácter distinto. Antes no
        -- restaba `lib.cts_may`/`lib.cts_nov` (el libro de depósitos directos),
        -- así que seguía contando CTS ya pagada por fuera de planilla.
        'cts_total', round(
            (dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0)
             - greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end, lib.cts_may))
          + (dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0)
             - greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end, lib.cts_nov)), 2),
        -- para que la pantalla pueda mostrar qué multiplicador se usó
        'sexto_cts', v_sexto_cts,
        'vac', round(dev.f_vac * coalesce(vv.pago,0), 2),
        -- Los días también, no solo el monto: mostrarle «12.4 días acumulados» a
        -- quien no devenga vacaciones es prometer por escrito algo que no
        -- existe, y esa pantalla la lee una persona.
        'vac_dias', case when dev.hay_vac
                         then round(15.0 * (v_as_of - va.aniv_ini)::numeric / 365.0, 1)
                         else 0 end,
        'proximo_aniversario', va.aniv_next,
        'gran_total', round(
            (case when pag.g1 then 0 else dev.f_grati * coalesce(g1.pago,0) * (1 + v_f_be) end)   -- CAMBIO 0134
          + (case when pag.g2 then 0 else dev.f_grati * coalesce(g2.pago,0) * (1 + v_f_be) end)   -- CAMBIO 0134
          + (dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0)
             - greatest(case when pag.cm then dev.f_cts * (1 + v_sexto_cts) * coalesce(cm.pago,0) else 0 end, lib.cts_may))
          + (dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0)
             - greatest(case when pag.cn then dev.f_cts * (1 + v_sexto_cts) * coalesce(cn.pago,0) else 0 end, lib.cts_nov))
          + dev.f_vac * coalesce(vv.pago,0), 2)
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
values (271, 'el_total_de_cts_descuenta_lo_mismo_que_sus_ventanas')
on conflict (numero) do nothing;
