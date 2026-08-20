# Dynamic — Histórico

**Acá vive lo cerrado.** Lo que está vivo hoy está en
[`estado.md`](estado.md), que es el único archivo de estado.

Sin fecha en el nombre a propósito: hubo cinco documentos de estado fechados que
se contradecían entre sí, y ese hábito no vuelve. Este archivo **solo crece por
abajo** con cosas que ya no cambian; si algo de acá vuelve a estar vivo, se mueve
a `estado.md`, no se duplica.

**Por qué existe, si git ya guarda todo.** Porque nadie hace arqueología en `git
log -p` para recuperar por qué se decidió algo hace tres meses. Lo que sigue son
decisiones y lecciones que costaron caro; el inventario de qué hizo cada
migración no está acá, porque eso lo dice mejor la cabecera de cada archivo en
`supabase/migrations/`.

---

## ~~2026-08-10 — regenerar `types.ts` ya no es solo reordenar~~ ✅ HECHO el 2026-08-14

**Cerrado.** Se hizo, y la causa era más simple —y peor— de lo que decía esta
sección: el generador declara los parámetros de cada función como NO anulables, y
`fn_set_fin_contrato(p_fecha)` acepta null a propósito. Correr el comando dejaba
**63 errores en diez pantallas**. `scripts/tipos-args-nullables.mjs` le agrega
`| null` a los 491 parámetros y va encadenado al script de `gen-types`, así que
el comando documentado ahora termina en verde. Se conserva lo de abajo por el
registro de cómo se midió.



**Medido, no supuesto.** El repositorio venía diciendo que regenerar
`packages/database/src/types.ts` «reordena las 4.400 líneas del archivo entero»
y por eso se aplazaba, resolviendo cada función nueva con un doble casteo. Se
probó de verdad al añadir `fn_expediente_resolver` (0206):

- Genera **4.217 líneas** contra las 2.535 de hoy.
- **Gana 65 nombres** y suelta exactamente dos: `fn_set_horario` y
  `fn_quitar_horario`, que la 0184 borró. Hasta ahí, estrictamente correcto.
- **Pero cambia la convención de los argumentos opcionales**, de
  `string | null` a `string | undefined`. Eso rompe de golpe Ausencias,
  Correcciones y Datos personales, que pasan `null` a propósito.

O sea: **no es un reordenamiento, es una migración de tipos.** Aplazarla sigue
siendo razonable, pero por un motivo distinto al que estaba escrito, y el coste
de aplazarla crece — ya son tres las funciones que el archivo no conoce
(`fn_expediente_resolver`, `fn_tardanza_escalon`, y las columnas nuevas de
`fn_tardanzas_resumen`).

Cuando se haga, va sola en su propia rama y con las tres pantallas revisadas.

---

## 2026-08-08 — seis puertas dejaban cambiar una planilla ya pagada

**El repositorio y producción llevaban semanas diciendo cosas distintas, y no
había manera de enterarse.** Se compararon los dos esquemas enteros —199
funciones, 261 candados, 467 columnas— y el resultado ordena todo lo de abajo:

| | |
|---|---|
| **candados** | idénticos, byte a byte. Es lo que volvió inofensivo casi todo lo demás |
| **columnas** | idénticas, salvo dos que solo existen en producción |
| **funciones** | **22 distintas** |

### Lo único que era grave

Seis funciones de producción no tenían el candado de periodo pagado que el
repositorio les puso en julio con la 0026 y la 0037: `fn_set_feriado`,
`fn_quitar_feriado`, `fn_set_turno`, `fn_quitar_turno`, `fn_set_horario_semanal`
y `fn_set_descanso`.

Reproducido en local el estado exacto de producción y llamadas las seis sobre una
fecha de un mes ya pagado, **las seis dejaron pasar el cambio y una borró un
feriado de un mes pagado sin decir una palabra.** El daño no se ve: la jornada se
recalcula sola con el trigger, las horas del mes cambian, y la planilla
depositada deja de cuadrar con lo que el sistema dice hoy. Se descubre cuando
alguien reclama.

