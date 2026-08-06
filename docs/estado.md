# Dynamic — Estado y pendientes

**Este es el único archivo de estado.** Se sobrescribe al avanzar; no se crean
copias con fecha. La historia vive en git. Cómo se trabaja: ver
[`CLAUDE.md`](../CLAUDE.md) en la raíz.

## Qué va acá y qué no

Este archivo guarda **solo lo que ninguna herramienta puede responder sola**:
las decisiones tomadas, los pendientes con fecha, lo que depende de una persona,
y lo que se descartó para no volver a investigarlo.

**Lo que se sacó, y dónde vive ahora.** Hasta el 2026-08-05 esto llevaba también
el inventario de migraciones, cuántas pruebas hay y qué está aplicado. Se
desfasó tres veces en tres días, y el encabezado llegó a decir «511 pruebas»
mientras su propio bloque de verificación —tres líneas más abajo— decía 477. Un
archivo que se contradice a sí mismo es peor que no tenerlo: se lee igual de
seguro y señala mal.

| Pregunta | Quién la responde de verdad |
|---|---|
| ¿Cuántas migraciones hay, hasta cuál? | `ls supabase/migrations \| tail -1` |
| ¿Cuántas pruebas, y pasan? | `npx supabase db reset && npx supabase test db` · `npx pnpm typecheck && npx pnpm test` |
| ¿Qué está aplicado en producción? | `scripts/sql-manual/comparar_funciones.sql` — y `migraciones_aplicadas` para el registro |
| ¿Falta anotar alguna migración? | la prueba `122_toda_migracion_deja_su_rastro`, en CI, en cada push |
| ¿Hay números duplicados o huecos nuevos? | `scripts/hooks/numeracion.sh`, antes de cada push |
| ¿Qué se hizo y cuándo? | `git log` |

Ninguna de esas seis puede envejecer sin que alguien se entere. Las de abajo sí,
y por eso están escritas.

**Regla para quien edite este archivo:** si lo que vas a agregar es un número que
un comando puede calcular, no va acá — va el comando.

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
| **0161** | El tablero informa también el **cargo del onomástico**, y el aviso es por **calendario**: solo se pone en rojo a quien ya cumplió años. Quien cumple más adelante, quien no tiene su fecha de nacimiento cargada y quien entró después de su onomástico salen en gris — el falso positivo cuesta más que la falta que se escapa. De paso, el bono deja de poder registrarse a nombre de un locador: esa regla solo cubría la declaración de ruta |
| **0162** | El tablero deja de pedirle la declaración a **quien firma por CAYLA** —no puede ser las dos partes del mismo pacto individual; sale de `configuracion.firmante_empresa`, no de un nombre escrito— y a **quien termina contrato este mes o antes**. El corte es «este mes» y no «tiene fecha de fin» a propósito: un contrato a plazo fijo hasta diciembre desaparecería en agosto y esa persona cobraría cinco meses de movilidad sin el pacto que la sostiene. No mueve ningún pago mientras el candado de la 0159 siga apagado |

**Pantallas:** Documentación pasó de imprimir a ciegas a ser un **tablero** de
quién está en planilla, con imprimir/subir/«se negó» en cada fila y la política
de empresa en franja roja si falta o si su fecha es posterior al primer pago.
Desde la 0161 se pueden subir **los tres** documentos firmados y no solo la
declaración de ruta: el guardado mandaba el tipo fijo en `"ruta"`, así que el
aviso rojo de la política se podía leer pero no cerrar, y el cargo del bono no
tenía dónde subirse aunque la base lo aceptaba desde la 0157.

**El 2026-08-05 se cazó ahí un error de monto.** La declaración de Taller LIM
salía impresa con **S/ 10.00** mientras la planilla le pagaba los **S/ 12.00**
que la 0142 fijó para Lima. La pantalla nunca leía la tarifa de la sede: buscaba
`sede_codigo` («LIM») comparándolo contra el *nombre* de la sede («Taller LIM»),
no coincidía jamás, caía a la fila general —que vale 0.00 desde la 0118, nace
apagada— y de ahí a un `TARIFA_POR_DEFECTO = 10` escrito a mano. Un valor por
defecto había convertido «no tengo el dato» en «el dato es 10», en el único
papel del sistema que alguien firma. Ese defecto ya no existe: sin tarifa
aplicable la pantalla **no imprime** y dice por qué. El mismo error archivaba el
`monto_declarado` equivocado al subir el escaneo; ahora los dos caminos llaman a
la misma función.

**Descubierto de paso, sin resolver: Central (CCO) no tiene tarifa de
movilidad.** Solo existen las filas de AQP, TRU y LIM (0142). Quien está en
Central cae a la general de 0.00, o sea **cobra S/ 0.00 de movilidad**, y hasta
hoy su declaración salía afirmando S/ 10.00. Decidir si Central lleva tarifa —y
de cuánto— es de Felipe; el sistema ya no imprime un número inventado mientras
tanto.
Disciplina ganó **«Subir cargo firmado»** como acción principal — su backend
existía desde la 0074 y nadie lo usaba, entre otras cosas porque
`expediente_adjuntos` no estaba en los tipos generados.

**El candado NO está encendido.** Cuando el tablero esté completo:

```sql
insert into parametros_laborales (clave, valor, vigente_desde, sustento)
values ('movilidad_exige_declaracion', 1, '<fecha>', '<por qué>');
```

---

## 2026-08-05 — llegaron las respuestas del contador

