-- ============================================================================
-- 0243 — La liquidación no vuelve a cobrar el mes que ya se pagó
-- ============================================================================
--
-- ⚠️⚠️ LEER ESTO ANTES DE PEGAR NADA — DECISIÓN PENDIENTE DE FELIPE ⚠️⚠️
--
--   Este archivo ESTÁ EDITADO respecto de la versión que el commit a09eade
--   («Rescatar la 0243, que ya estaba aplicada y solo vivía en esta Mac») dice
--   que se pegó en producción el 2026-08-14. Se editó porque esa versión tenía
--   cuatro defectos de dinero, medidos uno por uno contra el Postgres local y
--   corregidos aquí — están listados abajo, en «LO QUE SE ARREGLÓ DESPUÉS».
--
--   Si ese commit dice la verdad y la 0243 YA ESTÁ EN PRODUCCIÓN, entonces:
--
--     1. PRODUCCIÓN ESTÁ CORRIENDO HOY LA VERSIÓN DEFECTUOSA. El más urgente de
--        los cuatro no es silencioso: el freno del cierre no se levanta con el
--        descuento que su propio mensaje manda registrar cuando a la cesada le
--        queda un saldo ganado. El siguiente cierre de mes (28/08) se puede
--        atascar sin salida limpia con que una sola persona cese a mitad de
--        periodo, que es el orden normal —la ley obliga a liquidar en 48 h—.
--     2. ESTO NO DEBERÍA PEGARSE COMO «0243». Editar en el sitio una migración
--        ya aplicada deja el repo mintiendo sobre lo que producción recibió ese
--        día, y `migraciones_aplicadas` ya tiene el 243, así que su insert no
--        registraría nada. Lo que corresponde es cortar estos dos bloques como
--        migración NUEVA —`./scripts/siguiente-numero.sh` dice 0244— con esta
--        misma cabecera y la prueba renumerada a 185, y dejar la 0243 tal como
--        se pegó. Es un movimiento mecánico de diez minutos, pero cambia qué
--        número lleva el archivo y por eso no se hace sin decirlo.
--
--   Si ese commit se equivoca y la 0243 NO se pegó, esto se pega tal cual y no
--   hay nada más que decidir. Quien lo sabe es Felipe.
--
--   Lo que NO cambia en ninguno de los dos casos: los dos bloques son
--   `create or replace` idempotentes y el contenido es el mismo. Solo está en
--   duda el número del archivo.
--
-- ── LO QUE SE ARREGLÓ DESPUÉS (todo medido, todo con prueba que lo fija) ────
--
--   · La resta se fiaba de que la fila de la foto existiera. `fn_revertir_pago`
--     no borra la foto, así que un mes cerrado por error y revertido antes de
--     transferir le quitaba UN SUELDO ENTERO a quien no cobró nada — y la hoja
--     firmaba que sí se le había transferido. Ahora exige `estado = 'pagado'`.
--   · Una foto NEGATIVA sumaba en vez de restar: S/250 de más y sin aviso.
--   · El freno abortaba `fn_planilla_congelar_pendientes()` entera, y su
--     instrucción habría inventado un descuento sobre un pago viejo real.
--   · El freno no se levantaba con el descuento que su propio mensaje manda,
--     si a la cesada le quedaba un saldo ganado de verdad.
--   · Y la cabecera afirmaba que el freno alcanzaría a «casi nadie más». Es al
--     revés: salta en cada cese de mitad de periodo. Se explica abajo, entero.
--
-- ============================================================================
--
-- QUÉ PROMETE
--   Que el mismo mes no se pague dos veces a la misma persona, vaya por donde
--   vaya el dinero. Los dos caminos que registran un pago —la planilla del
--   periodo y la liquidación por cese— dejan de ignorarse:
--
--     · Si el periodo está PAGADO y tiene foto de esa persona, la liquidación
--       descuenta exactamente lo que esa foto registra, y lo DICE.
--     · Si la liquidación se pagó primero, congelar el periodo con esa persona
--       dentro se rechaza nombrándola, hasta que el descuento esté registrado.
--
--   Y tres promesas negativas, que son las que hay que poder comprobar de un
--   vistazo, porque son las que cuestan dinero si fallan:
--
--     · Donde no hay foto ACREDITADA no se resta nada. Ni un céntimo cambia para
--       nadie que no esté en la situación de arriba.
--     · Nadie cobra de menos por esto. El sueldo del periodo nunca baja de cero,
--       las tres truncas se pagan siempre enteras, y una foto que no acredita un
--       pago —la de un periodo reabierto, o una negativa— no descuenta.
--     · Nadie se queda sin poder cerrar el mes. El freno se levanta registrando
--       el importe que su propio mensaje nombra, y el saldo que la persona sí
--       ganó se le sigue pagando.
--
-- QUÉ ASUME
--   · La 0164: `fn_liquidacion` calcula el sueldo del periodo llamando a
--     `fn_planilla_calcular(v_per.fecha_ini, v_cese, v_per.id)` y le suma las
--     tres truncas.
--   · La 0096: `planilla_pagada_detalle` es la foto del pago, con PK
--     (periodo_id, persona_id, version) e inmutable por trigger.
--   · La 0167: `liquidacion_pagada` guarda `monto_periodo` —el sueldo del mes
--     que esa liquidación ya pagó— y su `congelada_at`. No tiene `periodo_id`:
--     el periodo se deduce por la fecha de cese, como ya hace la 0210.
--   · La 0201: `fn_planilla_congelar` asigna UNA sola versión a todo el periodo.
--   · La 0203: `fn_revertir_pago` devuelve el periodo a 'abierto' y NO borra la
--     foto — el trigger de inmutabilidad bloquea el delete. De ahí que el estado
--     del periodo, y no la existencia de la fila, sea lo que acredita el pago.
--   · La 0181: `fn_agregar_movimiento` rechaza el descuento con el periodo ya
--     'pagado' (por eso el mensaje del freno cambia según el estado), y
--     `fn_planilla_calcular` suma esos movimientos en la clave `descuentos`.
--   · La 0239 / 0242: `fn_planilla_calcular` saca el divisor del PERIODO cuando
--     la llamada trae `p_periodo_id`. Sin eso esta resta no se podría hacer —
--     ver más abajo, es lo que cambió respecto de la 0210.
--
-- ── EL CASO QUE LO PIDE ─────────────────────────────────────────────────────
--
-- Seis personas que cesaron entre el 16 y el 25 de julio quedaron dentro del
-- periodo 28/06–28/07, que se cerró el 28/07 con ellas dentro. DESPUÉS se les
-- pagó su liquidación, y esa liquidación volvía a incluir el mismo mes: el
-- sueldo del periodo no es un concepto aparte, es la propia planilla llamada
-- con el rango que va del inicio del periodo a la fecha de cese (0164:103).
--
-- Medido en producción: S/1,381.59 registrados dos veces.
--
-- La 0210 midió lo mismo el 2026-08-10 desde el otro lado —la foto del
-- periodo— y anotó S/1,145.87. Las dos cifras existen y no se contradicen
-- necesariamente: cuentan el solapamiento desde extremos distintos. Antes de
-- dar por buena ninguna, se vuelve a medir en el SQL Editor:
--
--     select p.nombres || ' ' || p.apellidos as persona,
--            d.total       as en_la_foto_del_periodo,
--            lp.monto_periodo as en_la_liquidacion,
--            least(d.total, lp.monto_periodo) as solapado
--     from periodos_planilla per
--     join planilla_pagada_detalle d on d.periodo_id = per.id
--     join lateral (select distinct on (x.persona_id) x.*
--                     from liquidacion_pagada x
--                    where x.persona_id = d.persona_id
--                    order by x.persona_id, x.version desc) lp on true
--     join personas p on p.id = d.persona_id
--     where lp.fecha_cese between per.fecha_ini and per.fecha_fin
--       and d.version = (select max(y.version) from planilla_pagada_detalle y
--                         where y.periodo_id = d.periodo_id
--                           and y.persona_id = d.persona_id)
--       and d.total > 0 and lp.monto_periodo > 0
--     order by per.fecha_ini, persona;
--
-- El cartel que dejó la 0210 avisa en la dirección contraria —se mira desde la
-- pantalla de Planilla, sobre gente que YA cobró— y es visual: no frena nada.
--
-- ── LA DECISIÓN: RESTAR EN LA LIQUIDACIÓN, FRENAR EN EL CIERRE ───────────────
--
-- Son dos remedios distintos porque los dos órdenes son situaciones distintas,
-- y confundirlos cuesta dinero en una de las dos direcciones.
--
-- (A) PERIODO CONGELADO PRIMERO, LIQUIDACIÓN DESPUÉS → SE RESTA, NO SE BLOQUEA.
--
--   Acá el dinero del mes YA salió al banco. Lo único pendiente de verdad es la
--   diferencia, si la hay, más las truncas.
--
--   Y «ya salió» se comprueba con el ESTADO DEL PERIODO, no con que la fila
--   exista. `fn_revertir_pago` (0203) devuelve el periodo a 'abierto' y NO borra
--   la foto —el trigger de inmutabilidad bloquea el delete—, así que un mes
--   cerrado por error y revertido antes de transferir deja una foto viva de un
--   pago que nunca ocurrió. Medido: fiándose de la fila, la liquidación caía de
--   S/2,676.19 a S/1,926.19 y la hoja afirmaba por escrito «ya se le transfirió
--   S/750.00». Un mes entero de sueldo, con el sistema certificando un pago
--   inexistente. Por eso la resta exige `v_per.estado = 'pagado'`.
--
--   El caso simétrico —reversión de un pago que SÍ salió, y liquidación cobrada
--   en esa ventana— la base no lo puede resolver: nada registra si el dinero
--   llegó al banco. Así que no se calla ni se adivina, se pregunta: el aviso lo
--   dice con todas las letras y lo decide quien firma. Y queda una segunda red,
--   que es la razón de que gatear no reabra el defecto: en esa ventana
--   `monto_periodo` se congela con el mes entero, así que al volver a cerrar el
--   periodo el freno de (B) la nombra. Con el gate quitado, en cambio, guardaba
--   0 y el freno no tenía a quién nombrar (prueba 184, aserción 33).
--
--   Bloquear la liquidación —negarse a calcularla porque el periodo ya está
--   congelado— habría sido lo fácil de escribir y lo peor de vivir: dejaría sin
--   cobrar las vacaciones truncas, la gratificación trunca y la CTS trunca, que
--   NO están en la planilla del mes, que sí corresponden y que además tienen
--   plazo legal —48 horas desde el cese, art. 4 del D.S. 001-97-TR—. Cobrar de
--   menos es el error que este sistema no ha cometido nunca; no lo va a
--   estrenar por arreglar un cobro de más.
--
--   Por eso: al sueldo del periodo se le resta lo ya transferido, con suelo en
--   CERO, y el resto de la liquidación se paga entero.
--
-- (B) LIQUIDACIÓN PRIMERO, CIERRE DESPUÉS → SE FRENA.
--
--   Acá el dinero TODAVÍA NO SALIÓ. Un freno antes de que salga no le quita
--   nada a nadie: solo obliga a registrar el descuento con el botón que ya
--   existe —«💸 Ya le pagué aparte» de /admin/planilla— y a cerrar después. Es
--   el único momento del proceso en el que un freno es gratis.
--
-- ── POR QUÉ AHORA SÍ, SI LA 0210 DIJO QUE NO ───────────────────────────────
--
-- La 0210 se negó a descontar automáticamente con este argumento, y era
-- correcto ese día: «la cifra de la liquidación HOY NO ES DE FIAR … viene
-- inflada entre 1.1× y 3.1× según lo temprano que se cesara». Esa inflación era
-- el divisor, y la arregló la **0239**: `fn_planilla_calcular` ya no saca
-- `v_dias` del rango recibido sino del periodo cuando la llamada trae
-- `p_periodo_id`, que es justo como la llama `fn_liquidacion`. Hoy los dos
-- lados usan el mismo divisor, así que `periodo.monto` y `foto.total` son la
-- misma clave ('total' de la misma función) medida con la misma vara: se pueden
-- restar sin conversión. En agosto no se podía.
--
-- La otra objeción de la 0210 —«automatizarlo pondría un freno duro justo al
-- cerrar el mes; si esa condición fallara una vez, el 28 no se podría pagar»—
-- se revierte a propósito, y se desarma por dónde está puesto el freno: no mide
-- una condición general que pueda fallar un día cualquiera, sino una lista
-- NOMINAL —quién cobró su liquidación, cuándo y cuánto— y su mensaje trae el
-- paso exacto que lo levanta. El 28 solo se para si de verdad hay alguien a
-- punto de cobrar dos veces, y con el nombre delante.
--
-- ── EL FRENO ACTÚA EN LOS DOS ESTADOS, Y ESO SE DECIDIÓ MIRANDO EL DINERO ───
--
-- La tentación era dejarlo solo con el periodo ABIERTO —el cierre normal—,
-- porque ahí el remedio está a mano: `fn_agregar_movimiento` acepta el descuento
-- mientras el estado no sea 'pagado' (0181:67-71), así que el freno para, se
-- corrige y se cierra, sin atascar a nadie.
--
-- No se hizo, y la razón se midió: `fn_repagar_periodo` (0098) vuelve a congelar
-- un periodo YA pagado y escribe una versión nueva con el total recalculado. Si
-- el freno se apagara ahí, un repago volvería a registrar el mes de quien ya lo
-- cobró en su liquidación — exactamente el defecto que esta migración cierra,
-- entrando por la otra puerta. El dinero del repago tampoco ha salido todavía:
-- es un recálculo previo a pagar una diferencia.
--
-- El precio es un rodeo, y hay que decirlo entero: con el periodo ya pagado, el
-- botón «Ya le pagué aparte» está bloqueado por el propio estado, así que la
-- salida es «Revertir pago» → registrar el descuento → volver a cerrar. Eso
-- LEVANTA LOS CANDADOS DE MARCAJE de ese periodo mientras dura —el sistema ya lo
-- avisa con esas palabras en 0096:267—, que no es gratis. Por eso el mensaje del
-- freno cambia según el estado y dice el rodeo completo, en vez de mandar a un
-- botón que en ese estado no va a estar.
--
-- CADA CUÁNTO SALTA ESTE FRENO, SIN ENDULZARLO: en CADA cese de mitad de
-- periodo. Un borrador de esta migración decía «de aquí en adelante casi nadie
-- más» y era falso, porque leía el orden de los hechos al revés. El art. 4 del
-- D.S. 001-97-TR obliga a liquidar dentro de las 48 horas del cese, y el periodo
-- cierra el 28: el orden NORMAL es liquidación primero, congelamiento después —
-- exactamente el que dispara el freno. Medido con el flujo legal limpio: alguien
-- que cesa el 10, se liquida el 12 y el 28 tumba el cierre del equipo entero.
--
-- Se deja igual, y no por inercia: sin el freno, esa persona cobraría el mismo
-- tramo dos veces, una en su liquidación y otra en la planilla del mes. Lo que
-- sí se paga es el precio de que sea frecuente, y por eso la salida tenía que
-- funcionar de verdad — ver la condición que lo levanta, más abajo. El coste
-- real es UNA acción por cese: registrar el descuento que además le deja rastro
-- en su boleta. A quien alcanza además hoy es a los seis casos de julio, cuyo
-- periodo ya está pagado y cuyas liquidaciones guardan el mes entero.
--
-- ── LA FOTO RETROACTIVA NO SE FRENA ────────────────────────────────────────
--
-- `fn_planilla_congelar_pendientes` (0096) recorre los periodos que están
-- pagados y NO tienen foto —meses transferidos antes de que la foto existiera— y
-- los documenta con `origen = 'retroactivo'`. Ahí la premisa del freno («el
-- dinero de este cierre todavía no salió») es falsa por construcción: ese dinero
-- salió hace meses. Medido: sin la excepción, esa función aborta ENTERA y esos
-- periodos se quedan sin foto para siempre; y seguir la instrucción del mensaje
-- —revertir, descontar, recerrar— inventaría un descuento que nunca ocurrió
-- sobre el registro de un pago viejo. Va con `raise warning` para no perder la
-- señal. No sirve de escape: solo alcanza periodos SIN ninguna foto, así que
-- nunca vuelve a congelar nada, y `origen` está acotado por CHECK.
--
-- ── POR QUÉ SOLO LA ÚLTIMA VERSIÓN, Y POR QUÉ NO SIRVE `v_planilla_pagada` ───
--
-- La `version` de la foto es DEL PERIODO ENTERO, no de la persona (0201: `select
-- coalesce(max(version),0)+1 … where periodo_id = p_periodo_id`), y un repago
-- (0098) o una reapertura (0203) escriben una versión nueva sin borrar la
-- anterior —el trigger de inmutabilidad bloquea update y delete, nunca insert—.
-- Sumar todas las versiones multiplicaría la resta por el número de repagos.
-- Medido: tres versiones de S/750 dan 2250 sumadas y 750 tomando la última.
--
-- Y no se usa la vista `v_planilla_pagada`, que ya resuelve la versión, porque
-- la resuelve con el máximo GLOBAL del periodo. Quien ya no aparece en el
-- recálculo —una cesada sin jornadas dentro del rango— tiene su fila pagada en
-- una versión anterior, y para la vista sería invisible: restaría 0 justo a la
-- población que esta migración persigue. Se toma `max(version)` DE ESA PERSONA
-- en ESE periodo, leyendo la tabla base.
--
-- ── QUÉ LEVANTA EL FRENO: EL DESCUENTO, NO QUE LA FILA QUEDE EN CERO ───────
--
-- La condición de salida NO es `total = 0`. Es que el descuento que el mensaje
-- manda registrar ya esté puesto: `descuentos >= monto_periodo` en la fila de
-- esa persona. La diferencia costó tres casos medidos, y los tres tenían la
-- misma forma — la persona hacía EXACTAMENTE lo que el mensaje dice y el freno
-- volvía a saltar con la frase idéntica, porque quedaba un saldo que la cesada
-- SÍ había ganado:
--
--   · feriado dentro del periodo pero posterior al cese: descontados S/700
--     —el importe que el mensaje nombra—, quedaban S/26.92 legítimos y el mes
--     no cerraba;
--   · reincorporación dentro del mismo periodo: descontados S/250, quedaban
--     S/1,050 de tres semanas trabajadas de verdad;
--   · un marcaje cerrado tarde que añade un día después del descuento.
--
-- Con `total > 0` como única salida, las dos únicas maneras de cerrar el mes
-- eran quitarle dinero ganado o volver a congelar su liquidación —falsear un
-- registro inmutable, y encima el que sostiene el propio freno—. Ninguna de las
-- dos es aceptable, y un freno del que no se puede salir termina en `--no-verify`.
--
-- `descuentos` es la suma de los movimientos de tipo descuento de esa persona en
-- ese periodo (`fn_planilla_calcular`), y el botón «💸 Ya le pagué aparte»
-- escribe justo uno de esos (planilla/page.tsx:1357-1363). Se prefiere a
-- reconocer el descuento por el TEXTO de su concepto: un freno que solo se
-- levanta con una frase literal deja de levantarse el día que alguien reescribe
-- el botón, y entonces no hay salida ninguna.
--
--   Su punto ciego, medido y aceptado: si esa persona ya arrastraba OTROS
--   descuentos que por sí solos igualan o superan `monto_periodo` —un adelanto
--   grande—, el freno no llega a morder. Es una ventana estrecha (hace falta que
--   el bruto del periodo supere al adelanto y el adelanto supere al mes
--   liquidado) y la red principal contra el doble pago sigue siendo la parte
--   (A), que cubre el otro orden entero.
--
-- ── DÓNDE SE RESTA, Y POR QUÉ AHÍ ───────────────────────────────────────────
--
-- Dentro de `periodo.monto`, que pasa a ser el importe NETO. No es un detalle
-- de forma:
--   · la prueba 130 exige que `total` sea la suma de las cuatro líneas sin
--     redondeo propio; restar solo del total y dejar `monto` bruto la pondría
--     roja, y con razón: la hoja no cuadraría consigo misma;
--   · `fn_liquidacion_pagar` congela esa clave en `liquidacion_pagada.
--     monto_periodo` (0167:149), que es lo que leen el cartel de la 0210 y el
--     freno de esta misma migración. Si ahí quedara el bruto, el freno mordería
--     a quien ya no debe nada y el cierre se atascaría.
--
-- Y NO se resta en silencio: `periodo` gana `devengado`, `ya_pagado_en_planilla`,
-- `foto_version` y `congelado_el`, y `aviso_periodo` lo dice en una frase. Son
-- claves NUEVAS: la firma no cambia y ninguna de las que la pantalla ya lee se
-- quita ni se renombra (el tipo `Detalle` de liquidaciones/page.tsx es
-- `Record<string, unknown> & {…}`, así que agregar no rompe el typecheck).
--
-- ── EFECTOS QUE ESTA MIGRACIÓN PROVOCA A PROPÓSITO ─────────────────────────
--
--   · `fn_liquidacion_diferencias` (0167) empezará a marcar «Sueldo del
--     periodo» para quien cobró su liquidación ANTES de que su periodo se
--     congelara —los seis casos de julio, entre otros—: compara la foto de la
--     liquidación contra el cálculo de hoy, y el cálculo de hoy ya resta. La
--     señal es correcta —nombra el doble pago— pero la pantalla la presenta con
--     el texto «el cálculo ya no coincide», que suena a avería de hoy. Es lo
--     primero que hay que retocar en pantalla.
--     Y no alcanza solo a los seis: en cuanto el freno obligue a registrar el
--     descuento de una cesada normal, su cálculo de hoy baja y ella también sale
--     marcada. Con esta migración puesta eso pasa a ser el estado corriente de
--     toda cesada, no una excepción — razón de más para cambiar ese texto.
--   · `fn_liquidaciones_del_periodo` (0210) mostrará «cobro del periodo S/0.00»
--     para quien se liquide DESPUÉS del congelamiento. Es lo correcto: esa
--     liquidación ya no cobra el mes.
--   · La hoja de una cesada a la que ya se le registró el descuento mostrará el
--     sueldo del periodo en S/0.00, porque el descuento entra en el cálculo del
--     mes. No queda mudo: `aviso_periodo` lo explica citando la fecha y el
--     importe de su liquidación ya pagada — es la tercera rama del aviso, y
--     existe justamente porque esa ruta la vuelve obligatoria esta migración.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ──────────────────────────────────────────
--
--   · No toca el dinero ya pagado de más. Las fotos son inmutables por diseño y
--     los seis casos de julio se resuelven a mano, uno por uno.
--   · No imprime todavía el descuento en la HOJA que se firma. Las claves ya
--     viajan en el JSON y `aviso_periodo` lo dice en pantalla, pero la sublínea
--     impresa —la forma que ya usa `Linea` con «devengado … − ya depositado …»,
--     liquidaciones/page.tsx:336-340— pide un cambio en la pantalla, en los DOS
--     sitios donde el sueldo del periodo está escrito a mano (:363-372 y
--     :446-455). Mientras no esté, quien firma ve el neto sin el desglose.
--   · No agrega un parámetro de escape a `fn_planilla_congelar`, y es decisión,
--     no olvido. Un `p_forzar boolean default false` obliga a `drop function` +
--     `create`: comprobado contra el Postgres local, con la sobrecarga puesta
--     toda llamada de 3 argumentos revienta con 42725 «function … is not
--     unique». Y esa función tiene CUATRO llamadores de 3 argumentos (0096:276,
--     0096:350, 0096:385, 0098:97) más unos GRANT que nadie vigila y que un
--     `drop` se lleva por delante en silencio —el daño de la 0189, que tuvo que
--     arreglar la 0204—. A cambio, un escape genérico convierte el freno en un
--     trámite: el día que estorbe, se pasa `true` y nadie vuelve a mirarlo. El
--     escape que hace falta es NOMINAL y ya existe: registrar el descuento de
--     esa persona, que es además lo que deja rastro en su boleta.
--     Si algún día hiciera falta de verdad, el sitio es un `drop` + `create` con
--     el parámetro al final Y las dos líneas de grant de esta misma migración
--     repetidas debajo.
--   · No le pone guard interno a `fn_planilla_congelar`, y hay que decirlo
--     porque este mismo archivo argumenta lo contrario tres párrafos más arriba
--     («un revoke se deshace la próxima vez que alguien conceda en masa, y un
--     guard no»). Esa función sigue protegida SOLO por el revoke. La razón de no
--     tocarlo aquí: sus cuatro llamadores ya guardan, uno de ellos es el bloque
--     `do` de 0096:385 que corre al reconstruir el esquema prestándose una
--     identidad admin que puede no existir en un clon nuevo, y meterle un guard a
--     una función del camino del dinero para arreglar una exposición que hoy no
--     existe es un riesgo mal pagado dentro de esta migración. Lo que sí queda
--     cubierto es lo que preocupaba: el revoke ya no depende solo del bloque de
--     comprobación de abajo, que corre UNA vez al pegar — la prueba 184 lo fija
--     en tres aserciones y la suite se entera el día que alguien conceda en masa.
--   · No resta a partir de `liquidacion_pagada`. Esa tabla se lee, pero solo para
--     poder EXPLICAR el número; quien resta es la foto. Restar de las dos sería
--     restar dos veces lo mismo.
--
-- ── LO QUE SE MIDIÓ ANTES DE DARLO POR BUENO ────────────────────────────────
--
-- Contra el Postgres local, en BEGIN … ROLLBACK, con el montaje de la prueba
-- 184 (S/1,500, jornadas de 6,5 h del 1 al 15, cese el 15, periodo entero de 30
-- días → S/750.00 de sueldo del mes):
--
--   caso                                        | antes  | esta 0243 | restado
--   --------------------------------------------+--------+-----------+---------
--   cese normal, periodo SIN congelar            | 750.00 |    750.00 |    0.00
--   periodo congelado y liquidación después      | 750.00 |      0.00 |  750.00
--   dos versiones de foto (v1 750 · v2 10)       | 750.00 |    740.00 |   10.00
--   foto mayor que lo calculado (9999)           | 750.00 |      0.00 | 9999.00
--   foto viva de un periodo REVERTIDO            | 750.00 |    750.00 |    0.00
--   foto NEGATIVA vigente (-250)                 | 750.00 |    750.00 |    0.00
--
-- Las dos últimas se añadieron después de que una revisión las midiera contra
-- esta misma migración, y en su momento daban 0.00 y 1000.00: un mes entero de
-- menos y S/250 de más, en las dos direcciones. Sobre el total de la liquidación
-- eso era S/1,926.19 y S/2,926.19 contra los S/2,676.19 correctos.
--
-- La primera fila es la regresión principal, y es la que vale: sin foto no hay
-- filas, la resta es 0 y el número no se mueve. Las pruebas 130, 133 y 180
-- montan sus periodos en estado `abierto` y no congelan nada, así que las tres
-- siguen pasando sin tocarles una línea — esa es la comprobación más barata de
-- que esto no cambia nada donde no debe. La suite entera, sobre una base
-- reconstruida con `supabase db reset` (o sea aplicando esta migración desde
-- cero): 110 archivos, todo en verde.
--
--   ⚠️ Al correrla otra vez, ojo con esto, que costó un rato el 2026-08-14: la
--   100 y la 107 congelan periodos que ellas no montaron y leen la base entera,
--   así que si el Postgres local tiene datos sembrados a mano dan rojos que no
--   son de nadie. Medido ese día con ocho personas de semilla en la base: la 100
--   contaba 8 personas de tienda en vez de 2 y una fila de taller en vez de
--   ninguna. Antes de culpar a un cambio, mirar `select count(*) from personas`.
--
-- La tercera fila es la trampa de la `version`: sumar las dos habría restado
-- 760.00 y dejado el neto en -10.00. La cuarta es el suelo: sin `greatest(…, 0)`
-- el sueldo del periodo habría salido en -9,249.00 y se habría comido las
-- truncas, que en ese mismo caso siguen pagándose enteras.
--
-- El freno, medido en el mismo montaje, con la liquidación cobrada primero
-- (`monto_periodo` congelado en S/750.00):
--
--   · periodo ABIERTO → `fn_periodo_pagado` aborta con «A Maria Perez ya se le
--     pagó su liquidación el … e incluye S/750.00 de este mismo periodo …»; el
--     periodo queda en `abierto` y `planilla_pagada_detalle` con 0 filas.
--   · se registra el descuento con `fn_agregar_movimiento` y el MISMO cierre
--     pasa: estado `pagado`, y la foto de esa persona guarda total 0.00.
--   · se le quita el descuento y se llama a `fn_repagar_periodo` sobre el
--     periodo ya PAGADO → vuelve a abortar, con el mensaje del rodeo. Sin esa
--     segunda mitad, el repago habría vuelto a registrar el mes.
--   · con un feriado posterior al cese, el descuento por el importe que el
--     mensaje NOMBRA (S/700.00) levanta el freno y le deja cobrar los S/26.92
--     que sí ganó. Antes de la condición del descuento, ese cierre no pasaba.
--   · `fn_planilla_congelar_pendientes()` sobre un periodo histórico con una
--     liquidación pagada dentro: pasa, con un warning que la nombra. Antes
--     abortaba la función entera.
--
-- Y cada una de esas garantías se comprobó por MUTACIÓN, que es la única forma
-- de saber que una prueba no es decorativa. Con el arreglo puesto la suite está
-- verde; quitando una pieza cada vez, la 184 se pone roja exactamente donde
-- toca y en ningún otro sitio:
--
--   pieza quitada                          | aserciones que mueren
--   ---------------------------------------+----------------------
--   el gate `v_per.estado = 'pagado'`       | 29, 30, 33
--   el suelo `greatest(v_foto, 0)`          | 34, 35
--   la excepción del `retroactivo`          | 37, 38
--   la condición `< lq.monto_periodo`       | 43, 44
--   la rama del aviso «periodo reabierto»   | 31
--   la rama del aviso «ya se pagó»          | 45
--
-- ── DE QUÉ VERSIONES PARTE ─────────────────────────────────────────────────
--
-- `fn_liquidacion` — de la 0164, única definición según ./scripts/donde-vive.sh.
--   md5 de partida: f346444e985b40caf0e5e4f3df4e1f43
--   Pedido a PRODUCCIÓN en el SQL Editor el 2026-08-14: coincide con el local,
--   o sea que producción tiene exactamente la 0164.
--
-- `fn_planilla_congelar` — de la 0201, la vigente de cuatro definiciones.
--   md5 del LOCAL: af7956b5b84122c148196ff6a559adda
--   ⚠️ DE ESTA NO TENEMOS EL md5 DE PRODUCCIÓN. Hay que pedirlo al SQL Editor
--   ANTES de pegar esta migración, y no pegarla si no coincide:
--
--     select md5(p.prosrc) from pg_proc p
--       join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'fn_planilla_congelar';
--
--   Si no coincide, NO pegues: mide dónde está la diferencia primero
--   —posiciones de marcadores dentro del `prosrc`, `octet_length` contra
--   `length`, un `substring` del principio— en vez de proponer explicaciones.
--
-- Los dos cuerpos se copiaron de esos archivos y solo se parchearon los bloques
-- marcados «CAMBIO 0243». Todo lo demás es lo que ya estaba, incluidos los
-- comentarios de las migraciones anteriores.
--
-- Y CÓMO SABER QUE LLEGÓ ENTERA. Después de pegar, esos dos md5 tienen que
-- quedar así —medido en el Postgres local con este mismo archivo—:
--
--     fn_liquidacion         c51658ead0eaa9fe4d12e938a05ba6c9
--     fn_planilla_congelar   5adda069874f86a0eea3826459f51baa
--
--     select p.proname, md5(p.prosrc) from pg_proc p
--       join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public'
--        and p.proname in ('fn_liquidacion', 'fn_planilla_congelar');
--
-- Si no coinciden, lo más probable no es que el SQL esté mal: es que el texto se
-- estropeó al copiarlo. Estas dos funciones llevan acentos y comillas angulares
-- dentro de mensajes que alguien va a leer en pantalla, y una copia con el
-- locale roto parte cada tilde en dos caracteres sin que nada falle — es lo que
-- le pasó a la 0185 el 2026-08-08, y por eso `scripts/dame-el-sql.sh` compara
-- ahora el portapapeles con el archivo byte por byte. El SQL corre igual; solo
-- se vuelve ilegible, y estas migraciones se leen.
--
-- ── IDEMPOTENTE ────────────────────────────────────────────────────────────
--   Solo `create or replace` y un insert con `on conflict do nothing`. Se puede
--   pegar dos veces sin efecto distinto. No hay cambio de esquema ni de datos.
--
-- ── CÓMO SE REVIERTE ───────────────────────────────────────────────────────
--   Volver a pegar `fn_liquidacion` desde la 0164 y `fn_planilla_congelar`
--   desde la 0201, tal cual están ahí. No hay dato que devolver: esta migración
--   no escribe ninguna fila de negocio.
--   Lo que vuelve con eso es el doble pago, así que revertir pide primero
--   entender por qué.
-- ============================================================================


