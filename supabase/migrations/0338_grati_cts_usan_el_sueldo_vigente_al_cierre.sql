-- ============================================================================
-- 0338 — Gratificación y CTS usan el sueldo vigente al cierre, no el promedio
--         histórico del semestre
-- ============================================================================
--
-- QUÉ PROMETE
--   Que cuando alguien tuvo un AUMENTO de sueldo a mitad de un semestre de
--   gratificación o CTS, el depósito real (no solo la reserva contable) nunca
--   salga por debajo de lo que exige D.S. 001-97-TR art. 10/21 (CTS, régimen
--   general) y D.S. 013-2013-PRODUCE art. 50 (CTS y gratificación de pequeña
--   empresa, que remite al régimen común para la mecánica): tomar el sueldo
--   vigente EN LA FECHA DE CORTE del semestre —30 abr/31 oct para CTS,
--   30 jun/30 nov para gratificación— y aplicarlo a TODO el semestre.
--
-- EL DEFECTO, encontrado el 2026-08-31 investigando otra pregunta de Felipe
--   (ver docs/planilla-anexo-tecnico.md, sección «Pendientes conocidos»).
--   `fn_provisiones` calcula el sueldo día por día: cada día del semestre
--   aporta al tramo de `asignaciones_salario` vigente ESE día específico. Es
--   exactamente lo que un contador esperaría para una RESERVA suavizada mes a
--   mes — pero `fn_grati_cts_periodo` usa ese mismo número como el DEPÓSITO
--   REAL que autocompleta en Planilla. La norma no promedia: fija la
--   remuneración computable en un punto y la aplica entera hacia atrás.
--
--   Con un aumento a mitad de semestre, el día a día sale MENOR que lo que
--   exige la norma — nunca mayor. Con una bajada pasa al revés (el día a día
--   ya sale mayor que el mínimo legal), así que ahí no hay nada que corregir.
--
-- POR QUÉ TOCA CUATRO FUNCIONES Y NO SOLO LA QUE SE VE
--   El sueldo día por día no vive solo en la rama de horas trabajadas: la
--   misma mecánica se repite en las ausencias pagadas (descanso médico,
--   maternidad), en el sueldo fijo, en el multiplicador `base_provision` de
--   la 0111/0276, y en los feriados (`fn_feriado_devengado`, una función
--   aparte que la boleta también usa). Corregir solo una rama habría dejado
--   el resto del hueco sin cerrar y, peor, habría hecho que el "piso" no
--   sirviera de piso: en una primera versión que solo cubría horas y
--   ausencias, comparar contra el día a día CON feriados incluidos hacía que
--   el piso pareciera siempre menor —por faltarle una pieza entera, no
--   porque el mecanismo estuviera bien—. Medido en laboratorio antes de
--   escribir esto: con un sueldo constante (sin ningún aumento, para aislar
--   el efecto), el piso parcial daba S/641.63 contra S/686.07 del día a día
--   completo — una diferencia de S/44.44 que eran, exactamente, los
--   feriados que el piso parcial no contaba. Cubrir las cuatro ramas a la
--   vez es lo que hace que la comparación sea justa.
--
-- CÓMO SE ARREGLA: UN PARÁMETRO NUEVO, NO UNA FUNCIÓN GEMELA
--   La alternativa obvia —escribir una `fn_provisiones_piso` que reimplemente
--   las cuatro ramas con el sueldo fijo en vez de día por día— habría
--   duplicado ~300 líneas de lógica ya auditada por 20+ migraciones, con el
--   riesgo de que un arreglo futuro a `fn_provisiones` se olvide de tocar
--   también la gemela. En vez de eso, `fn_provisiones` y `fn_feriado_devengado`
--   ganan un parámetro opcional `p_salario_asof date default null`: cuando se
--   pasa, CONGELA la fecha de referencia del sueldo para todas las búsquedas
--   en `asignaciones_salario` (en vez de usar el día de cada jornada/ausencia/
--   feriado). Sin el parámetro —el caso de CUALQUIER llamador de hoy—, el
--   comportamiento es idéntico, carácter por carácter, al de antes. Es la
--   misma función, con un interruptor nuevo, no una copia.
--
--   `fn_grati_cts_periodo` la llama dos veces por ventana —una vez con su
--   comportamiento de siempre, otra con `p_salario_asof` igual a su propia
--   fecha de corte (que ES, matemáticamente, «el sueldo vigente al cierre
--   aplicado a todo el semestre»)— y se queda con el MAYOR de los dos.
--
-- POR QUÉ «EL MAYOR», NUNCA EL PROMEDIO NI LA SUMA
--   Si el sueldo bajó a mitad de semestre, el día a día YA da más que el
--   piso (que usaría el sueldo nuevo, más bajo, para los días de antes) — y
--   ese caso no debe bajarle nada a nadie. Solo cuando hubo un aumento el
--   piso es mayor, y ahí sí corrige hacia arriba. Es imposible que este
--   cambio le pague de menos a alguien respecto de lo que el sistema ya le
--   paga hoy: en el peor caso, no cambia nada.
--
-- QUÉ NO TOCA
--   La liquidación por cese (`fn_liquidacion` → `fn_remuneracion_computable`)
--   ya usa el sueldo vigente a una fecha de referencia, como manda la norma —
--   no tiene este defecto y esta migración no la toca.
--
--   La asignación familiar (rama 3 de `fn_provisiones`) también busca su
--   monto día por día, pero ese valor cambia por decreto de RMV, no por
--   negociación de sueldo — es una pregunta distinta, no se toca acá.
--
-- MEDIDO EN LABORATORIO (local, BEGIN … ROLLBACK, con las cuatro funciones
--   ya modificadas, un caso sintético: sueldo S/1.500 → S/1.800 el 1 de
--   febrero, a mitad del semestre de CTS nov-2025→abr-2026):
--
--                                            antes    →   ahora
--     fn_provisiones(fecha), 1 argumento    S/306.76  →   S/306.76  (sin cambio)
--     fn_provisiones(fecha, fecha), piso     — no existía —  S/333.99
--     fn_grati_cts_periodo → 'cts'           S/306.76  →   S/333.99
--
--   Y con una bajada de sueldo en el mismo esquema (S/1.800 → S/1.500):
--   día a día S/305.55 contra piso S/278.32 — el piso pierde, no cambia nada.
--
--   Confirmado también que la llamada de 1 argumento (la que usan hoy
--   Provisiones y Costos) sigue devolviendo exactamente lo mismo que antes.
--
-- ⚠️ POR QUÉ HAY UN DROP ANTES DE CADA CREATE
--   `fn_provisiones` y `fn_feriado_devengado` ganan un parámetro nuevo.
--   `create or replace function` en Postgres NO reemplaza en el sitio cuando
--   cambia la LISTA de parámetros — crea una segunda función superpuesta, y
--   cualquier llamada con el número de argumentos de antes se vuelve
--   ambigua («function fn_provisiones(date) is not unique») y truena en
--   caliente. Se cazó en el propio laboratorio de esta migración, antes de
--   escribirla: con solo `create or replace`, la llamada de 1 argumento que
--   usa Provisiones dejaba de funcionar. `fn_grati_cts_periodo` no cambia su
--   firma (sigue siendo un solo `uuid`), así que a ella no le hace falta el
--   `drop`.
--
-- CÓMO SE REVIERTE
--   Restaurar las tres funciones desde sus migraciones vigentes anteriores:
--   `fn_provisiones` desde la 0310, `fn_feriado_devengado` desde la 0306,
--   `fn_grati_cts_periodo` desde la 0088 — y hacer `drop function
--   fn_provisiones(date, date); drop function fn_feriado_devengado(uuid,
--   date, date, integer, date);` antes de recrearlas con su firma de un
--   parámetro menos.
--
-- MD5 DE PARTIDA (pedido a producción antes de escribir, no antes de entregar)
--   fn_grati_cts_periodo: tal_cual 0bc70f11dd23ede89441e11486d58d70 · 4026
--     caracteres — confirmado idéntico entre producción y esta Mac.
--   fn_provisiones y fn_feriado_devengado: pendiente de confirmar contra
--   producción antes de pegar esta migración (ver docs/estado.md).
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- fn_provisiones — gana p_salario_asof. Cuatro ramas tocadas: horas
-- trabajadas, ausencias pagadas, sueldo fijo, y el multiplicador
-- base_provision. La llamada a fn_feriado_devengado también lo propaga.
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS fn_provisiones(date);