Dante respondió por escrito las cuatro preguntas abiertas. **Tres cierran**
(utilidades, SIRE, el 9% de la Ley 30334), una quedó a medias (los códigos PLAME),
y **una de sus respuestas no aplica a nuestro caso** (el tope del 4% en movilidad).
El detalle está en [A.5](#a5--las-cuatro-preguntas-al-contador-respondidas-2026-08-05).

Lo que salió de ahí:

| Qué | Dónde |
|---|---|
| **La repregunta**, redactada y lista para enviarle — la marca de afectación en el PDT es lo que ahora bloquea | [`movilidad-y-codigos-plame-para-el-contador.md`](movilidad-y-codigos-plame-para-el-contador.md) |
| **La lista real de quién va a la póliza** del Seguro de Vida Ley, para cruzar contra las 19 de la cotización antes de firmar | [`quienes_van_al_seguro_de_vida_ley.sql`](../scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql) |
| **0152 · el techo de la movilidad** — ninguna tarifa diaria puede pasar del 4% de la RMV vigente (hoy S/45.20). No mueve ningún pago: las tarifas vivas son S/10 y S/12 | [`0152_la_movilidad_tiene_techo.sql`](../supabase/migrations/0152_la_movilidad_tiene_techo.sql) · prueba [`119`](../supabase/tests/119_la_movilidad_tiene_techo.test.sql), 10 aserciones |
| **El indicador del umbral de 20 trabajadores** — definido, se construye después del seguro | sección [B](#b--lo-que-falta-construir) |

**La 0152 se pega tal cual en el SQL Editor**: es idempotente y auto-contenida, no
necesita una versión aparte en `scripts/sql-manual/`. Al aplicarla imprime
`0152 · Ninguna tarifa de movilidad supera su techo` si todo está en orden, o un
`warning` por cada tarifa que haya que mirar a mano.

⚠️ **Nació como 0151 y se renumeró el 2026-08-05.** Felipe ya la había pegado en
producción con el número viejo, así que **el SQL que corrió en producción imprime
`0151 ·` en sus mensajes**. No es un error: es el mismo archivo, renumerado después
de aplicarse porque `main` ya tenía otra 0151 (el tope de educación). El objeto que
quedó en la base —`fn_movilidad_no_supera_el_techo` y su trigger— no lleva el número
en el nombre, así que no hay nada que corregir en producción. El hook
`scripts/hooks/numeracion.sh` detectó la colisión antes del push, que es
exactamente para lo que se escribió.

**La prueba 119 se comprobó rompiendo el candado a propósito:** quitando el trigger
fallan exactamente las 4 aserciones que dependen de él (el borde de S/45.21, la
medición contra la RMV de la fecha, y las dos del UPDATE). No pasa por casualidad.

---

## 0128 — la base declarada por rango, escrita y sin aplicar

`fn_fijar_base_declarada(rango, monto, vigencia, omitir[])` baja **los dos**
campos que intervienen en el pago —`asignaciones_salario.salario_mensual_soles`
y `personas.sueldo_base_legal`— al mismo monto, versionando el salario vía
`fn_set_salario`. La migración **crea la función y no la llama**: crearla no
mueve ningún pago, llamarla sí.

**Las bases acordadas:** colibrí y cayla/caylo 1,130 · support 1,290 · aurora
1,500 · oráculo 1,810 · archicaylo 2,670. Dos excepciones nominales, que por PII
viven en `scripts/sql-manual/aplicar_0128.sql` (ignorado en git).

**Por qué NO se ha llamado todavía.** La baja de salario la compensan movilidad
+ educación + bono, y van **1 de 3**:

| Concepto | Estado al 2026-08-05 (noche) |
|---|---|
| movilidad | ✅ encendida, S/10/día (S/12 en LIM) desde el 29/07 |
| educación | 🟡 **la pantalla ya está y funciona** (0136/0149/0150). Lo que falta ya no es código: es el dato — quiénes estudian, dónde y cuánto cuesta. `asignaciones_educacion` sigue vacía |
| bono de cumpleaños | ❌ decidido en S/180, sin implementar |

**Lo que cambió el 05/08:** hasta esa fecha la educación estaba bloqueada por
falta de pantalla. Ya no. Ahora está bloqueada por falta de **un dato que solo
Felipe tiene**, y cargarlo son cinco minutos por persona en `/admin/educacion`.
Es la única de las tres compensaciones que se puede destrabar hoy sin escribir
una línea de código.

Medido contra Postgres local: bajar cayla de 1,450 a 1,130 le quita **S/367.37**
en el periodo 29/07–28/08. Y como la educación es **por persona y contra
comprobante**, a quien no estudia bajarle la base le recorta el sueldo sin nada
que lo reponga — para esa persona se usa `p_omitir`, o una base propia más alta.

**Lo que desbloquea esto** es el dato (c) de más abajo: quiénes estudian, dónde
y cuánto cuesta.

**Comprobado en producción el 2026-08-03:** Carlos Espejo es `rxh` —lo excluyen
el filtro `en_planilla` y la excepción por nombre, doble candado— y Felipe
Álvarez ya está en 1,500 en los dos campos, así que su bloque no tiene nada que
hacer (es idempotente y devuelve cero filas).

**Ya tiene prueba (2026-08-04).** `fn_fijar_base_declarada` estaba escrita,
revisada a ojo y **sin una sola prueba pgTAP** — justo lo que el `CLAUDE.md`
prohíbe para cualquier cosa que toque plata. Ahora la cubre
[`111_la_base_declarada_baja_los_dos_campos.test.sql`](../supabase/tests/111_la_base_declarada_baja_los_dos_campos.test.sql):
11 aserciones sobre los dos campos, las tres exclusiones (cesada · locadora ·
otro rango), `p_omitir`, el versionado del tramo anterior, la idempotencia y el
guard de admin. **Comprobada rompiendo la función a propósito**: quitándole la
llamada a `fn_set_sueldo_base_legal` fallan las aserciones 2 y 10, así que la
prueba no pasa por casualidad.

**Huecos de numeración (revisados el 2026-08-04).** Son cuatro:

| Hueco | Qué se sabe |
|---|---|
| **0031** y **0033** | Conocidos: existen solo como `scripts/sql-manual/aplicar_*.sql`, fuera de git por PII. **Falta la versión parametrizada**, que sigue pendiente abajo |
| **0108** | **Explicado el 2026-08-04:** no es un número saltado ni algo aplicado a escondidas. Vive en la rama `origin/movilidad-supeditada-a-asistencia` (`0108_movilidad_supeditada_a_asistencia.sql`), **sin fusionar**. Falta decidir si entra o si su contenido ya lo cubre la 0118 |
| **0133** | Va 0132 → 0134. **Sigue sin explicar** — no aparece en ninguna rama |

~~no existe la migración 0126~~ — **la 0126 sí existe**
(`0126_guard_null_safe_en_la_ficha_personal.sql`).

---

## ✅ Cerrado el 2026-08-01 — la boleta cuadra al céntimo

Fuera el «Rendimiento Extraordinario» y el «Incentivo Variable por Metas»;
entraron las líneas de movilidad y de descuento de pensión, y el bloque de lo que
CAYLA paga además. **El descuadre de 76.67 contra 71.84 que Felipe encontró está
cerrado.**

*El detalle de qué cerró cada migración vivía acá y salió: lo dice mejor el
encabezado de cada archivo en `supabase/migrations/`, que además no puede quedar
viejo. `git log --oneline supabase/migrations/` da el recorrido.*

### Lo que quedó comprobado sobre el equipo

- **22 personas activas**, no 26. Eso mueve el piso de EsSalud a ~S/2,237/mes y el
  bono de cumpleaños a S/3,960/año.
- **La asignación familiar está correcta**: Angie Chávez es la única con hijos y la
  única que la cobra. Cero desajustes en las 22.
- **Catherine, Claudia Pereyra y Claudia Solórzano están inactivas.** No hay nada
  que marcar como `rxh`, y la 0119 se negaría igual: no permite cambiar el vínculo
  de alguien ya cesado.
- **Carlos Espejo** sigue marcado `planilla` y sin régimen de pensión. No se le
  descuenta nada indebido, así que marcarlo como `rxh` puede esperar.
- **Nadie ingresó antes del 2025-01-02**, así que si la acreditación en el REMYPE
  es anterior, el frente de la asignación familiar bajo régimen general es cero.

---

# 📌 QUÉ FALTA — repartido por quién lo hace

## A · Lo que depende de Felipe

### A.1 · Con fecha límite

| Qué | Cuándo | Si no |
|---|---|---|
| **Los convenios individuales de movilidad, firmados y cargados** | **antes del 28/08/2026** — es cuando se paga el periodo | Se habrá pagado movilidad sin el papel que la sostiene. La **RTF 05449-4-2007** desconoció la de 14 de 21 trabajadores por eso exacto |
| **La política de movilidad de empresa, firmada** | con fecha **anterior al 29/07/2026** | Es cuando empezó a pagarse movilidad. Un documento posterior a los pagos que justifica **no los justifica, y encima lo deja por escrito**. El tablero lo avisa solo, en rojo, con las dos fechas |
| **Contratar el Seguro Vida Ley** | cuanto antes | ~S/1,560/año. Sin póliza, CAYLA responde con su patrimonio: 16 remuneraciones por muerte natural, 32 por accidente. Obligatorio desde el primer día (D.Leg. 688) |
| **Registrar la póliza en el MTPE** | 30 días desde que se firma | No registrarla es la misma infracción que no tenerla |

### A.2 · Un clic en GitHub

*Revisado el 2026-08-04: los #21 y #22 ya no están abiertos. **Queda uno solo.***

| PR | Qué trae |
|---|---|
| **#13** | «Documentación: los papeles que sostienen la movilidad», abierto desde el 29/07. **Se puede cerrar**: su pantalla de documentación entró actualizada por el #20 |

**Y 40 ramas en GitHub para un solo PR abierto.** Cada rama fusionada que se
queda es una copia vieja del sistema que alguien puede clonar por error. Limpiar
las fusionadas es un `git push origin --delete` por rama, sin riesgo: lo que
entró a `main` ya está en `main`.

### ✅ Los números de migración ya se vigilan solos (2026-08-05)

**Ya no hace falta acordarse de nada, y esta sección ya no lleva la cuenta.**
`scripts/hooks/numeracion.sh` corre antes de cada push y **bloquea** si hay dos
archivos con el mismo número, o si un número nuevo lo reclama otra rama. Los
huecos ya investigados viven en `scripts/hooks/huecos-conocidos.txt` con su razón
escrita al lado, así que el aviso solo habla cuando aparece uno nuevo.

**Por qué hizo falta.** En dos días hubo seis choques entre sesiones trabajando en
paralelo. Uno de ellos —dos `0158` a la vez, el 05/08— rompió algo de verdad:
`supabase db reset` **aborta** con `duplicate key value violates unique constraint
"schema_migrations_pkey"`, así que no se puede ni reconstruir el esquema. Y hubo
suerte: la otra 0158 tocaba `fn_provisiones` y no `fn_planilla_calcular`. **Si las
dos hubieran reescrito la misma función, la última aplicada habría borrado el
trabajo de la otra sin que nada avisara.**

Y peor, comprobado el 06/08: con dos archivos del mismo número, `db reset` aplica
uno, **saltea el otro en silencio y termina sin error**. El saltado nunca corre,
así que ninguna prueba de base de datos puede verlo — por eso el freno mira
nombres de archivo y no la base.

### A.3 · Datos que hacen falta para seguir

**a) Quiénes estudian y cuánto cuesta su curso.** Con el nombre y el monto alcanza.
Se cargan de a uno con `cargar_educacion_v2.sql`, que pide el nombre y no un UUID.

**b) La fecha de acreditación de CAYLA en el REMYPE.** Decide si queda algún frente
abierto de asignación familiar: quien haya ingresado antes de esa fecha se rige por
el régimen general, donde sí es exigible. La persona más antigua ingresó el
**2025-01-02**, así que si la acreditación es anterior, el frente es **cero**.

