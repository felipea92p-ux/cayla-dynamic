-- ============================================================================
-- 0244 — La 0243 deja de pagar de menos y de atascar el cierre
-- ============================================================================
--
-- ESTA MIGRACIÓN NO REESCRIBE LA 0243: SE PEGA DETRÁS.
--
--   La 0243 se pegó en producción el 2026-08-14 a las 12:03 y es lo que está
--   corriendo hoy. Vive en git desde el commit a09eade («Rescatar la 0243, que
--   ya estaba aplicada y solo vivía en esta Mac»). Una revisión posterior le
--   encontró SEIS bordes abiertos, y el primer intento de arreglarlos se
--   escribió EDITANDO la 0243 en el sitio. Eso no se puede hacer: una migración
--   aplicada es el registro de lo que producción recibió ese día, y editarla
--   deja el repo mintiendo sobre ese día. Además `migraciones_aplicadas` ya
--   tiene el 243, así que el insert de una 0243 reescrita no habría registrado
--   nada y `./scripts/que-falta-pegar.sh` habría dado por puesto lo que no está.
--
--   Así que la 0243 y su prueba 184 vuelven a ser byte por byte lo que se pegó,
--   y todo lo que se arregló vive acá, con su propia prueba: la 185.
--
--   Los dos bloques son `create or replace` con el cuerpo ENTERO, no un parche
--   encima de la 0243. Dentro se distingue quién puso qué: lo que la 0243 metió
--   está marcado «CAMBIO 0243» y sigue palabra por palabra como está en
--   producción; lo que agrega esta migración va marcado «CAMBIO 0244».
--
--   Y como los cuerpos van enteros, esta migración se sostiene sola: pegarla sin
--   la 0243 deja las funciones bien igual. Lo que NO se sostiene es lo que
--   vendría después, así que la parte 0 lo frena — está explicado ahí.
--
-- QUÉ PROMETE
--   Cerrar los seis bordes de abajo sin tocar lo que la 0243 sí hizo bien —que
--   el mismo mes no se pague dos veces, vaya por donde vaya el dinero— y sin
--   mover un céntimo a nadie que no esté en uno de esos seis casos.
--
--   Y tres promesas negativas, que son las que hay que poder comprobar de un
--   vistazo, porque son las que cuestan dinero si fallan:
--
--     · NADIE COBRA DE MENOS. El sueldo del periodo nunca baja de cero, las tres
--       truncas se pagan siempre enteras, y una foto que no acredita un pago
--       —la de un periodo reabierto, o una negativa— no descuenta nada.
--     · NADIE SE QUEDA SIN PODER CERRAR EL MES. El freno se levanta registrando
--       el importe que su propio mensaje nombra, y el saldo que la persona sí
--       ganó se le sigue pagando.
--     · DONDE NO HAY FOTO ACREDITADA NO SE RESTA NADA, igual que en la 0243. Las
--       ~30 personas que no están en esta situación cobran exactamente lo mismo.
--
-- QUÉ ASUME
--   · La 0243, ya aplicada: `fn_liquidacion` resta del sueldo del periodo lo que
--     la foto del pago registra, y `fn_planilla_congelar` frena el cierre cuando
--     alguien de ese periodo ya cobró su liquidación.
--   · La 0164: `fn_liquidacion` calcula el sueldo del periodo llamando a
--     `fn_planilla_calcular(v_per.fecha_ini, v_cese, v_per.id)` y le suma las
--     tres truncas.
--   · La 0096: `planilla_pagada_detalle` es la foto del pago, con PK
--     (periodo_id, persona_id, version) e inmutable por trigger; y
--     `fn_planilla_congelar_pendientes` documenta con `origen = 'retroactivo'`
--     los periodos ya pagados que se quedaron sin foto.
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
--
-- ── LOS SEIS BORDES, MEDIDOS ───────────────────────────────────────────────
--
-- Todo lo de abajo está medido contra el Postgres local, en BEGIN … ROLLBACK,
-- con el montaje de la prueba 185: S/1,500 de sueldo, jornadas de 6,5 h del 1 al
-- 15, cese el 15, periodo de 30 días → S/750.00 de sueldo del mes. Las cifras de
-- «hoy» son las que devuelve la 0243 tal como está pegada en producción.
--
--   1. PAGA DE MENOS, y este es el que este sistema no se puede permitir.
--      La resta se fiaba de que la FILA de la foto existiera, no de que el pago
--      hubiera salido. `fn_revertir_pago` no borra la foto, así que un mes
--      cerrado por error y revertido ANTES de transferir deja una foto viva de
--      un pago que nunca ocurrió. Medido, esa liquidación:
--
--          hoy (0243)            S/1,393.27      sueldo del periodo    S/0.00
--          con esta migración    S/2,143.27      sueldo del periodo  S/750.00
--
--      S/750.00 de menos —un mes entero— a quien no cobró un céntimo, y con la
--      hoja afirmándolo por escrito: «ya se le transfirió S/750.00».
--      Arreglo: la resta exige `v_per.estado = 'pagado'`.
--
--   2. Y EN LA DIRECCIÓN CONTRARIA, INFLA. La resta tenía suelo en cero sobre el
--      resultado, pero no sobre la FOTO. `planilla_pagada_detalle.total` es
--      numeric(12,2) sin check de no-negativo, y `chk_foto_cuadra` admite un
--      negativo en cuanto los descuentos superan lo devengado. Restar un
--      negativo SUMA. Medido con una foto vigente de −250.00:
--
--          hoy (0243)            S/2,817.65      sueldo del periodo S/1,000.00
--          con esta migración    S/2,567.65      sueldo del periodo   S/750.00
--
--      S/250.00 de más, sin una línea que lo explicara.
--      Arreglo: `greatest(coalesce(v_foto, 0), 0)`.
--
--   3. EL FRENO ABORTA `fn_planilla_congelar_pendientes()` ENTERA. Esa función
--      (0096) documenta con `origen = 'retroactivo'` los periodos que ya están
--      pagados y no tienen foto: meses transferidos antes de que la foto
--      existiera. Ahí la premisa del freno —«el dinero de este cierre todavía no
--      salió»— es falsa por construcción. Medido: la función aborta y esos
--      periodos se quedan sin foto para siempre; y seguir la instrucción de su
--      mensaje —revertir, descontar, recerrar— inventaría un descuento que nunca
--      ocurrió sobre el registro de un pago viejo y real.
--      Arreglo: con `p_origen = 'retroactivo'` avisa y no frena.
--
--   4. EL FRENO NO SE LEVANTA CON EL DESCUENTO QUE ÉL MISMO MANDA REGISTRAR, y
--      por eso puede atascar el cierre del mes entero. La condición de salida
--      era `total > 0`, o sea que solo se levantaba si la fila quedaba EN CERO.
--      Medido en el montaje de agosto —cesa el 10, se liquida el 12 como manda
--      la ley, y el periodo llega al 30 con un feriado el 20—: su liquidación
--      cobró S/500.00, el periodo le calcula S/519.23, y descontando los S/500
--      que el mensaje NOMBRA quedan S/19.23 que ella sí ganó. Hoy ese mes no
--      cierra, y las dos únicas salidas son quitarle esos S/19.23 o volver a
--      congelar su liquidación falseando un registro inmutable —justo el que
--      sostiene el propio freno—.
--      Arreglo: la condición pasa a ser `descuentos < monto_periodo`.
--
--   5. EL FRENO SALTA EN CADA CESE DE MITAD DE PERIODO, y la cabecera de la 0243
--      dice lo contrario: «de aquí en adelante casi nadie más». Es al revés, y
--      por el orden legal. El art. 4 del D.S. 001-97-TR obliga a liquidar dentro
--      de las 48 horas del cese y el periodo cierra el 28, así que el orden
--      NORMAL es liquidación primero, congelamiento después — exactamente el que
--      dispara el freno. El freno se mantiene, y no por inercia: sin él esa
--      persona cobraría el mismo tramo dos veces. Lo que cambia es que se cuenta
--      como lo que es, y que su salida tiene que funcionar de verdad — el 4.
--      Arreglo: cabecera. El comportamiento es el mismo, a propósito.
--
--   6. LA HOJA QUEDA EN S/0.00 SIN EXPLICAR POR QUÉ. Tras el descuento que el
--      freno OBLIGA a registrar, el devengado del mes baja solo; pero
--      `aviso_periodo` solo hablaba cuando había resta de la foto, así que la
--      pantalla mostraba un cero mudo mientras `liquidacion_pagada` seguía
--      diciendo el importe entero. Y con el borde 1 arreglado aparece un segundo
--      silencio: la foto viva de un periodo reabierto ya no descuenta, y no
--      decirlo sería esconder una transferencia que quizá sí se hizo.
--      Arreglo: el aviso pasa a tener tres ramas.
--
-- ── (1) UNA FOTO NO ACREDITA POR SÍ SOLA QUE EL DINERO SALIERA ─────────────
--
-- «Ya salió» se comprueba con el ESTADO DEL PERIODO, no con que la fila exista.
-- El caso simétrico —reversión de un pago que SÍ salió, y liquidación cobrada en
-- esa ventana— la base no lo puede resolver: nada registra si el dinero llegó al
-- banco. Así que no se calla ni se adivina, se pregunta: el aviso lo dice con
-- todas las letras y lo decide quien firma.
--
-- Y queda una segunda red, que es la razón de que este gate no reabra el defecto
-- que la 0243 vino a cerrar: en esa ventana `monto_periodo` se congela con el
-- mes entero, así que al volver a cerrar el periodo el freno la nombra. Con el
-- gate quitado, en cambio, guardaba 0 y el freno no tenía a quién nombrar
-- (prueba 185, aserción 33).
--
-- ── (3) LA FOTO RETROACTIVA NO SE FRENA ────────────────────────────────────
--
-- Va con `raise warning` para no perder la señal. No sirve de escape: solo
-- alcanza periodos SIN ninguna foto, así que nunca vuelve a congelar nada, y
-- `origen` está acotado por CHECK a 'pago' | 'retroactivo'.
--
-- Es lo contrario de una excepción cómoda: se abre exactamente donde la premisa
-- del freno es falsa por construcción, y en ningún otro sitio.
--
-- ── (4) QUÉ LEVANTA EL FRENO: EL DESCUENTO, NO QUE LA FILA QUEDE EN CERO ───
--
-- Tres casos medidos, todos con la misma forma — la persona hace EXACTAMENTE lo
-- que el mensaje dice y el freno vuelve a saltar con la frase idéntica, porque
-- queda un saldo que la cesada SÍ ganó:
--
--   · feriado dentro del periodo pero posterior al cese (el que fija la prueba
--     185): su liquidación cobró S/500.00, el periodo le calcula S/519.23, así
--     que descontados los S/500.00 que el mensaje nombra quedan S/19.23;
--   · reincorporación dentro del mismo periodo: sobre ese mismo montaje, si
--     vuelve el 16 y trabaja hasta el 30, el periodo le calcula S/1,348.08 y
--     descontados los mismos S/500.00 le quedan S/848.08 trabajados de verdad;
--   · un marcaje cerrado tarde que añade un día después del descuento.
--
-- Los dos primeros están medidos sobre el montaje de la 185 y se reproducen con
-- él; el tercero es la misma forma y no se montó. Cualquier cifra de aquí que no
-- salga de ese montaje es una cifra que alguien no va a poder comprobar.
--
-- `descuentos` es la suma de los movimientos de tipo descuento de esa persona en
-- ese periodo (`fn_planilla_calcular`), y el botón «💸 Ya le pagué aparte»
-- escribe justo uno de esos (planilla/page.tsx:1357-1363). Se prefiere a
-- reconocer el descuento por el TEXTO de su concepto: un freno que solo se
-- levanta con una frase literal deja de levantarse el día que alguien reescribe
-- el botón, y entonces no hay salida ninguna. Y un freno del que no se puede
-- salir termina en `--no-verify`, que es la peor forma de perderlo.
--
--   Su punto ciego, medido y aceptado: si esa persona ya arrastraba OTROS
--   descuentos que por sí solos igualan o superan `monto_periodo` —un adelanto
--   grande—, el freno no llega a morder. Es una ventana estrecha (hace falta que
--   el bruto del periodo supere al adelanto y el adelanto supere al mes
--   liquidado) y la red principal contra el doble pago sigue siendo la resta de
--   la liquidación, que cubre el otro orden entero.
--
-- ── EFECTOS QUE ESTA MIGRACIÓN PROVOCA A PROPÓSITO ─────────────────────────
--
--   · La 0243 ya hacía que `fn_liquidacion_diferencias` (0167) marcara «Sueldo
--     del periodo» para quien cobró su liquidación ANTES de que su periodo se
--     congelara, con el texto «el cálculo ya no coincide», que suena a avería de
--     hoy. Con esta migración eso deja de ser cosa de los seis casos de julio:
--     en cuanto el freno obligue a registrar el descuento de una cesada normal,
--     su cálculo de hoy baja y ella también sale marcada. Pasa a ser el estado
--     corriente de toda cesada — razón de más para retocar ese texto, que es lo
--     primero que hay que cambiar en pantalla.
--   · La hoja de una cesada a la que ya se le registró el descuento seguirá
--     mostrando el sueldo del periodo en S/0.00, porque el descuento entra en el
--     cálculo del mes. Lo que cambia es que ya no queda muda.
--
-- ── LO QUE ESTA MIGRACIÓN NO HACE ──────────────────────────────────────────
--
--   · No toca la 0243 ni su prueba 184. Las dos quedan como se pegaron. Si algún
--     día hay que leer qué recibió producción el 2026-08-14, están ahí.
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
--   · No le pone guard interno a `fn_planilla_congelar`. Esa función sigue
--     protegida SOLO por el revoke. La razón de no tocarlo aquí: sus cuatro
--     llamadores ya guardan, uno de ellos es el bloque `do` de 0096:385 que corre
--     al reconstruir el esquema prestándose una identidad admin que puede no
--     existir en un clon nuevo, y meterle un guard a una función del camino del
--     dinero para arreglar una exposición que hoy no existe es un riesgo mal
--     pagado dentro de esta migración. Lo que sí queda cubierto es lo que
--     preocupaba: el revoke ya no depende solo del bloque de comprobación de
--     abajo, que corre UNA vez al pegar — la prueba 185 lo fija en tres
--     aserciones y la suite se entera el día que alguien conceda en masa.
--   · No resta a partir de `liquidacion_pagada`. Esa tabla se lee, pero solo para
--     poder EXPLICAR el número; quien resta es la foto. Restar de las dos sería
--     restar dos veces lo mismo.
--
-- ── LO QUE SE MIDIÓ ANTES DE DARLO POR BUENO ────────────────────────────────
--
-- Contra el Postgres local, en BEGIN … ROLLBACK, con el montaje de la prueba 185
-- (S/1,500, jornadas de 6,5 h del 1 al 15, cese el 15, periodo entero de 30 días
-- → S/750.00 de sueldo del mes). «Antes» es sin nada de esto; «0243» es lo que
-- devuelve hoy producción; «0244» es lo que devuelve con esta migración puesta:
--
--   caso                                        | antes  |  0243  |  0244
--   --------------------------------------------+--------+--------+--------
--   cese normal, periodo SIN congelar            | 750.00 | 750.00 | 750.00
--   periodo congelado y liquidación después      | 750.00 |   0.00 |   0.00
--   dos versiones de foto (v1 750 · v2 10)       | 750.00 | 740.00 | 740.00
--   foto mayor que lo calculado (9999)           | 750.00 |   0.00 |   0.00
--   foto viva de un periodo REVERTIDO            | 750.00 |   0.00 | 750.00
--   foto NEGATIVA vigente (-250)                 | 750.00 |1000.00 | 750.00
--
-- Las dos últimas filas son los bordes 1 y 2, y son las únicas que se mueven:
-- todo lo que la 0243 ya hacía bien devuelve exactamente lo mismo. Sobre el
-- total de la liquidación, esas dos filas son S/1,393.27 y S/2,817.65 hoy contra
-- S/2,143.27 y S/2,567.65 con esta migración.
--
-- La primera fila es la regresión principal, y es la que vale: sin foto no hay
-- filas, la resta es 0 y el número no se mueve. Las pruebas 130, 133 y 180
-- montan sus periodos en estado `abierto` y no congelan nada, así que las tres
-- siguen pasando sin tocarles una línea. La 184 —que mide la 0243 y se queda—
-- también: lo que esta migración cambia son casos que aquella no monta.
--
--   ⚠️ Al correr la suite, ojo con esto, que costó un rato el 2026-08-14: la 100
--   y la 107 congelan periodos que ellas no montaron y leen la base entera, así
--   que si el Postgres local tiene datos sembrados a mano dan rojos que no son de
--   nadie. Antes de culpar a un cambio, mirar `select count(*) from personas`.
--
-- El freno, medido en el mismo montaje, con la liquidación cobrada primero:
--
--   · periodo ABIERTO → `fn_periodo_pagado` aborta nombrando a la persona; el
--     periodo queda en `abierto` y `planilla_pagada_detalle` con 0 filas.
--   · se registra el descuento y el MISMO cierre pasa.
--   · se le quita el descuento y se llama a `fn_repagar_periodo` sobre el
--     periodo ya PAGADO → vuelve a abortar, con el mensaje del rodeo.
--   · con un feriado posterior al cese, el descuento por el importe que el
--     mensaje NOMBRA (S/500.00) levanta el freno y le deja cobrar los S/19.23
--     que sí ganó. Con la 0243, ese cierre no pasa.
--   · `fn_planilla_congelar_pendientes()` sobre un periodo histórico con una
--     liquidación pagada dentro: pasa, con un warning que la nombra. Con la
--     0243, aborta la función entera.
--
-- Y LA COMPROBACIÓN QUE VALE POR TODAS: la prueba 185 corrida contra la 0243 tal
-- como está pegada en producción se pone roja en DOCE aserciones —29, 30, 31,
-- 33, 34, 35, 37, 38, 43, 44, 45 y 51—, y con esta migración queda verde. Qué
-- pieza sostiene cada grupo:
--
--   pieza                                   | aserciones que mueren sin ella
--   ----------------------------------------+-------------------------------
--   el gate `v_per.estado = 'pagado'`        | 29, 30, 33
--   el suelo `greatest(v_foto, 0)`           | 34, 35
--   la excepción del `retroactivo`           | 37, 38
--   la condición `< lq.monto_periodo`        | 43, 44
--   la rama del aviso «periodo reabierto»    | 31
--   la rama del aviso «ya se pagó»           | 45, 51
--   la rama del aviso de la 0243             | 49
--   el filtro por periodo del `v_liq`        | 50
--   el orden de versiones del `v_liq`        | 51
--
-- Eso es una prueba comprobada por MUTACIÓN, que es la única forma de saber que
-- no es decorativa: quitando una pieza cada vez, la 185 se pone roja exactamente
-- donde toca y en ningún otro sitio.
--
-- Las tres últimas filas son de una segunda pasada de mutación, y salieron de que
-- las tres piezas se podían romper con la 184 y la 185 ENTERAS EN VERDE. Las tres
-- redactan `aviso_periodo`, que mientras la hoja impresa no desglose el descuento
-- es el único sitio donde se le explica a quien firma por qué le bajó el sueldo
-- del periodo: la rama que dice cuánto se restó, el filtro que evita citar la
-- liquidación de OTRO periodo, y el orden que hace que se cite la última versión
-- y no la primera. Contra la 0243 caen doce y no catorce porque la 49 y la 50
-- pasan también allí —la 49 mira una rama que la 0243 ya tenía, y la 50 no puede
-- fallar en una versión que no lee `liquidacion_pagada`—.
--
-- Y lo que sigue SIN vigilar, dicho para que no se confunda con un descuido: el
-- `raise warning` del caso retroactivo se puede enmudecer sin que caiga ninguna
-- aserción, porque la 37 es un `lives_ok` y pgTAP no captura warnings. Lo que
-- importa de ese caso —que la función NO aborte y que la foto histórica quede
-- tomada— sí está medido, en la 37 y la 38.
--
-- ── DE QUÉ VERSIONES PARTE ─────────────────────────────────────────────────
--
-- De la 0243 PEGADA, no de la 0164 ni de la 0201. Estos son los md5 que
-- producción tiene que tener AHORA MISMO, medidos en esta Mac aplicando el
-- archivo 0243 tal como está en git:
--
--     fn_liquidacion         c724dc210b4974e2dd887aee373a02e8
--     fn_planilla_congelar   e7e8058baf4eaef7b832c089c7c47fbd
--
-- Se piden al SQL Editor de producción ANTES de pegar esto, y el md5 se pide a
-- PRODUCCIÓN, nunca se copia del local:
--
--     select p.proname, md5(p.prosrc) from pg_proc p
--       join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public'
--        and p.proname in ('fn_liquidacion', 'fn_planilla_congelar');
--
-- Si NO coinciden, no pegues todavía: mide dónde está la diferencia —posiciones
-- de marcadores dentro del `prosrc`, `octet_length` contra `length`, un
-- `substring` del principio— en vez de proponer explicaciones. El 2026-08-08 se
-- probaron tres hipótesis falsas antes de que el primer `substring` lo
-- resolviera de un vistazo.
--
--   Y hay un caso en el que sí se puede seguir aunque no coincidan: como los dos
--   bloques se pegan ENTEROS, esta migración deja las funciones bien incluso si
--   la 0243 llegó a medias. Lo que no se puede es pegarla a ciegas: si el md5 de
--   partida no es el de arriba, alguien tocó esas funciones por otro camino y hay
--   que saber quién antes de sobrescribirlo.
--
--   Ojo con la diferencia entre «llegó a medias» y «no llegó». Un md5 de partida
--   distinto NO frena nada —es un dato para mirar, y sigue siendo decisión de
--   quien pega—. Que la 0243 no conste aplicada SÍ frena, y lo hace la parte 0.
--   No es incoherencia: el problema de que no conste no son las funciones, que
--   quedan bien, sino que `que-falta-pegar.sh` la pediría después y pegarla
--   revertiría esto en silencio.
--
-- Y CÓMO SABER QUE LLEGÓ ENTERA. Después de pegar, esos dos md5 tienen que
-- quedar así —medido en el Postgres local con este mismo archivo—:
--
--     fn_liquidacion         c229efda8ca8ee484a9eafd7959e8829
--     fn_planilla_congelar   998f5305129d865719e531fd9c0d957f
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
--   Solo `create or replace`, un insert con `on conflict do nothing` y dos
--   bloques `do` que no escriben nada (el freno de orden de la parte 0 y la
--   comprobación de la parte 3). Se puede pegar dos veces sin efecto distinto
--   —medido: mismos md5 y una sola fila en `migraciones_aplicadas`—. No hay
--   cambio de esquema ni de datos.
--
-- ── CÓMO SE REVIERTE ───────────────────────────────────────────────────────
--   Volviendo a pegar los dos bloques de la 0243, que existen byte por byte en
--   `supabase/migrations/0243_la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago.sql`.
--   No hay dato que devolver: esta migración no escribe ninguna fila de negocio,
--   salvo su propia línea en `migraciones_aplicadas` —que habría que borrar a
--   mano, `delete from migraciones_aplicadas where numero = 244`—.
--   Lo que vuelve con eso es pagar S/750.00 de menos a quien tuvo un periodo
--   revertido, S/250.00 de más a quien tenga una foto negativa, y un cierre de
--   mes que se puede atascar. Revertir pide primero entender por qué.
-- ============================================================================


