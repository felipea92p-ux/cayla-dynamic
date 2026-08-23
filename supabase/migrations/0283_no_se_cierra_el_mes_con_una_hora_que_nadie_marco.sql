-- ============================================================================
-- 0283 — No se cierra el mes con una hora que nadie marcó
-- ============================================================================
--
-- QUÉ PROMETE
--   Que un periodo de planilla no se pueda congelar mientras haya días cuya
--   hora de salida la puso el proceso automático y todavía nadie confirmó.
--
-- QUÉ ASUME
--   · Que `fn_planilla_congelar` es la de la **0244**, confirmada con
--     `./scripts/donde-vive.sh fn_planilla_congelar`. El cuerpo NO se copió a
--     mano: se extrajo de la base con `pg_get_functiondef()` y se le insertaron
--     una declaración y un bloque, sin tocar una sola línea de lo demás.
--     md5 de partida — PEDIDO A PRODUCCIÓN antes de pegar esto, no copiado del
--     local. El de esta Mac es 1692771a95d4fe46d1d01d7005b37728
--     (sin comentarios, 63364f40980570e732b03374d04428cc).
--   · Que `fn_planilla_calcular` sigue devolviendo `dias_pendientes` por
--     persona dentro de `filas` (0276). Es el único dato nuevo que se lee.
--   · Que `jornadas.estado` sigue teniendo el valor `auto_cerrada_pendiente`.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- Cuando alguien olvida marcar su salida, `fn_auto_cierre` cierra el día
-- poniéndole una hora que calcula el sistema. Nadie la marcó.
--
-- El sistema ya sabe que esa hora no es de fiar: `fn_recalcular_jornada` se
-- niega a medir tardanza o salida temprana contra ella, y lo dice con todas las
-- letras en la 0249 — «esa hora la inventó el sistema y medir contra ella sería
-- acusar con un dato falso».
--
-- Pero para PAGAR sí la usa. Esa misma hora entra a `horas_trabajadas`, y de
-- ahí al ciclo de siete días que compara contra 48 h y paga recargo del 25 % o
-- 35 %. Ese recargo entra además a la base de EsSalud y pensión desde la 0193 y
-- se declara en la PLAME con código propio.
--
-- Dicho corto: la misma hora es demasiado dudosa para una conversación con una
-- persona, y suficientemente buena para una transferencia bancaria.
--
-- ── LO QUE HAY HOY, MEDIDO ANTES DE ESCRIBIR ESTO ───────────────────────────
--
-- Contra producción, el 2026-08-23, con las dos consultas que quedan en
-- `scripts/sql-manual/` (`cuanto_paga_la_hora_inventada.sql` y
-- `cuantas_veces_cierra_el_cron.sql`):
--
--   · 49 auto-cierres entre el 15/07 y el 22/08 — 19 en julio, 30 en agosto.
--     Pasa una o dos veces por día, y va en aumento.
--   · 12 de esos 49 quedaron ANULADOS: la hora inventada se equivoca una de
--     cada cuatro veces, y alguien tuvo que reemplazarla.
--   · CERO sin revisar en ese momento, y CERO soles de recargo apoyados en una
--     hora inventada. El sobretiempo pagado —8.52 h en el periodo abierto,
--     20.53 h en los cerrados— descansa todo en horas marcadas por personas.
--
-- **Hoy esto no cuesta nada, y por eso mismo conviene arreglarlo ahora.** Lo
-- que tapa el agujero no es el sistema: es que alguien entra a Correcciones
-- todos los días y confirma esas horas. La semana que nadie alcance —vacaciones,
-- una urgencia, un mes cargado— una hora sin dueño se paga y nadie se entera.
--
-- ── POR QUÉ UN FRENO Y NO TOCAR EL CÁLCULO ──────────────────────────────────
--
-- La otra mitad posible era que `fn_planilla_calcular` excluyera esos días del
-- recargo. Se descartó, y la razón es de riesgo, no de pereza: esa función pesa
-- 86.000 caracteres y tiene 47 versiones — es la más reescrita del repositorio,
-- y calcula todos los sueldos. Copiarla de la versión equivocada revierte en
-- silencio el sobretiempo de la foto o la provisión de la Ley 30334, y mover el
-- sobretiempo sin mover el total revienta `chk_foto_cuadra`, que deja el cierre
-- abortando con 23514 — o sea, sin poder pagarle a nadie.
--
-- Y no hace falta: **si no se puede cerrar el mes mientras haya una hora sin
-- confirmar, entonces cuando se paga todas fueron miradas por una persona.** Una
-- hora que alguien confirmó ya no es un dato inventado. El freno cierra el
-- circuito entero por sí solo.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   Pegar el cuerpo de `fn_planilla_congelar` de la 0244. No toca datos, no
--   toca tablas, y no escribe nada: revertir no pierde absolutamente nada.
--
-- ============================================================================


