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