### A.4 · Cuatro cosas para revisar en los datos

| Quién | Qué se vio | Por qué importa |
|---|---|---|
| **Catherine Pereyra** | inactiva, 0 días marcados, **total S/2,250.00** en el periodo abierto | Si es su liquidación, correcto. Si no, es plata que se paga a alguien que ya no trabaja |
| **Sandra Ramirez** | 27 días programados, **0 marcados**, total 0.00 | Puede ser vacaciones, permiso, o que no esté marcando |
| **Rufina Salvatierra** | aparece en el cálculo y **no estaba** en la lista de 22 activos | Tiene jornadas sin estar activa, o se agregó después |
| **Carlos Espejo** | sigue marcado `planilla` | Hoy no cobra movilidad porque no marca. **El día que marque, le va a salir.** Se cambia en Equipo → Tipo de vínculo |
| **Quien esté en rango `caylo`** | en local no hay nadie; **en producción no lo puedo mirar** | Ese rango quedó sin techo de educación desde la 0140, así que con un comprobante de S/727 le pagaría **S/545.25** en vez de S/180. La 0178 lo reasigna sola a `cayla` y avisa a quién — pero el SELECT está en la cabecera de `aplicar_0178.sql` para verlo antes de pegar |

### A.5 · ✅ Las cuatro preguntas al contador, respondidas (2026-08-05)

Dante respondió las cuatro por escrito. Tres cierran, una abrió otra pregunta.

| Se preguntó | Respondió | Qué sigue |
|---|---|---|
| **Renta imponible 2025** para saber si hay utilidades que repartir | Utilidad 2025 de S/63,655, **pero el umbral no se mide por eso**: se mide por promedio anual de trabajadores y son >20. CAYLA tuvo **5 de promedio en 2025** y proyecta **13 para 2026** | **Cerrado.** No hay nada que repartir. Ver el indicador de vigilancia en la sección B |
| **¿Se paga el 9% de la Ley 30334?** | **Sí**, y va en línea separada de la boleta con el código **0312** | **Cerrado.** Confirma lo que la [`0134`](../supabase/migrations/0134_la_bonificacion_extraordinaria_ley_30334.sql) ya asumía y verificó contra una boleta real |
| **Códigos PLAME** de los tres conceptos | Movilidad **0909** confirmado · educación «202» · cumpleaños «203» | **Casi.** Escribe los códigos sin el cero inicial (dijo «909» por 0909), así que son **0202** y **0203**. Falta su confirmación de una línea |
| **¿CAYLA está en el SIRE?** | **Sí**, ventas y compras al día. La gracia se amplió al **31/08/2026** | **Cerrado.** Fuera del alcance de Dynamic |

**Lo que quedó abierto, y es lo que ahora bloquea.** El código no es el problema:
el problema es **con qué marca de afectación** quedan el 0909, el 0202 y el 0203 en
el PDT — EsSalud, ONP/AFP y quinta categoría. Si alguno queda declarado afecto, no
solo se pagan aportes que la ley no exige: CAYLA declara por escrito y mes a mes que
el concepto es remunerativo, y eso destruye el sustento del artículo 19 con nuestra
propia firma. Es lo único que tiene que responderse **antes de declarar el primer
periodo** con los tres conceptos.

**Y una respuesta suya que no aplica a nuestro caso.** Sobre la movilidad, Dante
citó el tope del 4% de la RMV y la exigencia de comprobantes de pago. Eso es el
**art. 37 inciso a1) de la LIR**, que regula la movilidad como *condición de
trabajo* y se autoexcluye en su propio texto al aplicar solo a gastos «que no
constituyan beneficio o ventaja patrimonial directa» del trabajador. Lo de CAYLA es
el **art. 19 inciso e) del D.S. 001-97-TR**: le entra al bolsillo de la persona.
Seguir su consejo literal significaría juntar ~500 boletos de colectivo al mes y,
peor, convertiría el concepto en un reembolso de gastos — justo la figura que no
queremos.

Todo esto, redactado y listo para enviarle, está en
[`movilidad-y-codigos-plame-para-el-contador.md`](movilidad-y-codigos-plame-para-el-contador.md).

**Del Seguro de Vida Ley (D.Leg. 688 + D.U. 044-2019):** cotizado en **La Positiva,
S/170/mes por 19 personas**, sin comisión de corredor —Dante confirmó que el
reglamento no la contempla— y con factura. Cobertura de 16 sueldos por muerte
natural y 32 por accidente o invalidez total y permanente. **El 19 hay que
cruzarlo antes de firmar**: el diseño remunerativo asume 26 personas. Quien esté
en planilla y fuera de la póliza queda sin cobertura, y ese capital lo paga CAYLA
de su patrimonio. La consulta que arma la lista real está en
[`quienes_van_al_seguro_de_vida_ley.sql`](../scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql).

