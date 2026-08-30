-- ============================================================================
-- 0326 — Un marcaje sin revisar tampoco cierra el mes
-- ============================================================================
--
-- QUÉ PROMETE
--   Que un periodo de planilla no se pueda congelar mientras queden marcajes
--   `pendiente_revision` dentro de las fechas de ESE periodo, PARA EL GRUPO
--   que se está congelando. Es el tercer freno de `fn_planilla_congelar`,
--   junto a la liquidación ya cobrada (0243/0244) y la hora que puso el
--   auto-cierre sin confirmar (0284).
--
-- QUÉ ASUME
--   · Que `fn_planilla_congelar` es la de la 0323 (4 argumentos, con
--     `p_grupo`), no la de la 0284 (3 argumentos) — ver el aviso de abajo.
--   · Que `marcajes.fecha_jornada` (0240) es la fecha correcta para decidir a
--     qué periodo pertenece un marcaje que cruza medianoche, y que
--     `fn_fecha_de_jornada(timestamp_marca, fecha_jornada)` (0307) es la
--     única función que la resuelve — se reusa tal cual.
--   · Que `marcajes.estado_revision = 'pendiente_revision'` (0001) es la
--     bandera que `fn_registrar_marcaje` (0320) sella cuando `fn_dia_
--     incoherente` (0082) encuentra una secuencia entrada/salida que no
--     cuadra, o cuando una marca cae en un periodo ya pagado (0207).
--   · Que `personas.tipo_vinculo` (0085) es el dato que dice a qué grupo
--     pertenece cada persona — el mismo que usa la 0323 en sus otros dos
--     frenos, ahí leído de `v_calc->'filas'`; acá se lee directo de
--     `personas` porque esta consulta no pasa por `v_calc`.
--
--   md5 de partida de `fn_planilla_congelar` — PEDIDO A PRODUCCIÓN el
--   2026-08-29, DESPUÉS de que la 0323 se pegó (Felipe confirmó que ya
--   estaba pegada y cerrada antes de escribir esto). Confirmado exacto:
--   tal-cual 7a66a410278e86724092adf360904535, 16359 caracteres.
--
--   ⚠ POR QUÉ ESTA MIGRACIÓN SE ESCRIBIÓ DOS VECES. La primera versión
--   partió de la 0284 (3 argumentos) porque, al empezar, esa era la última
--   definición EN ESTE WORKTREE — la 0323 se fusionó a `main` mientras se
--   escribía. `donde-vive.sh` no lo detectó porque solo mira NÚMEROS, no
--   ARIDAD: un `create or replace function f(a,b,c)` no reemplaza a un
--   `f(a,b,c,d)` — Postgres los trata como dos funciones distintas que
--   coexisten. La primera versión habría creado una tercera sobrecarga muerta,
--   a la que nada llama (la 0323 ya actualizó a `fn_periodo_pagado`,
--   `fn_repagar_periodo` y `fn_planilla_congelar_pendientes` para llamar con
--   4 argumentos), dando la falsa sensación de que el freno existe cuando en
--   los hechos ninguna llamada real pasaría por él. Se cazó ANTES de pegar
--   nada, comparando el md5 de partida contra producción — la misma
--   disciplina que ya documentan la 0286 y la 0289, aplicada esta vez a un
--   cambio de ARIDAD en vez de a un cambio de NÚMERO. Lección para la próxima
--   vez que dos migraciones toquen la misma función: `donde-vive.sh` avisa de
--   colisiones de número, no de firma — mirar también si el `create or
--   replace` de la más nueva declara los mismos argumentos que el de la
--   anterior.
--
-- ── LO QUE HAY HOY, MEDIDO ANTES DE ESCRIBIR ESTO ───────────────────────────
--
-- Contra producción, el 2026-08-29:
--   · Periodo abierto: 29/07/26 → 28/08/26.
--   · CERO día(s)-persona pendientes en ESE periodo — a nadie afectaría pegar
--     esto hoy, el mes sigue cerrando igual que ahora.
--   · 2 día(s)-persona pendientes en total, contando todo el histórico — y
--     esos caen fuera del periodo abierto, así que ninguno de los dos frena
--     nada: el alcance de este freno es a propósito solo el periodo que se
--     está cerrando, no arrastre.
--
-- ── EL DEFECTO ──────────────────────────────────────────────────────────────
--
-- `fn_planilla_congelar` ya frena por `jornadas.estado = 'auto_cerrada_
-- pendiente'` (0284) — pero esa es otra bandera, sobre otra tabla, para otro
-- problema (una salida que el sistema inventó). `pendiente_revision` vive en
-- `marcajes` y se sella cuando la SECUENCIA de marcajes de un día no tiene
-- sentido — dos entradas seguidas, una salida sin entrada, etc. — algo que
-- una persona marcó de verdad, pero en un orden que el sistema no sabe leer.
--
-- La propia 0284 lo dice en su cabecera, citando una medición del
-- 2026-08-23: «Que no se pierde nada por ahí está medido [...] todo marcaje
-- sin revisar tenía su jornada en `auto_cerrada_pendiente`» — una
-- coincidencia observada un día, no una garantía estructural. Nada en el
-- código ata las dos banderas entre sí: un día puede tener una secuencia
-- incoherente sin haber pasado nunca por el auto-cierre (dos entradas
-- seguidas por ejemplo, sin ninguna salida de por medio que el cron necesite
-- inventar), y ese día se paga con las horas que la secuencia rota deje
-- calcular, sin que nadie lo haya mirado.
--
-- ── POR QUÉ AQUÍ Y NO EN `fn_planilla_calcular` ─────────────────────────────
--
-- Mismo argumento que la 0284: esa función pesa decenas de miles de
-- caracteres y calcula todos los sueldos — no es el sitio para agregar un
-- freno de cierre. `fn_planilla_congelar` ya es el cuello por el que pasan
-- `fn_periodo_pagado`, `fn_repagar_periodo` y `fn_planilla_congelar_
-- pendientes` (los tres actualizados por la 0323 para pasar `p_grupo`); un
-- tercer freno ahí hereda las tres puertas sin tocar ninguna.
--
-- ── FILTRADO POR `p_grupo`, IGUAL QUE LOS OTROS DOS FRENOS DE LA 0323 ──────
--
-- Un marcaje pendiente de alguien de RxH no puede frenar congelar planilla,
-- y viceversa: cada grupo se congela con SUS propios pendientes, ni más ni
-- menos, mismo criterio que ya aplican el freno de la liquidación y el de la
-- hora inventada desde la 0323.
--
-- ── EL RETROACTIVO SE AVISA, NO SE FRENA (a propósito, igual que 0243/0284) ──
--
-- `fn_planilla_congelar_pendientes` (0096, actualizada por la 0323 para
-- recorrer cada grupo con gente en el periodo) recongela periodos históricos
-- que nunca tuvieron foto — de antes de que este sistema existiera. Es
-- razonable, y hasta probable, que haya marcajes viejos sellados
-- `pendiente_revision` que nadie va a revisar nunca porque el mes ya se pagó
-- hace tiempo. Frenar ahí rompería el backfill histórico entero, que es
-- exactamente la lección que costó escribir la 0244. Este freno usa el mismo
-- interruptor (`p_origen = 'retroactivo'`) que los otros dos.
--
-- ── CÓMO SE REVIERTE ────────────────────────────────────────────────────────
--
--   Pegar el cuerpo de `fn_planilla_congelar` de la 0323 (líneas 312-589 de
--   ese archivo). No toca datos, no toca tablas: revertir no pierde nada.
--
-- ============================================================================


