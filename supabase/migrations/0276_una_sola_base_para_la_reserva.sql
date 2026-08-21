-- ============================================================================
-- 0276 — Una sola base para la reserva
-- ============================================================================
--
-- QUÉ PROMETE
--   Que la base sobre la que se PAGA y la base sobre la que se RESERVA vuelvan
--   a ser la misma, calculada en un solo sitio. Hoy son dos, y se separan por
--   dos motivos distintos:
--
--     · EL FERIADO. La boleta lo calcula en un lateral de 70 líneas dentro de
--       `fn_planilla_calcular`; en las 610 líneas de `fn_provisiones` la
--       palabra «feriado» aparece CERO veces.
--     · EL FACTOR DE LA 0111. `base_provision / salario` aparece diez veces en
--       `fn_planilla_calcular` y ninguna en `fn_provisiones`.
--
--   Desde esta migración el feriado lo responde una función nueva a la que
--   preguntan las dos, `fn_feriado_devengado`, y el factor se aplica también en
--   la reserva —una vez, envolviendo su base entera—.
--
--   Consecuencia con plata dentro: la gratificación, la CTS y las vacaciones
--   que reserva la pantalla de Provisiones —y que `fn_grati_cts_periodo` (0088)
--   AUTOCOMPLETA como monto a depositar el 15/05, 15/07, 15/11 y 15/12— pasan a
--   incluir el feriado y a respetar la base_provision. Hoy se deposita corto,
--   siempre.
--
-- LAS DOS MITADES DEL FERIADO ENTRAN, Y NO SE PREGUNTA POR REGULARIDAD
--   · el día prorrateado (art. 8 del D. Leg. 713, que remite al art. 4 del
--     D.S. 012-92-TR): es remuneración ordinaria y nunca estuvo en discusión.
--   · la sobretasa por trabajarlo (art. 9 del D. Leg. 713): es variable, así
--     que le aplica el test de regularidad del art. 16 del D.S. 001-97-TR
--     —haberse percibido en tres meses del semestre—. Medido sobre la tabla
--     `feriados` (112 fechas, de 2026 a 2032): las 27 ventanas semestrales que
--     caben enteras en ese tramo —14 de gratificación y 13 de CTS— tienen
--     feriados en 4 o 5 meses distintos, NUNCA menos de 4. Solo mirando las de
--     gratificación: 14 ventanas, mínimo 4 meses, máximo 5. El test de
--     regularidad lo pasa SIEMPRE, y con margen. Así que
--     un `if` de regularidad sería código muerto que algún día devolvería false
--     por un bug y le quitaría plata a alguien sin que nadie lo vea. No se
--     escribe.
--
-- LO YA PAGADO CORTO NO SE ESCONDE
--   ⚠ La CTS del 15/05/2026 y la gratificación del 15/07/2026 se depositaron
--   sin feriado. Al subir lo devengado, la resta «devengado − cobrado» que la
--   0273 dejó en un solo sitio devuelve un PENDIENTE POSITIVO para esas dos
--   ventanas. Eso es el reintegro que corresponde, y sale en la pantalla como
--   cualquier otro pendiente. No se le da tratamiento especial: esconderlo
--   sería decidir por Felipe que no se paga. Conviene saberlo ANTES de abrir la
--   pantalla, no descubrirlo ahí.
--
-- ── CÓMO ESTÁ HECHO, Y POR QUÉ ASÍ ──────────────────────────────────────────
--
-- LA FUNCIÓN NUEVA ES UN TRASLADO, NO UNA REESCRITURA. El cuerpo de
-- `fn_feriado_devengado` es el lateral `fer` de la 0275 movido de sitio: las
-- mismas condiciones, en el mismo orden, con los mismos comentarios. Por eso el
-- riesgo para la boleta es el más bajo posible — la boleta pasa de calcular a
-- preguntar, y el jsonb que recibe tiene los mismos campos que construía. La
-- casuística que viaja entera: descanso sustitutorio OTORGADO anula la
-- sobretasa y no el prorrateo (0069) · las horas de vacaciones entran al
-- prorrateo (0177) · las de descanso médico también (0269) · un locador no
-- cobra feriados (0199) · un feriado dentro de una licencia de maternidad
-- subsidiada no se devenga acá porque el lateral `mat` SÍ lo cuenta (0262) ·
-- el sueldo fijo no cobra el día prorrateado pero sí la sobretasa (0173) · un
-- feriado anterior a la fecha de ingreso no cuenta (0024/0027) · el salario
-- sale del tramo vigente ESE día, no del de hoy.
--
-- EL BLOQUE ES EL PARÁMETRO QUE HACE QUE SIRVA A LAS DOS. Un feriado no vale lo
-- mismo en cualquier rango: su prorrateo es
-- `7.5 × horas del bloque / (6.5 × días del bloque)`, y eso NO es invariante de
-- escala. Medido sobre una persona del laboratorio, del 01/04 al 28/08 de
-- 2026: preguntado como UN bloque de 150 días devuelve S/198,10; preguntado sin
-- `p_dias` —cada feriado con el bloque de su periodo, que es lo que su boleta
-- pagó— devuelve S/972,42. Casi cinco veces menos, y con toda la apariencia de
-- estar bien. Por eso `p_dias`:
--   · con `p_dias` → bloque único, el que manda quien llama. La boleta pasa su
--     `v_dias`, que ya trae la corrección de la 0239.
--   · con `p_dias` en null → cada feriado se cobra con el bloque del PERIODO DE
--     PLANILLA en que cayó. O sea: exactamente lo que su boleta pagó ese mes.
--
-- `p_dias` NO TIENE VALOR POR DEFECTO, a propósito. Obliga a que cada llamada
-- diga en qué modo está —el modo equivocado no falla, da un número— y de paso
-- deja la firma en cuatro parámetros, que es lo que la separa de cualquier
-- `fn_feriado_devengado(uuid, date, date)` que otra rama pueda traer.
--
-- EL RESPALDO, CUANDO NO HAY PERIODO, ES EL CICLO 29→28 Y NO EL MES CALENDARIO.
-- Medido borrando de `periodos_planilla` el periodo que contiene el 01/05/2026:
-- con el respaldo por mes calendario la reserva del laboratorio cae S/7,55 (10
-- personas, ~S/0,75 cada una) porque mayo tiene 31 días y el periodo real tiene
-- 30; con el ciclo 29→28 la deriva es S/0,00 EXACTOS. Un respaldo que se
-- equivoca en silencio es peor que uno que falla.
--
-- LAS PROVISIONES LLAMAN UNA VEZ POR PERSONA, NO UNA POR VENTANA. `base` ya es
-- un flujo por día y las cinco ventanas se reparten con un `between`; cada
-- feriado entra con SU fecha y cae solo en la ventana que le toca.
--
-- EL FACTOR DE LA 0111 SE ESCRIBE UNA VEZ, ENVOLVIENDO LA BASE. No cinco veces
-- dentro de las ramas: una expresión repetida en cinco sitios es un olvido
-- pedido, y el olvido no daría error — daría un número. Se busca POR DÍA, con
-- el tramo vigente ese día, y no una vez por persona. La justificación larga
-- está junto al código, en el CTE `base`.
--
-- ── LO QUE SE MIDIÓ ANTES DE DARLO POR BUENO ────────────────────────────────
--
-- Contra el Postgres local, con un laboratorio de 15 personas × 12 periodos de
-- planilla 29→28 (180 boletas) que ejercita la casuística entera: locadora,
-- persona en días de prueba, sueldo fijo que marca y sueldo fijo que no,
-- vacaciones sobre un feriado, descanso médico sobre un feriado, licencia de
-- maternidad subsidiada, descanso sustitutorio OTORGADO / PENDIENTE /
-- NO_OTORGADO, ingreso posterior al feriado, cambio de tramo a mitad de año,
-- `base_provision` distinta del salario, domingo laborable (TRU) y el periodo
-- raro de marzo de 2026.
--
--   · LA BOLETA NO SE MOVIÓ. Se capturó la fila jsonb ENTERA de las 180 boletas
--     con la 0275 y con esta, y se comparó campo por campo:
--     **0 campos distintos**. El ÚNICO cambio observable en la salida es una
--     clave NUEVA dentro de cada elemento de `feriados_detalle`:
--
--         'monto'  →  el prorrateo + la sobretasa de ESE feriado, sin redondear
--
--     Se declara acá porque es lo único que un diff de la boleta va a mostrar y
--     nadie debería descubrirlo leyéndolo. La pantalla no la lee (el panel usa
--     `fecha`, `antes_ingreso`, `horas_trabajadas` y `proporcional_horas`) y
--     `fn_planilla_foto_diferencias` compara solo `total`.
--
--   · EL REDONDEO SE MIDIÓ Y COSTÓ DOS INTENTOS. La primera versión devolvía
--     `monto` ya redondeado a dos decimales. La boleta muestra
--     `round(fer.monto, 2)` pero mete el número CRUDO en la base de provisión,
--     así que redondear dentro movía la provisión en céntimos. La función
--     devuelve el monto sin redondear y quien muestra redondea.
--
--   · CUÁNTO SUBE LA RESERVA. En el laboratorio, el gran total de Provisiones
--     pasó de S/24.219,33 a S/25.602,84: +S/1.383,51 (+5,71 %), repartido en
--     grati_s1 +417,57 · grati_s2 +244,34 · cts_may +113,36 · cts_nov +217,62 ·
--     vacaciones +331,01. Y donde sale del banco: la gratificación que
--     `fn_grati_cts_periodo` autocompleta al cerrar el periodo del 15/07/2026
--     pasa de S/8.139,01 a S/8.556,58 (+S/417,57, +5,13 %).
--     ⚠ Ese porcentaje es DEL LABORATORIO, donde casi todas trabajan casi todos
--     los feriados. En producción la sobretasa pesa menos. El número real de
--     CAYLA hay que pedírselo a producción ANTES de aplicar esto.
--
--   · EL FACTOR DE LA 0111 ARRANCA INERTE. `base_provision` nace en NULL, el
--     factor sale 1 y ninguna reserva se mueve: comparado contra la misma
--     función sin el envoltorio, 0 celdas distintas. Con `base_provision`
--     encendida, boleta y reserva se mueven EXACTAMENTE lo mismo (medido:
--     119,42 → 143,30 en las dos, con factor 1,2).
--
--   · LO QUE CUESTA. `fn_provisiones` pasó de 25 ms a 41 ms (13 personas, año y
--     medio de jornadas). `fn_planilla_calcular` pasó de 4,5 ms a 19 ms por
--     periodo, porque cada persona hace ahora una llamada plpgsql propia en vez
--     de compartir el escaneo de `jornadas`. En absoluto sigue siendo
--     invisible: la boleta se calcula para un periodo por vez.
--
--   · LAS PRUEBAS. `npx supabase db reset` seguido de `npx supabase test db`:
--     137 archivos, 1.339 pruebas, todo en verde. Y al revés — con
--     `fn_provisiones` devuelta a la 0274 y `fn_planilla_calcular` a la 0275,
--     la prueba 213 se pone roja en 9 de sus 24 aserciones. Un freno que no se
--     rompe cuando lo que vigila se rompe no es un freno.
--
-- ── LO QUE ESTA MIGRACIÓN NO CIERRA ─────────────────────────────────────────
--
-- Este apartado se reescribió el 2026-08-20, después de que tres verificadores
-- hostiles midieran la migración. La versión anterior decía que quedaba UNA
-- diferencia. Quedan CUATRO, y una de ellas ni siquiera es entre las dos bases
-- que este archivo unifica. Se dejan escritas con su medición para que nadie
-- —ni la siguiente sesión, ni quien lea el título— crea que el trabajo está
-- hecho. El título promete «una sola base»: hoy son DOS, no una.
--
--   1 · EL DIVISOR DEL SUELDO. La boleta divide entre los días del PERIODO
--       (29→28) y las cuatro ramas viejas de `fn_provisiones` entre los días
--       del MES CALENDARIO. Las dos bases solo coinciden al céntimo cuando el
--       periodo y el mes son el mismo tramo — y por eso el laboratorio de la
--       213 los hace coincidir a propósito. Medido sobre un ciclo 29→28 real
--       (2026-03-29 → 2026-04-28), las aserciones 1 y 2 no se cumplirían para
--       ninguno de los once perfiles: −2,5 % en tienda, −5,7 % con descanso
--       médico, −30,6 % en maternidad.
--
--   2 · EL DÍA DE AUSENCIA PAGADA. Es MAYOR que el divisor y no estaba escrito.
--       La boleta paga la ausencia solo por los días LABORABLES y a la tarifa
--       promedio de los días marcados; la rama 4 de `base` paga TODOS los días
--       CALENDARIO a `salario / días del mes`. Y la boleta le pone además dos
--       filtros que la rama 4 no tiene: el tope de 20 días del descanso médico
--       (0263) y la exclusión de los días que se solapan con vacaciones.
--       Medido con el divisor neutralizado: S/178,93 en un mes para quien tuvo
--       19 días de vacaciones. Lo ÚNICO que esta migración arregla de aquí es
--       el feriado duplicado dentro del descanso médico, porque ese lo rompía
--       ella misma; el resto es anterior y sigue abierto.
--
--   3 · EL FACTOR DE LA 0111, EN EL BORDE. Llega a las dos bases, pero por
--       reglas distintas: acá se busca DÍA A DÍA con el tramo vigente ese día
--       y la boleta usa el del ÚLTIMO tramo del periodo. Da igual mientras
--       `base_provision` no cambie a mitad de periodo; en cuanto cambie, los
--       dos números se separan entre −6,2 % y +13,1 % (medido). La elección de
--       acá es la deliberada —esta función acumula sobre años y la
--       simplificación del último tramo no vale— pero entonces la promesa de
--       una sola base no alcanza a esta mitad.
--
--   4 · LA LIQUIDACIÓN POR CESE NO USA NINGUNA DE LAS DOS. Ésta es la que más
--       importa y la que la primera versión de este encabezado callaba. Las
--       truncas bajan a una TERCERA base, `fn_remuneracion_computable` (0129),
--       a la que el feriado NO PUEDE LLEGAR: su único canal de conceptos
--       variables es `movimientos_planilla`, y el feriado no se escribe ahí
--       jamás. O sea que esta migración cierra la separación entre la boleta y
--       la reserva y deja abierta la que va de la reserva al cese.
--
--       Y para el SUELDO FIJO le cambia el signo. Medido, salario S/1.950,
--       mirado al 30/06/2026: antes la reserva daba S/974,96 contra S/975,00
--       de la liquidación —cuatro céntimos—; después la reserva pasa a
--       S/1.001,52 y la liquidación se queda en S/975,00. La brecha pasa de
--       S/−0,04 a S/+26,52. El mismo beneficio vale dos cifras distintas según
--       se cobre el 15/07 o se cese el 30/06.
--
--       Se entrega así a sabiendas, por decisión de Felipe del 2026-08-20: lo
--       que ya está costando plata es el depósito corto de los cuatro pagos
--       del año (~S/2.400 anuales, siempre en contra del equipo), y eso es lo
--       que esta migración cierra. La brecha del cese es de ~S/26 por caso y
--       en el otro sentido. Arreglarla exige entrar en
--       `fn_remuneracion_computable`, que además arrastra un defecto propio y
--       anterior —suma los `movimientos_planilla` con `monto > 0` sin filtrar
--       categoría ni tipo, así que un adelanto quincenal, que es dinero que la
--       persona debe, le SUBE la liquidación—. Eso va en migración aparte,
--       para que las dos se puedan revertir por separado.
--
-- Tampoco cierra la duplicación de los laterales `vacd`, `dmd` y `labp`
-- —quedan escritos en los dos sitios porque `pb` los sigue necesitando para
-- `monto_vacaciones` y `monto_descanso_medico`—.
--
-- QUÉ ASUME
--   · Que la versión de partida de `fn_planilla_calcular` es la **0269** y la
--     de `fn_provisiones` la **0274**, confirmadas con `./scripts/donde-vive.sh`.
--     Los dos cuerpos NO se copiaron a ojo: se extrajeron de sus archivos por
--     reemplazo de cadena EXACTA y ÚNICA con un script que aborta si el ancla
--     no aparece el número exacto de veces.
--
--   · md5 DE PARTIDA, medidos en el Postgres LOCAL con todas las migraciones
--     anteriores aplicadas —la 0275 no existe en este árbol, se la llevó otra
--     sesión— (`select md5(prosrc), length(prosrc) from pg_proc where
--     proname = …`):
--
--       fn_planilla_calcular  b132c828fde4aa5fedd6cf946fee7f08   90 707 chars
--       fn_provisiones        84aae8bf6905f372d08a49b2056c3c3b   28 118 chars
--
--     ⚠ ESTOS DOS NÚMEROS SON LA SEGUNDA VERSIÓN, Y LA PRIMERA CASI CUESTA UN
--     SUELDO. El 2026-08-20 esta migración se escribió declarando
--     `5e755bdedd964d289104e824eb2925ec` / 89 527 para la boleta, que era lo
--     que devolvía el Postgres local — construido sin la **0275**, que otra
--     sesión ya había fusionado a `main` y Felipe ya había pegado. El cuerpo
--     de partida era el de la 0269, dos versiones atrás.
--
--     Pegarla así habría revertido la 0275 EN SILENCIO: quien pasa el periodo
--     entero de vacaciones habría vuelto a cobrar **S/ 0.00** su mes. No da
--     error: corre y devuelve otro número. Lo cazó pedirle el md5 a
--     producción —90 707 caracteres allá contra 89 527 acá— y lo confirmó la
--     prueba 212, que falló en sus tres aserciones de vacaciones.
--
--     Ni `donde-vive.sh` ni `db reset` podían verlo: los dos miran el
--     worktree. Desde entonces avisa
--     `scripts/hooks/main-tiene-migraciones-que-no-tienes.sh`.
--
--     ⚠ SON DEL LOCAL, NO DE PRODUCCIÓN. La regla de la casa es que el md5 de
--     partida se le pide a producción en el SQL Editor y se espera la respuesta
--     ANTES de pegar nada — si se pega primero, el número se pierde para
--     siempre. Se pide así, en un solo select:
--
--       select proname, md5(prosrc), length(prosrc) from pg_proc
--        where proname in ('fn_planilla_calcular','fn_provisiones');
--
--     Si producción devuelve otros md5, PARAR: significa que allá hay una
--     versión que este repo no tiene, y esta migración la pisaría en silencio.
--
--   · md5 DESPUÉS, para comprobar que quedó lo que se quería (mismo local):
--
--       fn_feriado_devengado  f6bbe9ab3b4ce9d6e449a0068ea771ec   12 355 chars
--       fn_planilla_calcular  2f38e5ce76bcb22164cd0794671b349f   86 490 chars
--       fn_provisiones        93531851f35abcdd295fd8fb4aa77922   33 892 chars
--
--     (Este último cambió el 2026-08-20 respecto a la primera versión de esta
--      migración —era 40d40a93… con 32 218 chars—, al añadirse la exclusión del
--      feriado dentro del descanso médico. Ver el apartado de más abajo.)
--
-- CÓMO SE REVIERTE
--   Restaurar `fn_planilla_calcular` desde la **0275** —NO desde la 0269, que
--   es la trampa que casi se traga esta migración— y `fn_provisiones` desde la
--   0274, tal cual, y `drop function fn_feriado_devengado(uuid,date,date,int)`.
--   No toca tablas, ni datos, ni permisos de tabla. Revertir devuelve la
--   reserva al número corto de hoy — y hace que la prueba 213 se ponga roja,
--   que es lo que tiene que pasar.
--
-- CÓMO SE COMPRUEBA QUE QUEDÓ BIEN
--   La consulta del final: para cada persona y cada periodo, el
--   `monto_feriados` de la boleta contra `fn_feriado_devengado`. Tiene que dar
--   0 filas. La prueba 213 deja esa misma comparación escrita para siempre —
--   junto con la que de verdad importa, que compara la gratificación que
--   IMPRIME la boleta contra la que RESERVA la pantalla, al céntimo.
-- ============================================================================