---

## B · Lo que falta construir

| Qué | Bloqueado por |
|---|---|
| **Las bases declaradas** de los cuatro rangos altos — y hay que bajar **los dos campos**, `sueldo_base_legal` **y** `salario_mensual_soles` | confirmar los montos finales |
| ~~**Pantalla para subir comprobantes** de educación, con candado~~ | ✅ **hecha y en producción** el 2026-08-05: [`0136`](../supabase/migrations/0136_la_pantalla_de_educacion_con_su_comprobante.sql) + [`0149`](../supabase/migrations/0149_la_educacion_con_todas_sus_reglas.sql) + [`0150`](../supabase/migrations/0150_la_planilla_suma_la_educacion_y_exige_el_papel.sql). Sin comprobante se guarda pero **no paga** |
| ~~**Pantalla para subir los convenios de movilidad firmados**~~ | ✅ **hecha y en producción** el 2026-08-05: [`0157`](../supabase/migrations/0157_los_documentos_firmados_entran_al_sistema.sql). El tablero de `/admin/documentacion` dice a quién le falta |
| **Cargar las 22 declaraciones de ruta firmadas** | **de Felipe. Plazo: 28/08/2026.** El sitio donde subirlas ya existe |
| ~~**Bono de cumpleaños** con alerta en el mes del onomástico~~ | ✅ **hecho** en la [`0161`](../supabase/migrations/0161_el_tablero_tambien_ve_el_cargo_del_cumpleanos.sql) — falta pegarla. El tablero lee `datos_personales.fecha_nacimiento` y avisa por mes. **No condiciona el pago a propósito**: el cargo se firma AL recibir el dinero, así que exigirlo antes invertiría el orden real del acto. Queda pendiente cargar las fechas de nacimiento que falten: quien no la tenga sale como «falta su fecha», no como pendiente |
| ~~**Tarifa de movilidad para CCO**~~ | ✅ **resuelto el 2026-08-06** por la [`0166`](../supabase/migrations/0166_la_movilidad_se_paga_por_donde_se_trabaja.sql): Estefany trabaja dentro de la tienda de Arequipa, así que su `sede_fisica_id` apunta a AQP y cobra S/ 10. **Sigue en CCO** para marcajes, reportes y planilla por sede. Los otros dos de Central no devengan: Felipe por viáticos, Carlos y Catherine por ser RxH (0117) |
| **La fila general de movilidad vale S/ 10.00 y no está cerrada** — *decisión tomada: se queda así* | No es un descuido pendiente sino una **red deliberada** (Felipe, 2026-08-06): quien esté en una sede sin tarifa propia cobra S/ 10.00 en vez de cero. Conviene saber de dónde sale ese 10: es la **tarifa original de Trujillo** (su sustento lo dice, «colectivo urbano de Trujillo a S/2.50 por tramo»), que quedó sin `vigente_hasta` cuando la [`0142`](../supabase/migrations/0142_la_tarifa_de_movilidad_por_sede.sql) abrió las filas por sede. **El escenario que la activa: abrir una sede nueva.** Esa gente cobra S/ 10.00 desde el primer día sin que nadie haya mirado el pasaje de esa ciudad, y sin aviso. Si algún día se prefiere que un dato faltante se note en vez de rellenarse, se cierra con `vigente_hasta` y pasan a S/ 0.00 — hoy eso no movería la plata de nadie |
| ~~**La bonificación del 9%** de la Ley 30334~~ | ✅ **hecha** en la [`0134`](../supabase/migrations/0134_la_bonificacion_extraordinaria_ley_30334.sql), y el contador confirmó el 2026-08-05 que la premisa era correcta |
| **Indicador del umbral de 20 trabajadores** — promedio corrido del ejercicio, con aviso al acercarse | nada. Definido abajo |
| **Versionar la RMV a S/1,300** cuando se publique el decreto | que salga la norma |

**El indicador del umbral de 20, y por qué vale construirlo.** Dante zanjó las
utilidades para 2025 y 2026, pero lo hizo con una foto: 5 y 13 de promedio. Ese 13
es un accidente del año de crecimiento —de enero a junio hubo entre 5 y 8 personas,
y recién desde julio hay 19—. **Si CAYLA mantiene 19 los doce meses de 2027, el
promedio de 2027 es 19.** A una contratación del umbral.

Y la persona número 21 no cuesta su sueldo: cuesta su sueldo **más el 8% de la renta
imponible de todo el ejercicio** repartida entre todos (D.L. 892, comercio). Sobre
los S/63,655 de 2025 serían ~S/5,092 al año que hoy no se ven en el momento de
decidir la contratación.

El sistema tiene todos los datos para calcularlo solo —quién está activo, en
planilla, en qué mes— y puede mostrar el promedio corrido **antes** de que se firme
el contrato, en vez de que lo diga el contador en marzo del año siguiente cuando ya
no hay nada que decidir. Es convertir un dato contable retrospectivo en una decisión
de negocio informada. **Acordado con Felipe el 2026-08-05: se construye después de
cerrar el Seguro de Vida Ley.**

**Sobre la RMV:** el alza se anunció el 28/07/2026 y **el decreto no está
publicado**. Cuando salga, son dos sentencias por cada clave —`rmv` y
`asignacion_familiar`— y están escritas en las cabeceras de la 0116 y la 0122. Los
periodos ya pagados quedan intactos, que es todo el punto de haberlas versionado.

⚠️ **Ojo con el plazo, porque Dante lo describió mal.** Dijo que hay que esperar al
Congreso, al Senado y a la promulgación. La RMV **no se fija por ley**: se fija por
**Decreto Supremo del Ejecutivo**, previa consulta al Consejo Nacional de Trabajo,
conforme al art. 24 de la Constitución (la subida a S/1,130 fue el D.S. 006-2024-TR).
Puede publicarse de un día para otro y regir desde el 1° del mes siguiente. **La
vigilancia se mide en semanas, no en meses.** Donde Dante sí puede tener razón es en
el **bono compensatorio para MYPE**: eso es gasto público y probablemente sí necesita
norma con rango de ley o decreto de urgencia. Son dos normas con dos plazos, y está
repreguntado.

---

## C · Lo que se descartó y no vuelve

Cinco cosas que sonaron graves y se cayeron al verificarlas. Quedan acá para que no
vuelvan a costar tiempo.

| Se dijo | La verdad |
|---|---|
| El límite del RER de 10 trabajadores por turno | **CAYLA está en Régimen MYPE Tributario** desde 2023 (ficha RUC). El RER no aplica. **No hay que mover ningún horario** |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **No existe ese umbral en la ley.** Era una regla de dedo mía |
| La asignación familiar se debe a todos los que tengan hijos | El régimen de **pequeña empresa NO la incluye** — las palabras aparecen cero veces en el TUO de la Ley MYPE y en la Ley 32353, leído en texto primario. **Pero a quien ya la cobra no se le puede quitar**: sería reducción unilateral de remuneración (art. 30.b) |
| Un pacto colectivo blinda la movilidad | Solo es requisito del inciso g) para festividades. Art. 9 TUO CTS: la denominación es irrelevante. **La firma no blinda, incrimina** |
| El SCTR es obligatorio por el taller | **No.** Se revisaron las 270 actividades del Anexo 5: la confección de prendas (CIIU 141x) no está. Evita S/1,600–2,500/año de un seguro que nadie exige |