-- ── 1 · La liquidación descuenta lo que la foto del pago ya registra ─────────
-- Cuerpo de la 0164 con dos bloques nuevos. El resto, byte por byte lo de allí.
create or replace function fn_liquidacion(
  p_persona_id uuid,
  p_fecha_cese date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_p        personas%rowtype;
  v_cese     date;
  v_per      periodos_planilla%rowtype;
  v_fila     jsonb;
  v_vac      jsonb;
  v_grati    jsonb;
  v_cts      jsonb;
  v_periodo  numeric := 0;
  v_devengado numeric := 0;      -- CAMBIO 0243: lo que toca por el mes, antes de restar
  v_ya       numeric := 0;       -- CAMBIO 0243: lo que se ACREDITA como ya transferido
  v_ya_ver   int;                -- CAMBIO 0243
  v_ya_at    timestamptz;        -- CAMBIO 0243
  v_foto     numeric;            -- CAMBIO 0243: la foto tal cual, se acredite o no
  v_foto_ver int;                -- CAMBIO 0243
  v_foto_at  timestamptz;        -- CAMBIO 0243
  v_liq      numeric;            -- CAMBIO 0243: lo que su liquidación ya pagada cobró de este mes
  v_liq_at   timestamptz;        -- CAMBIO 0243
  v_aviso    text;               -- CAMBIO 0243
  v_total    numeric;
begin
  -- El guard va DENTRO, como en las otras cuatro funciones de liquidación: un
  -- revoke se deshace la próxima vez que alguien conceda en masa (0076), y un
  -- guard no. La forma `is not true` es obligatoria: un null no pasa.
  if fn_es_admin_o_lider() is not true then
    raise exception 'Solo un administrador o líder puede ver la liquidación de una persona.';
  end if;

  select * into v_p from personas where id = p_persona_id;
  if not found then raise exception 'La persona no existe.'; end if;

  v_cese := coalesce(p_fecha_cese, v_p.fecha_cese);
  if v_cese is null then
    raise exception 'Esa persona no tiene fecha de cese. Regístrala en Equipo antes de liquidar.';
  end if;

  -- El periodo que CONTIENE el cese. Si no hay ninguno —el cese cae fuera de todo
  -- periodo cargado— no se inventa uno: se dice, porque un sueldo pendiente
  -- calculado sobre un rango imaginario es peor que no calcularlo.
  select * into v_per
  from periodos_planilla
  where v_cese between fecha_ini and fecha_fin
  order by fecha_ini desc
  limit 1;

  if found then
    -- Del inicio del periodo a la fecha de cese: ni un día más.
    select value into v_fila
    from jsonb_array_elements(
           fn_planilla_calcular(v_per.fecha_ini, v_cese, v_per.id) -> 'filas'
         ) as t(value)
    where (value->>'persona_id')::uuid = p_persona_id;

    v_periodo := coalesce((v_fila->>'total')::numeric, 0);

    -- ── CAMBIO 0243 ─────────────────────────────────────────────────────────
    -- Lo que la FOTO del pago registra para esta persona en ESTE periodo.
    --
    -- Solo la última versión SUYA. La `version` es del periodo entero
    -- (fn_planilla_congelar, 0201), así que un repago deja versiones viejas
    -- vivas y sumarlas duplicaría la resta. Y no se toma el max(version) del
    -- periodo —lo que hace la vista v_planilla_pagada— porque quien ya no sale
    -- en el recálculo (una cesada sin jornadas dentro del rango) tiene su fila
    -- pagada en una versión anterior, y ese es justo el caso que esto viene a
    -- cazar: la vista le restaría 0.
    --
    -- Se lee de la tabla base a propósito. `total` es la misma clave que
    -- `v_periodo` —las dos salen de `fn_planilla_calcular` (0201:186 y la línea
    -- de arriba)— y desde la 0239 con el mismo divisor: son restables sin
    -- conversión.
    select d.total, d.version, d.congelada_at
      into v_foto, v_foto_ver, v_foto_at
    from planilla_pagada_detalle d
    where d.periodo_id = v_per.id
      and d.persona_id = p_persona_id
    order by d.version desc
    limit 1;

    v_devengado := round(v_periodo, 2);

    -- ── UNA FOTO NO ACREDITA POR SÍ SOLA QUE EL DINERO SALIERA ──────────────
    -- `fn_revertir_pago` (0203) devuelve el periodo a 'abierto' y NO borra la
    -- foto: el trigger de inmutabilidad bloquea el delete, así que la fila
    -- sobrevive a la reapertura. Un mes cerrado por error y revertido ANTES de
    -- transferir nada deja, por tanto, una foto viva de un pago que no ocurrió.
    -- Restar contra ella le quitaría el mes entero a quien no cobró un céntimo
    -- —medido: la liquidación caía de S/2,676.19 a S/1,926.19— y encima la hoja
    -- lo afirmaría por escrito. Cobrar de menos es el error que este sistema no
    -- comete, así que la resta EXIGE que el periodo siga pagado hoy.
    --
    -- El caso simétrico —reversión de un pago que SÍ salió, y liquidación
    -- cobrada en esa ventana— no se resuelve solo, y por eso no se calla: se
    -- explica en `aviso_periodo` para que lo decida quien firma, que es la única
    -- que sabe si esa transferencia se hizo. Además queda la segunda red: al
    -- volver a cerrar el periodo, el freno de la parte (B) muerde.
    if v_per.estado = 'pagado' then
      -- `greatest(…, 0)` sobre la propia foto, no solo sobre la resta: `total`
      -- es numeric(12,2) sin check de no-negativo y `chk_foto_cuadra` admite un
      -- negativo en cuanto los descuentos superan lo devengado. Una foto
      -- negativa SUMARÍA al sueldo pendiente en vez de restar — medido, S/250 de
      -- más y sin una línea que lo explicara.
      v_ya     := greatest(coalesce(v_foto, 0), 0);
      v_ya_ver := v_foto_ver;
      v_ya_at  := v_foto_at;
    end if;

    -- Suelo en CERO, nunca negativo. Si lo ya transferido supera lo calculado,
    -- el sueldo del periodo va a 0 y las tres truncas se pagan enteras: cobrar
    -- de menos es el error que este sistema no comete.
    v_periodo   := greatest(round(v_devengado - v_ya, 2), 0);

    -- Y lo que su liquidación YA PAGADA cobró de este mismo periodo. No se usa
    -- para restar —de eso se encarga la foto—: se usa para poder EXPLICAR el
    -- cero. Después del descuento que el freno obliga a registrar, el devengado
    -- baja solo y la hoja quedaba en S/0.00 sin decir por qué, mientras
    -- `liquidacion_pagada` seguía diciendo el importe entero.
    -- Última versión y luego se filtra por el periodo, en ese orden: es el mismo
    -- criterio que el freno y que la 0210.
    select lp.monto_periodo, lp.congelada_at
      into v_liq, v_liq_at
    from (
      select distinct on (x.persona_id) x.*
      from liquidacion_pagada x
      where x.persona_id = p_persona_id
      order by x.persona_id, x.version desc
    ) lp
    where lp.fecha_cese between v_per.fecha_ini and v_per.fecha_fin;
    -- ── fin CAMBIO 0243 ─────────────────────────────────────────────────────
  end if;

  -- ── CAMBIO 0243 · el descuento no se hace en silencio, y el cero tampoco ───
  -- Mientras la hoja impresa no desglose la resta, este aviso es lo único que la
  -- explica en pantalla. Tiene que hablar en las TRES situaciones en las que el
  -- número de arriba no se entiende solo, no únicamente cuando hubo resta.
  if v_per.id is null then
    v_aviso := 'El cese no cae dentro de ningún periodo de planilla cargado: el sueldo pendiente no se pudo calcular y hay que cargarlo.';
  else
    if v_per.estado = 'pagado' and v_ya > 0 then
      v_aviso := 'De este periodo ya se le transfirió S/' || to_char(v_ya, 'FM999999990.00')
              || ' con la planilla, congelada el '
              || to_char(v_ya_at at time zone 'America/Lima', 'DD/MM/YYYY')
              || '. El sueldo del periodo se muestra YA DESCONTADO: devengado S/'
              || to_char(v_devengado, 'FM999999990.00')
              || ' menos S/' || to_char(v_ya, 'FM999999990.00')
              || '. Las vacaciones, la gratificación y la CTS truncas se pagan enteras.';
    elsif v_per.estado is distinct from 'pagado' and v_foto is not null then
      v_aviso := 'OJO, COMPRUÉBALO A MANO: este periodo se congeló el '
              || to_char(v_foto_at at time zone 'America/Lima', 'DD/MM/YYYY')
              || ' (versión ' || v_foto_ver || ') con S/' || to_char(v_foto, 'FM999999990.00')
              || ' para esta persona, y DESPUÉS se reabrió con «Revertir pago»: hoy está '
              || upper(v_per.estado) || '. NO se descuenta nada, porque la foto de un periodo '
              || 'reabierto no acredita que el dinero saliera. Si esa transferencia sí se hizo, '
              || 'resta ese importe antes de pagar esta liquidación.';
    end if;
    if coalesce(v_liq, 0) > 0 then
      v_aviso := coalesce(v_aviso || ' ', '')
              || 'Su liquidación ya se pagó el '
              || to_char(v_liq_at at time zone 'America/Lima', 'DD/MM/YYYY')
              || ' y ahí se le abonaron S/' || to_char(v_liq, 'FM999999990.00')
              || ' por este periodo; si el sueldo del periodo sale más bajo de lo esperado o en '
              || 'cero, es porque ese importe ya está descontado en la planilla del mes.';
    end if;
  end if;
  -- ── fin CAMBIO 0243 ───────────────────────────────────────────────────────

  v_vac   := fn_vacaciones_truncas(p_persona_id, v_cese);
  v_grati := fn_grati_trunca(p_persona_id, v_cese);
  v_cts   := fn_cts_trunca(p_persona_id, v_cese);

  v_total := v_periodo
           + coalesce((v_vac->>'monto')::numeric, 0)
           + coalesce((v_grati->>'monto')::numeric, 0)
           + coalesce((v_cts->>'monto')::numeric, 0);

  return jsonb_build_object(
    'persona_id',   p_persona_id,
    'persona',      v_p.nombres || ' ' || v_p.apellidos,
    'fecha_ingreso', v_p.fecha_ingreso,
    'fecha_cese',   v_cese,
    'tipo_vinculo', v_p.tipo_vinculo,

    -- El plazo legal, calculado y no recordado. 48 horas desde el cese.
    'vence_el',     (v_cese + 2),
    'dias_restantes', (v_cese + 2 - fn_hoy_lima()),
    'vencido',      (fn_hoy_lima() > v_cese + 2),

    -- El periodo en curso, entero, para que la hoja pueda desglosarlo. Si el cese
    -- cayó fuera de todo periodo cargado, `periodo` viene nulo y el aviso lo dice:
    -- es un dato que falta, no un cero.
    --
    -- CAMBIO 0243 · `monto` es el NETO —lo que queda por transferir— y las
    -- claves nuevas explican de dónde sale. Son aditivas: nada de lo que la
    -- pantalla ya lee cambia de nombre ni desaparece.
    --
    -- `ya_pagado_en_planilla`, `foto_version` y `congelado_el` dicen lo que se
    -- ACREDITÓ, no lo que hay en la tabla: con el periodo reabierto valen 0/null
    -- aunque exista una foto viva, porque es exactamente lo que la resta hizo.
    -- Lo otro —que esa foto existe— lo cuenta `aviso_periodo`, y `estado` ya
    -- estaba ahí desde la 0164 para que la pantalla lo distinga sin adivinar.
    'periodo',      case when v_per.id is null then null else jsonb_build_object(
                      'id', v_per.id, 'desde', v_per.fecha_ini, 'hasta', v_cese,
                      'estado', v_per.estado, 'detalle', v_fila,
                      'monto', round(v_periodo, 2),
                      'devengado',             round(v_devengado, 2),           -- CAMBIO 0243
                      'ya_pagado_en_planilla', round(v_ya, 2),                  -- CAMBIO 0243
                      'foto_version',          v_ya_ver,                        -- CAMBIO 0243
                      'congelado_el',          (v_ya_at at time zone 'America/Lima')::date  -- CAMBIO 0243
                    ) end,
    'aviso_periodo', v_aviso,   -- CAMBIO 0243 · se arma arriba, en tres ramas

    'vacaciones_truncas',   v_vac,
    'gratificacion_trunca', v_grati,
    'cts_trunca',           v_cts,

    'total', round(v_total, 2)
  );
end;
$$;

grant execute on function fn_liquidacion(uuid, date) to authenticated;

comment on function fn_liquidacion(uuid, date) is
  'Cuánto se le debe a quien cesa: sueldo del periodo (NETO de lo que la foto del '
  'pago ya registra para esa persona en ese periodo, y solo si ese periodo SIGUE '
  'pagado — ver 0243) más las tres truncas. Las claves periodo.devengado, '
  'periodo.ya_pagado_en_planilla, periodo.foto_version y periodo.congelado_el '
  'explican el descuento; sin foto acreditada valen 0/null y el importe es el de '
  'siempre. aviso_periodo habla en tres casos: hubo resta, hay una foto viva de un '
  'periodo reabierto que NO se acredita, o su liquidación ya se pagó.';


-- ── 2 · Y el cierre del periodo se niega a pagar dos veces el mismo mes ──────
-- Cuerpo de la 0201 (la vigente según ./scripts/donde-vive.sh) con UN bloque
-- nuevo antes del insert. Ni un carácter más cambió: copiarla de la 0134 habría
-- revertido en silencio el sobretiempo de la foto, y de la 0127, la provisión de
-- la bonificación extraordinaria de la Ley 30334.
create or replace function fn_planilla_congelar(p_periodo_id uuid, p_origen text, p_autor uuid)
returns int
language plpgsql security definer set search_path = public as $fn$
declare
  v_per record;
  v_calc jsonb;
  v_ver int;
  v_n int;
  v_cobradas text;   -- CAMBIO 0243
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
  -- LA CONDICIÓN QUE LEVANTA EL FRENO ES EL DESCUENTO, NO QUE LA FILA QUEDE EN
  -- CERO. Esto costó tres casos medidos, y los tres tenían la misma forma: la
  -- persona hacía EXACTAMENTE lo que el mensaje manda —descontar `monto_periodo`—
  -- y el freno volvía a saltar con la frase idéntica, porque quedaba un saldo que
  -- la cesada SÍ había ganado.
  --   · un feriado dentro del periodo pero posterior al cese: descontados S/700,
  --     quedaban S/26.92 legítimos y el mes no cerraba;
  --   · una reincorporación dentro del mismo periodo: descontados S/250, quedaban
  --     S/1,050 de tres semanas trabajadas de verdad;
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
      and coalesce((f->>'descuentos')::numeric, 0) < lq.monto_periodo
  ) x;

  if v_cobradas is not null then
    -- Una sola frase corrida, sin saltos de línea: la pantalla imprime el texto
    -- de un P0001 tal cual, sin `whitespace-pre-line`, así que un `\n` se
    -- colapsaría en un espacio (apps/web/lib/admin/mensaje-error.ts:81).
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
      raise warning '0243 · foto retroactiva de un periodo ya transferido: %. No se frena —ese dinero salió hace tiempo— pero conviene mirarlo.', v_cobradas;
    elsif v_per.estado = 'abierto' then
      raise exception '%. Cerrar así pagaría ese mes por segunda vez. Antes de cerrar, entra a su fila en Planilla y usa el botón «💸 Ya le pagué aparte» por ESE importe y con esa fecha; si el filtro «Mostrar» no la enseña, cámbialo a «Todos» o pulsa «Verlas» en el aviso de quienes ya no están. Si tras ese descuento le queda un saldo, ese saldo es suyo y se paga con la planilla: no hace falta dejar su fila en cero. El periodo sigue ABIERTO: no se congeló nada.', v_cobradas;
    else
      raise exception '%. Volver a congelarlo así registraría ese mes por segunda vez. Este periodo ya está PAGADO, así que el descuento no se puede anotar sin reabrirlo: usa «Revertir pago» con su motivo (ojo, eso levanta los candados de los marcajes de este periodo mientras esté abierto), registra el descuento con «💸 Ya le pagué aparte» por ESE importe y con esa fecha, y vuelve a marcarlo como pagado. Si tras el descuento le queda un saldo, ese saldo es suyo y se paga: no hace falta dejar su fila en cero. Nada se congeló: la foto anterior sigue intacta.', v_cobradas;
    end if;
  end if;
  -- ── fin CAMBIO 0243 ─────────────────────────────────────────────────────────

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
$fn$;