-- ============================================================================
-- 0310 · EL FERIADO DENTRO DE UN DESCANSO MÉDICO NO LO CONTABA NADIE
-- ============================================================================
--
-- ⚠️ SE PEGA DESPUÉS DE LA 0308. Parte de su cuerpo, no del de la 0302.
--
-- QUÉ PROMETE
--   Que un feriado que cae dentro de un descanso médico se reserve, como ya se
--   paga en la boleta desde la 0293.
--
-- CÓMO APARECIÓ
--   No lo buscaba nadie. Salió al construir la prueba 244 —la matriz que
--   compara la boleta contra la reserva persona por persona— la primera vez que
--   se la corrió. Tres de sus doce escenarios divergían por S/5,24 y ninguno de
--   los tres estaba en la lista de divergencias esperadas.
--
-- EL DEFECTO
--   La 0276 puso en la rama de ausencias de `fn_provisiones`:
--
--       and not (au.tipo = 'descanso_medico'
--                and exists (select 1 from feriados f where f.fecha = gs::date))
--
--   con una razón escrita y correcta: «su lateral `dmd` EXCLUYE el feriado
--   desde la 0254, así que acá también hay que excluirlo». Lo era.
--
--   La **0293** quitó esa exclusión de `dmd` — «el feriado dentro de un
--   descanso médico se paga». La premisa de la línea de la 0276 quedó falsa y
--   nadie lo notó, porque **una línea con la premisa caducada no falla: solo
--   deja de tener razón.** Sigue corriendo, sigue sin dar error, y sigue
--   restando un día.
--
--   Así que el feriado dentro de un descanso médico **no lo contaba nadie**:
--   acá se excluía «porque ya lo cuenta el feriado», y `fn_feriado_devengado`
--   lo excluye por su cuenta. Es el mismo día sin dueño que la 0262 advirtió
--   que aparecería si se quitaba de los dos lados, y que la 0306 volvió a
--   advertir en su cabecera. Esta vez apareció por el camino contrario: no se
--   quitó de los dos lados a la vez, se quitó de uno y el otro se quedó viejo.
--
-- MEDIDO (local, BEGIN … ROLLBACK, marzo 2026, S/1.950, mes calendario como
-- periodo para no arrastrar la divergencia del divisor 29→28 de la 0276; dos
-- feriados, uno en miércoles y otro en domingo):
--
--                                                        antes → ahora
--     descanso médico 02–20 con feriado dentro           −5,24 →  0,00
--     descanso médico 09–13 justo sobre el feriado       −5,24 →  0,00
--     ídem en Trujillo, feriado en DOMINGO               −5,24 →  0,00
--
--   El signo importa: la reserva devengaba **menos** que la boleta. Va contra
--   la persona, que es el error que esta casa considera el más caro.
--
--   La fila de Trujillo no es adorno: allá el domingo se trabaja, así que un
--   arreglo que tratara el feriado en domingo como «día que no tocaba» pasaría
--   las otras dos y fallaría ésa.
--
-- QUÉ NO SE TOCA
--   · **Vacaciones** — su lateral `vacd` nunca excluyó el feriado y esta rama
--     tampoco lo excluía para ellas. Simétrico ya, y sigue igual.
--   · **Maternidad** — la 0262 lo dejó decidido y medido: el feriado lo excluye
--     `fn_feriado_devengado` y lo cuenta el lateral `mat`. Quitarlo de los dos
--     lados dejaría el día sin dueño, que es el defecto que esta migración
--     arregla. No se toca.
--   Por eso la línea se retira entera en vez de cambiarla: solo hablaba de
--   `descanso_medico`.
--
-- QUÉ SIGUE ABIERTO, MEDIDO Y DECLARADO
--   La prueba 244 deja escritas las dos divergencias que **deben** seguir:
--   maternidad firmada (el subsidio lo paga EsSalud; la reserva devenga por el
--   art. 3.2 c) del D.S. 005-2002-TR) y licencia con goce (la boleta no la paga
--   por ningún camino — defecto conocido, sin lote).
--
-- CÓMO SE REVIERTE
--   Volviendo a poner las dos líneas que el comentario «CAMBIO 0310» cita
--   textualmente. No hay datos que deshacer: la función solo lee.
--
-- MD5 DE PARTIDA
--   → adb0a986b32d26920fb9488a314b4d45 · 38 053 caracteres
--   Es el md5 de llegada declarado por la 0308 y el que devuelve el Postgres
--   local reconstruido desde cero. Si producción devuelve otro, lo más probable
--   es que la 0308 todavía no esté pegada: pégala primero.
--
-- MD5 DE LLEGADA (medido DESPUÉS de fijar el número 0310 — el marcador
--   «CAMBIO 00NN» cambia con él, y el hash cambia mientras la longitud NO)
--   → b40ded0faad67ac72625369d22699562 · 39 308 caracteres
--   Y si no coincide pero la longitud sí:
--   select position('CAMBIO 0310' in prosrc) from pg_proc
--    where proname='fn_provisiones';   → 19252
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_provisiones(p_as_of date DEFAULT NULL::date, p_salario_asof date DEFAULT NULL::date)
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

  with base_cruda as (
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
        -- ⇩⇩⇩ CAMBIO 0338 ⇩⇩⇩ p_salario_asof, si se pasa, congela la fecha
        -- de referencia del sueldo en vez de usar el día de la jornada.
        and coalesce(p_salario_asof, j.fecha) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, j.fecha) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    where j.horas_trabajadas is not null and j.horas_trabajadas > 0

    union all

    -- ⇩⇩⇩ CAMBIO 0276 ⇩⇩⇩ 5) EL FERIADO, EL MISMO QUE PAGA LA BOLETA.
    --
    -- Las dos mitades entran: el dia prorrateado (art. 8 del D. Leg. 713) y la
    -- sobretasa por haberlo trabajado (art. 9). Ninguna se calcula aca: se
    -- pregunta a `fn_feriado_devengado`, que es el MISMO sitio del que sale la
    -- linea de feriados de la boleta. Una regla, un sitio.
    --
    -- CADA FERIADO ENTRA POR SU FECHA, no por la ventana. Por eso basta UNA
    -- llamada por persona sobre el tramo mas ancho que alguna ventana pueda
    -- pedir: las cinco ventanas se reparten solas con el `between` que ya
    -- existe abajo. Una llamada por persona en vez de cinco: preguntar ventana
    -- por ventana multiplicaria por cinco un recorrido de `jornadas` que ya es
    -- lo mas caro que hace esta funcion.
    --
    -- SIN p_dias: en ese modo la funcion cobra cada feriado con el bloque del
    -- PERIODO DE PLANILLA en que cayo — o sea, exactamente lo que su boleta
    -- pago ese mes.
    select p.id as persona_id, (e->>'fecha')::date as fecha,
           (e->>'monto')::numeric as pago_dia
    from personas p
    cross join lateral jsonb_array_elements(
      -- ⇩ CAMBIO 0338 ⇩ Se propaga p_salario_asof: el feriado tiene el
      -- mismo defecto de sueldo día por día, por su propia búsqueda interna.
      fn_feriado_devengado(p.id,
        greatest(p.fecha_ingreso, least(c1_ini, g1_ini, v_as_of - 366)),
        v_as_of, null::int, p_salario_asof) -> 'detalle') e
    where fn_devenga_algo(p.id)

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
    -- ⇩⇩⇩ CAMBIO 0302 ⇩⇩⇩ DÍAS LABORABLES, NO DÍAS DE CALENDARIO.
    --
    -- Acá decía `salario / días del mes` por cada día de CALENDARIO de la
    -- ausencia. La boleta hace otra cosa: paga la ausencia como si la persona
    -- hubiera trabajado, o sea sus días LABORABLES del tramo. Contar los de
    -- calendario mete los sábados y domingos dos veces —una dentro del sueldo
    -- mensual y otra como día de ausencia—.
    --
    -- Medido con periodo = mes calendario, para aislar esto del divisor:
    -- alguien con 19 días de vacaciones en marzo reservaba S/136,28 de
    -- gratificación mientras la boleta le apuntaba S/115,32. Y ahí está la
    -- prueba de que el equivocado era éste y no la boleta: la reserva le daba
    -- MÁS gratificación a quien estuvo de vacaciones que a quien trabajó el mes
    -- entero. No se devenga más beneficio por no venir.
    --
    -- Y como `fn_grati_cts_periodo` autocompleta el depósito desde acá, ese
    -- exceso salía del banco el 15/05, 15/07, 15/11 y 15/12.
    --
    -- LO QUE NO SE TOCA, Y ES EL CUIDADO DE ESTA RAMA. Existe desde la 0135
    -- porque sin ella tomarse las vacaciones te BAJABA la gratificación —el
    -- error contrario, y ése sí contra la persona—. Sigue contando la ausencia:
    -- lo que cambia es cuántos días y a cuánto el día.
    select p.id as persona_id, gs::date as fecha,
           -- EL DÍA VALE LO MISMO QUE UN DÍA TRABAJADO, y esa es la mitad
           -- que hay que NO tocar. La rama 1 paga cada día marcado a
           -- `salario / días del mes`; si acá se pusiera `salario / días
           -- laborables` —que suena más fino— el día de ausencia valdría MÁS
           -- que el día trabajado. Medido al intentarlo: la diferencia contra
           -- la boleta subía de S/20,96 a S/32,16 en vez de bajar a cero.
           tt.salario
             / extract(day from (date_trunc('month', gs) + interval '1 month - 1 day'))::numeric as pago_dia
    from ausencias au
    join tipos_ausencia ta on ta.codigo = au.tipo and ta.paga
    -- ⇩⇩⇩ CAMBIO 0308 ⇩⇩⇩ SIN LA FIRMA DE DO NO SE DEVENGA, IGUAL QUE EN LA
    -- BOLETA. La 0306 hizo que `fn_planilla_calcular` dejara de pagar el
    -- descanso médico y la maternidad sin aprobar, y esta función se quedó sin
    -- enterarse: seguía devengando el mes completo. Un descanso médico
    -- registrado y sin firmar pagaba S/0 de sueldo y reservaba como si se
    -- hubiera pagado entero — y de acá sale el depósito, porque
    -- `fn_grati_cts_periodo` es la única que llama a esta función.
    --
    -- Medido (marzo 2026, S/1.950, 19 días del 02 al 20): la reserva se pasaba
    -- S/78,63 de gratificación y S/164,34 sumando CTS, vacaciones y la
    -- bonificación extraordinaria.
    --
    -- SE PREGUNTA AL CATÁLOGO, NO SE ESCRIBE LA LISTA DE TIPOS. La boleta
    -- nombra `descanso_medico` y `maternidad` uno por uno porque tiene un
    -- lateral para cada uno; acá hay una sola rama para los cuatro tipos que
    -- pagan, así que la lista escrita a mano sería exactamente lo que prohíbe
    -- la tercera regla de la casa. `tipos_ausencia.requiere_aprobacion` ya dice
    -- quién necesita firma, y dice lo correcto: descanso médico, maternidad y
    -- licencia con goce sí; vacaciones NO — que es lo que impide que este
    -- cambio le quite las vacaciones a nadie.
    --
    -- `is not true` y no `not`: la guarda tiene que negar también el null, por
    -- la misma razón que los guards SECURITY DEFINER de toda la casa.
    and (ta.requiere_aprobacion is not true or au.aprobada_at is not null)
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
        -- ⇩ CAMBIO 0338 ⇩
        and coalesce(p_salario_asof, gs::date) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, gs::date) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) tt on true
    -- ⇩ CAMBIO 0302 ⇩ El horario vigente ESE día, y cuántos días laborables
    -- tiene su mes. Se busca por día y no una vez, por lo mismo que la 0122
    -- hizo con la asignación familiar: un cambio de horario no puede reescribir
    -- lo que ya se devengó.
    join lateral (
      select ha.dias_laborables, ha.horario_por_dia
      from horarios_asignados ha
      where ha.persona_id = p.id and ha.vigente_desde <= gs::date
      order by ha.vigente_desde desc limit 1
    ) hor on true
    where au.anulada_at is null
      -- ⇩ CAMBIO 0302 ⇩ Solo los días que le tocaba trabajar. Un domingo dentro
      -- de unas vacaciones no es un día de vacaciones: ya era descanso.
      and case when hor.horario_por_dia is not null
               then hor.horario_por_dia ? (extract(dow from gs)::int::text)
               else extract(dow from gs)::int = any(hor.dias_laborables) end
      -- Si ese día SÍ marcó, la rama 1 ya lo contó. Puede pasar: media jornada
      -- trabajada y media de permiso, o una ausencia registrada tarde sobre un
      -- día que ya tenía marcas.
      and not exists (
        select 1 from jornadas j
        where j.persona_id = p.id and j.fecha = gs::date
          and j.horas_trabajadas is not null and j.horas_trabajadas > 0
      )
      -- ⇩⇩⇩ CAMBIO 0276 ⇩⇩⇩ UN FERIADO DENTRO DE UN DESCANSO MÉDICO NO SE
      -- CUENTA DOS VECES.
      --
      -- Esta línea nace de esta misma migración y arregla algo que ella misma
      -- rompía. Al aparecer la rama 5 —el feriado, que antes no estaba en esta
      -- base—, un feriado caído dentro de un descanso médico entraba DOS veces:
      -- una como día de ausencia pagada acá, y otra como feriado allá.
      --
      -- SE ESPEJA A LA BOLETA, TIPO POR TIPO, y no se aplica a los tres por
      -- igual, porque la boleta no los trata igual:
      --   · descanso médico → su lateral `dmd` EXCLUYE el feriado desde la
      --     0254 («un día que ya paga por otra vía no se paga dos veces»), así
      --     que acá también hay que excluirlo. Es esta línea.
      --   · vacaciones      → su lateral `vacd` NO lo excluye: el feriado se
      --     cuenta como día de vacaciones. Simétrico, no se toca.
      --   · maternidad      → la 0262 lo dejó decidido y medido al revés: el
      --     feriado lo excluye `fn_feriado_devengado` y lo cuenta el lateral
      --     `mat`. Si se quitara de los dos lados el día no lo pagaría nadie,
      --     que fue el primer intento de aquella migración. No se toca.
      --
      -- Medido: descanso médico del 27/04 al 08/05/2026, que contiene el 01/05.
      -- Sin esta línea la base de mayo salía S/169.33 por encima de la boleta;
      -- con ella sale S/102.48, que es exactamente lo que vale el feriado y lo
      -- mismo que sube su gemela con vacaciones en el mismo rango.
      -- ⇩⇩⇩ CAMBIO 0310 ⇩⇩⇩ Y ESTA LÍNEA YA NO VA. Decía:
      --
      --     and not (au.tipo = 'descanso_medico'
      --              and exists (select 1 from feriados f where f.fecha = gs::date))
      --
      -- Se escribió bien y su razón está tres párrafos más arriba: «su lateral
      -- `dmd` EXCLUYE el feriado desde la 0254, así que acá también hay que
      -- excluirlo». Era verdad el día que se escribió.
      --
      -- La 0293 —«el feriado dentro de un descanso médico se paga»— quitó esa
      -- exclusión de `dmd`. La premisa de esta línea quedó falsa y nadie lo
      -- notó, porque la línea sigue corriendo igual de bien: no falla, solo
      -- deja de tener razón.
      --
      -- Resultado: el feriado dentro de un descanso médico **no lo contaba
      -- nadie**. Acá se excluía «porque ya lo cuenta el feriado», y
      -- `fn_feriado_devengado` lo excluye por su cuenta. El día caía entre dos
      -- sillas — exactamente lo que la cabecera de la 0262 advertía que pasaría
      -- si se quitaba de los dos lados, y lo que la 0306 volvió a advertir.
      --
      -- Medido: S/5,24 de gratificación por feriado — un día a salario/31 —
      -- y en la dirección que esta casa considera la más cara, contra la
      -- persona. Con la línea fuera, los tres escenarios que lo tocan cuadran
      -- al céntimo con la boleta (prueba 244).

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
        -- ⇩ CAMBIO 0338 ⇩
        and coalesce(p_salario_asof, gs::date) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, gs::date) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) sal on true
    -- ⇩ CAMBIO 0160 ⇩ También el sueldo fijo: un socio con sueldo fijo que no
    -- está en planilla tampoco devenga CTS, gratificación ni vacaciones.
    where p.sueldo_fijo and fn_devenga_algo(p.id)   -- CAMBIO 0196
  ),
  -- ⇩⇩⇩ CAMBIO 0276 ⇩⇩⇩ EL FACTOR DE LA 0111, QUE AQUÍ NUNCA ESTUVO.
  --
  -- ESTA ERA LA SEGUNDA DIFERENCIA ENTRE LAS DOS BASES. La 0111 agregó
  -- `asignaciones_salario.base_provision` para que bajar el rango a la básica
  -- legal —lo que la 0110 permite, para que el Rendimiento Extraordinario se
  -- anule solo— no le recortara a nadie la gratificación, la CTS ni las
  -- vacaciones. La boleta multiplica su base por
  -- `base_provision / salario` en cinco sitios. `fn_provisiones` no lo hacía en
  -- ninguno: la palabra `base_provision` aparecía 10 veces en
  -- `fn_planilla_calcular` y CERO acá.
  --
  -- El efecto era el que la 0111 vino a evitar, pero solo en la reserva: con el
  -- rango bajado a 1,130 y `base_provision` en 1,320, la boleta provisionaba
  -- sobre 1,320 y la pantalla de Provisiones —la que dice cuánto hay que tener
  -- guardado, y de la que `fn_grati_cts_periodo` AUTOCOMPLETA el depósito— lo
  -- hacía sobre 1,130. Un 14.4 % menos, en silencio.
  --
  -- SE ESCRIBE UNA VEZ, ENVOLVIENDO LA BASE ENTERA, no cinco veces dentro de
  -- las ramas. Es exactamente el mismo motivo por el que la 0196 apagó los
  -- factores en origen y la 0273 dejó `devengado`/`cobrado` en un solo sitio:
  -- una expresión repetida en cinco ramas es un olvido pedido, y el olvido no
  -- daría error — daría un número.
  --
  -- EL FACTOR SE BUSCA POR DÍA, no una vez por persona. `base` ya es un flujo
  -- diario y cada día trae su propio tramo salarial; aplicar el factor de hoy a
  -- los días de un tramo anterior movería una reserva ya devengada. La boleta,
  -- que solo mira un periodo, se conforma con el ÚLTIMO tramo del periodo
  -- (`ref`); acá se acumula sobre años y esa simplificación no vale. En el caso
  -- normal —un solo tramo, o varios con el mismo factor— las dos dan el mismo
  -- número, que es lo que la prueba 213 comprueba.
  --
  -- ARRANCA INERTE: `base_provision` nace en NULL, el factor sale 1 y ninguna
  -- reserva se mueve al pegar esto. Medido contra la misma función SIN este
  -- envoltorio, celda por celda: 0 distintas. Y encendida, boleta y reserva se
  -- mueven exactamente lo mismo — S/119,42 → S/143,30 en las dos, con
  -- `base_provision` = 2.340 sobre un salario de 1.950.
  base as (
    select bc.persona_id, bc.fecha, bc.pago_dia * coalesce(fac.factor, 1) as pago_dia
    from base_cruda bc
    left join lateral (
      select coalesce(a.base_provision / nullif(a.salario_mensual_soles, 0), 1) as factor
      from asignaciones_salario a
      where a.persona_id = bc.persona_id
        -- ⇩⇩⇩ CAMBIO 0338 ⇩⇩⇩ El factor base_provision/salario también se
        -- congela al sueldo del cierre cuando p_salario_asof se pasa.
        and coalesce(p_salario_asof, bc.fecha) >= a.vigente_desde
        and (a.vigente_hasta is null or coalesce(p_salario_asof, bc.fecha) <= a.vigente_hasta)
      order by a.vigente_desde desc limit 1
    ) fac on true
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
    -- ⇩⇩⇩ CAMBIO 0274 ⇩⇩⇩ ESTA PANTALLA ES UNA RESERVA, NO UN CENSO.
    --
    -- Hasta hoy la única condición era «activo», así que la tabla listaba a
    -- TODO el equipo: locadoras, gente en días de prueba y accionistas salían
    -- con cinco columnas en S/ 0.00. Los ceros no eran un error de cálculo
    -- —la 0196 ya apagaba sus factores en origen y esa parte sigue igual—,
    -- pero llenaban la pantalla de filas que no reservan nada y obligaban a
    -- leerlas una por una para comprobar que, en efecto, no reservan nada.
    --
    -- LA CONDICIÓN NO ES EL TIPO DE VÍNCULO, ES SI DEVENGA. Sería más corto
    -- escribir `tipo_vinculo = 'planilla'`, y estaría mal: desde la 0196 el
    -- devengo se decide POR PERSONA y POR BENEFICIO, y ese interruptor existe
    -- justo para los casos que el tipo de vínculo no sabe expresar. Filtrar
    -- por el tipo escondería a quien tenga un beneficio encendido a mano —y
    -- esconder a alguien de la pantalla de reservas es dejar de reservar su
    -- plata sin que nadie lo vea. `fn_devenga_algo` pregunta por los tres
    -- beneficios; quien no devenga ninguno es quien no tiene nada que reservar.
    --
    -- QUIEN DEVENGA Y HOY SUMA CERO SIGUE SALIENDO, a propósito: alguien que
    -- entró esta semana reserva S/ 0.00 porque aún no devengó, no porque no le
    -- corresponda. Ese cero sí significa algo y tiene que verse.
    where p.estado = 'activo' and fn_devenga_algo(p.id)   -- CAMBIO 0274
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


$function$
;

-- ────────────────────────────────────────────────────────────────────────────
-- fn_feriado_devengado — gana p_salario_asof, propagado desde fn_provisiones.
-- ────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS fn_feriado_devengado(uuid, date, date, integer);

CREATE OR REPLACE FUNCTION public.fn_feriado_devengado(p_persona uuid, p_desde date, p_hasta date, p_dias integer, p_salario_asof date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tope_dm int;
  v_out jsonb;
begin
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular el feriado devengado.';
  end if;

  select coalesce((valor->>'umbral_essalud')::int, 20) into v_tope_dm
  from configuracion where clave = 'descanso_medico_aviso_dias';
  if v_tope_dm is null then v_tope_dm := 20; end if;

  with pe as (
    select p.id, p.fecha_ingreso, p.sueldo_fijo, p.en_planilla
    from personas p where p.id = p_persona
  ),
  fer_bloque as (
    select f.fecha,
           case when p_dias is not null then p_desde else coalesce(pp.fecha_ini, can.ini) end as b_ini,
           case when p_dias is not null then p_hasta else coalesce(pp.fecha_fin, can.fin) end as b_fin,
           case when p_dias is not null then p_dias
                else coalesce((pp.fecha_fin - pp.fecha_ini) + 1, (can.fin - can.ini) + 1) end as b_dias
    from feriados f
    left join periodos_planilla pp on p_dias is null and f.fecha between pp.fecha_ini and pp.fecha_fin
    cross join lateral (
      select (q.m + make_interval(days =>
                least(29, extract(day from (date_trunc('month', q.m) + interval '1 month - 1 day'))::int) - 1))::date as ini,
             (date_trunc('month', q.m + interval '1 month') + interval '27 days')::date as fin
      from (select case when extract(day from f.fecha) >= 29
                        then date_trunc('month', f.fecha::timestamp)
                        else date_trunc('month', f.fecha::timestamp) - interval '1 month' end as m) q
    ) can
    where f.fecha between p_desde and p_hasta
  ),
  bloque as (
    select distinct b.b_ini, b.b_fin, b.b_dias, 6.5 * b.b_dias as v_base
    from fer_bloque b
  ),
  horas_bloque as (
    select bq.b_ini, bq.b_fin, bq.b_dias, bq.v_base,
           coalesce(hh.horas_totales, 0) as horas_mes,
           case when pe.sueldo_fijo then 0
                else coalesce(hh.horas_totales / nullif(hh.dias_marcados, 0),
                              bq.v_base / nullif(labp.dias, 0),
                              0) * coalesce(vacd.dias, 0) end as horas_vacaciones,
           case when pe.sueldo_fijo then 0
                else coalesce(hh.horas_totales / nullif(hh.dias_marcados, 0),
                              bq.v_base / nullif(labp.dias, 0),
                              0) * coalesce(dmd.dias, 0) end as horas_descanso_medico
    from bloque bq
    cross join pe
    left join lateral (
      select coalesce(sum(coalesce(j.horas_trabajadas, 0)), 0) as horas_totales,
             count(*) filter (where coalesce(j.horas_trabajadas, 0) > 0) as dias_marcados
      from jornadas j
      where j.persona_id = pe.id and j.fecha between bq.b_ini and bq.b_fin
    ) hh on true
    left join lateral (
      select count(*)::int as dias
      from generate_series(bq.b_ini, bq.b_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hv on true
      where pe.en_planilla
        and exists (select 1 from vacaciones v
                     where v.persona_id = pe.id
                       and d.d::date between v.fecha_inicio and v.fecha_fin)
        and not exists (
              select 1 from jornadas j
              where j.persona_id = pe.id and j.fecha = d.d::date
                and j.horas_trabajadas is not null and j.horas_trabajadas > 0)
        and case when hv.horario_por_dia is not null
                 then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                 else extract(dow from d.d)::int = any(hv.dias_laborables) end
    ) vacd on true
    left join lateral (
      select count(*)::int as dias
      from (
        select dd.d::date as dia,
               row_number() over (partition by extract(year from dd.d) order by dd.d) as n
        from ausencias a
        join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
        where a.persona_id = pe.id and a.tipo = 'descanso_medico' and a.anulada_at is null
          and a.aprobada_at is not null
      ) dm
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= dm.dia
        order by ha.vigente_desde desc limit 1
      ) hv on true
      where pe.en_planilla
        and dm.n <= v_tope_dm
        and dm.dia between bq.b_ini and bq.b_fin
        and not exists (select 1 from vacaciones v
                         where v.persona_id = pe.id
                           and dm.dia between v.fecha_inicio and v.fecha_fin)
        and not exists (
              select 1 from jornadas j
              where j.persona_id = pe.id and j.fecha = dm.dia
                and j.horas_trabajadas is not null and j.horas_trabajadas > 0)
        and case when hv.horario_por_dia is not null
                 then hv.horario_por_dia ? (extract(dow from dm.dia)::int::text)
                 else extract(dow from dm.dia)::int = any(hv.dias_laborables) end
    ) dmd on true
    left join lateral (
      select count(*)::int as dias
      from generate_series(bq.b_ini, bq.b_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hv on true
      where case when hv.horario_por_dia is not null
                 then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                 else extract(dow from d.d)::int = any(hv.dias_laborables) end
    ) labp on true
  ),
  dias as (
    select fb.fecha,
           coalesce(hf.horas_trabajadas, 0) as horas_trabajadas,
           case when pe.en_planilla and tt.salario is not null and fb.fecha >= pe.fecha_ingreso
                then (case when pe.sueldo_fijo then 0
                           else 7.5 * (hb.horas_mes + hb.horas_vacaciones + hb.horas_descanso_medico)
                                / hb.v_base end) * tt.salario / hb.v_base
                else 0 end as prorrateo,
           case when pe.en_planilla and tt.salario is not null and fb.fecha >= pe.fecha_ingreso
                then (case when ds.otorgado then 0 else coalesce(hf.horas_trabajadas, 0) end)
                     * tt.salario / hb.v_base
                else 0 end as sobretasa,
           case when pe.sueldo_fijo then 0
                else 7.5 * (hb.horas_mes + hb.horas_vacaciones + hb.horas_descanso_medico)
                     / hb.v_base end as proporcional_horas,
           (tt.salario is null and fb.fecha >= pe.fecha_ingreso) as sin_salario,
           (fb.fecha < pe.fecha_ingreso) as antes_ingreso,
           ds.otorgado as descanso_sustitutorio,
           ds.fecha_descanso,
           pe.en_planilla, pe.fecha_ingreso
    from fer_bloque fb
    cross join pe
    join horas_bloque hb on hb.b_ini = fb.b_ini and hb.b_fin = fb.b_fin
    left join lateral (
      select a.salario_mensual_soles as salario
      from asignaciones_salario a
      where a.persona_id = pe.id
        -- ⇩⇩⇩ CAMBIO 0338 ⇩⇩⇩ p_salario_asof, si se pasa, congela la fecha
        -- de referencia del sueldo en vez de usar el día del feriado.
        and a.vigente_desde <= coalesce(p_salario_asof, fb.fecha)
        and (a.vigente_hasta is null or a.vigente_hasta >= coalesce(p_salario_asof, fb.fecha))
      order by a.vigente_desde desc limit 1
    ) tt on true
    left join jornadas hf on hf.persona_id = pe.id and hf.fecha = fb.fecha
    left join lateral (
      select true as otorgado, d.fecha_descanso_sustitutorio as fecha_descanso
      from feriados_descanso_sustitutorio d
      where d.persona_id = pe.id and d.fecha_feriado = fb.fecha and d.estado = 'OTORGADO'
      limit 1
    ) ds on true
    where not exists (
      select 1 from ausencias a
      where a.persona_id = pe.id and a.tipo = 'maternidad' and a.anulada_at is null
        and a.subsidio_diario is not null
        and a.aprobada_at is not null
        and fb.fecha between a.fecha_inicio and a.fecha_fin
    )
  )
  select jsonb_build_object(
    'monto',          coalesce(sum(prorrateo + sobretasa), 0),
    'prorrateo',      coalesce(sum(prorrateo), 0),
    'sobretasa',      coalesce(sum(sobretasa), 0),
    'sin_tramo',      count(*) filter (where sin_salario),
    'no_corresponde', count(*) filter (where antes_ingreso),
    'compensados',    count(*) filter (where descanso_sustitutorio),
    'detalle', coalesce(jsonb_agg(jsonb_build_object(
        'fecha', fecha,
        'horas_trabajadas', horas_trabajadas,
        'proporcional_horas', case when en_planilla and fecha >= fecha_ingreso
                                   then round(proporcional_horas, 2) else 0 end,
        'monto', prorrateo + sobretasa,
        'sin_salario', sin_salario,
        'antes_ingreso', antes_ingreso,
        'descanso_sustitutorio', descanso_sustitutorio,
        'descanso_fecha', fecha_descanso
      ) order by fecha), '[]'::jsonb)
  ) into v_out
  from dias;

  return v_out;
end;
$function$;

-- ────────────────────────────────────────────────────────────────────────────
-- fn_grati_cts_periodo — llama a fn_provisiones dos veces por ventana y se
-- queda con el mayor entre el día a día y el piso legal. Misma firma de
-- siempre (un solo uuid): no hace falta drop.
-- ────────────────────────────────────────────────────────────────────────────
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
  v_prov_g_piso jsonb; v_prov_c_piso jsonb;   -- CAMBIO 0338
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

  -- ⇩⇩⇩ CAMBIO 0338 ⇩⇩⇩ EL PISO LEGAL.
  --
  -- D.S. 001-97-TR art. 10/21 (CTS) y D.S. 013-2013-PRODUCE art. 50 (CTS y
  -- gratificación de pequeña empresa, que remite al régimen común) mandan
  -- tomar el sueldo vigente EN LA FECHA DE CORTE del semestre y aplicarlo a
  -- TODO el semestre — no promediar el sueldo histórico día por día, que es
  -- lo que fn_provisiones hace por defecto (sirve bien como cifra de reserva
  -- suavizada mes a mes; el defecto está solo en usar ese mismo número como
  -- el depósito real).
  --
  -- Pasarle a fn_provisiones su MISMA fecha de corte como p_salario_asof
  -- congela, para cada día del semestre, el sueldo vigente EN ESA fecha en
  -- vez del vigente ese día — exactamente la mecánica que pide la norma,
  -- calculada con el mismo código ya auditado, sin reimplementarlo aparte.
  --
  -- SE TOMA EL MAYOR, nunca el promedio ni la suma: si el sueldo bajó a
  -- mitad de semestre, el día a día ya da MÁS que el piso (el piso usaría el
  -- sueldo nuevo, más bajo, para los días de antes) y no debe bajarle nada a
  -- nadie. Solo cuando hubo un AUMENTO a mitad de semestre el piso es mayor,
  -- y ahí sí corrige hacia arriba. Medido en laboratorio (BEGIN…ROLLBACK,
  -- caso hipotético S/1.500→S/1.800 a mitad de semestre): día a día
  -- S/306.76, piso S/333.99 en CTS — nunca al revés con una bajada de sueldo.
  v_prov_g_piso := fn_provisiones(v_asof_g, v_asof_g);
  v_prov_c_piso := case when v_asof_c = v_asof_g then v_prov_g_piso else fn_provisiones(v_asof_c, v_asof_c) end;

  return jsonb_build_object(
    'grati_aplica', v_gkey is not null, 'grati_concepto', v_gtxt,
    'cts_aplica',   v_ckey is not null, 'cts_concepto',   v_ctxt,
    'personas', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'persona_id', g.pid,
        'grati', case when v_gkey is null then 0 else greatest(
                   coalesce((g.fila->>v_gkey)::numeric, 0),
                   coalesce((gp.fila->>v_gkey)::numeric, 0)
                 ) end,
        'cts',   case when v_ckey is null then 0 else greatest(
                   coalesce((c.fila->>v_ckey)::numeric, 0),
                   coalesce((cp.fila->>v_ckey)::numeric, 0)
                 ) end
      )), '[]'::jsonb)
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
    )
  );