**Y el techo que ordena todas las multas:** todas las de una misma inspección de
SUNAFIL topan en el **1% de los ingresos netos del año anterior** (art. 48.1-A del
Reglamento de Inspección). Con ~S/900,000 de facturación el techo es **~S/8,000**,
no las seis cifras que suman los hallazgos por separado. **Pero no se aplica solo**:
exige presentar la constancia de REMYPE y sustentar los ingresos netos. Sin esos dos
papeles se cobra el nominal.

---

## D · Consultas útiles que ya existen

| Archivo | Para qué |
|---|---|
| `revision_completa.sql` | 15 comprobaciones de las migraciones 0115–0122 |
| `encender_movilidad.sql` | Encender la tarifa, en transacción y con verificación |
| `cargar_educacion_v2.sql` | Cargar una asignación por nombre, sin copiar UUID |

**Y el prólogo que hace falta seguido:** `fn_planilla_calcular`, `fn_provisiones` y
`fn_set_tipo_vinculo` exigen sesión de admin, y el SQL Editor no la tiene. Dos líneas
al inicio lo resuelven:

```sql
select set_config('request.jwt.claim.sub',
  (select auth_user_id::text from personas
    where rol = 'admin' and nombres ilike '%Felipe%' and auth_user_id is not null limit 1),
  true);
```

---

## Lo que sigue, sin urgencia

### Tres datos que hacen falta

**a) Quiénes estudian y cuánto cuesta su curso** (`aurora 1 → universidad S/520`).

**b) La lista nominal real:**

```sql
select a.rango::text, p.nombres || ' ' || p.apellidos as persona, p.estado,
       p.tipo_vinculo, a.salario_mensual_soles as salario,
       p.sueldo_base_legal as declarado, p.regimen_pension, p.fecha_ingreso
from personas p
left join asignaciones_salario a on a.persona_id = p.id and a.vigente_hasta is null
order by a.salario_mensual_soles desc nulls last, p.apellidos;
```

**c) El refrigerio real**, que deja el sustento de la movilidad atado a tus datos:

```sql
with dia as (
  select m.persona_id, (m.timestamp_marca at time zone 'America/Lima')::date as f,
         min(case when m.tipo = 'salida_almuerzo'  then m.timestamp_marca end) as sale,
         min(case when m.tipo = 'retorno_almuerzo' then m.timestamp_marca end) as vuelve
  from marcajes m
  where m.anulada_at is null and m.timestamp_marca >= now() - interval '90 days'
  group by 1, 2
)
select count(*) as dias_con_marcas,
       count(*) filter (where sale is not null and vuelve is not null) as dias_con_4_traslados,
       round(avg(extract(epoch from (vuelve - sale)) / 60) filter (where vuelve > sale)) as refrigerio_min,
       count(*) filter (where extract(epoch from (vuelve - sale)) / 60 >= 60) as dias_1h_o_mas
from dia;
```

### 4 · Una llamada que no depende de código

**El Seguro Vida Ley no está contratado.** Obligatorio desde el primer día
(D.Leg. 688, mod. Ley 31408). Cuesta **~S/1,560 al año** por los 26. Si falta y
alguien fallece, CAYLA paga de su bolsillo 16 remuneraciones (~S/18,000) por causa
natural o 32 (~S/36,000) por accidente. **Lo mejor del expediente por relación
costo-beneficio.**

---

## 🔴 Lo que la auditoría empírica encontró, y cambia el diseño

Contra Postgres local con datos reales, en `BEGIN … ROLLBACK` como manda el
`CLAUDE.md`. Es el hallazgo más importante de la madrugada.

**`pago_base` se calcula sobre `asignaciones_salario.salario_mensual_soles` —el
rango completo— y NO sobre `personas.sueldo_base_legal`:**

```
pago_base = horas × salario_mensual_soles / v_base
basica    = horas × least(sueldo_base_legal, salario) / v_base
```

**Declarar menos NO reduce lo que se paga.** Sumar movilidad, educación y bono
encima del rango completo sobrepagaría por el monto entero de esos conceptos —
del orden de **S/4,900 al mes** entre las 26 personas.

**La corrección:** al fijar las bases declaradas hay que bajar **los dos campos**
—`sueldo_base_legal` **y** `salario_mensual_soles`— al mismo monto. Es exactamente
lo que Felipe eligió al decir «base = lo declarado»; lo que faltaba era saber que
toca dos campos y no uno.

Con esa corrección, en un mes **sin feriados**:

| Rango | declarado → base | + movilidad | − pensión | = total | objetivo | necesita educ. + bono |
|---|---|---|---|---|---|---|
| colibrí | 1,129.55 | +270.00 | −147.52 | 1,252.03 | 1,320 | **67.97** |
| cayla | 1,129.55 | +270.00 | −160.54 | 1,352.01\* | 1,450 | **97.99** |
| support | 1,289.49 | +270.00 | −167.25 | 1,392.24 | 1,650 | **257.76** |
| aurora | 1,499.40 | +270.00 | −194.92 | 1,574.48 | 1,890 | **315.52** |
| oráculo | 1,809.28 | +270.00 | −232.31 | 1,846.97 | 2,250 | **403.03** |
| archicaylo | 2,668.94 | +270.00 | −348.56 | 2,590.38 | 3,000 | **409.62** |

*\*La fila de cayla del fixture tiene hijos, así que incluye S/113 de asignación
familiar; sin hijos necesitaría ~S/198.*

**Los cuatro rangos altos cuadran casi exacto con el diseño acordado** — aurora
+0.52, oráculo −1.97, archicaylo +4.62, support −7.24.

### Dos cosas más que aparecieron

**Los días son 27, no 26.** En un periodo de 31 días con domingos libres hay 27
laborables, así que la movilidad a S/10 da **270**, no 260.

**Los feriados oscilan el total entre S/90 y S/196 por mes.** Por feriado se paga
el día prorrateado por la asistencia del mes **más** las horas efectivamente
trabajadas ese día, salvo compensación con día libre (lógica de la 0069). Agosto
2026 tiene dos: 29 de julio y 6 de agosto.

**Por eso el diseño no puede cerrar exacto todos los meses**, y forzarlo con
educación o bono sería el reverse-engineering que hunde los conceptos (caso Albis).
Cada concepto se fija por su propio mérito y el total aterriza cerca del rango.

---

## Decisiones del diseño remunerativo (2026-07-31)

**En la boleta:** lo que CAYLA paga además —el EsSalud y las tres provisiones—
va en un bloque aparte, fuera de la tabla del pago, con la leyenda «no se
descuenta de tu sueldo». **Sin total y sin porcentaje**, por decisión tomada.