-- ── 0 · Comprobar ANTES de tocar nada ────────────────────────────────────────
-- Mismo patrón que la 0323: si producción no está en la versión de partida
-- declarada arriba, esta migración no aplica NADA.
do $$
declare v_md5 text; v_len int;
begin
  select md5(p.prosrc), length(p.prosrc) into v_md5, v_len
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_planilla_congelar' and p.pronargs = 4;
  if v_md5 is distinct from '7a66a410278e86724092adf360904535' then
    raise exception '0326 · PARA. fn_planilla_congelar(4 args) en esta base es % (% caracteres), se esperaba 7a66a410278e86724092adf360904535 (16359, el cuerpo de la 0323). No se aplicó nada. Compruébalo con ./scripts/donde-vive.sh fn_planilla_congelar.', v_md5, v_len;
  end if;
end
$$;


CREATE OR REPLACE FUNCTION public.fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid, p_grupo text DEFAULT 'planilla')
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
  v_pendientes text;   -- CAMBIO 0284
  v_sin_revisar text;   -- CAMBIO 0326
begin
  -- CAMBIO 0323 · esta función ahora congela UN grupo a la vez, no el
  -- periodo entero. p_grupo decide qué personas de `v_calc->'filas'` entran.
  if p_grupo not in ('planilla','prueba','rxh','no_trabajador','practicante') then
    raise exception 'Grupo inválido: %. Los válidos son planilla, prueba, rxh, no_trabajador, practicante.', p_grupo;
  end if;

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
  --
  -- CAMBIO 0323 · `f->>'tipo_vinculo' = p_grupo` en las tres consultas de este
  -- freno y del siguiente: un pendiente o una liquidación de OTRO grupo no
  -- debe frenar congelar este.
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
      and f->>'tipo_vinculo' = p_grupo   -- CAMBIO 0323
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

  -- ── CAMBIO 0284 · el freno de la hora que nadie marcó ───────────────────────
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
      and f->>'tipo_vinculo' = p_grupo   -- CAMBIO 0323
  ) x;

  if v_pendientes is not null then
    -- Una sola frase corrida, sin saltos de línea, por lo mismo que la 0244:
    -- la pantalla imprime el texto de un P0001 tal cual (mensaje-error.ts:81).
    if p_origen = 'retroactivo' then
      -- Misma razón que la rama retroactiva de la 0244:
      -- `fn_planilla_congelar_pendientes` (0096) documenta meses transferidos
      -- hace años. Abortar ahí dejaría los periodos históricos sin foto para
      -- siempre — está medido en la cabecera de la 0244.
      raise warning '0284 · foto retroactiva con días auto-cerrados sin revisar: %. No se frena —ese mes se pagó hace tiempo— pero conviene mirarlo.', v_pendientes;
    elsif v_per.estado = 'abierto' then
      raise exception 'Hay días cuya hora de salida la puso el sistema y todavía nadie la confirmó: %. Esa hora no la marcó ninguna persona, y si cruza las 48 h de la semana se paga recargo sobre ella. Entra a Correcciones, confirma o corrige esas salidas, y vuelve a cerrar. El periodo sigue ABIERTO: no se congeló nada.', v_pendientes;
    else
      raise exception 'Hay días cuya hora de salida la puso el sistema y nadie la confirmó: %. Este periodo ya está PAGADO, así que para arreglarlo hay que usar «Revertir pago» con su motivo (ojo, eso levanta los candados de los marcajes de este periodo mientras esté abierto), confirmar esas salidas en Correcciones, y volver a marcarlo como pagado. Nada se congeló: la foto anterior sigue intacta.', v_pendientes;
    end if;
  end if;
  -- ── fin CAMBIO 0284 ─────────────────────────────────────────────────────────

  -- ── CAMBIO 0326 · el freno del marcaje sin revisar ──────────────────────────
  --
  -- `pendiente_revision` (0001) es una bandera de `marcajes`, no de `jornadas`.
  -- `fn_registrar_marcaje` (0320) la sella cuando `fn_dia_incoherente` (0082)
  -- encuentra una secuencia entrada/salida que no cuadra —dos entradas
  -- seguidas, una salida sin entrada— o cuando una marca cae en un periodo ya
  -- pagado (0207). Es un problema distinto al de la 0284: ahí la hora la puso
  -- el sistema; aquí la marcó una persona, pero en un orden que el sistema no
  -- sabe leer solo.
  --
  -- Se agrupa por persona y por día (`fn_fecha_de_jornada`, 0307, la misma
  -- función que ya resuelve el cruce de medianoche en las correcciones —no
  -- una copia nueva del mismo cálculo), contando días distintos con al menos
  -- un marcaje pendiente, no marcajes sueltos: dos marcas pendientes del
  -- mismo día son un solo día por revisar, igual que cuenta la 0284.
  --
  -- FILTRADO POR `p_grupo` (`p.tipo_vinculo = p_grupo`, directo de `personas`
  -- — esta consulta no pasa por `v_calc`, así que no hay `f->>'tipo_vinculo'`
  -- del que leer): mismo criterio que los otros dos frenos desde la 0323, un
  -- pendiente de otro grupo no frena congelar este.
  --
  -- SOLO EL PERIODO QUE SE ESTÁ CERRANDO: se filtra contra
  -- `v_per.fecha_ini .. v_per.fecha_fin`, nunca contra el histórico completo
  -- — arrastre de periodos ya cerrados no bloquea este cierre, y `/admin/
  -- correcciones` (`fn_dias_por_revisar`, 0321) sigue siendo el lugar para
  -- verlos todos, resueltos o no.
  select case when count(*) = 0 then null
              else string_agg(x.frase, ' · ' order by x.frase)
                     filter (where x.rn <= 6)
                   || case when count(*) > 6
                           then ' · y ' || (count(*) - 6)::text || ' más'
                           else '' end
         end into v_sin_revisar
  from (
    select y.nombre || ' (' || y.dias || ' día(s))' as frase,
           row_number() over (order by y.nombre) as rn
    from (
      select (p.nombres || ' ' || p.apellidos) as nombre,
             count(distinct fn_fecha_de_jornada(m.timestamp_marca, m.fecha_jornada)) as dias
      from marcajes m
      join personas p on p.id = m.persona_id
      where m.estado_revision = 'pendiente_revision'
        and m.anulada_at is null
        and p.tipo_vinculo = p_grupo   -- CAMBIO 0326, mismo criterio que la 0323
        and fn_fecha_de_jornada(m.timestamp_marca, m.fecha_jornada)
              between v_per.fecha_ini and v_per.fecha_fin
      group by p.id, p.nombres, p.apellidos
    ) y
  ) x;

  if v_sin_revisar is not null then
    -- Una sola frase corrida, sin saltos de línea, por lo mismo que la 0244 y
    -- la 0284: la pantalla imprime el texto de un P0001 tal cual
    -- (mensaje-error.ts:81).
    if p_origen = 'retroactivo' then
      -- Mismo interruptor y misma razón que 0243/0244 y 0284: recongelar
      -- historia vieja no puede depender de que alguien revise hoy un
      -- marcaje de hace meses. Abortar aquí rompería
      -- `fn_planilla_congelar_pendientes` (0096) para siempre.
      raise warning '0326 · foto retroactiva con marcajes sin revisar: %. No se frena —ese mes se pagó hace tiempo— pero conviene mirarlo.', v_sin_revisar;
    elsif v_per.estado = 'abierto' then
      raise exception 'Hay marcajes sin revisar en este periodo: %. Una secuencia de entrada/salida no cuadra ese día, y sus horas se están calculando con ese hueco. Entra a Correcciones, revisa esos marcajes, y vuelve a cerrar. El periodo sigue ABIERTO: no se congeló nada.', v_sin_revisar;
    else
      raise exception 'Hay marcajes sin revisar en este periodo: %. Este periodo ya está PAGADO, así que para arreglarlo hay que usar «Revertir pago» con su motivo (ojo, eso levanta los candados de los marcajes de este periodo mientras esté abierto), revisar esos marcajes en Correcciones, y volver a marcarlo como pagado. Nada se congeló: la foto anterior sigue intacta.', v_sin_revisar;
    end if;
  end if;
  -- ── fin CAMBIO 0326 ─────────────────────────────────────────────────────────

  -- CAMBIO 0323 · el version es por (periodo, grupo), no por periodo a secas.
  select coalesce(max(version), 0) + 1 into v_ver
  from planilla_pagada_detalle where periodo_id = p_periodo_id and grupo = p_grupo;

  insert into planilla_pagada_detalle (
    periodo_id, grupo, persona_id, version, congelada_por, origen,
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
    p_grupo,   -- CAMBIO 0323
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
  left join personas pe on pe.id = (f->>'persona_id')::uuid
  where f->>'tipo_vinculo' = p_grupo;   -- CAMBIO 0323

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

insert into migraciones_aplicadas (numero, nombre)
values (326, 'un_marcaje_sin_revisar_tampoco_cierra_el_mes')
on conflict (numero) do nothing;