-- ── 0 · Esta migración va DETRÁS de la 0243, y el orden importa ─────────────
-- No porque haga falta para que las funciones queden bien: los dos cuerpos se
-- pegan ENTEROS y esta migración sola ya las deja correctas. Importa por lo que
-- viene DESPUÉS, y está medido: pegada sin la 0243, esta migración entra sin un
-- aviso y `migraciones_aplicadas` queda con el 244 y sin el 243. Entonces
-- `./scripts/que-falta-pegar.sh` pide la 0243 —hace bien, le falta—, y pegarla
-- DEVUELVE las dos funciones al cuerpo que paga S/750.00 de menos, imprime
-- «0243 · listo» y deja las dos marcadas como aplicadas. Ni un warning en todo
-- el camino: el `do $mig$` de la 0243 comprueba su propio contenido, y su propio
-- contenido está bien — lo que no puede saber es que está pisando algo posterior.
--
-- Así que el freno se pone acá, que es el único sitio donde todavía se puede.
-- No es un escape ni una comprobación de md5 (esa decisión está más arriba, y
-- sigue en pie): solo obliga al orden que siempre es seguro. En producción la
-- 0243 se pegó el 2026-08-14 12:03, así que esto no salta; y en un `db reset` la
-- 0243 corre antes y registra su número, así que tampoco.
do $orden$
begin
  if to_regclass('public.migraciones_aplicadas') is null then
    -- Base sin registro de migraciones: no hay con qué comprobar el orden, así
    -- que este freno no opina. `to_regclass` en vez de leer la tabla a secas
    -- para que el guard no sea él la causa del error.
    raise notice '0244 · esta base no lleva `migraciones_aplicadas`: el orden no se pudo comprobar.';
  elsif not exists (select 1 from migraciones_aplicadas where numero = 243) then
    raise exception '0244 · falta la 0243. Pega PRIMERO supabase/migrations/0243_la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago.sql y esta después. Al revés no falla nada hoy, pero `que-falta-pegar.sh` te pedirá la 0243 mañana y pegarla revertiría este arreglo en silencio. Si de verdad la 0243 no existe y no se va a pegar nunca, registra su número a mano antes: insert into migraciones_aplicadas (numero, nombre) values (243, ''la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago'') on conflict do nothing;';
  end if;