| Concepto | Decisión | Amparo |
|---|---|---|
| **Movilidad** | S/10.00 por día marcado en AQP y TRU, **S/12.00 en LIM** (0142) · 4 traslados · refrigerio de 1h15 habilita almorzar en casa | Art. 19 e) · PLAME **0909** ✅ confirmado por el contador |
| **Educación** | 75% del comprobante, tope por rango · vale para el trabajador **y/o sus hijos**, sin tope de edad | Art. 19 f) · PLAME **0202** ⚠️ el contador dijo «202», falta confirmar el cero |
| **Bono cumpleaños** | **S/180**, igual para los 26, en el mes del onomástico, sin condición de antigüedad | Art. 19 g) · PLAME **0203** ⚠️ mismo caso |
| **Pensión** | Tasa real por persona (12.84%–13.06% u ONP 13%), desde el periodo abierto | — |
| **EsSalud** | 9% con piso de la RMV, visible como aporte de la empresa | Ley 26790 art. 6 |
| **Base de beneficios** | Igual al monto declarado de cada persona | decisión de Felipe |
| **Fuera de la estructura** | Felipe y Catherine | decisión de Felipe |
| **Por honorarios** | Carlos Espejo y Claudia Pereyra — falta marcarlos con la 0119 | — |

**La cláusula del bono, textual.** No usar la que decía «gratificación
extraordinaria a título de liberalidad»: invocaba el inciso a), que exige que el
pago sea *ocasional*, y hacía el gasto **no deducible** (art. 44 d) LIR).

> *Asignación por cumpleaños, otorgada con ocasión del onomástico del trabajador,
> conforme al literal g) del artículo 19 del D.S. 001-97-TR. No constituye
> remuneración computable para ningún efecto legal.*

---

## ⏳ Pendiente de la estructura remunerativa

| Qué | Bloqueado por |
|---|---|
| **0121** bases declaradas (los **dos** campos) | la lista nominal real |
| **0122** bono automático con alerta | conectar `datos_personales.fecha_nacimiento` |
| Cargar las asignaciones de educación en la 0120 | la lista de quién estudia y su comprobante |
| Pantalla de comprobantes con candado en el pago | nada |
| Documentación con las cláusulas (PR #13, 413 líneas escritas) | nada |
| ~~El 9% de la Ley 30334 sobre cada gratificación~~ | ✅ **cerrado** el 2026-08-05: el contador confirmó que ya lo paga y lo separa con el código 0312, que es lo que la 0134 asumía |
| Los 26 convenios individuales de movilidad firmados | **antes de encender la tarifa** |
| **Los tres conceptos, en el contrato de trabajo** | nada — pero **no existe generador de contratos** en el sistema |

**Lo del contrato es un hueco nuevo (2026-08-05).** Dante lo dijo sin que se le
preguntara: *«estos conceptos no remunerativos tienes que incluirlos en el contrato
de trabajo»*. Hoy el sistema tiene fecha de fin de contrato (0144) y sabe cuándo
vence (0143), pero **no genera ni guarda el texto del contrato**. Los tres conceptos
viven en la boleta y en los convenios de movilidad; en el contrato, en ninguna
parte. Es el mismo tipo de riesgo que la RTF 05449-4-2007 ya nos enseñó con los
convenios: el concepto sin su papel no se sostiene el día de la fiscalización.

**Sobre los convenios:** la **RTF 05449-4-2007** desconoció la movilidad de 14 de
21 trabajadores por falta de convenio exhibido. El inciso e) nombra el «pacto
individual» como la vía del monto fijo. La sentencia para encender la tarifa, con
su memoria de cálculo completa, está en la cabecera de la 0118.

---

## Correcciones a información que yo di mal

Quedan anotadas porque se tomaron decisiones sobre ellas.

| Lo que dije | Lo correcto |
|---|---|
| «El límite del RER de 10 trabajadores por turno es tu problema más caro» | **CAYLA está en Régimen MYPE Tributario desde 2023** (ficha RUC). El RER no aplica. No hay que mover ningún horario |
| «Sobre 25% de conceptos no remunerativos se activa la presunción de salariedad» | **Era mi regla de dedo, no una norma.** No existe porcentaje en la ley peruana |
| La cláusula del bono con «liberalidad» y «a discreción» | Invocaba el inciso a), que exige ocasionalidad, y hacía el gasto no deducible |
| «Ninguna función respeta `en_planilla`» | **Las de liquidación sí:** `fn_cts_trunca`, `fn_grati_trunca` y `fn_vacaciones_truncas` vía `fn_devenga_beneficios` |
| «Un pacto colectivo blinda la movilidad» | Solo es requisito del inciso g) para festividades. Art. 9 TUO CTS: la denominación es irrelevante. **La firma no blinda, incrimina** |
| «CAYLA es un instituto de idiomas» *(en un prompt de verificación)* | Es **CIIU 4641 — venta al por mayor de textiles**. Se descartó todo el análisis de IGV educativo que salió de ahí |

---

## Notas del entorno (MacBook, 2026-08-03)

**✅ RESUELTO: las pgTAP sí corren en esta Mac.** La clave es `db start`, no
`start`:

```bash
npx supabase db reset    # reconstruye desde cero y aplica TODAS las migraciones
npx supabase test db     # tarda ~2 segundos
```

Es la mejor verificación de una migración nueva —construye el esquema entero
desde cero— y ahorra el viaje de ida y vuelta a GitHub Actions. *Cuántos archivos
y cuántas pruebas son lo dice el propio comando; no se anota acá porque cambia
cada día.*

**`db reset` y no `db start`:** `db start` no reaplica nada si la base ya está
levantada, así que una migración nueva parece aplicar y en realidad no se probó
desde cero. `db reset` sí. Y es además la única forma de detectar una colisión de
números: es lo que destapó las dos `0158` del 2026-08-05, abortando con
`duplicate key value violates unique constraint "schema_migrations_pkey"`.

**Si las pruebas fallan todas a la vez con «relation "sedes" does not exist»**,
no es el código: el contenedor de Postgres se reinició vacío. Pasó el 2026-08-04.
Se arregla con `npx supabase db reset`, que vuelve a aplicar todas las
migraciones sobre una base limpia. La base local es un laboratorio: no guarda
nada que no se pueda reconstruir.

**Lo que sí falla es `supabase start`** (el stack completo: Auth, Storage,
Realtime). Revienta aplicando la 0001 con «type rol_usuario already exists», sin
volúmenes ni contenedores previos. Esa era la nota del 2026-08-01, y de ahí salió
la creencia —que llegó al `CLAUDE.md` y ya está corregida— de que las pruebas de
base de datos no corrían acá. Corrían: el comando estaba mal.

**La alternativa que sí funciona**, y con la que se hizo la auditoría empírica:
levantar la imagen a mano y aplicar las migraciones sobre la base `postgres` (para
que `pg_cron` de la 0007 funcione), con dos andamios previos —`storage.buckets` y
`storage.objects` creados como `supabase_admin`, y una fila en `auth.users`—.

```bash
docker run -d --name cayla_audit -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_HOST_AUTH_METHOD=trust public.ecr.aws/supabase/postgres:17.6.1.141
```

Con eso el esquema entero aplica limpio.

**Los 8 errores de tipos ya no están** (revisado el 2026-08-04): `npx pnpm
typecheck` pasa limpio en los tres paquetes. Las entradas de RPC que faltaban en
`packages/database/src/types.ts` se agregaron a mano, marcadas con comentario,
porque `supabase gen types` no corre en esta máquina («Failed to end the
connection on error»).

**Pero CI sigue sin correr typecheck.** `.github/workflows/tests.yml` tiene dos
trabajos —pgTAP y Vitest— y ninguno lo llama. Hoy el único freno es el hook local
`pre-push`, que sí lo corre: si alguien empuja con `--no-verify`, o desde otra
máquina sin `git config core.hooksPath scripts/hooks`, un error de tipos llega a
`main` sin que nada avise. Agregarlo al workflow son cuatro líneas.