La [`0180`](../supabase/migrations/0180_el_candado_de_pagado_vuelve_a_las_seis_que_lo_perdieron.sql)
lo repone —aplicada y confirmada, 6 de 6— y la prueba
[`141`](../supabase/tests/141_las_seis_puertas_a_una_planilla_pagada.test.sql)
exige **las dos mitades**: que dentro de lo pagado lancen, y que fuera de lo
pagado sigan funcionando. Un candado que cierra siempre lo quita cualquiera en la
primera urgencia.

Antes de sobrescribirlas se pidieron sus cuerpos y se compararon línea a línea:
producción era el repositorio **menos** el bloque, ni una línea de más. Mirar
antes de escribir no era ceremonia — siete funciones de las 22 tienen código que
el repositorio no conoce (ver abajo).

### El resto era texto roto

Seis funciones decían `l√≠der` donde debía decir `líder`: UTF-8 leído como **Mac
OS Roman**, que parte cada acento en dos. Se confirmó simulando esa conversión
sobre el cuerpo del repositorio — los md5 salen exactos, así que se identificaron
sin gastar consultas. Lo arreglan la **0181** (cuatro) y la **0183** (las dos que
la comprobación de la 0181 destapó, que además corrían la versión de julio de
`fn_crear_periodo` y `fn_eliminar_periodo`). Las dos aplicadas y confirmadas.

⚠️ **Y ese mismo día se demostró que el daño SIGUE ENTRANDO.** Horas después de
limpiar las seis, la consulta «qué falta pegar» devolvió `⚠ md5 SIN CATALOGAR`
para `fn_planilla_calcular` — la función que decide lo que cobra cada persona.
Medido: era el cuerpo de la **0185 pasado por Mac OS Roman**, y la 0185 se había
pegado ese mismo día.

O sea que el razonamiento de arriba —«si el canal fuera el culpable estarían
rotas las 199»— **era falso**: el daño no entra de una vez, entra **por pegada**.

✅ **Y la causa se encontró el mismo día: era `pbcopy` con el locale en `C`**
dentro del propio `dame-el-sql.sh`. Con `LC_CTYPE=C` el portapapeles interpreta
el UTF-8 como MacRoman y cada acento se parte en dos. O sea que la ruta culpable
no era «otra vía»: era la nuestra, en las sesiones cuyo entorno tenía ese locale
—por eso cuatro migraciones del mismo día salieron limpias y una no—. Ya está
arreglado: el script compara el portapapeles byte por byte contra el archivo y se
niega si no coinciden. Ver la regla en `CLAUDE.md`.

**Quedan dos detectores permanentes, y ninguno depende de una lista a mano:** la
fila **ACENTOS** de `que_falta_pegar.sql`, que barre el esquema entero buscando
el signo «√», y la columna `tiene_acentos_rotos` de
`en_que_version_esta_la_planilla.sql`. El catálogo de md5 de esa consulta
**también se calcula solo** desde las migraciones, con `iconv -f MAC` para
generar la variante rota de cada versión: llegó a mentir tres veces en un día
mientras se escribía a mano.

### El agujero que casi se anuncia y no existía

La 0026 le añadió a `fn_crear_periodo` un candado contra dos periodos que cierren
el mismo mes, con su motivo escrito en julio: «el plus de objetivos se pagaría
doble». Producción no lo tenía. La conclusión saltaba sola.

**Se probó antes de afirmarlo y es falsa.** El segundo periodo falla igual: lo
frena el índice único `periodos_etiqueta_unica` sobre (año, mes) de la fecha de
cierre. Y los 261 candados de producción son idénticos a los del repositorio.
Igual con el `advisory lock` que falta: `periodos_sin_solape` impide el solape de
todos modos.

**Aquí lo que protege el dinero es el candado de la BASE, no el de la función.**
Las seis puertas eran un agujero real porque detrás no había ningún constraint;
esta no lo era porque sí lo hay. Misma forma, conclusiones opuestas, y solo
medirlo las distingue.

### La lección de método, que costó medio día

**Un dato de referencia nunca viaja guardado — ni en un archivo ni en un
mensaje.** El comparador viejo llevaba las huellas del repositorio dentro y
acusó a 25 funciones que estaban bien. Se sacaron del archivo… y entonces
caducaron en el mensaje que las transportaba: se calcularon a las 10:28, entraron
cinco migraciones a las 10:55 y 11:14, y la comparación de las 11:30 ya no valía.