end
$orden$;


-- ── 1 · La liquidación descuenta lo ACREDITADO, y nunca hacia arriba ─────────
-- Cuerpo COMPLETO de `fn_liquidacion`: la 0164 con los bloques que le puso la
-- 0243 (marcados «CAMBIO 0243», tal como están hoy en producción) más los que
-- pone esta migración (marcados «CAMBIO 0244»). No es un parche encima de la
-- 0243: es la función entera, así que pegar esto deja la versión definitiva
-- aunque la 0243 se hubiera pegado a medias.
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
  v_foto     numeric;            -- CAMBIO 0244: la foto tal cual, se acredite o no
  v_foto_ver int;                -- CAMBIO 0244
  v_foto_at  timestamptz;        -- CAMBIO 0244
  v_liq      numeric;            -- CAMBIO 0244: lo que su liquidación ya pagada cobró de este mes
  v_liq_at   timestamptz;        -- CAMBIO 0244
  v_aviso    text;               -- CAMBIO 0244
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
    --
    -- CAMBIO 0244 · la lectura va a `v_foto`, no directo a `v_ya` como en la
    -- 0243. Que esa foto ACREDITE un pago lo decide el bloque de abajo; leerla y
    -- acreditarla son dos cosas distintas, y confundirlas costaba un mes entero.
    select d.total, d.version, d.congelada_at
      into v_foto, v_foto_ver, v_foto_at
    from planilla_pagada_detalle d
    where d.periodo_id = v_per.id
      and d.persona_id = p_persona_id
    order by d.version desc
    limit 1;

    v_devengado := round(v_periodo, 2);

    -- ── CAMBIO 0244 · UNA FOTO NO ACREDITA POR SÍ SOLA QUE EL DINERO SALIERA ─
    -- `fn_revertir_pago` (0203) devuelve el periodo a 'abierto' y NO borra la
    -- foto: el trigger de inmutabilidad bloquea el delete, así que la fila
    -- sobrevive a la reapertura. Un mes cerrado por error y revertido ANTES de
    -- transferir nada deja, por tanto, una foto viva de un pago que no ocurrió.
    -- Restar contra ella le quitaría el mes entero a quien no cobró un céntimo
    -- —medido en el montaje de la prueba 185: la liquidación caía de S/2,143.27
    -- a S/1,393.27, y el sueldo del periodo de S/750.00 a S/0.00— y encima la
    -- hoja lo afirmaría por escrito. Cobrar de menos es el error que este
    -- sistema no comete, así que la resta EXIGE que el periodo siga pagado hoy.
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
    -- ── fin CAMBIO 0244 ────────────────────────────────────────────────────

    -- Suelo en CERO, nunca negativo. Si lo ya transferido supera lo calculado,
    -- el sueldo del periodo va a 0 y las tres truncas se pagan enteras: cobrar
    -- de menos es el error que este sistema no comete.
    v_periodo   := greatest(round(v_devengado - v_ya, 2), 0);

    -- ── CAMBIO 0244 · para poder explicar el cero ──────────────────────────
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
    -- ── fin CAMBIO 0244 ────────────────────────────────────────────────────
    -- ── fin CAMBIO 0243 ─────────────────────────────────────────────────────
  end if;

  -- ── CAMBIO 0244 · el aviso de la 0243, con las dos ramas que le faltaban ───
  -- El aviso lo puso la 0243 y hablaba en un solo caso: cuando hubo resta.
  -- Mientras la hoja impresa no desglose el descuento, este texto es lo único
  -- que lo explica en pantalla, así que tiene que hablar en las TRES
  -- situaciones en las que el número de arriba no se entiende solo. Las dos que
  -- faltaban son la foto viva de un periodo reabierto —que ya no descuenta, y
  -- callarlo sería esconder una transferencia que quizá sí se hizo— y el cero
  -- que deja el descuento que el freno OBLIGA a registrar.
  -- Se saca del `jsonb_build_object` a una variable porque con tres ramas y una
  -- que se concatena a las otras, un `case` en línea ya no se lee.
  if v_per.id is null then
    v_aviso := 'El cese no cae dentro de ningún periodo de planilla cargado: el sueldo pendiente no se pudo calcular y hay que cargarlo.';
  else
    if v_per.estado = 'pagado' and v_ya > 0 then
      -- La rama de la 0243, palabra por palabra, y con la misma condición
      -- EFECTIVA que tenía: `v_ya` arranca en 0 y solo se asigna dentro del gate
      -- de arriba, así que `v_ya > 0` ya implica `estado = 'pagado'`. El primer
      -- término no cambia a quién alcanza esta rama —comprobado por mutación:
      -- quitarlo no mueve ni una aserción de la 184 ni de la 185—; se deja
      -- escrito porque es la invariante de la que depende el texto, y el día que
      -- alguien asigne `v_ya` en otro sitio esta rama seguiría diciendo la
      -- verdad. Quien hace el trabajo es el gate de la línea de arriba.
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
  -- ── fin CAMBIO 0244 ───────────────────────────────────────────────────────

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
    -- CAMBIO 0244 · `ya_pagado_en_planilla`, `foto_version` y `congelado_el`
    -- dicen lo que se ACREDITÓ, no lo que hay en la tabla: con el periodo
    -- reabierto valen 0/null
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
    'aviso_periodo', v_aviso,   -- CAMBIO 0243, reescrito por la 0244: tres ramas

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