**Un bug que vale recordar:** `jsonb_build_object` admite **máximo 100
argumentos**. El objeto de la boleta estaba cerca del techo y cuatro campos nuevos
lo pasaron — compilaba y fallaba al ejecutarse. Ahora está partido en dos unidos
con `||`, y el generador cuenta los argumentos y falla si alguno se acerca al tope.

---

## Nota histórica — consolidación del 2026-07-27

Lo que sigue es el estado tal como quedó esa noche, con las migraciones hasta la
0102. Se conserva porque contiene decisiones que no se reabren y aprendizajes que
no conviene volver a pagar. Lo de arriba es lo vigente.

> 🔴 **Advertencia de entonces, todavía válida como criterio:** el repositorio no
> describía fielmente la producción. `migraciones_aplicadas` decía que la 0089
> estaba aplicada y su contenido no estaba en la base. Un registro no es una
> comprobación. Las herramientas para medirlo están en
> `scripts/sql-manual/comparar_funciones.sql`.

---

## La lección de julio: un registro no es una comprobación

Se dio por hecho que las 0088 y 0089 se habían aplicado bajo sus números viejos.
La **0089 no se había aplicado**: se registró, y su contenido nunca llegó a la
base. Esa distinción sigue siendo la más cara de este proyecto, y hay dos
herramientas distintas justamente porque son dos preguntas distintas:

- **¿está anotada?** → `migraciones_aplicadas` (y la prueba `122`, en CI)
- **¿está su contenido?** → `scripts/sql-manual/comparar_funciones.sql`

*El inventario de qué cerró cada migración de julio vivía acá y salió: lo dice el
encabezado de cada archivo en `supabase/migrations/`, que no puede quedar viejo.*

### Lo que costó aprender hoy

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
- **El sello de "día por revisar" era tinta, no una pregunta.** Se ponía cuando el
  día se rompía y nada lo levantaba: cuantas más marcas del día estuvieran bien,
  más fácil era que el día se quedara pegado en la lista para siempre.
- **Numerar migraciones sin volver a mirar el directorio** produjo dos colisiones
  (0085 y 0086) en la misma sesión en que se criticó ese error. Mirar `ls` antes
  de crear el archivo, siempre — otra sesión puede haber avanzado.

---

## 🔴 Atender primero

1. **El terminal decide en dos sitios a la vez.** "Qué toca marcar ahora" vive en
   SQL (`fn_siguiente_tipo_esperado`) y en el navegador
   (`determinarSiguienteAccion`, `packages/shared`). Hoy se arregló que las dos
   ignoren las marcas anuladas, pero **arreglar una dejaba la otra rota** y nada
   avisa de la divergencia. Es el mismo problema de raíz que produjo el fallo:
   unificar, o al menos una prueba que compare las dos respuestas con los mismos
   datos y falle si difieren.

2. **Liquidación por cese + foto del pago.** Pantalla propia: sueldo pendiente +
   vacaciones truncas + grati trunca + CTS trunca, congelado e imprimible. La ley
   da 48 h desde el cese (art. 4 D.S. 001-97-TR), así que **no** se puede prohibir
   el cierre anticipado sin esto. Incluye el pago por horas del día de prueba, con
   recordatorio del T-Registro de 24 h. Al marcar PAGADO se guarda copia intacta
   de los montos y el sistema avisa si un recálculo posterior ya no coincide.
   **Dónde quedó exactamente (27-07, pedido de Felipe: recordárselo):**
   - `0085` tipo de vínculo y `0086` fecha de cese: **probadas**, en el repo, sin
     aplicar en producción.
   - `0087` truncas: **retirada de producción** con
     [`quitar_0087_truncas.sql`](../scripts/sql-manual/quitar_0087_truncas.sql)
     porque se aplicó sin pruebas y fallaba dos de seis casos.
     `fn_grati_trunca` ya está corregida y pasa **6/6**;
     **Ya probadas: 19 casos en la prueba 103**, escritos desde la norma antes
     de correr nada. Falta la pantalla.
   - La trampa que falta cazar en CTS: el sexto de la gratificación es
     `sueldo/12` en MYPE, no `sueldo/6` — usar el del régimen general paga de
     más en cada liquidación.
   - Falta la pantalla.

3. **Los 4 scripts de `sql-manual` que divergen de su migración fuente.** El peor,
   `aplicar_0017`, lleva la fórmula vieja de tardanza: pegarlo retrocede el
   cálculo de horas de todo el equipo. O se regeneran desde la migración, o se
   borran.

4. **Terminal, 4 bordes graves:** marca rechazada que se anuncia como "Listo" y
   desaparece · cola offline que se reenvía en orden de UUID y no cronológico ·
   reloj de la Mac sin verificación de desfase · persona que marca en dos sedes
   el mismo día y pierde una marca.

5. **Seguridad pendiente** (de `revision-2026-07-15/`, revisado el 2026-08-04):
   - ~~`generarClave()` usa `Math.random()`~~ → **cerrado.** Hoy usa
     `crypto.getRandomValues` con descarte de la cola incompleta, y el porqué
     está escrito en el archivo (`api/admin/cuentas/route.ts:13`).
   - Contraseña mínima 6 sin complejidad, sin cambio forzado en primer login
     (cuentas que ven salarios). **Sigue abierto.**
   - Las rutas de API devuelven el mensaje crudo de Postgres → envolver.
     **Sigue abierto:** `api/admin/cuentas/route.ts` lo devuelve tal cual en las
     líneas 113, 126 y 143, y `api/espejo/route.ts:32` lo relanza.

6. **Partir `planilla/page.tsx`.** Maneja dinero. Los tests SQL que fijan la
   matemática ya existen (`supabase/tests/10` y `20`); falta el refactor antes de
   seguir tocándolo. **Y el pendiente empeoró: eran 1 587 líneas el 27-07 y hoy
   son 2 082** — creció un 31 % mientras el refactor esperaba. Es la pantalla más
   grande del sistema por lejos; la segunda (`turnos`) tiene 1 288.

**El catálogo completo de lo que queda está en
[`hallazgos-abiertos.md`](hallazgos-abiertos.md)**: 24 hallazgos vivos de una
auditoría por áreas con verificación adversaria (52 agentes; de 42 candidatos
sobrevivieron 34, y 10 ya se cerraron). Cada uno con su evidencia y su arreglo.

**El patrón que se repite, y que conviene mirar antes que los síntomas:** la
misma regla escrita en dos sitios, y una corrección que arregla solo uno. Pasó
con «qué toca marcar» (SQL y navegador), con «qué es una falta» (pantalla y
documento) y con «quién puede leer la planilla» (un revoke y ningún guard). En
los tres casos nadie se enteró hasta que alguien miró. Cada arreglo lleva ahora
una prueba que compara las dos copias y falla si se separan.

### Lo que la foto del pago sí cierra, y lo que no

**Sí:** un periodo pagado ya no puede cambiar de total en silencio. Si algo se
mueve, `fn_planilla_foto_diferencias` lo nombra persona por persona. Y ahora hay
una cifra de costo que se puede entregar al contador y sumar por sede y por área.