`huella_del_esquema.sql` calcula las dos mitades en el mismo minuto y trae
`hasta_migracion`, para que comparar dos generaciones distintas se delate en vez
de asustar. Los tres comparadores que mentían —`comparar_funciones.sql`,
`comparar_solo_funciones.sql`, `huellas_produccion.sql`— quedan **vaciados, no
borrados**: su contenido está en git y su ruta sigue avisando por qué no usarlos.

**Y una comprobación que barre gana a una que pregunta por una lista.** La de la
0181 no preguntaba por sus cuatro funciones: buscaba el signo «√» en el esquema
entero. Devolvió dos que nadie había señalado.

---

## 2026-08-06 — ningún papel firmado se podía subir, y nunca se pudo

**Lo que parecía un módulo terminado desde julio no funcionaba ni una vez.** El
cargo firmado de un memo disciplinario no se podía archivar desde que existe el
módulo (0074). Los tres memos entregados de producción llevaban semanas con «sin
el papel archivado» al lado y no era descuido de nadie: la base los rechazaba.

**La causa, que no se veía leyendo el código.** Supabase Storage no escribe el
objeto con un `INSERT`. Escribe `INSERT … ON CONFLICT DO UPDATE … RETURNING *`, y
esa forma necesita **tres** permisos, no uno: INSERT por la fila, SELECT por el
`RETURNING`, y UPDATE por el `ON CONFLICT`. Ningún bucket tenía política de
UPDATE. Y la de SELECT de `expedientes` exigía que el adjunto ya estuviera
registrado en `expediente_adjuntos`… registro que se crea DESPUÉS de subir el
archivo. Un círculo cerrado: no se podía escribir sin poder leer, ni leer sin
haber registrado, ni registrar sin haber escrito.

Lo que más costó: `fn_expediente_puede_adjuntar` devolvía **`true`** mientras la
fila se rechazaba, así que el fallo se leía como un problema de permisos de la
persona. El mensaje de Postgres nombra la tabla pero **no dice cuál de las
políticas faltó**. Se resolvió leyendo el log del contenedor de storage.

| # | Qué |
|---|---|
| **0170** | El acta de descanso acepta **HEIC/HEIF** — el formato en que un iPhone guarda sus fotos. Sin esto salían en gris en el diálogo de archivos: no se podían ni seleccionar, y la pantalla no daba ningún error |
| **0172** | Las políticas que faltaban en los tres buckets. Abre exactamente el hueco medido y nada más: quien subió un archivo puede leer **lo suyo** mientras lo registra (`owner_id = auth.uid()`), y quien puede crearlo puede reemplazarlo |
| **0175** | El acta de descanso **deja de guardarse como texto en una columna** y pasa al almacén, con los mismos 50 MB que los demás papeles. Los 3 MB de antes no eran una decisión sobre las actas: eran el precio de dónde vivían |

**Tres fallos más de pantalla, cada uno con causa distinta:** el formulario para
subir el cargo estaba escrito **solo** en «Firmados — por entregar», y los tres
memos de producción están entregados · Chrome **no reconoce el `.HEIC`** y
entrega la foto sin tipo, que el almacén rechaza con `415` (el tipo se deduce
ahora de la extensión, en `lib/tipos-archivo.ts`) · «Ver acta» abría un
`<iframe src="data:…">` que Chrome **bloquea**, dejando la pestaña en blanco.

**Por qué ninguna prueba lo cazó.** No había una sola que tocara
`storage.objects`, y un `INSERT` simple pasaba mientras el sistema no
funcionaba. La prueba **136** ejecuta ahora la sentencia real de Storage,
copiada de su log; la **137** cubre las dos ubicaciones posibles del acta.

---

## 2026-08-06 — los cuatro casos de datos que había que revisar

La sección A.4 de `estado.md` llevaba cuatro nombres para mirar a mano. Tres
cerraron y uno resultó ser una decisión, no un pendiente.