-- ── 2 · Y el freno del cierre se puede levantar sin quitarle dinero a nadie ──
-- Cuerpo COMPLETO de `fn_planilla_congelar`: la 0201 (la vigente según
-- ./scripts/donde-vive.sh) con el freno que le puso la 0243 y las tres cosas
-- que le pone esta migración —la condición del descuento, la rama del
-- retroactivo y la salida del saldo en las dos frases—. Ni un carácter más
-- cambió del cuerpo de la 0201: copiarla de la 0134 habría revertido en silencio
-- el sobretiempo de la foto, y de la 0127, la provisión de la bonificación
-- extraordinaria de la Ley 30334.
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


-- El 243 ya está registrado desde el 2026-08-14 12:03 y no se toca. Acá se
-- registra el 244, que es lo que hace que `./scripts/que-falta-pegar.sh` deje de
-- pedirlo.
insert into migraciones_aplicadas (numero, nombre)
values (244, 'la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre')
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

  -- Las comprobaciones van todas con el prefijo 0244 porque este bloque corre al
  -- pegar ESTA migración: si algo salta, el archivo que hay que mirar es este.
  -- Las tres primeras verifican que el contenido de la 0243 sigue debajo —los
  -- dos cuerpos se pegan enteros—; de ahí en adelante, lo que agrega la 0244.
  if v_src is null then
    raise exception '0244 · fn_liquidacion no existe. Algo se quedo a medias.';
  end if;
  if v_src not like '%planilla_pagada_detalle%' then
    raise exception '0244 · fn_liquidacion NO lee la foto del pago: el mes se seguiria pagando dos veces.';
  end if;
  if v_src not like '%greatest(round(v_devengado - v_ya, 2), 0)%' then
    raise exception '0244 · fn_liquidacion no tiene el suelo en cero: podria devolver un negativo.';
  end if;
  if v_src not like '%greatest(coalesce(v_foto, 0), 0)%' then
    raise exception '0244 · fn_liquidacion no acota la foto por abajo: una foto negativa sumaria.';
  end if;
  if v_src not like '%if v_per.estado = ''pagado'' then%' then
    raise exception '0244 · fn_liquidacion acredita la foto de un periodo reabierto: le quitaria un mes entero a quien no cobro nada.';
  end if;
  if v_src not like '%ya_pagado_en_planilla%' then
    raise exception '0244 · fn_liquidacion resta pero no lo dice. La hoja no podria explicarlo.';
  end if;

  select p.prosrc into v_src_cong
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'fn_planilla_congelar';

  if v_src_cong is null then
    raise exception '0244 · fn_planilla_congelar no existe. NADIE PUEDE COBRAR: revisar ya.';
  end if;
  if v_src_cong not like '%liquidacion_pagada%' then
    raise exception '0244 · fn_planilla_congelar no mira las liquidaciones pagadas: el freno no quedo puesto.';
  end if;
  if v_src_cong not like '%< lq.monto_periodo%' then
    raise exception '0244 · el freno no se levanta con el descuento: la unica salida seria quitarle dinero ganado.';
  end if;
  if v_src_cong not like '%p_origen = ''retroactivo''%' then
    raise exception '0244 · el freno muerde la foto retroactiva: fn_planilla_congelar_pendientes abortaria entera.';
  end if;
  -- Lo que un `drop` se lleva por delante en silencio (0189 → 0204). Acá se usa
  -- «create or replace», que no los pierde, pero comprobarlo cuesta nada.
  if has_function_privilege('authenticated', 'fn_planilla_congelar(uuid, text, uuid)', 'execute') then
    raise exception '0244 · authenticated puede llamar a fn_planilla_congelar, y no debe.';
  end if;
  if not has_function_privilege('service_role', 'fn_planilla_congelar(uuid, text, uuid)', 'execute') then
    raise exception '0244 · service_role NO puede llamar a fn_planilla_congelar: el cierre del mes se rompe.';
  end if;
  if not has_function_privilege('authenticated', 'fn_liquidacion(uuid, date)', 'execute') then
    raise exception '0244 · authenticated NO puede llamar a fn_liquidacion: la pantalla se queda en blanco.';
  end if;

  raise notice '0244 · listo. La foto de un periodo reabierto ya no descuenta, una foto negativa no suma, el freno se levanta con el descuento y el backfill retroactivo no se atasca.';

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
    raise warning '0244 · % persona(s) YA tienen el mismo mes en la foto del periodo y en su liquidacion.', v_pend;
    raise warning '0244 · Esta migracion NO las arregla: las fotos son inmutables. Se revisan una por una con la consulta de la cabecera.';
  else
    raise notice '0244 · no hay solapamientos previos en esta base.';
  end if;
end
$mig$;