-- Los grants se repiten porque «create or replace» no los pierde, pero dejarlos
-- escritos hace que este archivo se sostenga sobre una base reconstruida.
revoke all     on function fn_planilla_congelar(uuid, text, uuid) from public, anon, authenticated;
grant  execute on function fn_planilla_congelar(uuid, text, uuid) to service_role;


insert into migraciones_aplicadas (numero, nombre)
values (243, 'la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago')
on conflict (numero) do nothing;

notify pgrst, 'reload schema';


-- ── 3 · Comprobación posterior ──────────────────────────────────────────────
-- Que la migración diga en voz alta que quedó como prometió. Se pega a mano, y
-- una mano se equivoca: media migración aplicada es peor que ninguna, porque no
-- se nota.
do $mig$
declare
  v_src text;
  v_src_cong text;
  v_pend int;
begin
  select p.prosrc into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_liquidacion';

  if v_src is null then
    raise exception '0243 · fn_liquidacion no existe. Algo se quedo a medias.';
  end if;
  if v_src not like '%planilla_pagada_detalle%' then
    raise exception '0243 · fn_liquidacion NO lee la foto del pago: el mes se seguiria pagando dos veces.';
  end if;
  if v_src not like '%greatest(round(v_devengado - v_ya, 2), 0)%' then
    raise exception '0243 · fn_liquidacion no tiene el suelo en cero: podria devolver un negativo.';
  end if;
  if v_src not like '%greatest(coalesce(v_foto, 0), 0)%' then
    raise exception '0243 · fn_liquidacion no acota la foto por abajo: una foto negativa sumaria.';
  end if;
  if v_src not like '%if v_per.estado = ''pagado'' then%' then
    raise exception '0243 · fn_liquidacion acredita la foto de un periodo reabierto: le quitaria un mes entero a quien no cobro nada.';
  end if;
  if v_src not like '%ya_pagado_en_planilla%' then
    raise exception '0243 · fn_liquidacion resta pero no lo dice. La hoja no podria explicarlo.';
  end if;

  select p.prosrc into v_src_cong
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_planilla_congelar';

  if v_src_cong is null then
    raise exception '0243 · fn_planilla_congelar no existe. NADIE PUEDE COBRAR: revisar ya.';
  end if;
  if v_src_cong not like '%liquidacion_pagada%' then
    raise exception '0243 · fn_planilla_congelar no mira las liquidaciones pagadas: el freno no quedo puesto.';
  end if;
  if v_src_cong not like '%< lq.monto_periodo%' then
    raise exception '0243 · el freno no se levanta con el descuento: la unica salida seria quitarle dinero ganado.';
  end if;
  if v_src_cong not like '%p_origen = ''retroactivo''%' then
    raise exception '0243 · el freno muerde la foto retroactiva: fn_planilla_congelar_pendientes abortaria entera.';
  end if;
  -- Lo que un `drop` se lleva por delante en silencio (0189 → 0204). Acá se usa
  -- «create or replace», que no los pierde, pero comprobarlo cuesta nada.
  if has_function_privilege('authenticated', 'fn_planilla_congelar(uuid, text, uuid)', 'execute') then
    raise exception '0243 · authenticated puede llamar a fn_planilla_congelar, y no debe.';
  end if;
  if not has_function_privilege('service_role', 'fn_planilla_congelar(uuid, text, uuid)', 'execute') then
    raise exception '0243 · service_role NO puede llamar a fn_planilla_congelar: el cierre del mes se rompe.';
  end if;
  if not has_function_privilege('authenticated', 'fn_liquidacion(uuid, date)', 'execute') then
    raise exception '0243 · authenticated NO puede llamar a fn_liquidacion: la pantalla se queda en blanco.';
  end if;

  raise notice '0243 · listo. La liquidacion resta lo ya transferido y el cierre frena el orden inverso.';

  -- Y el dato que hay que mirar a mano después de pegar: quién quedó con el mes
  -- registrado dos veces ANTES de esta migración. Esas filas no se tocan.
  select count(*) into v_pend
  from periodos_planilla per
  join planilla_pagada_detalle d on d.periodo_id = per.id
  join lateral (select distinct on (x.persona_id) x.*
                  from liquidacion_pagada x
                 where x.persona_id = d.persona_id
                 order by x.persona_id, x.version desc) lp on true
  where lp.fecha_cese between per.fecha_ini and per.fecha_fin
    and d.version = (select max(y.version) from planilla_pagada_detalle y
                      where y.periodo_id = d.periodo_id and y.persona_id = d.persona_id)
    and d.total > 0 and lp.monto_periodo > 0;

  if v_pend > 0 then
    raise warning '0243 · % persona(s) YA tienen el mismo mes en la foto del periodo y en su liquidacion.', v_pend;
    raise warning '0243 · Esta migracion NO las arregla: las fotos son inmutables. Se revisan una por una con la consulta de la cabecera.';
  else
    raise notice '0243 · no hay solapamientos previos en esta base.';
  end if;
end
$mig$;