| Quién | Cómo cerró |
|---|---|
| **Catherine Pereyra** — inactiva con S/2,250 en el periodo abierto | Cerrado por [`f781674`](https://github.com/felipea92p-ux/cayla-dynamic/commit/f781674). Cuatro personas que se fueron en julio salían con sueldo vigente: el ajuste del 29/07 las encontró activas, y el backfill de la 0086 escribió su cese seis días después por debajo de tramos que ya existían. Se borraron los tramos posteriores al cese y se acortaron los que se pasaban de largo, todo con rastro en `correcciones_auditoria`. **No movió plata:** su liquidación daba S/ 0.00 antes y después |
| **Rufina Salvatierra** — aparecía en el cálculo sin estar en la lista de 22 activos | No era un fantasma: está activa y marcando en TRU (se la ve trabajando el feriado del 06/08). Lo que estaba mal era la lista de 22, no su fila |
| **Sandra Ramirez** — 27 días programados, 0 marcados | Sin rastro en git de una corrección explícita. Deja de seguirse por nombre: la consulta de «quién tiene días programados sin marcar» en `estado.md` la encuentra sola si sigue así |
| **Carlos Espejo** — marcado `planilla` siendo RxH | **No es un pendiente: es una decisión** ([`f1db8eb`](https://github.com/felipea92p-ux/cayla-dynamic/commit/f1db8eb)). El tipo de vínculo es un sí/no para los tres conceptos a la vez, así que marcarlo `rxh` le pondría gratificación y CTS en cero — lo contrario de lo acordado. Mientras no exista la excepción por persona, no se le toca. Pasó a «Decisiones tomadas» |

---

## 2026-08-05 (noche) — el papel entra al sistema

Dos frentes cerrados el mismo día, y los dos van de lo mismo: **el documento que
sostiene un concepto no remunerativo deja de vivir en una carpeta.**

### Educación, completa y en producción

La pantalla `/admin/educacion` existía escrita en una rama desde el 04/08 y no
estaba fusionada. Se fusionó y se le pusieron las reglas que le faltaban.

| # | Qué |
|---|---|
| **0136** | La pantalla, su bucket `comprobantes` y las 5 funciones de escritura |
| **0149** | Las 13 reglas: monto calculado (`min(costo × 75 %, techo del rango)`) y no tecleado · cobertura 75 % fija · **el techo se mide sobre la SUMA**, no fila por fila · `vigente_hasta` obligatoria · nombre del hijo obligatorio · candado de periodo pagado · corregir abre vigencia nueva · motivo y rastro en auditoría · cierre automático al cesar |
| **0150** | La planilla **suma** todas las asignaciones vigentes (antes pagaba una y descartaba el resto en silencio), **exige comprobante** para devengar, y cuenta el mes completo si estaba vigente al **iniciar** el periodo |
| **0154** | El comprobante pesa hasta **50 MB** (rebotó un PDF de 11.7 MB al cargar el primero), y el límite deja de estar escrito en dos sitios: la pantalla lo **pregunta** a la base |

**Tres agujeros medidos, no supuestos:** dos asignaciones de S/150 pagaban S/150 ·
una fila sin comprobante devengaba igual · un ciclo que terminaba el 15 hacía que
ese mes pagara **cero**, habiendo estudiado y pagado la pensión.

**Y el índice único de la 0120 impedía el caso que el diseño promete:** era
`(persona_id, vigente_desde)`, así que madre e hija registradas el mismo día
chocaban. Encontrado ejecutando la prueba, no leyendo.

### Documentos firmados — la pieza con plazo

| # | Qué |
|---|---|
| **0157** | Tabla `documentos_firmados` + bucket `documentos`. El **alcance se declara** (`individual`/`empresa`) en vez de deducirse de un hueco, y cinco constraints hacen imposibles los estados que dejarían el expediente sin valor. Cierra de paso el bucket `expedientes`, que **no tenía límite de tamaño ni de formato** |
| **0159** | La planilla consulta si se exige la declaración de ruta. **Nace apagado**: encenderlo es un `insert` en `parametros_laborales` con su fecha |
| **0161** | El tablero informa también el **cargo del onomástico**, y el aviso es por **calendario**: solo se pone en rojo a quien ya cumplió años. El falso positivo cuesta más que la falta que se escapa |
| **0162** | El tablero deja de pedirle la declaración a **quien firma por CAYLA** —no puede ser las dos partes del mismo pacto individual— y a **quien termina contrato este mes o antes**. El corte es «este mes» y no «tiene fecha de fin» a propósito: un contrato a plazo fijo hasta diciembre desaparecería en agosto y esa persona cobraría cinco meses de movilidad sin el pacto que la sostiene |

**El 2026-08-05 se cazó ahí un error de monto.** La declaración de Taller LIM
salía impresa con **S/ 10.00** mientras la planilla le pagaba los **S/ 12.00**
que la 0142 fijó para Lima. La pantalla nunca leía la tarifa de la sede: buscaba
`sede_codigo` («LIM») comparándolo contra el *nombre* de la sede («Taller LIM»),
no coincidía jamás, caía a la fila general —que vale 0.00 desde la 0118— y de ahí
a un `TARIFA_POR_DEFECTO = 10` escrito a mano. **Un valor por defecto había
convertido «no tengo el dato» en «el dato es 10», en el único papel del sistema
que alguien firma.** Ese defecto ya no existe: sin tarifa aplicable la pantalla
no imprime y dice por qué.

---

## 2026-08-05 — las respuestas del contador

Dante respondió por escrito las cuatro preguntas abiertas. Tres cerraron; lo que
quedó abierto (la marca de afectación de los códigos PLAME) sigue vivo en
`estado.md`.

| Se preguntó | Respondió |
|---|---|
| **Renta imponible 2025** para saber si hay utilidades que repartir | Utilidad 2025 de S/63,655, **pero el umbral no se mide por eso**: se mide por promedio anual de trabajadores y son >20. CAYLA tuvo **5 de promedio en 2025** y proyecta **13 para 2026**. No hay nada que repartir |
| **¿Se paga el 9% de la Ley 30334?** | **Sí**, en línea separada con el código **0312**. Confirma lo que la 0134 ya asumía |
| **¿CAYLA está en el SIRE?** | **Sí**, ventas y compras al día. Fuera del alcance de Dynamic |

**Una respuesta suya que no aplica a nuestro caso.** Sobre la movilidad, Dante
citó el tope del 4% de la RMV y la exigencia de comprobantes de pago. Eso es el
**art. 37 inciso a1) de la LIR**, que regula la movilidad como *condición de
trabajo* y se autoexcluye en su propio texto al aplicar solo a gastos «que no
constituyan beneficio o ventaja patrimonial directa» del trabajador. Lo de CAYLA
es el **art. 19 inciso e) del D.S. 001-97-TR**: le entra al bolsillo de la
persona. Seguir su consejo literal significaría juntar ~500 boletos de colectivo
al mes y, peor, convertiría el concepto en un reembolso de gastos — justo la
figura que no queremos.

**La 0152 (techo de la movilidad) nació como 0151 y se renumeró.** Felipe ya la
había pegado en producción con el número viejo, así que el SQL que corrió allá
imprime `0151 ·` en sus mensajes. No es un error: es el mismo archivo. El objeto
que quedó en la base no lleva el número en el nombre, así que no hay nada que
corregir. El hook `numeracion.sh` detectó la colisión antes del push, que es
exactamente para lo que se escribió.

---

## 2026-08-05 — los números de migración pasaron a vigilarse solos

`scripts/hooks/numeracion.sh` corre antes de cada push y **bloquea** si hay dos
archivos con el mismo número, o si un número nuevo lo reclama otra rama.

**Por qué hizo falta.** En dos días hubo seis choques entre sesiones trabajando en
paralelo. Uno de ellos —dos `0158` a la vez— rompió algo de verdad: `supabase db
reset` **aborta** con `duplicate key value violates unique constraint
"schema_migrations_pkey"`, así que no se puede ni reconstruir el esquema. Y hubo
suerte: la otra 0158 tocaba `fn_provisiones` y no `fn_planilla_calcular`. **Si
las dos hubieran reescrito la misma función, la última aplicada habría borrado el
trabajo de la otra sin que nada avisara.**

Y peor, comprobado el 06/08: con dos archivos del mismo número, `db reset` aplica
uno, **saltea el otro en silencio y termina sin error**. El saltado nunca corre,
así que ninguna prueba de base de datos puede verlo — por eso el freno mira
nombres de archivo y no la base.

---

## 2026-08-01 — la boleta cuadra al céntimo

Fuera el «Rendimiento Extraordinario» y el «Incentivo Variable por Metas»;
entraron las líneas de movilidad y de descuento de pensión, y el bloque de lo que
CAYLA paga además. **El descuadre de 76.67 contra 71.84 quedó cerrado.**

### Lo que quedó comprobado sobre el equipo

- **22 personas activas**, no 26. Eso mueve el piso de EsSalud a ~S/2,237/mes y el
  bono de cumpleaños a S/3,960/año.
- **La asignación familiar está correcta**: Angie Chávez es la única con hijos y la
  única que la cobra. Cero desajustes en las 22.
- **Nadie ingresó antes del 2025-01-02**, así que si la acreditación en el REMYPE
  es anterior, el frente de la asignación familiar bajo régimen general es cero.

---

## La lección de julio: un registro no es una comprobación

Se dio por hecho que las 0088 y 0089 se habían aplicado bajo sus números viejos.
La **0089 no se había aplicado**: se registró, y su contenido nunca llegó a la
base.

Esa distinción sigue siendo la más cara de este proyecto, y por eso hay dos
herramientas distintas — son dos preguntas distintas, y siguen vigentes:

- **¿está anotada?** → `migraciones_aplicadas` (y la prueba `122`, en CI)
- **¿está su contenido?** → `scripts/sql-manual/comparar_funciones.sql`

### Lo que costó aprender entonces

- **Un bloque que recorre objetos en masa aborta entero** al topar con uno que no
  pertenece al rol `postgres` de Supabase, que **no es superusuario**. Probar como
  superusuario local no reproduce esa condición. Todo barrido lleva manejo de
  excepción por elemento y reporta al final lo que no pudo tocar.
- **`alter default privileges ... in schema public revoke execute ... from public`
  no hace nada.** El EXECUTE que PUBLIC tiene por defecto sobre funciones es
  global, no por schema, y una cláusula `IN SCHEMA` solo puede *añadir*. Sin
  `in schema` sí funciona. La sentencia se acepta sin error en las dos formas.
- **Un `revoke` por columna no reduce nada** si el rol tiene `SELECT` sobre la
  tabla entera. Por eso la firma escaneada se mudó de tabla en vez de revocarse.
- **El sello de «día por revisar» era tinta, no una pregunta.** Se ponía cuando el
  día se rompía y nada lo levantaba: cuantas más marcas del día estuvieran bien,
  más fácil era que el día se quedara pegado en la lista para siempre.
- **Numerar migraciones sin volver a mirar el directorio** produjo dos colisiones
  (0085 y 0086) en la misma sesión en que se criticó ese error. De ahí salió el
  hook de numeración.

---

## Entorno — lo que se creyó y era falso (2026-08-01 → 2026-08-06)

Durante días se dio por cierto que **las pruebas de base de datos no corrían en la
MacBook**. Era falso: el comando estaba mal. `supabase start` fallaba aplicando la
0001 con «type rol_usuario already exists», y de ahí salió la creencia — que llegó
al `CLAUDE.md` y ya está corregida.

Lo correcto es `npx supabase db reset` seguido de `npx supabase test db`. Y el
2026-08-06 se comprobó que **`supabase start` también funciona**: levanta el stack
completo (Auth, Storage, Realtime), que es lo que hace falta para probar una
subida de archivos de punta a punta.

El andamio manual con `docker run` que se usó para la auditoría empírica de julio
ya no hace falta y no se conserva.

---

## Registro de lo cerrado (para no re-investigar)

Deshacer pago de planilla ✅ (0066 + test 30) · faltas Fase 2 completa ✅
(0051–0060) · cobertura en vivo ✅ · bono de puntualidad ✅ (0034) · menú móvil ✅
· recuperar clave ✅ · boleta individual ✅ · patrón de tardanzas ✅ · descanso
sustitutorio con actas ✅ (0069–0073) · ejecución anónima cerrada ✅ (0076) ·
`generarClave()` con `crypto.getRandomValues` ✅ · la 0126 sí existe ✅ · el PR #13
cerrado y las 40 ramas limpiadas ✅ (quedan 4) · `permisos.ts` y `fecha-lima.ts`
fusionados en `packages/shared` ✅ · CI corre typecheck ✅ · `aplicar_0017.sql`
eliminado ✅