create or replace function public.fn_feriado_devengado(
  p_persona uuid,
  p_desde   date,
  p_hasta   date,
  p_dias    int
) returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
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
  -- Un feriado se paga DENTRO de un bloque, y el bloque decide el divisor y las
  -- horas. Con p_dias el bloque lo manda quien llama (la boleta pasa su v_dias);
  -- sin p_dias el bloque es el periodo de planilla al que pertenece el feriado
  -- —el mismo en que la boleta lo pagó—.
  --
  -- EL RESPALDO, CUANDO ESE PERIODO NO EXISTE, NO ES EL MES CALENDARIO. Es el
  -- ciclo 29→28 que CAYLA usa de verdad, reconstruido a partir de la fecha del
  -- feriado. La diferencia no es teórica: medido borrando de
  -- `periodos_planilla` el periodo que contiene el 01/05/2026, el respaldo por
  -- mes calendario deja la reserva del laboratorio S/7,55 MÁS BAJA (10 personas
  -- reservando, ~S/0,75 cada una) —mayo tiene 31 días y el periodo real tiene
  -- 30— y lo hace en silencio, con toda la apariencia de estar bien. Con el
  -- ciclo 29→28 la deriva es S/0,00 EXACTOS. `periodos_planilla` sigue mandando
  -- siempre que exista: esto es el respaldo, no la regla.
  --
  -- FEBRERO ES EL ÚNICO MES QUE NO TIENE 29 SIEMPRE, y por eso el `least`: en
  -- un febrero de 28 días el ciclo arranca el 28. Ese día queda entonces en dos
  -- ciclos (cierra el de enero y abre el de febrero), pero cada FERIADO se
  -- asigna a uno solo —el `case` de arriba decide por su día del mes— así que
  -- nada se cuenta dos veces.
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
  -- Las horas equivalentes del bloque: las marcadas más las de las ausencias
  -- pagadas que la ley manda contar como trabajadas. Es literal lo que hoy le
  -- llega al lateral `fer` desde `h` y `pb`.
  bloque as (
    select distinct b.b_ini, b.b_fin, b.b_dias, 6.5 * b.b_dias as v_base
    from fer_bloque b
  ),
  horas_bloque as (
    select bq.b_ini, bq.b_fin, bq.b_dias, bq.v_base,
           coalesce(hh.horas_totales, 0) as horas_mes,
           -- ⇩⇩⇩ EL RESPALDO DE LA 0275, Y POR QUÉ ESTÁ ESCRITO ACÁ ⇩⇩⇩
           --
           -- Las dos expresiones de abajo se ven casi iguales y durante unas
           -- horas NO lo fueron: la de descanso médico tenía su respaldo desde
           -- la 0254 y la de vacaciones no, porque el de vacaciones nació el
           -- 2026-08-19 con la 0275 y esta función se copió de un cuerpo
           -- anterior. Sin él, quien pasa el periodo ENTERO de vacaciones no
           -- tiene días marcados, el promedio es 0/0, y el prorrateo de su
           -- feriado sale en cero. Lo cazó la prueba 212 —«el feriado de quien
           -- está de vacaciones se prorratea: las horas también tienen
           -- respaldo»—, que es de la otra sesión, no de esta.
           --
           -- Que las dos estén juntas y con la misma forma es a propósito: la
           -- próxima vez que alguien toque una, la de al lado le recuerda que
           -- son la misma regla.
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
    -- Días de vacaciones que además le tocaba trabajar (0177 / 0186)
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
        and case when hv.horario_por_dia is not null
                 then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                 else extract(dow from d.d)::int = any(hv.dias_laborables) end
    ) vacd on true
    -- Días de descanso médico que CAYLA paga (0254 / 0263)
    left join lateral (
      select count(*)::int as dias
      from (
        select dd.d::date as dia,
               row_number() over (partition by extract(year from dd.d) order by dd.d) as n
        from ausencias a
        join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
        where a.persona_id = pe.id and a.tipo = 'descanso_medico' and a.anulada_at is null
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
        and not exists (select 1 from feriados f where f.fecha = dm.dia)
        and not exists (select 1 from vacaciones v
                         where v.persona_id = pe.id
                           and dm.dia between v.fecha_inicio and v.fecha_fin)
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
           -- prorrateo: el día de feriado, proporcional a lo devengado en el bloque
           case when pe.en_planilla and tt.salario is not null and fb.fecha >= pe.fecha_ingreso
                then (case when pe.sueldo_fijo then 0
                           else 7.5 * (hb.horas_mes + hb.horas_vacaciones + hb.horas_descanso_medico)
                                / hb.v_base end) * tt.salario / hb.v_base
                else 0 end as prorrateo,
           -- sobretasa: el pago EXTRA por haberlo trabajado. El descanso
           -- sustitutorio OTORGADO la anula; PENDIENTE y NO_OTORGADO pagan.
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
        and a.vigente_desde <= fb.fecha
        and (a.vigente_hasta is null or a.vigente_hasta >= fb.fecha)
      order by a.vigente_desde desc limit 1
    ) tt on true
    left join jornadas hf on hf.persona_id = pe.id and hf.fecha = fb.fecha
    left join lateral (
      select true as otorgado, d.fecha_descanso_sustitutorio as fecha_descanso
      from feriados_descanso_sustitutorio d
      where d.persona_id = pe.id and d.fecha_feriado = fb.fecha and d.estado = 'OTORGADO'
      limit 1
    ) ds on true
    -- 0262 · un feriado dentro de una licencia de maternidad subsidiada no se
    -- devenga acá: lo cubre el subsidio, y el lateral `mat` de la boleta SÍ lo
    -- cuenta. Quitarlo de los dos lados dejaría el día sin pagar por nadie.
    where not exists (
      select 1 from ausencias a
      where a.persona_id = pe.id and a.tipo = 'maternidad' and a.anulada_at is null
        and a.subsidio_diario is not null
        and fb.fecha between a.fecha_inicio and a.fecha_fin
    )
  )
  select jsonb_build_object(
    -- SIN REDONDEAR, a proposito. La boleta ya hace `round(fer.monto, 2)` donde
    -- lo muestra, pero mete el numero CRUDO en la base de provision. Redondear
    -- aca mueve esa base y con ella la provision, en centimos.
    --
    -- Medido con la version que redondea dentro: 11 celdas de 410 movidas S/0.01
    -- en el laboratorio de la sesion que escribio esto, y 0 de 180 en el de la
    -- que lo audito. Que un laboratorio no lo pille no lo vuelve seguro — solo
    -- significa que ninguno de sus 180 numeros cayo en el borde. Devolver el
    -- crudo no puede mover nada; redondear si puede. Quien muestre, redondea.
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
        'monto', prorrateo + sobretasa,   -- crudo: quien muestre, redondea
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

-- El feriado no lo pregunta nadie de fuera: lo preguntan fn_planilla_calcular
-- y fn_provisiones, que ya corren como SECURITY DEFINER de postgres. Menos
-- superficie es menos que auditar.
revoke execute on function public.fn_feriado_devengado(uuid, date, date, int) from public;

-- ── La boleta: el lateral `fer` sustituido por la llamada ───────────────────

CREATE OR REPLACE FUNCTION public.fn_planilla_calcular(p_ini date, p_fin date, p_periodo_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dias int; v_base numeric;
  v_dias_periodo int;                        -- CAMBIO 0239
  v_feriados jsonb; v_out jsonb; v_prov jsonb;
  v_f_grati numeric; v_f_cts numeric; v_f_vacas numeric;
  v_f_be numeric;   -- CAMBIO 0134: tasa de la bonificacion extraordinaria
  v_asig numeric; v_anio int; v_mes int;
  v_movilidad numeric; v_tasa_afp numeric;   -- CAMBIO 0110
  v_tope_dm int;   -- CAMBIO 0254
  v_exige_decl numeric;                      -- CAMBIO 0159
  v_sexto_cts numeric;                       -- CAMBIO 0112
  v_rmv numeric; v_tasa_essalud numeric;     -- CAMBIO 0116
  v_tasa_4ta numeric; v_tope_4ta numeric;    -- CAMBIO 0245
begin
  -- ⚠️ ESTE GUARD ES DE LA 0090 Y NO SE TOCA NUNCA.
  -- La 0076 abrió esta función a cualquier sesión con login —el terminal de
  -- tienda incluido— al conceder permisos en masa, y la 0090 lo cerró poniendo
  -- la comprobación DENTRO de la función, porque un `revoke` se deshace solo la
  -- próxima vez que alguien conceda en masa y un guard no.
  -- Quien copie este cuerpo para otra migración tiene que copiar esto también:
  -- al escribir la 0100 se copió el texto de la 0069, que es anterior, y el
  -- guard desapareció sin que nada fallara salvo la prueba 91.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede calcular la planilla.';
  end if;

  -- ── CAMBIO 0239 ──────────────────────────────────────────────────────────
  -- El rango decide QUÉ entra (marcas, feriados). El periodo decide CUÁNTO vale
  -- una hora. Estaban conflatados en una sola variable, así que un rango corto
  -- encarecía la hora en vez de cobrar menos días.
  --
  -- Solo se corrige cuando la llamada declara a qué periodo pertenece el rango.
  -- `fn_simular_planilla` pasa null a propósito —simula un rango libre, que no
  -- es el trozo de ningún periodo— y ahí el divisor sigue siendo el del rango.
  v_dias := (p_fin - p_ini) + 1;

  if p_periodo_id is not null then
    select (pp.fecha_fin - pp.fecha_ini) + 1
      into v_dias_periodo
      from periodos_planilla pp
     where pp.id = p_periodo_id;

    if v_dias_periodo is not null and v_dias_periodo > 0 then
      v_dias := v_dias_periodo;
    end if;
  end if;

  v_base := 6.5 * v_dias;
  v_anio := extract(year from p_fin)::int;
  v_mes := extract(month from p_fin)::int;

  select valor into v_prov from configuracion where clave = 'planilla_provisiones';
  if v_prov is null then
    v_prov := '{"gratificacion": 0.08333, "cts": 0.04167, "vacaciones": 0.04167}'::jsonb;
  end if;
  v_f_grati := coalesce((v_prov->>'gratificacion')::numeric, 0);
  v_f_cts := coalesce((v_prov->>'cts')::numeric, 0);
  v_f_vacas := coalesce((v_prov->>'vacaciones')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0134 ⇩⇩⇩ LA BONIFICACION EXTRAORDINARIA DE LA LEY 30334.
  -- Versionada en parametros_laborales y no clavada en el codigo, por el mismo
  -- motivo que la movilidad (0118) y la asignacion familiar (0122): es una tasa
  -- legal, y el dia que cambie los periodos ya pagados no pueden moverse.
  -- Es 6.75 % para quien esta afiliado a una EPS. Hoy nadie lo esta y el sistema
  -- no tiene ese campo; cuando lo tenga, esta lectura pasa a ser por persona.
  select pl.valor into v_f_be
  from parametros_laborales pl
  where pl.clave = 'bonificacion_extraordinaria'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_f_be is null then v_f_be := 0.09; end if;
  -- CAMBIO 0112 — el sexto de la gratificación en la base de la CTS (Art. 16
  -- D.S. 001-97-TR). Arranca en 0: sin la clave, la CTS sale como hoy.
  v_sexto_cts := coalesce((v_prov->>'sexto_cts')::numeric, 0);

  -- ⇩⇩⇩ CAMBIO 0122 ⇩⇩⇩ LA ASIGNACIÓN FAMILIAR, CON VIGENCIA.
  --
  -- Es el 10% de la RMV (Ley 25129), así que SUBE CUANDO SUBE LA RMV. El 28 de
  -- julio de 2026 se anunció el alza a S/1,300, que la llevaría de S/113 a S/130.
  --
  -- Hasta esta migración el monto vivía en 'configuracion' como un escalar SIN
  -- FECHA. El día que alguien lo actualizara a 130, TODOS los periodos ya pagados
  -- se recalcularían con el valor nuevo y las boletas viejas dejarían de
  -- reproducirse. Es el mismo defecto que ya nos mordió con tasa_afp y que la 0116
  -- y la 0118 resolvieron para la RMV, el EsSalud y la movilidad. A esta se le
  -- pasó, y se arregla ANTES de que salga la norma y no después.
  --
  -- Acá la lectura es exacta: un periodo de planilla tiene una sola asignación
  -- vigente, la del cierre, y los 15 usos de v_asig pertenecen al mismo periodo.
  select pl.valor into v_asig
  from parametros_laborales pl
  where pl.clave = 'asignacion_familiar'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;

  -- Respaldo, para que una base sin la fila se comporte igual que antes.
  if v_asig is null then
    select coalesce((valor->>'monto')::numeric, 113.00) into v_asig
    from configuracion where clave = 'asignacion_familiar';
  end if;
  if v_asig is null then v_asig := 113.00; end if;

  -- ⇩⇩⇩ CAMBIO 0110 ⇩⇩⇩ Las dos viven en configuracion, no en el código.
  --
  -- AMBAS ARRANCAN EN CERO A PROPÓSITO. Si las claves no existen, la movilidad
  -- y el descuento de AFP salen 0 y NINGÚN pago se mueve: esta migración se puede
  -- pegar en producción sin que nadie cobre un sol distinto. Se activan con dos
  -- UPDATE cuando Felipe decida, no al aplicar la migración.
  --
  --   update configuracion set valor = '{"monto": 12.50}'::jsonb
  --    where clave = 'movilidad_diaria';
  --   update configuracion set valor = '{"tasa": 0.13}'::jsonb
  --    where clave = 'tasa_afp';
  --
  -- La tarifa vive en configuracion porque los pasajes cambian (Trujillo pasó de
  -- S/2.50 a S/2.00 en junio de 2026) y la tasa de AFP porque varía por AFP:
  -- entre 12.84% (Habitat) y 13.06% (Profuturo). El 13% es el techo práctico.
  -- ⇩⇩⇩ CAMBIO 0118 ⇩⇩⇩ LA TARIFA DE MOVILIDAD, CON VIGENCIA Y CON SUSTENTO.
  --
  -- Antes salía de 'configuracion', que guarda valores globales SIN fecha. El día
  -- que la tarifa cambie —y va a cambiar, porque sigue al pasaje— ese valor único
  -- recalcularía TODOS los periodos ya pagados. Es el mismo defecto que ya nos
  -- mordió con tasa_afp y que la 0116 evitó para la RMV.
  --
  -- Ahora sale de parametros_laborales, eligiendo la fila vigente al FIN del
  -- periodo. Cuando el pasaje suba se cierra la fila con vigente_hasta y se abre
  -- otra: el pasado queda intacto y el porqué de cada tarifa queda archivado en
  -- la columna 'sustento' de su propia fila.
  --
  -- Se conserva la lectura de 'configuracion' como respaldo, para que una base
  -- que aún no tenga la fila siga comportándose igual que antes.
  -- ⇩⇩⇩ CAMBIO 0159 ⇩⇩⇩ ¿Se exige la declaración de ruta en este periodo?
  -- Se lee al FIN del periodo, igual que la tarifa: un parámetro versionado que
  -- vale 0 mientras el candado está apagado. Los periodos ya pagados no cambian
  -- por encenderlo — es el mismo blindaje que la 0115 usó con la pensión.
  select pl.valor into v_exige_decl
  from parametros_laborales pl
  where pl.clave = 'movilidad_exige_declaracion'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_exige_decl is null then v_exige_decl := 0; end if;

  -- ⇩⇩⇩ CAMBIO 0166 ⇩⇩⇩ EL RESPALDO TIENE QUE SER LA FILA GENERAL, NO UNA CUALQUIERA.
  --
  -- Faltaba `sede_codigo is null`. Sin eso esta consulta miraba TODAS las filas
  -- de movilidad y se quedaba con la de fecha mas reciente: las de AQP, LIM y
  -- TRU son del 2026-07-29 y la general es del 2020, asi que el respaldo se
  -- quedaba con el pasaje de una ciudad cualquiera —la que el motor devolviera
  -- primero entre las tres empatadas— en vez de con el cero de la fila general.
  --
  -- Efecto real: quien esta en una sede sin tarifa propia no cobraba S/ 0.00,
  -- cobraba el pasaje de otra ciudad. Un cero se ve y se corrige; un monto
  -- plausible de otra ciudad no se nota nunca. Y es justo lo que el Exp.
  -- 01038-2019 castiga: un monto que no atiende a ningun criterio objetivo.
  --
  -- Encontrado el 2026-08-05 auditando esta misma migracion contra el Postgres
  -- local: el caso de control —Central sin sede fisica— debia dar 0.00 y dio
  -- 10.00. No lo encontro nadie leyendo; lo encontro correr el calculo.
  select pl.valor into v_movilidad
  from parametros_laborales pl
  where pl.clave = 'movilidad_diaria'
    and pl.sede_codigo is null
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;

  if v_movilidad is null then
    select coalesce((valor->>'monto')::numeric, 0) into v_movilidad
    from configuracion where clave = 'movilidad_diaria';
  end if;
  if v_movilidad is null then v_movilidad := 0; end if;

  -- CAMBIO 0254 · El tope del RIT art. 31 f): CAYLA asume los primeros 20 dias
  -- de incapacidad del ANO CALENDARIO; del 21 en adelante subsidia EsSalud. Se
  -- lee de la misma clave que ya usa el aviso de la 0197, para que no haya dos
  -- numeros distintos diciendo lo mismo.
  select coalesce((valor->>'umbral_essalud')::int, 20) into v_tope_dm
  from configuracion where clave = 'descanso_medico_aviso_dias';
  if v_tope_dm is null then v_tope_dm := 20; end if;

  select coalesce((valor->>'tasa')::numeric, 0) into v_tasa_afp
  from configuracion where clave = 'tasa_afp';
  if v_tasa_afp is null then v_tasa_afp := 0; end if;

  -- ⇩⇩⇩ CAMBIO 0116 ⇩⇩⇩ EL ESSALUD, DESDE UNA TABLA VERSIONADA.
  --
  -- La RMV y la tasa NO van en 'configuracion' a propósito. Esa tabla guarda
  -- valores globales SIN fecha, así que el día que la RMV suba de 1,130 a 1,200
  -- todos los periodos ya pagados se recalcularían con el valor nuevo — el mismo
  -- defecto que tenían movilidad_diaria y tasa_afp. Aquí se elige la fila vigente
  -- al FIN del periodo, que además es lo que manda la norma: el piso se congela
  -- con la RMV vigente al último día calendario del período declarado.
  select pl.valor into v_rmv
  from parametros_laborales pl
  where pl.clave = 'rmv'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_rmv is null then v_rmv := 0; end if;

  select pl.valor into v_tasa_essalud
  from parametros_laborales pl
  where pl.clave = 'tasa_essalud'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_tasa_essalud is null then v_tasa_essalud := 0; end if;

  -- ⇩⇩⇩ CAMBIO 0245 ⇩⇩⇩ LA RETENCIÓN DE RENTA DE CUARTA CATEGORÍA.
  --
  -- Las dos van a parametros_laborales y no clavadas en el código, por el
  -- mismo motivo que la RMV (0116) y la asignación familiar (0122): son
  -- cifras que SUNAT mueve, y el día que se muevan los periodos ya pagados
  -- no pueden recalcularse solos. Se lee la fila vigente al FIN del periodo.
  --
  -- LA TASA ARRANCA EN 0 SI LA FILA NO EXISTE, igual que la movilidad y la
  -- AFP de la 0110: una base sin las filas se comporta EXACTAMENTE como
  -- antes de esta migración.
  select pl.valor into v_tasa_4ta
  from parametros_laborales pl
  where pl.clave = 'retencion_4ta_tasa'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_tasa_4ta is null then v_tasa_4ta := 0; end if;

  -- El tope arranca ALTÍSIMO si la fila no existe, y no en 0: un tope en 0
  -- haría que la regla automática retuviera a todo el mundo. El respaldo de
  -- un parámetro que EXCLUYE tiene que caer del lado que no cobra de más.
  select pl.valor into v_tope_4ta
  from parametros_laborales pl
  where pl.clave = 'retencion_4ta_tope'
    and pl.vigente_desde <= p_fin
    and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
  order by pl.vigente_desde desc
  limit 1;
  if v_tope_4ta is null then v_tope_4ta := 9999999; end if;

  select coalesce(jsonb_agg(jsonb_build_object('fecha', f.fecha, 'nombre', f.nombre) order by f.fecha), '[]'::jsonb)
    into v_feriados
  from feriados f
  where f.fecha between p_ini and p_fin;

  with pers as (
    select p.id, p.nombres, p.apellidos, p.estado, p.con_hijos, p.fecha_ingreso, p.sueldo_fijo,
           p.sueldo_base_legal,   -- CAMBIO 0105
           -- ⇩⇩⇩ CAMBIO 0261 ⇩⇩⇩ EL RÉGIMEN QUE TENÍA EN **ESE** PERIODO.
           --
           -- Antes decía `p.regimen_pension` a secas: el valor de HOY aplicado a
           -- cualquier periodo. La TASA sí estaba versionada por fecha desde la
           -- 0114/0115; la PERTENENCIA de la persona a un régimen, no. Así que
           -- recalcular un mes viejo mezclaba el régimen de hoy con la tasa de
           -- entonces, y el resultado no era ninguno de los dos.
           --
           -- Es el mismo defecto que la 0116 evitó para la RMV y la 0118 para la
           -- movilidad, una capa más arriba: allá el valor global no tenía fecha,
           -- aquí la tenía el valor y no la pertenencia.
           --
           -- SE ANCLA AL CIERRE DEL PERIODO, exactamente igual que la tasa mil
           -- líneas más abajo, y eso es a propósito: leer el régimen en una fecha
           -- y su tasa en otra puede emparejar un régimen con una tasa que nunca
           -- coexistieron.
           --
           -- EL COALESCE ES EL RESPALDO Y NO SOBRA: quien no tenga historial se
           -- comporta EXACTAMENTE igual que antes de esta migración. Por eso
           -- aplicarla no mueve un céntimo de nadie el día que se pega.
           coalesce(
             (select h.regimen
                from asignaciones_regimen_pension h
               where h.persona_id = p.id
                 and h.vigente_desde <= p_fin
                 and (h.vigente_hasta is null or h.vigente_hasta >= p_fin)
               order by h.vigente_desde desc
               limit 1),
             p.regimen_pension) as regimen_pension,   -- CAMBIO 0114 · 0261
           p.tipo_vinculo, p.en_planilla,   -- CAMBIO 0117
           p.personal_direccion,  -- CAMBIO 0187 · art. 5 D.S. 007-2002-TR
           p.retencion_4ta, p.constancia_4ta_hasta,   -- CAMBIO 0245
           s.codigo as sede,
           -- CAMBIO 0166 · la sede que decide la MOVILIDAD es donde la persona
           -- trabaja de verdad, no su area administrativa. Central no es una
           -- ciudad: es un rotulo. Quien esta en CCO pero trabaja dentro de la
           -- tienda de Arequipa paga pasaje de Arequipa. Sin sede fisica cargada
           -- manda su sede base, asi que nadie cambia salvo quien se declare.
           coalesce(sf.codigo, s.codigo) as sede_movilidad,
           p.cobra_movilidad   -- CAMBIO 0166
    from personas p
    join sedes s on s.id = p.sede_base_id
    left join sedes sf on sf.id = p.sede_fisica_id
    where p.estado = 'activo'
       or exists (select 1 from jornadas j where j.persona_id = p.id and j.fecha between p_ini and p_fin)
       or (p_periodo_id is not null and exists (
             select 1 from movimientos_planilla m
             where m.persona_id = p.id and m.periodo_id = p_periodo_id))
  ),
  horas as (
    select j.persona_id, j.fecha,
           coalesce(j.horas_trabajadas, 0) as h,
           (j.estado = 'auto_cerrada_pendiente') as pendiente
    from jornadas j
    where j.fecha between p_ini and p_fin
  ),
  -- ⇩⇩⇩ CAMBIO 0185 ⇩⇩⇩ Sobretiempo (D.S. 007-2002-TR arts. 9 y 10)
  --
  -- Se lee desde SIETE DÍAS ANTES de p_ini a propósito: un ciclo que empezó en
  -- el periodo anterior tiene que medirse entero o el exceso desaparece. Solo se
  -- PAGA lo que cae dentro del periodo — el filtro está más abajo, en `sobret`.
  --
  -- Se filtran las horas <= 0: el auto-cierre puede dejar jornadas negativas
  -- cuando la salida sintética queda antes de la entrada, y una negativa dentro
  -- de un ciclo bajaría el acumulado y escondería un exceso real.
  ot_dias as (
    select j.persona_id, j.fecha, j.horas_trabajadas as h
    from jornadas j
    where j.fecha between p_ini - 7 and p_fin
      and coalesce(j.horas_trabajadas, 0) > 0
  ),
  -- Rachas de días consecutivos. Un descanso las corta: en días seguidos, la
  -- fecha menos su número de orden da siempre el mismo valor.
  ot_islas as (
    select persona_id, fecha, h,
           fecha - (row_number() over (partition by persona_id order by fecha))::int as isla
    from ot_dias
  ),
  -- Dentro de cada racha, bloques de 7 días. Un ciclo = (racha, bloque), y los
  -- ciclos NO se solapan: por eso ninguna hora se paga dos veces.
  --
  -- El corte a 7 días es lo que hace que doce días seguidos de 8 h se midan como
  -- dos ciclos (56 h y 40 h → 8 h de exceso) y no como uno de 96 h → 48 h. El
  -- tope de 48 es SEMANAL: doce días son casi dos semanas y se miden como dos.
  ot_ciclos as (
    select persona_id, fecha, h, isla,
           ((row_number() over (partition by persona_id, isla order by fecha) - 1) / 7)::int as bloque
    from ot_islas
  ),
  -- El exceso se imputa AL DÍA en que el acumulado del ciclo cruza las 48 y a
  -- los siguientes. Así cada hora extra tiene una fecha, y las que caen en un
  -- periodo ya pagado se quedan fuera solas.
  ot_exceso as (
    select persona_id, fecha,
           greatest(0, least(h, sum(h) over (partition by persona_id, isla, bloque order by fecha) - 48)) as h_exceso
    from ot_ciclos
  ),
  -- El recargo se cuenta POR DÍA y se reinicia cada día: 25 % las dos primeras
  -- horas de ese día, 35 % las siguientes (D.S. 007-2002-TR art. 10). Lo que se
  -- guarda son las horas EQUIVALENTES de recargo — las horas en sí ya están
  -- pagadas dentro de pago_base, y sumarlas otra vez sería pagarlas dos veces.
  sobret as (
    select persona_id,
           sum(h_exceso) as horas,
           sum(least(h_exceso, 2) * 0.25 + greatest(h_exceso - 2, 0) * 0.35) as horas_recargo,
           min(fecha) as desde, max(fecha) as hasta
    from ot_exceso
    where h_exceso > 0 and fecha between p_ini and p_fin
    group by persona_id
  ),
  -- ⇧⇧⇧ CAMBIO 0185 ⇧⇧⇧
  tramos as (
    select a.persona_id, a.rango, a.salario_mensual_soles as salario,
           a.base_provision,                                   -- CAMBIO 0111
           greatest(a.vigente_desde, p_ini) as t_ini,
           least(coalesce(a.vigente_hasta, p_fin), p_fin) as t_fin
    from asignaciones_salario a
    where a.vigente_desde <= p_fin
      and (a.vigente_hasta is null or a.vigente_hasta >= p_ini)
  )
  select jsonb_build_object(
    'fecha_ini', p_ini,
    'fecha_fin', p_fin,
    'anio_etiqueta', v_anio,
    'mes_etiqueta', v_mes,
    'dias', v_dias,
    'base_horas', v_base,
    'feriados', v_feriados,
    'factores_provision', v_prov,
    'asignacion_monto', v_asig,
    'filas', coalesce(jsonb_agg(sub.fila order by sub.orden_nombre), '[]'::jsonb)
  )
  into v_out
  from (
    select (pe.nombres || ' ' || pe.apellidos) as orden_nombre,
      jsonb_build_object(
        'persona_id', pe.id,
        'nombre', pe.nombres || ' ' || pe.apellidos,
        'sede', pe.sede,
        'estado', pe.estado,
        'fecha_ingreso', pe.fecha_ingreso,
        'rango', ref.rango,
        'salario_ref', ref.salario,
        'horas_mes', round(h.horas_mes, 2),
        'dias_trabajados', h.dias,
        -- ⇩ CAMBIO 0110 ⇩ MOVILIDAD SUPEDITADA A LA ASISTENCIA.
        -- Se devenga por DÍA EFECTIVAMENTE ASISTIDO, que es el requisito del
        -- Art. 19 inciso e) del D.S. 001-97-TR: «el valor del transporte, siempre
        -- que esté supeditado a la asistencia al centro de trabajo». h.dias cuenta
        -- los días con horas > 0, así que si no vino, no la cobra, sin que nadie
        -- tenga que acordarse. La Res. 239-2020-SUNAFIL declaró remunerativa una
        -- movilidad de monto razonable justamente por pagarse 30 días cuando se
        -- laboraban 6.
        'monto_movilidad', round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla then 1 else 0 end)
          -- CAMBIO 0166: quien no devenga movilidad (se cubre por viaticos) no la devenga
          * (case when pe.cobra_movilidad then 1 else 0 end)
          -- CAMBIO 0159: sin declaracion firmada no devenga, si el candado esta encendido
          * (case when v_exige_decl > 0 and not decl.tiene_declaracion then 0 else 1 end), 2),   -- CAMBIO 0142
        'movilidad_diaria', tar.tarifa,
        -- ⇩ CAMBIO 0159 ⇩ Para que la pantalla pueda decir POR QUÉ salió cero.
        -- «Un cero no explica nada» (0100): sin esto, quien mire la planilla vería
        -- movilidad 0.00 y no sabría si es que no marcó o si le falta el papel.
        'movilidad_sin_declaracion', (v_exige_decl > 0 and not decl.tiene_declaracion),
        -- ⇩ CAMBIO 0110 ⇩ DESCUENTO DE AFP/ONP, visible en la boleta.
        -- Se calcula sobre la REMUNERACIÓN ASEGURABLE: la básica legal proporcional
        -- más la asignación familiar, que también es remuneración (Ley 25129). No
        -- entran la movilidad ni los bonos no remunerativos.
        -- Sale 0 para quien no tenga básica legal fijada (sueldo fijo: socios,
        -- dirección), porque para ellos pb.basica es 0.
        'descuento_afp',
          round(bri.base_pension * coalesce(tpen.tasa, v_tasa_afp), 2),
        'tasa_afp', coalesce(tpen.tasa, v_tasa_afp),
        'regimen_pension', pe.regimen_pension,          -- CAMBIO 0114
        'tasa_es_del_regimen', (tpen.tasa is not null),  -- CAMBIO 0114
        'dias_pendientes', h.pendientes,
        -- ⇩ CAMBIO 0100 ⇩ por qué esta persona está en cero. Sin esto, «de
        -- vacaciones», «no marcó» y «sin salario» se ven exactamente igual: 0.
        'dias_vacaciones', vac.dias,
        'dias_laborables', lab.dias,
        'horas_sin_salario', round(pb.horas_sin_salario, 2),
        'pago_base', round(pb.pago_base, 2),
        -- CAMBIO 0105 — Desglose legal. Sale en cuanto la persona tiene básica
        -- legal fijada: ya NO hace falta puntuación, porque sin fila el defecto es
        -- 100 y el pago es el mismo de siempre. Sin básica legal sigue saliendo
        -- NULL y la boleta muestra el pago sin partir, antes que inventar una
        -- separación. Los de sueldo fijo (socios, dirección) quedan fuera.
        -- La básica tal cual, sin prorratear: la pantalla de Planilla la necesita
        -- para poder editarla en su celda.
        'sueldo_base_legal', pe.sueldo_base_legal,
        'basica_legal_prop',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else round(pb.basica, 2) end,
        'complemento_variable',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else round(pb.pago_base, 2) - round(pb.basica, 2) end,
        'rendimiento_pct',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else coalesce(rmp.porcentaje, 100) end,
        -- true cuando el 100 es el defecto y no una decisión escrita. Sirve para
        -- que la pantalla distinga «nadie lo ha puntuado» de «lo puntuaron 100».
        'rendimiento_por_defecto', (rmp.porcentaje is null),
        -- El coalesce va AQUÍ y no dentro del lateral: sin fila el lateral no
        -- devuelve nada, así que rmp.etiqueta sería NULL y la boleta se quedaría
        -- sin nombre en la fila del complemento.
        'complemento_etiqueta',
          case when pe.sueldo_base_legal is null or pe.sueldo_fijo
               then null else coalesce(rmp.etiqueta, 'Rendimiento Extraordinario') end,
        'feriados_detalle', fer.detalle,
        'monto_feriados', round(fer.monto, 2),
        'feriados_no_corresponde', fer.no_corresponde,
        'feriados_compensados', fer.compensados,
        'objetivos_cumplidos', obj.cumplidos,
        'objetivos_total', obj.total,
        'monto_plus', round(obj.monto, 2),
        'bajo_desempeno', (obj.cumplidos is not null and obj.total > 0
                           and obj.cumplidos::numeric / obj.total < 0.3),
        'feriados_sin_salario', fer.sin_tramo,
        'con_hijos', pe.con_hijos,
        -- ⇩ CAMBIO 0242 ⇩ `and pe.en_planilla is true`. La Ley 25129 da la
        -- asignación familiar a trabajadores del régimen laboral privado. Un
        -- locador no lo es, y cobrarla no solo es plata que no le toca: es un
        -- indicio de laboralidad, igual que la movilidad de la 0117.
        'asignacion_familiar',
          case when pe.con_hijos and pe.en_planilla is true
               then round(v_asig, 2) else 0 end,
        'bonos', round(mov.bonos, 2),
        'descuentos', round(mov.descuentos, 2),
        'movimientos', mov.detalle,
        -- ⇩ CAMBIO 0113 ⇩ La base de provisión incluye la ASIGNACIÓN FAMILIAR.
        -- Los S/113 de la Ley 25129 son remuneración, así que integran la
        -- remuneración computable de gratificación, CTS y vacaciones. Antes se
        -- pagaban como línea aparte y quedaban fuera de la base.
        --
        -- ⇩⇩⇩ CAMBIO 0111 ⇩⇩⇩ Las cuatro provisiones llevan un FACTOR.
        --
        -- POR QUÉ EXISTE. La 0110 permite bajar el rango a la básica legal para que
        -- el Rendimiento Extraordinario desaparezca (la fórmula lo anula sola cuando
        -- rango = básica). Pero las provisiones se calculan sobre pago_base, así que
        -- bajar el rango de 1,320 a 1,130 les recortaría la gratificación, la CTS y
        -- las vacaciones en un 14.4% — unos S/422 al año por persona. Eso es plata
        -- del equipo, no del empleador, y Felipe decidió no tocarla.
        --
        -- CÓMO FUNCIONA. factor = base_provision / salario. Si base_provision está
        -- en NULL el factor sale 1 y NADA cambia: la migración se puede pegar sin
        -- que ninguna provisión se mueva. Si se pone en 1,320 mientras el salario es
        -- 1,130, el factor es 1.1681 y las provisiones quedan idénticas a las de
        -- antes de bajar el rango.
        --
        -- POR QUÉ UN FACTOR Y NO OTRA BASE. pago_base y feriados escalan LINEALMENTE
        -- con el salario del tramo (los dos usan tt.salario), así que multiplicar el
        -- resultado por el factor da exactamente lo mismo que haber calculado todo
        -- con el salario viejo. Verificado: (1,090.74 + 165.43) × 1.1681 = 1,467.33
        -- contra (1,274.14 + 193.25) = 1,467.39 con el rango en 1,320.
        --
        -- LO QUE NO CAMBIA: la movilidad sigue FUERA de esta base. El factor
        -- multiplica (pago_base + feriados), no la movilidad ni el AFP.
        'provision_gratificacion',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * dev.f_grati, 2),
        -- CAMBIO 0134 — se calcula del MISMO numero que la gratificacion, nunca
        -- de una base propia: si manana cambia la formula de la grati, esta la
        -- sigue sola. Es la linea 0312 del PLAME.
        'provision_bonif_extraordinaria',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * dev.f_grati * v_f_be, 2),
        'provision_cts',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * dev.f_cts * (1 + v_sexto_cts), 2),
        'provision_vacaciones',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1) * dev.f_vacas, 2),
        'provision_total',
          round((pb.pago_base + fer.monto
                 + (case when pe.con_hijos then v_asig else 0 end)) * coalesce(ref.base_provision / nullif(ref.salario, 0), 1)
                * (dev.f_grati * (1 + v_f_be) + dev.f_cts * (1 + v_sexto_cts) + dev.f_vacas), 2),   -- CAMBIO 0134
        -- Para que la pantalla pueda mostrar sobre qué base se provisionó.
        'base_provision', ref.base_provision,
        'factor_provision', coalesce(ref.base_provision / nullif(ref.salario, 0), 1),
        'total', round(pb.pago_base, 2) + round(fer.monto, 2) + round(obj.monto, 2)
                 -- CAMBIO 0242 · el pago, con la misma condición que el concepto
                 -- de arriba. Van por separado en el JSON y hay que tocar los dos:
                 -- arreglar solo uno deja la boleta diciendo 0 y el total cobrándolo.
                 + (case when pe.con_hijos and pe.en_planilla is true
                         then round(v_asig, 2) else 0 end)
                 -- CAMBIO 0252 · EL MISMO FILTRO QUE LA LINEA DE LA BOLETA.
                 -- Faltaba `cobra_movilidad`, que el concepto `monto_movilidad`
                 -- tiene desde la 0166. El concepto salia 0.00 y el total la
                 -- cobraba igual: chk_foto_cuadra rechazaba la fila y, como
                 -- fn_planilla_congelar inserta las ~30 en UNA sentencia, no se
                 -- congelaba NINGUNA. El cierre entero se caia por una persona.
                 + round(coalesce(h.dias, 0) * tar.tarifa * (case when pe.en_planilla then 1 else 0 end)
          -- CAMBIO 0166: quien no devenga movilidad (se cubre por viaticos) no la devenga
          * (case when pe.cobra_movilidad then 1 else 0 end)
          -- CAMBIO 0159: sin declaracion firmada no devenga, si el candado esta encendido
          * (case when v_exige_decl > 0 and not decl.tiene_declaracion then 0 else 1 end), 2)              -- CAMBIO 0142
                 + round(coalesce(edu.monto, 0) * (case when pe.en_planilla then 1 else 0 end), 2)   -- CAMBIO 0120
                 - round((bri.base_pension)
                         * coalesce(tpen.tasa, v_tasa_afp), 2)                                    -- CAMBIO 0110
                 + round(mov.bonos, 2) - round(mov.descuentos, 2)
                 -- CAMBIO 0245 · la retención sale del pago, como manda el
                 -- art. 71 de la Ley del Impuesto a la Renta. No se queda en
                 -- CAYLA: se declara en la PLAME y se paga a SUNAT a nombre
                 -- de la persona. Va en DOS sitios del JSON —el concepto y
                 -- este término— y hay que tocar los dos, que es la lección
                 -- que dejó la asignación familiar en la 0242.
                 - r4.monto
                 -- CAMBIO 0185 · el recargo del sobretiempo. Solo el RECARGO:
                 -- las horas ya están dentro de pago_base.
                 + round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2)
      )
      || jsonb_build_object(
        -- ⇩⇩⇩ CAMBIO 0116 ⇩⇩⇩ EL APORTE DE ESSALUD QUE PAGA CAYLA.
        --
        -- NO entra en el 'total' y no debe entrar nunca: el 9% es íntegramente de
        -- cargo del empleador (Ley 26790 art. 6). Descontárselo al trabajador
        -- sería una retención ilegal. Va como dato, para que cada integrante vea
        -- lo que la empresa paga por él — que es lo que Felipe pidió el 2026-07-31.
        --
        -- LA BASE LLEVA PISO, y es lo que más se equivoca. La base imponible
        -- mínima mensual no puede ser inferior a la RMV, y ese piso se aplica
        -- «independientemente de las horas y días laborados» (reglamento de la
        -- Ley 26790, D.S. 009-97-SA modificado por el D.S. 020-2006-TR; criterio
        -- confirmado en el Informe 003-2007-SUNAT/2B0000).
        --
        -- O sea: por alguien que trabajó 6 h 35 min y devengó S/36.96, la empresa
        -- NO aporta 9% × 36.96 = S/3.33. Aporta 9% × 1,130 = S/101.70 — el mismo
        -- monto que por alguien de mes completo. Prorratear RMV/30 × días está
        -- expresamente prohibido, salvo el caso de subsidios (descanso médico,
        -- maternidad). CAMBIO 0254: el descanso médico SÍ se modela desde
        -- entonces —los 20 días del RIT art. 31 f) entran en pago_base—.
        -- CAMBIO 0262: la maternidad también, y por eso el piso RMV de esta
        -- línea NO se le aplica: el subsidio entra en `pago_base` pero no en
        -- `pb.basica`, así que no llega a `bri.base` y no infla la base de
        -- EsSalud. Es exactamente lo que manda el reglamento.
        --
        -- Consecuencia de gestión: el costo de EsSalud lo manda el número de
        -- personas, no el monto de la planilla. Calcularlo como «9% del total de
        -- la planilla» subestima el aporte real cuando hay gente de pocas horas.
        'base_essalud',
          round(greatest(bri.base, pb.piso_essalud), 2),
        'aporte_essalud',
          round(greatest(bri.base, pb.piso_essalud) * v_tasa_essalud
                * (case when pe.en_planilla then 1 else 0 end), 2),
        'essalud_tasa', v_tasa_essalud,
        -- ⇩⇩⇩ CAMBIO 0117 ⇩⇩⇩ Qué es esta persona para el sistema. Sin este dato
        -- la boleta no puede explicar por qué a alguien no le aparece movilidad ni
        -- EsSalud, y la pantalla de Planilla no puede advertir que un locador con
        -- conceptos laborales encima es un problema.
        -- ⇩ CAMBIO 0120 ⇩ Condicionada a en_planilla igual que la movilidad: un
        -- locador no recibe asignaciones laborales. Y el monto NO se prorratea por
        -- asistencia — es el costo de un estudio, no una compensación por venir.
        'monto_educacion',
          round(coalesce(edu.monto, 0) * (case when pe.en_planilla then 1 else 0 end), 2),
        -- ⇩ CAMBIO 0150 ⇩ Para que la boleta pueda decir de qué institución sale
        -- ese dinero. Una línea que dice sólo «S/270» no le permite a la persona
        -- cuadrar su propio pago, y un concepto no remunerativo que no se
        -- identifica es el que se reclasifica como sueldo.
        'instituciones_educacion',
          case when pe.en_planilla then edu.instituciones else null end,
        -- ⇩ CAMBIO 0236 ⇩ Los dos datos con los que la boleta explica un cero.
        -- Condicionados a `en_planilla` como todo lo demás de educación: a un
        -- locador no se le explica por qué no cobra un concepto laboral, no le
        -- corresponde y punto.
        'educacion_registrada',
          case when pe.en_planilla then coalesce(edudiag.hay, false) else false end,
        'educacion_sin_comprobante',
          case when pe.en_planilla then coalesce(edudiag.sin_papel, false) else false end,
        'tipo_vinculo', pe.tipo_vinculo,
        'en_planilla', pe.en_planilla,
        -- true cuando el piso fue lo que decidió la base, o sea cuando la persona
        -- devengó MENOS que la RMV. Sirve para que la boleta pueda explicarlo en
        -- vez de mostrar un número que no cuadra con el sueldo del mes.
        'essalud_es_piso',
          (bri.base) < pb.piso_essalud
      )
      -- ⇩ CAMBIO 0177 ⇩ Se CONCATENA en vez de ampliar el jsonb_build_object de
      -- arriba: ese ya tiene 57 pares y Postgres corta a 100 ARGUMENTOS. Agregar
      -- dos claves más ahí revienta con «cannot pass more than 100 arguments to
      -- a function», y no al escribirla sino al EJECUTARLA. Quien agregue el
      -- siguiente campo del JSON tiene que hacerlo acá.
      || jsonb_build_object(
        'monto_vacaciones', round(pb.monto_vacaciones, 2),
        'dias_vacaciones_pagados', pb.dias_vacaciones_pagados,
        -- CAMBIO 0254 · para que la boleta lo diga con su nombre en vez de
        -- esconderlo dentro del sueldo. Informativos: el monto YA esta en
        -- pago_base, asi que no se suma otra vez en ningun sitio.
        'monto_descanso_medico', round(pb.monto_descanso_medico, 2),
        'dias_descanso_medico_pagados', pb.dias_descanso_medico_pagados,
        -- CAMBIO 0262 · el subsidio, con su nombre. Informativos: el monto YA
        -- esta dentro de pago_base, asi que no se suma otra vez en ningun sitio.
        'monto_subsidio_maternidad', round(pb.monto_subsidio_maternidad, 2),
        'dias_subsidio_maternidad', pb.dias_subsidio_maternidad,
        -- ⇩ LA ALARMA ⇩ dias de licencia registrados a los que nadie les puso
        -- monto. Es lo unico de este cambio que la pantalla TIENE que mirar: sin
        -- esto, una licencia sin monto se paga 0.00 y se lee igual que un mes
        -- normal de alguien que no vino.
        'dias_maternidad_sin_monto', pb.dias_maternidad_sin_monto,
        -- CAMBIO 0185 · las tres piezas que la boleta necesita para explicarse:
        -- cuánto, cuántas horas y cuándo. Un monto pelado no se puede verificar
        -- contra el registro de asistencia, que es lo que lo sostiene.
        'monto_sobretiempo', round(coalesce(ot.horas_recargo, 0) * coalesce(ref.salario, 0) / v_base, 2),
        'horas_sobretiempo', round(coalesce(ot.horas, 0), 2),
        'sobretiempo_desde', ot.desde,
        'sobretiempo_hasta', ot.hasta,
        -- CAMBIO 0245 · los cuatro que necesita la boleta de un locador para
        -- explicarse. El monto pelado no se puede verificar contra su recibo:
        -- hace falta sobre qué base salió y bajo qué regla.
        'retencion_4ta', r4.monto,
        'retencion_4ta_base', r4.base,
        'retencion_4ta_modo', pe.retencion_4ta,
        'retencion_4ta_constancia_hasta', pe.constancia_4ta_hasta,
        'retencion_4ta_sin_configurar', r4.sin_configurar,
        -- CAMBIO 0250 · ¿su pago depende de las horas que registre?
        --
        -- Es un campo de PRESENTACIÓN y no mueve un céntimo: `pago_base` ya
        -- se calcula distinto para quien lo tiene desde la 0047. Viaja porque
        -- sin él la boleta no puede distinguir dos locadores que cobran de
        -- formas opuestas, y les ponía a los dos la misma etiqueta: «Honorarios
        -- por las horas prestadas (0 h) …… S/ 652.17». Cero horas y un monto,
        -- en el papel que se le entrega a alguien externo — y describiendo el
        -- acuerdo al revés, porque lo pactado con él es un monto fijo.
        --
        -- Va en el ÚLTIMO jsonb_build_object, el que abrió la 0177: el primero
        -- está a 57 pares y Postgres corta a 100 ARGUMENTOS al EJECUTAR.
        'sueldo_fijo', pe.sueldo_fijo
      ) as fila
    from pers pe
    -- ⇩ CAMBIO 0142 ⇩ La tarifa de movilidad de LA SEDE de esta persona.
    --
    -- Antes era un escalar unico para las tres ciudades. Pero el Art. 19 inciso e)
    -- del D.S. 001-97-TR pide que el monto «razonablemente cubra el respectivo
    -- traslado», y el traslado no cuesta lo mismo en Arequipa que en Lima.
    --
    -- Una tarifa uniforme fijada al caso mas caro deja a las otras ciudades
    -- pagando por encima de su costo real, y ese exceso es lo que se reclasifica.
    -- El Exp. 01038-2019 de Lima Norte tumbo una movilidad ENTERA —no solo el
    -- exceso— porque el monto «depende del mero arbitrio del empleador sin
    -- atender a los lugares de residencia ni a otros criterios objetivos». Una
    -- tarifa que sigue al pasaje de cada ciudad es exactamente ese criterio.
    --
    -- Sin fila para su sede cae al valor general, asi que una base sin las filas
    -- nuevas se comporta exactamente igual que antes.
    cross join lateral (
      select coalesce((
        select pl.valor
        from parametros_laborales pl
        where pl.clave = 'movilidad_diaria'
          and pl.sede_codigo = pe.sede_movilidad   -- CAMBIO 0166
          and pl.vigente_desde <= p_fin
          and (pl.vigente_hasta is null or pl.vigente_hasta >= p_fin)
        order by pl.vigente_desde desc
        limit 1
      ), v_movilidad) as tarifa
    ) tar
    -- ⇩⇩⇩ CAMBIO 0159 ⇩⇩⇩ ¿Tiene su declaración de ruta firmada?
    --
    -- Cuenta si está firmada en o antes del fin del periodo: el papel tiene que
    -- existir antes de que el pago se haga, no antes de que el periodo empiece.
    -- Firmar a mitad de mes cubre ese mes, que es lo indulgente y lo defendible.
    --
    -- Una NEGATIVA no habilita: se documenta que se ofreció, pero sin pacto
    -- individual firmado el monto deja de ser no remunerativo, y pagarlo igual
    -- es exactamente lo que la RTF 05449-4-2007 sancionó — con el agravante de
    -- que el acta deja por escrito que la persona se negó.
    cross join lateral (
      select exists (
        select 1 from documentos_firmados d
        where d.tipo = 'ruta'
          and d.persona_id = pe.id
          and d.anulado_at is null
          and not d.es_negativa
          and d.fecha_firma <= p_fin
      ) as tiene_declaracion
    ) decl
    left join lateral (
      select coalesce(sum(x.h), 0) as horas_mes,
             count(*) filter (where x.h > 0) as dias,
             count(*) filter (where x.pendiente) as pendientes
      from horas x where x.persona_id = pe.id
    ) h on true
    left join lateral (
      -- CAMBIO 0105 — Puntuación de rendimiento del mes.
      --
      -- SIN FILA, EL DEFECTO ES 100 (decidido con Felipe el 2026-07-28). Eso no
      -- le cambia el sueldo a nadie: al 100% la fórmula da
      -- básica + (rango − básica) = el rango exacto, que es lo que ya se pagaba.
      -- Lo que sí gana es que la boleta muestre la estructura legal en TODAS,
      -- desde el primer mes, en vez de solo en las de quien tenga puntuación.
      -- Para bajarle a alguien hay que escribir su fila a mano: el sistema nunca
      -- recorta por omisión.
      select rm.porcentaje,
             coalesce(ec.etiqueta, 'Rendimiento Extraordinario') as etiqueta
      from rendimiento_mensual rm
      left join etiquetas_complemento ec on ec.codigo = rm.etiqueta_codigo
      where rm.persona_id = pe.id and rm.anio = v_anio and rm.mes = v_mes
      limit 1
    ) rmp on true
    left join lateral (
      -- SUELDO FIJO: quien lo tiene cobra su remuneración completa del periodo,
      -- marque o no (socios, dirección). Para el resto la fórmula es EXACTAMENTE
      -- la de siempre — la rama `else` es idéntica a la anterior, así que ningún
      -- pago existente se mueve.
      -- ⇩ CAMBIO 0177 ⇩ Un día de vacaciones vale el PROMEDIO de lo que se le
      -- pagó por día trabajado en el periodo. Es literal el art. 15 del D. Leg.
      -- 713: «la remuneración que hubiera percibido de continuar laborando».
      -- Se deriva de hh.pago en vez de recalcular el salario, para que cualquier
      -- cambio futuro en la fórmula del sueldo arrastre solo, sin dos verdades.
      -- Sueldo fijo no lo suma: ya cobra el periodo completo, marque o no.
      -- `horas_vacaciones` es el mismo día expresado en HORAS, y lo usa el bloque
      -- `fer`: si el día cuenta como trabajado para el sueldo, cuenta también
      -- para el prorrateo del feriado. Tenerlo en un solo sitio evita que el
      -- mismo día sea «trabajado» en una línea y «no trabajado» en la de al lado.
      select case when pe.sueldo_fijo then coalesce(sf.salario, 0)
                  else coalesce(hh.pago, 0)
                       -- CAMBIO 0275 · LA MISMA TARIFA DE RESPALDO QUE LA 0254.
                       -- Lo normal sigue siendo el promedio de lo que se le pago
                       -- por dia trabajado (art. 15 del D. Leg. 713, la 0177).
                       -- Pero quien pasa el periodo ENTERO de vacaciones no tiene
                       -- dias marcados: el promedio es 0/0 y cobra CERO el mes de
                       -- su descanso. La 0254 ya resolvio exactamente esto para el
                       -- descanso medico y la 0262 para la maternidad; vacaciones
                       -- —que es el caso MAS probable de los tres, porque son 30
                       -- dias calendario contra un periodo de 31— se quedo sin el.
                       + coalesce(
                           hh.pago / nullif(hh.dias_marcados, 0),
                           coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                           0
                         ) * coalesce(vacd.dias, 0)
                       -- CAMBIO 0254 · los dias de descanso medico que asume CAYLA.
                       -- Van DENTRO de pago_base, igual que los de vacaciones desde
                       -- la 0177, y por la misma razon practica: chk_foto_cuadra
                       -- compara el total contra pago_base, asi que un concepto
                       -- nuevo por fuera obligaria a tocar la tabla congelada, la
                       -- restriccion y fn_planilla_congelar. Aqui los dos lados se
                       -- mueven juntos y no hay nada que descuadrar.
                       --
                       -- LA TARIFA DEL DIA, con respaldo. Lo normal es el promedio
                       -- de lo que se le pago por dia trabajado, que es lo que hace
                       -- la 0177. Pero quien pasa el periodo ENTERO de descanso
                       -- medico no tiene dias marcados: el promedio seria 0/0 y
                       -- cobraria cero, que es justo el defecto que esta migracion
                       -- viene a quitar. Por eso el respaldo con su tarifa de
                       -- contrato: salario del tramo entre sus dias laborables.
                       + coalesce(
                           hh.pago / nullif(hh.dias_marcados, 0),
                           coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                           0
                         ) * coalesce(dmd.dias, 0)
                       -- CAMBIO 0262 · el subsidio por maternidad, DENTRO de
                       -- pago_base por el mismo argumento que la 0254 escribio
                       -- para el descanso medico: un concepto por fuera obliga a
                       -- columna nueva, a tocar fn_planilla_congelar y a
                       -- reescribir chk_foto_cuadra, y olvidar uno de los tres
                       -- aborta el cierre para todo el equipo. Aqui los dos lados
                       -- se mueven juntos y no hay nada que descuadrar.
                       + round(coalesce(mat.monto, 0), 2)
                  end as pago_base,
             -- Informativos, para que la boleta pueda decirlo con su nombre.
             case when pe.sueldo_fijo then 0
                  else coalesce(
                         hh.pago / nullif(hh.dias_marcados, 0),
                         coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                         0
                       ) * coalesce(dmd.dias, 0) end as monto_descanso_medico,
             coalesce(dmd.dias, 0) as dias_descanso_medico_pagados,
             -- CAMBIO 0262 · informativos. El monto YA esta en pago_base.
             case when pe.sueldo_fijo then 0
                  else round(coalesce(mat.monto, 0), 2) end as monto_subsidio_maternidad,
             coalesce(mat.dias, 0) as dias_subsidio_maternidad,
             coalesce(mat.dias_sin_monto, 0) as dias_maternidad_sin_monto,
             -- CAMBIO 0262 · EL PISO DE ESSALUD, PRORRATEADO.
             --
             -- El art. 33 del D.S. 009-97-SA dice que la base minima RMV se
             -- aplica «independientemente de las horas y dias laborados» —de ahi
             -- el piso de la 0116— PERO agrega una excepcion expresa: cuando la
             -- persona percibe SUBSIDIOS, la base minima «se determinara de forma
             -- proporcional a los dias no subsidiados del mes».
             --
             -- Sin esto, por alguien de licencia todo el mes CAYLA declararia la
             -- RMV entera y aportaria 9% sobre ella, cuando la ley le pide 9%
             -- sobre la parte no subsidiada. No perjudica a la persona: es plata
             -- de la empresa y una declaracion que no corresponde.
             --
             -- El divisor es el PERIODO (29 al 28), no el mes calendario, porque
             -- es el tramo que esta planilla liquida. La norma dice «del mes»;
             -- aqui el mes de pago es el periodo.
             round(v_rmv * ((p_fin - p_ini + 1)
                            - (case when pe.sueldo_fijo then 0
                                    else coalesce(mat.dias, 0) end))::numeric
                         / (p_fin - p_ini + 1), 2) as piso_essalud,
             case when pe.sueldo_fijo then 0
                  else coalesce(                       -- CAMBIO 0275
                         hh.pago / nullif(hh.dias_marcados, 0),
                         coalesce(sf.salario, 0) / nullif(labp.dias, 0),
                         0
                       ) * coalesce(vacd.dias, 0) end as monto_vacaciones,
             -- ⇩ CAMBIO 0276 ⇩ `horas_vacaciones` y `horas_descanso_medico`
             -- vivían acá y las usaba UN solo consumidor: el prorrateo del
             -- feriado. Ese se mudó a `fn_feriado_devengado`, que las calcula
             -- con la MISMA fórmula —respaldo de la 0275 incluido— y por eso
             -- estas dos columnas se retiran en vez de quedarse sin lector.
             coalesce(vacd.dias, 0) as dias_vacaciones_pagados,
             coalesce(hh.basica, 0) as basica,   -- CAMBIO 0105
             coalesce(hh.sin_sal, 0) as horas_sin_salario
      from (select 1) _sf
      left join lateral (
        -- ⇩ CAMBIO 0105 ⇩ El salario del día deja de ser un bloque único: es la
        -- básica legal más la brecha hasta el rango, multiplicada por la
        -- puntuación del mes (100 si no hay fila). Dos guardas para que nunca
        -- pague de menos por descuido:
        --   · sin básica legal fijada → el salario del tramo, como siempre
        --   · si el tramo está por debajo de la básica → el tramo, sin subirlo
        -- Y la propiedad que lo hace seguro: al 100%, base + (rango − base) es
        -- el rango exacto, así que el defecto no mueve ningún pago.
        select coalesce(sum(case when tt.salario is not null then x.h * (
                 case
                   when pe.sueldo_base_legal is null then tt.salario
                   when tt.salario <= pe.sueldo_base_legal then tt.salario
                   -- CAMBIO 0171 · el rendimiento ya no escala el sueldo.
                   -- Antes: basica + (salario - basica) x porcentaje/100. Al 100%
                   -- daba el salario exacto, pero escribir un 80 le recortaba el
                   -- sueldo a una persona con dos clics. Ahora se paga el tramo.
                   else tt.salario
                 end
               ) / v_base end), 0) as pago,
               -- La parte que corresponde a la básica legal NO se escala por la
               -- puntuación: es lo fijo. Se prorratea solo por horas.
               coalesce(sum(case when tt.salario is not null and pe.sueldo_base_legal is not null
                                 then x.h * least(pe.sueldo_base_legal, tt.salario) / v_base end), 0) as basica,
               coalesce(sum(case when tt.salario is null then x.h end), 0) as sin_sal,
               -- CAMBIO 0177 · cuánto vale UN día de esta persona, en soles y en
               -- horas, sin volver a derivar su salario ni su jornada.
               count(*) filter (where x.h > 0) as dias_marcados,
               coalesce(sum(x.h), 0) as horas_totales
        from horas x
        left join lateral (
          select t.salario from tramos t
          where t.persona_id = x.persona_id and x.fecha between t.t_ini and t.t_fin
          order by t.t_ini desc limit 1
        ) tt on true
        where x.persona_id = pe.id
      ) hh on true
      left join lateral (
        select t.salario from tramos t
        where t.persona_id = pe.id
        order by t.t_fin desc, t.t_ini desc limit 1
      ) sf on true
      -- ⇩⇩⇩ CAMBIO 0177 ⇩⇩⇩ Días del periodo que esta persona pasó de vacaciones
      -- Y que además le tocaba trabajar. Los domingos dentro del rango no se
      -- cuentan: no los habría trabajado, así que pagarlos sería pagar de más.
      -- La condición de «¿le tocaba?» es LA MISMA que usa el bloque `lab` y que
      -- usan las faltas (0054, 0060): horario_por_dia si existe, dias_laborables si no.
      left join lateral (
        select count(*)::int as dias
        from generate_series(p_ini, p_fin, interval '1 day') d
        join lateral (
          select ha.dias_laborables, ha.horario_por_dia
          from horarios_asignados ha
          where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
          order by ha.vigente_desde desc limit 1
        ) hv on true
        -- ⇩ CAMBIO 0186 ⇩ Solo a quien está en planilla. Un locador no tiene
        -- vacaciones: no son un permiso, son un beneficio social de una relación
        -- laboral. Va acá arriba y no en el `select` de fuera porque `vacd.dias`
        -- alimenta tres columnas —pago_base, monto_vacaciones y horas_vacaciones—
        -- y filtrar en una sola dejaría el día siendo «pagado» en un sitio y
        -- «no trabajado» en otro. Es el mismo cuidado que la 0177 se tomó con el
        -- feriado. Ver la cabecera para por qué esto es más que un monto.
        where pe.en_planilla
          and exists (
                select 1 from vacaciones v
                where v.persona_id = pe.id
                  and d.d::date between v.fecha_inicio and v.fecha_fin)
          and case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                else extract(dow from d.d)::int = any(hv.dias_laborables)
              end
      ) vacd on true
      -- ⇧⇧⇧ CAMBIO 0177 ⇧⇧⇧

      -- ⇩⇩⇩ CAMBIO 0254 ⇩⇩⇩ Dias de descanso medico que CAYLA paga
      --
      -- DOS CUENTAS DISTINTAS QUE NO SE MEZCLAN, y mezclarlas da mal las dos:
      --   · el TOPE se cuenta en dias CALENDARIO del ano, porque asi lo cuenta
      --     EsSalud y asi lo escribe el RIT art. 31 f);
      --   · lo que se PAGA son los dias que le tocaba trabajar, porque pagar un
      --     domingo que no habria trabajado seria pagar de mas. Es el mismo
      --     cuidado que se tomo la 0177 con las vacaciones.
      --
      -- La numeracion va PARTIDA POR ANO y sobre el rango entero de la ausencia,
      -- no recortada al periodo: un descanso del 28/12 al 05/01 aporta 4 dias a
      -- un ano y 5 al siguiente, que es como lo cuenta la 0197.
      --
      -- Y UN DIA QUE YA PAGA POR OTRA VIA NO SE PAGA DOS VECES. El caso salio
      -- solo: el descanso medico del 29/07 al 03/08 de 2026 empieza en Fiestas
      -- Patrias, que la planilla ya paga en su propia linea. Sin este filtro ese
      -- dia se cobraria dos veces, y el descuadre no lo caza nadie porque las dos
      -- lineas estarian "bien" cada una por su lado.
      left join lateral (
        select count(*)::int as dias
        from (
          select dd.d::date as dia,
                 row_number() over (partition by extract(year from dd.d)
                                    order by dd.d) as n
          from ausencias a
          join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
          where a.persona_id = pe.id
            and a.tipo = 'descanso_medico'
            and a.anulada_at is null
        ) dm
        join lateral (
          select ha.dias_laborables, ha.horario_por_dia
          from horarios_asignados ha
          where ha.persona_id = pe.id and ha.vigente_desde <= dm.dia
          order by ha.vigente_desde desc limit 1
        ) hv on true
        where pe.en_planilla
          and dm.n <= v_tope_dm
          and dm.dia between p_ini and p_fin
          and not exists (select 1 from feriados f where f.fecha = dm.dia)
          and not exists (select 1 from vacaciones v
                           where v.persona_id = pe.id
                             and dm.dia between v.fecha_inicio and v.fecha_fin)
          and case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from dm.dia)::int::text)
                else extract(dow from dm.dia)::int = any(hv.dias_laborables)
              end
      ) dmd on true

      -- ⇩⇩⇩ CAMBIO 0262 ⇩⇩⇩ EL SUBSIDIO POR MATERNIDAD.
      --
      -- CUENTA DIAS CALENDARIO, no dias laborables, y esa es la diferencia de
      -- fondo con el lateral `dmd` de arriba. El descanso medico que asume CAYLA
      -- es SUELDO: se paga por los dias que a esa persona le tocaba trabajar. El
      -- subsidio de maternidad no es sueldo — es una prestacion economica de
      -- EsSalud que cubre los 98 dias corridos de la licencia, domingos
      -- incluidos. Contarlo por dias laborables le quitaria a una integrante de
      -- Lima (5 dias) dos septimos de lo que le corresponde.
      --
      -- EL MONTO NO SE CALCULA AQUI, Y ES DELIBERADO. El promedio diario sale de
      -- los 12 meses anteriores a la contingencia, y esos 12 meses pueden incluir
      -- empleadores anteriores a CAYLA: una persona con ocho meses de casa tiene
      -- cuatro meses de historia que esta base NO CONTIENE. Calcularlo con lo que
      -- hay adentro produciria un numero mas bajo que el legal, con toda la
      -- apariencia de estar bien. Lo entra DO en `ausencias.subsidio_diario`,
      -- tomandolo del calculo de EsSalud, y aqui solo se multiplica.
      --
      -- EL FERIADO DE DENTRO SI SE CUENTA, y aqui esta la diferencia con el
      -- lateral `dmd`. Medido el 2026-08-15: quien pasa el periodo entero de
      -- licencia devenga S/0.00 de feriados —`fer` los paga en proporcion a las
      -- horas del mes, y no marco ninguna—, asi que excluir el feriado no evitaba
      -- una duplicacion: le quitaba el dia. Diez dias de licencia le pagaban
      -- nueve.
      --
      -- La duplicacion se evita por el OTRO lado, que es donde corresponde: el
      -- lateral `fer` deja de devengar los feriados que caen dentro de una
      -- licencia subsidiada. Durante el descanso el contrato esta suspendido y
      -- el feriado no genera concepto propio (D. Leg. 713 art. 8, que remite al
      -- art. 4: se abona «en forma directamente proporcional al numero de dias
      -- efectivamente trabajados»). El dia lo cubre el subsidio, entero.
      left join lateral (
        select coalesce(sum(case when x.subsidio_diario is not null
                                 then x.dias else 0 end), 0)::int          as dias,
               coalesce(sum(case when x.subsidio_diario is not null
                                 then x.dias * x.subsidio_diario
                                 else 0 end), 0)                           as monto,
               -- Los dias de licencia SIN monto entrado. No se pagan —no hay con
               -- que— pero viajan al JSON para que la pantalla pueda gritarlo. Un
               -- cero mudo aqui es exactamente el defecto que la 0254 vino a
               -- quitar del descanso medico.
               coalesce(sum(case when x.subsidio_diario is null
                                 then x.dias else 0 end), 0)::int          as dias_sin_monto
        from (
          select a.id, a.subsidio_diario, count(*)::int as dias
          from ausencias a
          join lateral generate_series(a.fecha_inicio, a.fecha_fin, interval '1 day') as dd(d) on true
          where a.persona_id = pe.id
            and a.tipo = 'maternidad'
            and a.anulada_at is null
            and pe.en_planilla
            and dd.d::date between p_ini and p_fin
            -- Las vacaciones si se descuentan: viven en otra tabla, pueden
            -- solaparse con la licencia y `vacd` ya las paga por su cuenta.
            and not exists (select 1 from vacaciones v
                             where v.persona_id = pe.id
                               and dd.d::date between v.fecha_inicio and v.fecha_fin)
          group by a.id, a.subsidio_diario
        ) x
      ) mat on true

      -- Sus dias laborables del periodo. Solo alimenta el respaldo de la tarifa
      -- de arriba, para quien no marco ni un dia. No entra en ningun otro pago.
      left join lateral (
        select count(*)::int as dias
        from generate_series(p_ini, p_fin, interval '1 day') d
        join lateral (
          select ha.dias_laborables, ha.horario_por_dia
          from horarios_asignados ha
          where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
          order by ha.vigente_desde desc limit 1
        ) hv on true
        where case
                when hv.horario_por_dia is not null
                  then hv.horario_por_dia ? (extract(dow from d.d)::int::text)
                else extract(dow from d.d)::int = any(hv.dias_laborables)
              end
      ) labp on true
      -- ⇧⇧⇧ CAMBIO 0254 ⇧⇧⇧
    ) pb on true
    -- ⇩⇩⇩ CAMBIO 0199 ⇩⇩⇩ EL FACTOR SE APAGA EN ORIGEN, igual que en la 0196.
    --
    -- LA BOLETA TIENE SUS PROPIAS PROVISIONES. No salen de `fn_provisiones`:
    -- salen de acá. La 0196 conectó el interruptor por persona allá y dejó esta
    -- función sin tocar, así que la boleta de un locador seguía imprimiendo
    -- «Gratificación — la parte de este mes» con su monto al lado. Lo destapó la
    -- boleta en pantalla, no ninguna prueba: dos funciones calculaban lo mismo y
    -- solo una se enteró del cambio.
    --
    -- Cinco expresiones usan estos factores. Apagarlos acá las apaga las cinco;
    -- ponerle un `case` a cada una sería pedir que alguien olvide la quinta.
    cross join lateral (
      select case when fn_devenga(pe.id, 'grati')      then v_f_grati else 0 end as f_grati,
             case when fn_devenga(pe.id, 'cts')        then v_f_cts   else 0 end as f_cts,
             case when fn_devenga(pe.id, 'vacaciones') then v_f_vacas else 0 end as f_vacas
    ) dev
    -- ⇩ CAMBIO 0185 ⇩ El sobretiempo de esta persona, si lo hubo.
    --
    -- NO aplica a RxH ni a sueldo fijo, y por motivos distintos:
    --   · RxH: un locador no tiene jornada de trabajo. Pagarle horas extras
    --     sería un indicio de laboralidad, igual que la movilidad supeditada a
    --     asistencia que la 0117 ya le quitó.
    --   · Sueldo fijo: el art. 5 del D.S. 007-2002-TR excluye de la jornada
    --     máxima al personal de dirección y a quien no está sujeto a
    --     fiscalización inmediata — que es exactamente quién tiene sueldo fijo
    --     acá. Y su pago no depende de horas: calcular recargo sobre un monto
    --     fijo no significaría nada.
    left join lateral (
      select s.horas, s.horas_recargo, s.desde, s.hasta
      from sobret s
      where s.persona_id = pe.id
        and pe.en_planilla is true
        and pe.sueldo_fijo is not true
        -- ⇩ CAMBIO 0187 ⇩ Personal de dirección. Es una tercera exclusión, no
        -- una variante de las dos de arriba: cobra por horas (no tiene sueldo
        -- fijo) y está en planilla (no es locador). Lo que la deja fuera es una
        -- categoría laboral, y por eso vive en su propia columna.
        and pe.personal_direccion is not true
    ) ot on true
    left join lateral (
      select t.rango, t.salario, t.base_provision              -- CAMBIO 0111
      from tramos t
      where t.persona_id = pe.id
      order by t.t_fin desc, t.t_ini desc
      limit 1
    ) ref on true
    -- ⇩⇩⇩ CAMBIO 0114 ⇩⇩⇩ La tasa de pensión EXACTA de esta persona.
    --
    -- Hasta la 0113 el descuento usaba una sola tasa global (configuracion.tasa_afp,
    -- el 13% aproximado). Ahora sale del régimen de cada uno: Profuturo cobra
    -- 13.06%, Integra 12.92%, Prima 12.97%, Habitat 12.84% y la ONP 13.00% exacto.
    --
    -- Se elige la fila VIGENTE a la fecha de fin del periodo, no la última: así un
    -- periodo de mayo se calcula con la comisión que estaba vigente en mayo, aunque
    -- la AFP la haya cambiado en junio. Las comisiones se mueven, y la prima de
    -- seguro la actualiza la SBS cada trimestre.
    --
    -- SI LA PERSONA NO TIENE RÉGIMEN ASIGNADO, el lateral no devuelve fila y más
    -- abajo el coalesce cae a la tasa global. Así nadie se queda sin descuento por
    -- un dato faltante, y la migración se puede aplicar aunque falten personas por
    -- clasificar.
    left join lateral (
      select tp.aporte + tp.comision + tp.prima as tasa,
             -- CAMBIO 0262 · si este regimen grava el subsidio de EsSalud.
             tp.grava_subsidio
      from tasas_pension tp
      where tp.regimen = pe.regimen_pension
        and tp.vigente_desde <= p_fin
        and (tp.vigente_hasta is null or tp.vigente_hasta >= p_fin)
      order by tp.vigente_desde desc
      limit 1
    ) tpen on true
    -- ⇩⇩⇩ CAMBIO 0120 ⇩⇩⇩ LA ASIGNACIÓN POR EDUCACIÓN, por persona y con vigencia.
    --
    -- Por persona y no por rango porque depende del curso que cada uno lleva y de
    -- que traiga su comprobante. Dos personas del mismo rango pueden tener montos
    -- distintos, y eso no es un problema: es lo correcto, porque cada monto sigue
    -- el costo real de SU estudio. Que fueran todos iguales sería la señal de que
    -- el monto no sale de un comprobante sino de una resta.
    --
    -- Con vigencia porque alguien deja de estudiar en diciembre y en enero su
    -- asignación tiene que ser cero sin reescribir los meses en que sí estudió.
    -- ⇩⇩⇩ CAMBIO 0150 ⇩⇩⇩ Tres cambios, cada uno cerrando un agujero medido:
    --
    --   SUM y no LIMIT 1 · quien estudia y además tiene un hijo estudiando tenía
    --     dos filas y cobraba una; la otra se descartaba en silencio. El techo
    --     del rango se valida sobre la suma desde la 0149, así que sumar acá no
    --     puede pasarse del techo.
    --
    --   comprobante_url is not null · sin el papel no se paga. Una asignación se
    --     puede guardar mientras el comprobante llega (queda en amarillo en la
    --     pantalla), pero no devenga hasta que el papel esté cargado. Es lo que
    --     mantiene al concepto fuera de la remuneración: pagar sin comprobante es
    --     el caso exacto que la RTF 05449-4-2007 usó para desconocerlo.
    --
    --   p_ini y no p_fin · antes exigía seguir vigente el ÚLTIMO día del periodo,
    --     así que un ciclo que terminaba el 15 hacía que ese mes pagara CERO —
    --     habiendo estudiado y pagado la pensión del mes. Ahora basta con estar
    --     vigente al INICIAR el periodo y se paga el mes completo, que es como
    --     factura la institución.
    left join lateral (
      select sum(ae.monto) as monto,
             string_agg(distinct ae.institucion, ' · ') as instituciones
      -- ⇩⇩⇩ CAMBIO 0233 ⇩⇩⇩ El día de referencia, no el primer día del periodo.
      --
      -- La regla «vigente al iniciar» de arriba dejaba en CERO a todo el equipo:
      -- el periodo empieza el 29 del mes anterior y DO registra con fecha del
      -- día 1, así que `01/08 <= 29/07` era falso para las siete filas vigentes.
      -- Con periodos del 29 al 28, el día 1 ya es «a mitad de periodo»: el borde
      -- que la 0150 dejó abierto a propósito resultó ser el caso normal.
      --
      -- La 0150 anotó el arreglo como «cambiar p_ini por p_fin, una línea». Esa
      -- línea sola paga DOBLE, medido: una renovación que corta dentro del
      -- periodo —ciclo I hasta el 20/08, ciclo II desde el 21/08— se solapa por
      -- los dos lados y `sum()` cobra los dos ciclos. Con los datos de hoy no es
      -- hipotético: seis de las siete filas vencen entre el 31/08 y el 15/09 y
      -- renuevan al día siguiente.
      --
      -- Así que el filtro se parte en dos. `dref` busca el primer día del periodo
      -- en que la persona tiene ALGUNA asignación vigente; el `where` cobra las
      -- que estén vigentes ESE día. Un solo instante —nunca dos ciclos seguidos
      -- en el mismo mes— y un instante que se corre hacia adelante —quien
      -- empieza a mitad ya cobra—.
      --
      -- Las otras tres reglas siguen intactas y están medidas: dos cursos de
      -- verdad simultáneos suman igual, sin comprobante sigue sin pagar, y un
      -- ciclo que termina el día 5 sigue cobrando el mes completo.
      from asignaciones_educacion ae
      cross join lateral (
        select min(greatest(a2.vigente_desde, p_ini)) as dia
        from asignaciones_educacion a2
        where a2.persona_id = pe.id
          and a2.comprobante_url is not null
          and a2.vigente_desde <= p_fin
          and a2.vigente_hasta >= p_ini
      ) dref
      where ae.persona_id = pe.id
        and ae.comprobante_url is not null
        and ae.vigente_desde <= dref.dia
        and ae.vigente_hasta >= dref.dia
    ) edu on true
    -- ⇩⇩⇩ CAMBIO 0236 ⇩⇩⇩ Por qué la educación vale cero, para que la boleta
    -- pueda decirlo en vez de borrar la línea.
    --
    -- Hasta hoy la boleta pintaba el concepto bajo `educacion > 0`, así que un
    -- monto en cero no salía en el documento: no salía «S/0.00», no salía nada.
    -- Es la razón de que el defecto que arregló la 0233 estuviera un mes entero
    -- a la vista de todo el equipo sin que nadie pudiera verlo — siete personas
    -- con su asignación vigente y su comprobante cargado, cobrando cero, y siete
    -- boletas que no mencionaban la educación por ninguna parte.
    --
    -- Un concepto que desaparece cuando falla es peor que uno que sale mal: el
    -- que sale mal se reclama. Con estos dos datos la boleta escribe la línea en
    -- cero y dice cuál de las dos cosas pasó.
    --
    -- Mira TODAS las asignaciones que se solapan con el periodo, con papel o sin
    -- él: la pregunta no es «cuánto se paga» —eso ya lo contestó `edu`— sino «hay
    -- algo que explicar». Por eso no filtra por comprobante ni por día de
    -- referencia. Si no hay ninguna, la persona no estudia y la boleta no dibuja
    -- nada, que es lo correcto: una línea en cero para quien no estudia sería
    -- ruido, no transparencia.
    left join lateral (
      select count(*) > 0 as hay,
             count(*) filter (where ae.comprobante_url is null) > 0 as sin_papel
      from asignaciones_educacion ae
      where ae.persona_id = pe.id
        and ae.vigente_desde <= p_fin
        and ae.vigente_hasta >= p_ini
    ) edudiag on true
    -- CAMBIO 0276 - EL FERIADO YA NO SE CALCULA ACA: SE PREGUNTA.
    left join lateral (
      select (fd.j->>'monto')::numeric      as monto,
             (fd.j->>'sin_tramo')::int      as sin_tramo,
             (fd.j->>'no_corresponde')::int as no_corresponde,
             (fd.j->>'compensados')::int    as compensados,
             fd.j->'detalle'                as detalle
      from (select fn_feriado_devengado(pe.id, p_ini, p_fin, v_dias) as j) fd
    ) fer on true
    left join lateral (
      select om.cumplidos, om.total,
             case
               when om.cumplidos is null or ref.salario is null then 0
               -- CAMBIO 0171 · el plus por objetivos deja de pagar. Antes:
               -- 21% del salario al 100% de metas, 12.6% desde el 60%. Se
               -- devuelven los objetivos (sirven para promover) y cero soles.
               else 0
             end as monto
      from (select 1) uno
      left join objetivos_mensuales om
        on om.persona_id = pe.id and om.anio = v_anio and om.mes = v_mes
    ) obj on true
    -- ⇩ CAMBIO 0100 ⇩ Días del periodo que caen dentro de un periodo de
    -- vacaciones de esta persona. Solo se LEE: esta función nunca escribe.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      where exists (
        select 1 from vacaciones v
        where v.persona_id = pe.id
          and d.d::date between v.fecha_inicio and v.fecha_fin
      )
    ) vac on true
    -- Días que esta persona TENÍA que trabajar según su horario vigente. Si son
    -- cero, no marcó porque no le tocaba: no es una ausencia, es un dato que falta.
    left join lateral (
      select count(*)::int as dias
      from generate_series(p_ini, p_fin, interval '1 day') d
      join lateral (
        select ha.dias_laborables, ha.horario_por_dia   -- CAMBIO 0109
        from horarios_asignados ha
        where ha.persona_id = pe.id and ha.vigente_desde <= d.d::date
        order by ha.vigente_desde desc limit 1
      ) hh on true
      -- ⇩⇩⇩ CAMBIO 0109 ⇩⇩⇩ Dos arreglos en una condición.
      --
      -- 1. isodow → dow. Postgres tiene dos funciones de día de semana y devuelven
      --    números distintos para el domingo: dow da 0, isodow da 7. TODO el resto
      --    del sistema usa dow —la 0015 valida el rango 0..6, las faltas (0054, 0060),
      --    el auto-cierre (0036) y la pantalla de Turnos— y el esquema documenta
      --    «0=domingo … 6=sábado». Solo esta línea usaba isodow.
      --    Como el array solo admite 0..6, el domingo únicamente puede guardarse
      --    como 0, e isodow jamás devuelve 0: el domingo NUNCA contaba como día
      --    laborable. En Trujillo se trabaja domingo, así que a esa gente le faltaban
      --    ~4 días al mes en la cuenta.
      --    Ese era el origen del «21 de 10 días que te tocaba trabajar» que apareció
      --    en producción: dias_trabajados sí cuenta domingos y dias_laborables no.
      --    En su momento se corrigió el TEXTO de la boleta; esta es la causa.
      --
      -- 2. Preferir horario_por_dia. La 0016 dejó dicho que dias_laborables queda
      --    como RESUMEN de compatibilidad y que la fuente de verdad es
      --    horario_por_dia (claves 0..6, día ausente = descanso). Las faltas ya lo
      --    leen así; la planilla se había quedado en el campo viejo. Ahora usa el
      --    mismo orden de preferencia que 0054 y 0060, para que no haya dos
      --    respuestas distintas a «¿le tocaba trabajar este día?».
      --
      -- NO MUEVE NINGÚN PAGO. lab.dias se usa en un solo lugar de toda la función:
      -- el campo 'dias_laborables' del JSON. No entra en pago_base, ni en feriados,
      -- ni en las provisiones. El generador lo verifica abajo.
      where case
              when hh.horario_por_dia is not null
                then hh.horario_por_dia ? (extract(dow from d.d)::int::text)
              else extract(dow from d.d)::int = any(hh.dias_laborables)
            end
    ) lab on true
    left join lateral (
      select coalesce(sum(m.monto) filter (where m.tipo = 'bono'), 0) as bonos,
             coalesce(sum(m.monto) filter (where m.tipo = 'descuento'), 0) as descuentos,
             coalesce(jsonb_agg(jsonb_build_object(
               'id', m.id, 'tipo', m.tipo, 'concepto', m.concepto, 'monto', m.monto
             ) order by m.created_at) filter (where m.id is not null), '[]'::jsonb) as detalle
      from movimientos_planilla m
      where p_periodo_id is not null
        and m.periodo_id = p_periodo_id
        and m.persona_id = pe.id
    ) mov on true
    -- ⇩⇩⇩ CAMBIO 0192 ⇩⇩⇩ LA BASE IMPONIBLE, EN UN SOLO SITIO.
    --
    -- Refactor puro: esta migración NO cambia ni un céntimo. Lo único que hace
    -- es dejar de repetir cinco veces la misma expresión.
    --
    -- «básica + asignación familiar» estaba escrita literal en cinco lugares:
    -- descuento_afp, la resta de ese descuento dentro del total, base_essalud,
    -- aporte_essalud y essalud_es_piso. Cinco copias de una regla que la ley
    -- puede cambiar de un día para otro, y donde basta olvidar una para que la
    -- boleta muestre un descuento que no cuadra con su propia base.
    --
    -- Es el mismo patrón que en este repo ya juntó 35 copias de una condición de
    -- permiso y 32 del huso horario de Lima, y se resuelve igual: un solo sitio
    -- que lo diga, y todos leyendo de ahí.
    --
    -- QUÉ PROMETE ESTE BLOQUE
    --   bri.base = la remuneración afecta a EsSalud y a pensión, ANTES del piso
    --   de la RMV. El piso se aplica solo a EsSalud (Ley 26790 art. 6) y por eso
    --   vive fuera de acá: la pensión no tiene piso.
    --
    -- QUÉ ASUME
    --   Que la base sale de pb.basica y NO de pb.pago_base. La diferencia entre
    --   las dos es el complemento variable, y que quede fuera es una decisión de
    --   estructura remunerativa, no un olvido: está sustentada en
    --   docs/analisis-estructura-remunerativa-2026-07-30.md. Al 2026-08-08 esa
    --   diferencia es CERO —se declara el sueldo íntegro, medido: 22 de 22
    --   personas— pero la distinción sigue importando el día que alguien vuelva
    --   a mirar esto.
    left join lateral (
      -- ⇩⇩⇩ CAMBIO 0242 ⇩⇩⇩ QUIEN NO ES TRABAJADORA NO TIENE BASE IMPONIBLE.
      --
      -- El descuento de pensión es `bri.base × tasa` y era el ÚNICO concepto sin
      -- guarda de vínculo: EsSalud y movilidad la llevan desde la 0117, la
      -- educación desde la 0120, las sobretasas desde la 0193. Este descansaba en
      -- que la base de un locador fuera 0 «porque su básica es 0» — y eso lo
      -- decide el DEFAULT 1130.00 de `personas.sueldo_base_legal` (0103), no una
      -- decisión. Medido el 2026-08-13: con el default puesto se le retenían
      -- S/154.02 al mes, y S/168.62 si además cobraba asignación familiar.
      --
      -- Se guarda la base COMPLETA y no cada término suyo a propósito: así el día
      -- que alguien agregue un concepto nuevo a la base, queda excluido sin que
      -- tenga que acordarse. Es la lección de los tres términos que sí llevaban
      -- su condición y del que no.
      -- ⇩⇩⇩ CAMBIO 0262 ⇩⇩⇩ DOS BASES, PORQUE LA LEY LAS SEPARA.
      --
      -- El subsidio por maternidad NO es remuneracion: no entra a EsSalud (el
      -- 9% de la Ley 26790 grava remuneracion, y por eso mismo el propio
      -- reglamento excluye los subsidios del piso RMV) ni a renta de 5ta. Pero
      -- SI esta afecto al aporte a la AFP — asimetria conocida del sistema
      -- peruano: el TUO de la Ley del SPP lo cuenta como remuneracion
      -- asegurable, y la ONP no. Por eso el termino extra va condicionado a
      -- `grava_subsidio`, que vive en `tasas_pension` y no en una lista escrita
      -- aqui: el dia que cambie el criterio es un UPDATE, no una migracion.
      --
      -- `base_pension` se DERIVA de `base` por nombre, no repitiendo la suma.
      -- Es la regla de la 0192: la base imponible se dice una sola vez. Un
      -- envoltorio de mas cuesta una linea; dos copias de la misma suma cuestan
      -- el dia que alguien agregue un concepto a una y no a la otra.
      -- SE RETIENE SOBRE LO QUE SE PAGO, y por eso el termino se toma de
      -- `pb.monto_subsidio_maternidad` y no del lateral `mat`. Los dos valen lo
      -- mismo casi siempre, pero no para quien cobra monto fijo: `pb` ya lleva
      -- dentro el `case when pe.sueldo_fijo then 0`, porque a esa persona el
      -- subsidio no se le suma al pago. Leyendo `mat` en crudo se le retendria
      -- AFP sobre dinero que nunca entro. Una sola fuente para «cuanto cobro» y
      -- para «sobre cuanto se retiene» es lo que impide que se separen.
      select b.base,
             b.base + (case when coalesce(tpen.grava_subsidio, true)
                            then round(coalesce(pb.monto_subsidio_maternidad, 0), 2)
                            else 0 end) as base_pension
      from (
      select (case when pe.en_planilla is not true then 0 else
             coalesce(pb.basica, 0)
             + (case when pe.con_hijos then v_asig else 0 end)
             -- ⇩ CAMBIO 0193 ⇩ Las dos sobretasas legales entran a la base.
             --
             -- No son conceptos que se puedan presentar como no remunerativos:
             -- el art. 19 del D.S. 001-97-TR no las lista, y SUNAT las nombra
             -- una por una con código propio en la PLAME —0105 (sobretiempo al
             -- 25 %), 0106 (al 35 %) y 0107 (feriado o día de descanso)—. No hay
             -- estructura que defender acá; simplemente no se estaban sumando.
             --
             -- El feriado es lo que más pesa, y la razón es que no es un extra
             -- sobre el sueldo: como en CAYLA se paga por horas, quien no marca
             -- el día feriado tiene una básica más baja, y `monto_feriados` es
             -- justo la parte del sueldo que la completa. Sin él se declara
             -- MENOS que el sueldo pactado.
             --
             -- Se leen ya redondeados, igual que en el `total`, para que la base
             -- que imprime la boleta sume exactamente lo que suman sus líneas.
             --
             -- La condición NO es decoración. Las sobretasas COMPLETAN una base
             -- declarada; no pueden crear una donde no la hay:
             --   · Un locador (RxH) no aporta a pensión ni genera EsSalud. Su
             --     básica es 0, así que hoy su descuento es 0 — y sumarle el
             --     feriado se lo inventaría. Medido antes de poner esto: le
             --     aparecían S/41.39 de pensión de la nada.
             --   · Sueldo fijo (socios, dirección) tiene básica 0 a propósito,
             --     y por la misma razón: lo suyo no se declara por esta vía.
             --     Sin la condición le salían S/46.45.
             -- Es la misma condición que usa el lateral `ot` de la 0185, y eso
             -- es a propósito: dos formas distintas de decir «quién queda fuera»
             -- es como se empieza a tener dos verdades.
             + (case when pe.en_planilla is true and pe.sueldo_fijo is not true
                     then round(coalesce(fer.monto, 0), 2)
                          + round(coalesce(ot.horas_recargo, 0)
                                  * coalesce(ref.salario, 0) / v_base, 2)
                     else 0 end)
             -- ⇩⇩⇩ CAMBIO 0263 ⇩⇩⇩ LOS 20 DIAS DE DESCANSO MEDICO SON SUELDO.
             --
             -- La 0254 los metio en `pago_base` pero no en `pb.basica`, asi que
             -- no llegaban aqui: se pagaban y no se declaraban. Y no son un
             -- subsidio — el subsidio de EsSalud recien nace el dia 21. Lo que
             -- CAYLA asume del 1 al 20 es REMUNERACION (art. 15 del D.S.
             -- 009-97-SA; criterio de los Informes SUNAT 259-2004 y 003-2007), y
             -- por tanto entra a la base de EsSalud y a la de pension igual que
             -- cualquier dia trabajado.
             --
             -- EL CODIGO DE LA PLAME ES DONDE SE COMETE EL ERROR: el 0916
             -- «Subsidios de incapacidad por enfermedad» es SOLO para lo que
             -- paga EsSalud desde el dia 21. Estos 20 dias no van ahi.
             --
             -- OJO CON LA CONFUSION FACIL: esto es lo CONTRARIO del subsidio por
             -- maternidad de la 0262. Aquel NO entra a EsSalud (no es
             -- remuneracion) y ademas prorratea el piso RMV; este entra a las
             -- dos bases y no toca el piso. Se parecen en la pantalla y son
             -- opuestos en la ley. Por eso el termino va aparte y con su nombre.
             --
             -- Se lee de `pb.monto_descanso_medico` —lo efectivamente pagado— y
             -- no del lateral `dmd`, por la misma razon que la 0262: `pb` ya
             -- lleva dentro la guarda de sueldo fijo, y una sola fuente para
             -- «cuanto cobro» y para «sobre cuanto se declara» es lo que impide
             -- que se separen.
             + (case when pe.en_planilla is true and pe.sueldo_fijo is not true
                     then round(coalesce(pb.monto_descanso_medico, 0), 2)
                     else 0 end)
             end)                                             -- CAMBIO 0242
             as base
      ) b
    ) bri on true
    -- ⇧⇧⇧ CAMBIO 0192 ⇧⇧⇧
    -- ⇩⇩⇩ CAMBIO 0245 ⇩⇩⇩ LA RETENCIÓN DE 4TA, DICHA UNA SOLA VEZ.
    --
    -- Va en un lateral y no escrita dos veces por la lección de la 0192: el
    -- monto lo usan el concepto del JSON y el término del `total`, y dos
    -- copias de una regla de dinero es como se empieza a tener dos verdades.
    --
    -- LA BASE. Es lo que CAYLA le paga por su servicio ese mes: su pago por
    -- horas más los bonos más el incentivo por metas. NO se le restan los
    -- descuentos: un descuento de planilla es casi siempre «esto ya se te
    -- transfirió por fuera», y restarlo bajaría la retención de un recibo que
    -- se emitió por el monto completo. `obj.monto` vale 0 desde la 0171 y se
    -- suma igual, para que el día que el incentivo vuelva no haya que
    -- acordarse de esta línea.
    --
    -- LAS TRES PUERTAS, y ninguna se abre sola:
    --   · `retencion_4ta` en NULL —como nace todo el mundo— NO retiene nada.
    --     Por eso pegar esta migración no mueve un céntimo de nadie.
    --   · 'automatica' es la regla del art. 74 de la Ley del Impuesto a la
    --     Renta: 8 % solo si el recibo del mes SUPERA el tope (R.S.
    --     013-2007/SUNAT, hoy S/1,500). Igual o por debajo, cero.
    --   · 'siempre' retiene sea cual sea el monto. No es un capricho: lo pide
    --     el prestador al emitir el recibo, cuando sabe que sus ingresos del
    --     año lo dejan fuera de la suspensión y prefiere adelantar el pago en
    --     vez de que le caiga entero en la regularización de marzo.
    --
    -- Y LA CONSTANCIA MANDA SOBRE LAS TRES. Con el Formulario Virtual 1609
    -- vigente, SUNAT prohíbe retener. Se compara contra el FIN del periodo
    -- porque la constancia cubre el mes en que se paga, no el que se calcula.
    -- Cuando vence, el modo vuelve a mandar — que es lo que SUNAT llama
    -- «reinicio de retenciones» — y por eso el modo lo escribe una persona.
    --
    -- EL GUARDA DE VÍNCULO ES `tipo_vinculo = 'rxh'` Y NO `not en_planilla`.
    -- La renta de cuarta es del trabajador independiente; un accionista que
    -- no presta servicios ('no_trabajador') tampoco emite recibo. Nombrar la
    -- condición exacta evita que el día que aparezca un quinto vínculo herede
    -- una retención que nadie decidió darle.
    cross join lateral (
      select b.base,
             case when pe.tipo_vinculo <> 'rxh' then 0
                  when pe.retencion_4ta is null then 0
                  when pe.constancia_4ta_hasta is not null
                   and pe.constancia_4ta_hasta >= p_fin then 0
                  when pe.retencion_4ta = 'siempre' then round(b.base * v_tasa_4ta, 2)
                  when b.base > v_tope_4ta then round(b.base * v_tasa_4ta, 2)
                  else 0 end as monto,
             -- El aviso, que es la otra mitad del trabajo: un locador cuyo
             -- recibo pasa el tope y a quien nadie le configuró el modo. No
             -- retiene por su cuenta —Dynamic avisa, nunca sanciona solo—,
             -- pero deja de ser invisible en la pantalla de planilla.
             (pe.tipo_vinculo = 'rxh'
              and pe.retencion_4ta is null
              and b.base > v_tope_4ta) as sin_configurar
      from (select round(pb.pago_base, 2) + round(obj.monto, 2)
                   + round(mov.bonos, 2) as base) b
    ) r4
  ) sub;

  return v_out;