end;
$fn$;
grant execute on function fn_grati_cts_periodo(uuid) to authenticated;
revoke execute on function fn_grati_cts_periodo(uuid) from public, anon;

insert into migraciones_aplicadas (numero, nombre)
values (338, 'grati_cts_usan_el_sueldo_vigente_al_cierre')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';

-- ── COMPROBACIÓN ────────────────────────────────────────────────────────────
-- Un solo select, porque el SQL Editor de Supabase corre nada más el último.
select
  case when (select count(*) from migraciones_aplicadas where numero = 338) = 1
        and (select count(*) from pg_proc where proname = 'fn_provisiones' and prosrc like '%CAMBIO 0338%') = 1
        and (select count(*) from pg_proc where proname = 'fn_feriado_devengado' and prosrc like '%CAMBIO 0338%') = 1
        and (select count(*) from pg_proc where proname = 'fn_grati_cts_periodo' and prosrc like '%CAMBIO 0338%') = 1
       then '0338 · OK — gratificación y CTS usan el sueldo vigente al cierre'
       else '0338 · ATENCION — no entró, revisa antes de seguir'
  end as resultado,
  (select md5(prosrc) from pg_proc where proname = 'fn_provisiones') as md5_provisiones,
  (select md5(prosrc) from pg_proc where proname = 'fn_feriado_devengado') as md5_feriado,
  (select md5(prosrc) from pg_proc where proname = 'fn_grati_cts_periodo') as md5_grati_cts;