CREATE OR REPLACE FUNCTION public.fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_per record;
  v_calc jsonb;
  v_ver int;
  v_n int;
  v_cobradas text;   -- CAMBIO 0243
  v_pendientes text;   -- CAMBIO 0283
begin
  -- `for update` sobre el periodo: dos personas pulsando «Pagado» a la vez no
  -- pueden calcular ambas la versión 1 y chocar contra la llave primaria.
  select * into v_per from periodos_planilla where id = p_periodo_id for update;
  if not found then raise exception 'Periodo inexistente.'; end if;

  v_calc := fn_planilla_calcular(v_per.fecha_ini, v_per.fecha_fin, p_periodo_id);

  -- ── CAMBIO 0243 · el freno del orden inverso ────────────────────────────────
  -- Si alguien de este periodo YA cobró su liquidación —y esa liquidación
  -- incluía el sueldo de este mismo mes, que es lo que dice `monto_periodo`—
  -- congelar ahora volvería a registrarle ese mes. El dinero de este cierre
  -- todavía no salió, así que frenar no le quita nada a nadie: obliga a
  -- registrar el descuento antes, y eso además le deja rastro en su boleta.
  --
  -- ACTÚA EN LOS DOS ESTADOS, a propósito. Con el periodo abierto es el cierre
  -- normal (`fn_periodo_pagado` congela antes de marcar pagado, 0096:276-280).
  -- Con el periodo ya pagado es `fn_repagar_periodo` (0098), que escribe una
  -- versión nueva con el total recalculado: apagarlo ahí dejaría entrar el mismo
  -- doble pago por la otra puerta. Lo que cambia según el estado es el CAMINO
  -- que el mensaje manda a seguir, porque con el periodo pagado
  -- `fn_agregar_movimiento` rechaza el descuento (0181:67-71) y mandar al botón
  -- sería mandar a una puerta cerrada.
  --
  -- La última versión de la liquidación manda (`distinct on … order by version
  -- desc`), igual que en la 0210 y en la pantalla. Y `monto_periodo > 0` es la
  -- condición exacta: desde esta misma migración, una liquidación pagada DESPUÉS
  -- del congelamiento guarda 0 ahí —ya restó—, y entonces no hay nada que
  -- frenar.
  --
  -- ── CAMBIO 0244 ───────────────────────────────────────────────────────────
  -- LA CONDICIÓN QUE LEVANTA EL FRENO ES EL DESCUENTO, NO QUE LA FILA QUEDE EN
  -- CERO. La 0243 salía por `total > 0`, o sea solo si la fila quedaba EN CERO.
  -- Esto costó tres casos medidos, y los tres tenían la misma forma: la
  -- persona hacía EXACTAMENTE lo que el mensaje manda —descontar `monto_periodo`—
  -- y el freno volvía a saltar con la frase idéntica, porque quedaba un saldo que
  -- la cesada SÍ había ganado.
  --   · un feriado dentro del periodo pero posterior al cese —el que fija la
  --     prueba 185—: su liquidación cobró S/500.00, el periodo le calcula
  --     S/519.23, así que descontados los S/500.00 que el mensaje NOMBRA quedan
  --     S/19.23 legítimos y el mes no cerraba;
  --   · una reincorporación dentro del mismo periodo: sobre ese mismo montaje, si
  --     vuelve el 16 y trabaja hasta el 30, el periodo le calcula S/1,348.08 y
  --     descontados los mismos S/500.00 le quedan S/848.08 trabajados de verdad;
  --   · un marcaje que se cerró tarde y añadió un día después del descuento.
  -- Con `total > 0` como única salida, las dos únicas maneras de cerrar el mes
  -- eran quitarle dinero ganado o volver a congelar su liquidación falseando un
  -- registro inmutable. Por eso la condición mira si el DESCUENTO ya está puesto:
  -- `descuentos` es la suma de los movimientos de tipo descuento de esa persona
  -- en este periodo (fn_planilla_calcular), y el botón «💸 Ya le pagué aparte»
  -- escribe justo uno de esos (planilla/page.tsx:1357-1363). Registrado el
  -- importe que el mensaje nombra, el freno se levanta y el saldo se paga.
  --
  -- Su punto ciego, medido y aceptado: si esa persona ya arrastraba OTROS
  -- descuentos que por sí solos igualan o superan `monto_periodo` —un adelanto
  -- grande—, el freno no llega a morder. Se prefiere a acoplar la condición al
  -- texto del concepto: un freno que solo se levanta con una frase literal deja
  -- de levantarse el día que alguien reescribe el botón, y un freno del que no se
  -- puede salir se termina saltando con `--no-verify`. La red principal contra el
  -- doble pago es la parte (A), que cubre el otro orden entero.
  -- ── fin CAMBIO 0244 ───────────────────────────────────────────────────────
  select string_agg(x.frase, ' · ' order by x.frase) into v_cobradas
  from (
    select 'A ' || lq.persona || ' ya se le pagó su liquidación el '
           || to_char(lq.congelada_at at time zone 'America/Lima', 'DD/MM/YYYY')
           || ' e incluye S/' || to_char(lq.monto_periodo, 'FM999999990.00')
           || ' de este mismo periodo' as frase
    from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
    join lateral (
      select distinct on (lp.persona_id) lp.*
      from liquidacion_pagada lp
      where lp.persona_id = (f->>'persona_id')::uuid
      order by lp.persona_id, lp.version desc
    ) lq on true
    -- Solo si el cese cae DENTRO de este periodo se solapa el mismo mes.
    -- Quien cesó en un periodo anterior ya cobró aquel mes: avisar de él sería
    -- ruido. Mismo criterio y mismo patrón que la 0210, sostenido por el
    -- EXCLUDE `periodos_sin_solape`: a lo sumo un periodo contiene esa fecha.
    where lq.fecha_cese between v_per.fecha_ini and v_per.fecha_fin
      and lq.monto_periodo > 0
      and coalesce((f->>'total')::numeric, 0) > 0
      and coalesce((f->>'descuentos')::numeric, 0) < lq.monto_periodo   -- CAMBIO 0244
  ) x;

  if v_cobradas is not null then
    -- Una sola frase corrida, sin saltos de línea: la pantalla imprime el texto
    -- de un P0001 tal cual, sin `whitespace-pre-line`, así que un `\n` se
    -- colapsaría en un espacio (apps/web/lib/admin/mensaje-error.ts:81).
    -- CAMBIO 0244 · la rama del retroactivo es nueva, y las dos frases de abajo
    -- añaden la salida del saldo («si tras el descuento le queda un saldo…»).
    -- La 0243 tenía solo el if/else de los dos estados.
    if p_origen = 'retroactivo' then
      -- LA FOTO RETROACTIVA NO SE FRENA, Y ES LO CONTRARIO DE UNA EXCEPCIÓN
      -- CÓMODA. `fn_planilla_congelar_pendientes` (0096) documenta periodos que
      -- ya están pagados y no tienen foto: meses transferidos hace tiempo, de
      -- antes de que la foto existiera. Ahí la premisa del freno —«el dinero de
      -- este cierre todavía no salió»— es falsa por construcción, y seguir su
      -- instrucción inventaría un descuento que nunca ocurrió sobre el registro
      -- de un pago viejo. Medido: sin esto, esa función aborta entera y deja los
      -- periodos históricos sin foto para siempre.
      -- No puede usarse como escape: solo alcanza periodos SIN ninguna foto, así
      -- que nunca vuelve a congelar nada, y `origen` está acotado por CHECK a
      -- 'pago' | 'retroactivo'.
      raise warning '0244 · foto retroactiva de un periodo ya transferido: %. No se frena —ese dinero salió hace tiempo— pero conviene mirarlo.', v_cobradas;
    elsif v_per.estado = 'abierto' then
      raise exception '%. Cerrar así pagaría ese mes por segunda vez. Antes de cerrar, entra a su fila en Planilla y usa el botón «💸 Ya le pagué aparte» por ESE importe y con esa fecha; si el filtro «Mostrar» no la enseña, cámbialo a «Todos» o pulsa «Verlas» en el aviso de quienes ya no están. Si tras ese descuento le queda un saldo, ese saldo es suyo y se paga con la planilla: no hace falta dejar su fila en cero. El periodo sigue ABIERTO: no se congeló nada.', v_cobradas;
    else
      raise exception '%. Volver a congelarlo así registraría ese mes por segunda vez. Este periodo ya está PAGADO, así que el descuento no se puede anotar sin reabrirlo: usa «Revertir pago» con su motivo (ojo, eso levanta los candados de los marcajes de este periodo mientras esté abierto), registra el descuento con «💸 Ya le pagué aparte» por ESE importe y con esa fecha, y vuelve a marcarlo como pagado. Si tras el descuento le queda un saldo, ese saldo es suyo y se paga: no hace falta dejar su fila en cero. Nada se congeló: la foto anterior sigue intacta.', v_cobradas;
    end if;
  end if;
  -- ── fin CAMBIO 0243 ─────────────────────────────────────────────────────────

  -- ── CAMBIO 0283 · el freno de la hora que nadie marcó ───────────────────────
  --
  -- Cuando alguien olvida marcar su salida, `fn_auto_cierre` cierra el día con
  -- una hora que calcula el sistema, y la jornada queda en
  -- `auto_cerrada_pendiente` esperando que una encargada la confirme.
  --
  -- `fn_recalcular_jornada` se NIEGA a medir tardanza o salida temprana contra
  -- esa hora (0249): «esa hora la inventó el sistema y medir contra ella sería
  -- acusar con un dato falso». Pero esa MISMA hora sí entra a `horas_trabajadas`
  -- y de ahí al ciclo de 48 h que paga recargo del 25/35 % — que además entra a
  -- la base de EsSalud y pensión (0193) y se declara en la PLAME con código
  -- propio. La misma hora es demasiado dudosa para una conversación y
  -- suficientemente buena para una transferencia.
  --
  -- MEDIDO EN PRODUCCIÓN el 2026-08-23, antes de escribir esto:
  --   · 49 auto-cierres entre el 15/07 y el 22/08 — 19 en julio, 30 en agosto.
  --   · 12 de los 49 ANULADOS: la hora inventada se equivoca 1 de cada 4 veces.
  --   · 0 sin revisar en ese momento, y 0 soles de recargo apoyados en una hora
  --     inventada. HOY NO CUESTA NADA. Lo que tapa el agujero es que alguien
  --     entra a Correcciones y las confirma — no el sistema.
  --
  -- Este freno convierte esa disciplina en garantía. Y como el equipo ya las
  -- revisa todas, en la práctica no va a saltar: solo el mes que nadie alcance
  -- a mirarlas. Un freno que no estorba y que solo aparece cuando hace falta es
  -- lo contrario del guardián que chilla siempre.
  --
  -- POR QUÉ AQUÍ Y NO EN `fn_periodo_pagado`: esta función es el cuello por el
  -- que pasan las dos puertas —`fn_periodo_pagado` (0096) y `fn_repagar_periodo`
  -- (0098)— más cualquier llamada por `service_role`. Y no en la pantalla, por
  -- el mismo argumento con el que la 0244 se negó a acoplar su condición al
  -- texto de un botón: se levanta el día que alguien lo reescribe.
  --
  -- POR QUÉ MIRA LA JORNADA Y NO EL MARCAJE: `dias_pendientes` ya viaja en
  -- `v_calc->'filas'` (0276), así que no hace falta consulta nueva. Que no se
  -- pierde nada por ahí está medido: el cruce marcaje × jornada de
  -- `scripts/sql-manual/cuantas_veces_cierra_el_cron.sql`, corrido en producción
  -- ese mismo día, salió limpio — todo marcaje sin revisar tenía su jornada en
  -- `auto_cerrada_pendiente`.
  --
  -- LO QUE NO MIRA, A PROPÓSITO: las jornadas `abierta` y `en_pausa`. No las
  -- trae `v_calc` y exigirían una consulta nueva dentro de esta función,
  -- multiplicando la superficie del atasco. Queda como pendiente deliberado.
  select case when count(*) = 0 then null
              else string_agg(x.frase, ' · ' order by x.frase)
                     filter (where x.rn <= 6)
                   || case when count(*) > 6
                           then ' · y ' || (count(*) - 6)::text || ' más'
                           else '' end
         end into v_pendientes
  from (
    select (f->>'nombre') || ' (' || (f->>'dias_pendientes') || ' día(s))' as frase,
           row_number() over (order by (f->>'nombre')) as rn
    from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
    where coalesce((f->>'dias_pendientes')::int, 0) > 0
  ) x;

  if v_pendientes is not null then
    -- Una sola frase corrida, sin saltos de línea, por lo mismo que la 0244:
    -- la pantalla imprime el texto de un P0001 tal cual (mensaje-error.ts:81).
    if p_origen = 'retroactivo' then
      -- Misma razón que la rama retroactiva de la 0244:
      -- `fn_planilla_congelar_pendientes` (0096) documenta meses transferidos
      -- hace años. Abortar ahí dejaría los periodos históricos sin foto para
      -- siempre — está medido en la cabecera de la 0244.
      raise warning '0283 · foto retroactiva con días auto-cerrados sin revisar: %. No se frena —ese mes se pagó hace tiempo— pero conviene mirarlo.', v_pendientes;
    elsif v_per.estado = 'abierto' then
      raise exception 'Hay días cuya hora de salida la puso el sistema y todavía nadie la confirmó: %. Esa hora no la marcó ninguna persona, y si cruza las 48 h de la semana se paga recargo sobre ella. Entra a Correcciones, confirma o corrige esas salidas, y vuelve a cerrar. El periodo sigue ABIERTO: no se congeló nada.', v_pendientes;
    else
      raise exception 'Hay días cuya hora de salida la puso el sistema y nadie la confirmó: %. Este periodo ya está PAGADO, así que para arreglarlo hay que usar «Revertir pago» con su motivo (ojo, eso levanta los candados de los marcajes de este periodo mientras esté abierto), confirmar esas salidas en Correcciones, y volver a marcarlo como pagado. Nada se congeló: la foto anterior sigue intacta.', v_pendientes;
    end if;
  end if;
  -- ── fin CAMBIO 0283 ─────────────────────────────────────────────────────────

  select coalesce(max(version), 0) + 1 into v_ver
  from planilla_pagada_detalle where periodo_id = p_periodo_id;

  insert into planilla_pagada_detalle (
    periodo_id, persona_id, version, congelada_por, origen,
    nombre, sede_codigo, area_codigo, rango, salario_ref,
    horas_mes, dias_trabajados,
    pago_base, monto_feriados, monto_plus, asignacion_familiar,
    bonos, descuentos,
    monto_movilidad, monto_educacion, descuento_pension, aporte_essalud,   -- CAMBIO 0127
    monto_sobretiempo,                                                     -- CAMBIO 0201
    monto_descanso_semanal,                                                -- CAMBIO 0280
    total,
    provision_gratificacion, provision_bonif_extraordinaria, provision_cts, provision_vacaciones, provision_total,   -- CAMBIO 0134
    fila
  )
  select
    p_periodo_id,
    (f->>'persona_id')::uuid,
    v_ver,
    p_autor,
    p_origen,
    f->>'nombre',
    f->>'sede',
    pe.funcion,
    f->>'rango',
    (f->>'salario_ref')::numeric,
    coalesce((f->>'horas_mes')::numeric, 0),
    coalesce((f->>'dias_trabajados')::int, 0),
    coalesce((f->>'pago_base')::numeric, 0),
    coalesce((f->>'monto_feriados')::numeric, 0),
    coalesce((f->>'monto_plus')::numeric, 0),
    coalesce((f->>'asignacion_familiar')::numeric, 0),
    coalesce((f->>'bonos')::numeric, 0),
    coalesce((f->>'descuentos')::numeric, 0),
    -- CAMBIO 0127 — los tres conceptos que entraron al total en la 0110 y la
    -- 0120, mas el EsSalud como dato. Sin esto la foto no puede cuadrar.
    coalesce((f->>'monto_movilidad')::numeric, 0),
    coalesce((f->>'monto_educacion')::numeric, 0),
    coalesce((f->>'descuento_afp')::numeric, 0),
    coalesce((f->>'aporte_essalud')::numeric, 0),
    -- CAMBIO 0201 — el recargo del sobretiempo, que la 0185 metio al total.
    -- Mismo motivo que la linea de arriba: sin columna, la foto no cuadra.
    coalesce((f->>'monto_sobretiempo')::numeric, 0),
    coalesce((f->>'monto_descanso_semanal')::numeric, 0),                  -- CAMBIO 0280
    coalesce((f->>'total')::numeric, 0),
    coalesce((f->>'provision_gratificacion')::numeric, 0),
    coalesce((f->>'provision_bonif_extraordinaria')::numeric, 0),   -- CAMBIO 0134
    coalesce((f->>'provision_cts')::numeric, 0),
    coalesce((f->>'provision_vacaciones')::numeric, 0),
    coalesce((f->>'provision_total')::numeric, 0),
    f
  from jsonb_array_elements(coalesce(v_calc->'filas', '[]'::jsonb)) f
  left join personas pe on pe.id = (f->>'persona_id')::uuid;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (283, 'no_se_cierra_el_mes_con_una_hora_que_nadie_marco')
on conflict (numero) do nothing;