end;






$function$;

-- ── Las provisiones: una rama más en `base`, por fecha de feriado ───────────
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
        and j.fecha >= a.vigente_desde
        and (a.vigente_hasta is null or j.fecha <= a.vigente_hasta)
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
      fn_feriado_devengado(p.id,
        greatest(p.fecha_ingreso, least(c1_ini, g1_ini, v_as_of - 366)),
        v_as_of, null::int) -> 'detalle') e
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
      and not (au.tipo = 'descanso_medico'
               and exists (select 1 from feriados f where f.fecha = gs::date))

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
        and bc.fecha >= a.vigente_desde
        and (a.vigente_hasta is null or bc.fecha <= a.vigente_hasta)
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


$function$;

insert into migraciones_aplicadas (numero, nombre)
values (276, 'una_sola_base_para_la_reserva')
on conflict (numero) do nothing;

-- ── Comprobación ────────────────────────────────────────────────────────────
-- Para cada persona y cada periodo, lo que la boleta dice de feriados contra lo
-- que responde la función. Tiene que devolver CERO filas.
--
-- select pp.fecha_ini, pp.fecha_fin, e->>'nombre' as persona,
--        (e->>'monto_feriados')::numeric      as boleta,
--        round((fn_feriado_devengado((e->>'persona_id')::uuid,
--               pp.fecha_ini, pp.fecha_fin,
--               (pp.fecha_fin - pp.fecha_ini + 1)::int) ->> 'monto')::numeric, 2) as funcion
-- from periodos_planilla pp
-- cross join lateral jsonb_array_elements(
--   fn_planilla_calcular(pp.fecha_ini, pp.fecha_fin, pp.id) -> 'filas') e
-- where (e->>'monto_feriados')::numeric
--       <> round((fn_feriado_devengado((e->>'persona_id')::uuid,
--                 pp.fecha_ini, pp.fecha_fin,
--                 (pp.fecha_fin - pp.fecha_ini + 1)::int) ->> 'monto')::numeric, 2);