**No:** los periodos que ya estaban pagados antes de la 0096 tienen la foto
*reconstruida* — es el número del día de la migración, no el del día del pago.
La pantalla de Costos lo avisa arriba. No se puede saber cuánto se desvió cada
uno; ese dato no existe en ninguna parte, y por eso la foto se construyó.

**Y una decisión pendiente que la 0096 hace visible:** cuando la foto y el
cálculo en vivo difieren, el sistema hoy solo lo *dice*. Nadie decidió todavía
qué pasa entonces — si se reabre el periodo, si se ajusta en el siguiente, o si
se deja constancia y ya. Es una decisión de negocio, no técnica.

## 🟡 Valioso pronto

- **El candado del periodo que quedó a medias.** Se acordó el 26-07: no dejar
  cerrar un periodo con días sin resolver. Ahora que la incidencia del almuerzo
  ya se puede cerrar desde la pantalla, el candado no bloquearía a nadie.
- **Blindar con pruebas lo que aún mueve dinero sin ninguna:** descanso
  sustitutorio, bono de puntualidad, provisiones, feriado triple.
- **Versionar 0031 y 0033**: existen solo como `scripts/sql-manual/aplicar_*.sql`
  (fuera de git por PII). Crear versiones con los datos personales parametrizados.
- **Grati/CTS — regla legal de regularidad**: la sobretasa de feriado entra solo
  si se percibió en ≥3 meses del semestre (promedio entre 6). Felipe pidió ver
  primero el impacto con
  [`consulta_impacto_regularidad_feriados.sql`](../scripts/sql-manual/consulta_impacto_regularidad_feriados.sql).
- **Colibrí en cargas**: ~22 pantallas y ~49 estados vacíos sin marca.
- **Integración Dynamic ↔ retail**: Fase 0 (reconciliación, solo lectura) lista
  para arrancar — `docs/integracion-retail/`.
- **Objetivos: botón "copiar del mes anterior"** — urge al arrancar agosto.
- **Espejo a Google Sheets legible** (encabezados fijos, una fila por persona).
- **Un solo lugar para "quién puede qué" y para "cuándo es hoy en Perú".** Hoy la
  regla que más importa —*una encargada de sede no ve sueldos*— está escrita a
  mano en **16 pantallas**, y la zona horaria de Lima se repite en **23
  archivos**. Nada está roto ahora, pero la protección depende de que nadie se
  olvide al agregar la pantalla 17: un descuido ahí filtra sueldos en silencio, y
  uno en la fecha carga un día de pago al día equivocado. **El trabajo ya está
  hecho y no hay que rediseñarlo**: vive en la rama `rescate-1442-04ago`
  (`packages/shared/src/permisos.ts` y `fecha-lima.ts`, más `tests/permisos.test.ts`
  y `tests/fecha-lima.test.ts`, 76 líneas cada uno, que cubren el borde de
  medianoche y que un rol `null` no pase como autorizado). **Esa rama no se
  fusiona** — es una línea paralela a la que le faltan 4.873 líneas que `main` sí
  tiene; se usa como especificación y se reaplica sobre `main`. Rescatada el
  2026-08-04 de una copia suelta del repo que estaba a punto de borrarse.

## 🟢 Dependen de Felipe / redondeo

- Datos personales: 5 fichas faltantes + celular/instrucción/estado civil (~13).
  Import SIN commitear PII.
- Validar factores de provisiones con el contador (MYPE: 8.33/4.17/4.17).
- **El rol de Catherine.** Tiene `supervisor_sede` en CCO, así que el sistema le
  da lo de una encargada de tienda —ver a la gente de CCO, firmar amonestaciones
  de CCO— y le niega lo que querría una accionista: ver las tres tiendas. Está al
  revés de su papel.
- **Cuatro personas con rol admin** (Carlos, Estefany, Felipe, Janis). Un admin ve
  todas las sedes, todos los datos personales —cuentas bancarias y DNI incluidos—
  y puede firmar despidos. Cuatro accesos totales en un equipo de 23.
- Cuenta de Estefany (falta su correo) · revisar áreas reales de cada quien ·
  checkbox "encargada de piso" en Equipo · split mañana/tarde por sede.

---

## Decisiones tomadas (no reabrir)

- **Planilla**: régimen MYPE pequeña empresa, base 6.5 h, pago = salario × horas/(6.5 × días).
- **La CTS incluye el sexto de la gratificación** — encendido en producción el
  2026-08-05. La base pasa de sueldo pelado a sueldo × 13/12 (Art. 16 del
  D.S. 001-97-TR; en pequeña empresa la grati es media remuneración, así que el
  sexto vale sueldo/12). Sobre S/1,130 la CTS del año sube de 565.00 a 612.08.
  **Ninguna autoridad zanjó este punto para el régimen MYPE**: es derivación del
  TUO de la Ley de CTS y del documento del MTPE. Se eligió la lectura prudente
  —provisionar de más no es infracción, de menos sí—. Se apaga con una línea, y
  la prueba `126` blinda que el sexto no se cuele en la gratificación ni en las
  vacaciones. **Falta contárselo al contador antes del depósito de mayo**: si él
  calcula sobre el sueldo pelado, la discrepancia aparece el día del depósito.
- **El terminal marca sin PIN**, a propósito. No se puede usar una marca como
  prueba individual en un procedimiento disciplinario sin otro respaldo.
- **Fecha de ingreso = decisión de negocio, no cálculo.** Se edita persona por
  persona en Equipo; el botón masivo se eliminó (0041).
- **Disciplina**: Dynamic avisa y documenta, nunca sanciona solo (D.S. 003-97-TR
  art. 25: umbrales 4 consecutivas / 6 en 30 d / 16 en 180 d).
- **Una marca se anula, nunca se borra** (0081). El botón "Eliminar" no vuelve:
  para el cálculo y para el pago anular hace lo mismo, pero deja quién la quitó y
  por qué, y se puede deshacer.
- **Cuando falta el retorno del almuerzo, el sistema no inventa una hora.** Avisa
  y decide una persona: registrando las marcas reales, o dando el visto bueno si
  de verdad trabajó de corrido. Las tres realidades posibles (se fue, volvió sin
  marcar, no tomó refrigerio) son indistinguibles para el sistema.
- **Corregir el tipo de una marca puede dejar el día roto a mitad de camino, y no
  se bloquea**: ese estado intermedio es el primer paso del flujo de arreglo. Se
  sella para revisión y el sello se levanta solo cuando el día cuadra.
- **Meta operativas TRU = 8** · **Melany y Catherine como encargadas** · **Janis
  admin + encargada de piso** · **Keyla/Raquel/Felipe: ingresos quedan 2026**.

## Registro de lo cerrado (para no re-investigar)

Deshacer pago de planilla ✅ (0066 + test 30) · faltas Fase 2 completa ✅
(0051–0060) · cobertura en vivo ✅ · bono de puntualidad ✅ (0034) · menú móvil ✅
· recuperar clave ✅ · boleta individual ✅ · patrón de tardanzas ✅ · descanso
sustitutorio con actas ✅ (0069–0073) · ejecución anónima cerrada ✅ (0076) ·
firma escaneada fuera de `personas` ✅ (0076) · anular/corregir tipo/confirmar
✅ (0081–0084, 0089) · gratificación en periodos que cruzan el año ✅ (0088) ·
pruebas de `fn_recalcular_jornada` ✅ (60 aserciones, tests 80–89).
