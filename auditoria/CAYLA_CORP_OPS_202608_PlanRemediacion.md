# Plan de remediación — auditoría de agosto 2026

**Regla de esta guía: un lote por vez.** Aquí está el mapa completo para que se vea a dónde va la
cosa, pero **solo el lote en curso se entrega con sus comandos**. El siguiente llega cuando el
anterior cierre con evidencia.

**Un lote es un tema, no un archivo.** «Tapar las fugas de lectura» es un lote; «arreglar 12
archivos sueltos» no lo es.

**Reglas que no se negocian**, y son las del repositorio:

- Las migraciones **se proponen aquí y las pega Felipe a mano** en el SQL Editor.
- El número se pide con `./scripts/siguiente-numero.sh`, nunca se cuenta a ojo.
- El cuerpo de una función se copia de la que diga `./scripts/donde-vive.sh`, **preguntado el
  mismo día**: entre el 17 y el 18 de agosto entraron cinco migraciones y la vigente cambió.
- El SQL se entrega con `./scripts/dame-el-sql.sh <n>`, que exige que esté en GitHub byte por byte.
- **Refactor y cambio nunca en el mismo commit.**
- Nada de `git commit --amend` en este árbol.
- **Y la que se ganó a pulso el 2026-08-18: se commitea ANTES de pasar a lo siguiente.** Ese día se
  perdieron los tres informes de esta auditoría y una migración ya auditada por dejarlos sin
  guardar mientras otra sesión movía el árbol.

---

## El mapa de lotes, en orden

| # | Lote | Estado | Por qué va aquí |
|---|---|---|---|
| **0** | Medir en producción | 🟡 **1 de 4 hecho** | Solo lectura, cero riesgo. Sin esto todos los alcances del informe son cero. |
| **1** | El descanso médico exige aprobación | 🔵 **en curso** | Único hallazgo con fecha: afecta la planilla que cierra el 28. |
| **2** | Decisión sobre los datos publicados en GitHub | ⬜ | Es P0 y **no es una tarea de código**: es una decisión sobre el historial. |
| **3** | Cerrar las tres fugas de lectura | ✅ **3 de 3 — CERRADO** | Terminal ✅ (0291) · `SECURITY DEFINER` ✅ (0292) · ascenso a Admin ✅ (0295/0296, pegadas el 2026-08-25). Las tres en producción, verificadas por md5. |
| **4** | Las tardanzas dejan de contar feriados y vacaciones | ⬜ | Más grande y necesita pgTAP nuevo. |
| **5** | Terminar la 0240 (el cruce de medianoche) | ⬜ | Cuatro hallazgos de un mismo origen: `fecha_jornada` existe y cinco funciones no la conocen. |
| **6** | El guardián de las reglas del `CLAUDE.md` | 🟡 **La parte literal, hecha; la aspiración, no** | Lo que el informe pide con nombre y forma —el `grep` de veinte líneas para `rol ===` y `America/Lima`— ya existe: `scripts/hooks/reglas-de-la-casa.sh`, de agosto, activo en el pre-push. Esta fila no se había actualizado. Quedan los dos ejemplos que el informe cita como «memoria, no guardián» y que SÍ siguen sin guardián: la triplicación de «qué le tocaba trabajar ese día» (probada y descartada por ruido — 28 aciertos, casi todos legítimos) y los 84 colores sobre 9 tokens (sección de diseño, sin explorar). Ninguno de los dos es un grep de veinte líneas. |
| **7** | Encender el linter y subir Next a 16.2.11 | ⬜ | 119 errores viejos + parche de seguridad. |
| **8** | Unificar «qué le tocaba trabajar ese día» | ⬜ | Refactor puro: cuatro copias a una. |

Los 29 P2 y 39 P3 restantes no tienen lote propio: se recogen dentro del lote que ya toca su
archivo.

---

# LOTE 0 — Medir en producción · **1 de 4**

## ✅ Detector 1 · Descanso médico pagado sin aprobación — CORRIDO el 2026-08-18

**Resultado: nadie afectado.** Dos filas, las dos de descanso médico de Paola Cahuana (6 y 7 de
julio), registradas por Felipe. Aunque el periodo está pagado, la foto del pago devolvió
`la_foto_conoce_el_concepto = false` en sus tres versiones (congeladas el 28/07, 31/07 y 01/08):
julio se calculó **antes** de que existiera el pago por descanso médico, que entró con la 0254 el
14 de agosto.

**Conclusión: cero soles mal pagados.** El hallazgo baja de «ya ocurrió» a «puerta abierta por la
que no entró nadie», y el LOTE 1 pasa de urgente a preventivo.

## ⬜ Faltan tres

Están en la §7 del informe, cada uno en su desplegable, listos para pegar:

1. **Tardanzas contadas sobre días excluidos** — dice cuántos memos salieron con tardanzas falsas.
   Es el más importante de los tres: es un P0 y ya ocurrió.
2. **Régimen de pensión cambiado por la puerta sin candado** — dice si tocó un periodo pagado.
3. **Marcas de madrugada perdidas o rechazadas** — dice el tamaño real del LOTE 5.

Una tabla vacía es un resultado bueno **y es información**: significa que el defecto, aunque el
código lo permita, no llegó a ejecutarse sobre nadie.

---

# LOTE 1 — El descanso médico exige aprobación · **en curso**

## Qué se descubrió al diagnosticarlo

El sistema **ya tiene la regla**, y está bien pensada:

- `fn_registrar_ausencia` deja registrar a admin, líder DO **y a la encargada de la sede**.
- `fn_aprobar_ausencia` solo deja aprobar a admin o líder DO, y explica por qué, textual: *«La
  aprobación es de DO, no de la sede: es lo único que convierte días en plata, y por eso no la
  puede dar quien la registró desde la tienda.»*
- La pantalla de Ausencias tiene su botón, y avisa: *«Es un tipo que SE PAGA: al aprobarlo, esos
  días entran en su planilla.»*

**Las tres piezas existen y son correctas. La que no las escuchaba era `fn_planilla_calcular`.**
Sus laterales filtraban `anulada_at` y nunca `aprobada_at`. O sea que la frase del comentario era
falsa: lo que convertía días en plata no era aprobarlos, era registrarlos.

## Por qué el arreglo toca tres líneas y no dos

Dentro del bloque de feriados hay un `not exists` que quita el feriado caído dentro de una licencia
de maternidad, porque el lateral `mat` ya lo paga por días calendario. Si `mat` deja de pagar por
falta de firma y ese `not exists` sigue excluyendo, **ese día no lo paga nadie**.

Medido: con solo dos líneas, la persona pierde **S/22.17**. Con las tres, el feriado vuelve a
pagarse por su propia línea. La 0262 ya dejó escrito que ese fue su primer intento, medido y
descartado.

## Evidencia de la auditoría empírica (2026-08-17, `BEGIN … ROLLBACK`)

| Caso | antes | después | |
|---|---|---|---|
| Descanso médico **sin firma** | 1 824.58 | **1 526.81** | deja de pagarse ✓ |
| Descanso médico **firmado** | 1 824.58 | **1 824.58** | no se movió un céntimo ✓ |
| Maternidad **sin firma** | 1 577.25 | **699.42** | subsidio fuera ✓ y el feriado sube de 81.72 a 103.89 ✓ |
| Maternidad **firmada** | 1 577.25 | **1 577.25** | intacta ✓ |

## Estado y qué falta

La migración se escribió como **0268** el 17 de agosto, se auditó y su prueba pasaba. **Se perdió
al día siguiente** junto con estos informes, y además quedó obsoleta: partía de la 0263 y la
vigente pasó a ser la **0269**. Pegarla hoy habría revertido la 0269 en silencio.

Rehacer, en este orden:

1. Volver a preguntar `./scripts/donde-vive.sh fn_planilla_calcular` y `./scripts/siguiente-numero.sh`.
2. Pedir a **producción** el md5 de partida, antes de tocar nada.
3. Rehacer el injerto de las tres líneas sobre el cuerpo vigente.
4. Re-auditar con los cuatro casos de la tabla de arriba.
5. Reescribir la prueba pgTAP (6 comprobaciones) y actualizar los fixtures de las pruebas 195, 199
   y 200, que crean ausencias sin aprobar y por eso medirían cero.
6. **Commitear y subir ANTES de entregar el SQL.**

## La segunda pieza, que no es una migración

Un aviso antes de cerrar el periodo que liste las ausencias remuneradas sin aprobar. Sin él, esta
migración convierte un olvido de DO en un no-pago: si alguien presenta un descanso médico el 20 y
nadie lo aprueba antes del 28, esa persona no cobra esos días. Va en la pantalla de Planilla y se
despliega por Vercel.

Medido el 2026-08-18: hoy **no hay ni una** ausencia remunerada sin aprobar en el periodo abierto,
así que el orden entre las dos piezas no deja a nadie sin cobrar.

## Un hueco vecino, encontrado de paso

`licencia_con_goce` está marcada en el catálogo como que **paga** y **requiere aprobación**, pero
`fn_planilla_calcular` no la paga por ningún lado: solo menciona `descanso_medico` y `maternidad`.
Es el error contrario al de este lote —alguien deja de cobrar lo que le toca— y no se investigó.
Queda anotado, sin lote asignado.

---

# Hallazgos nuevos del 2026-08-18, encontrados al medir

Los tres salieron de verificar el md5 antes de escribir una migración. Ninguno estaba en el
informe: la auditoría no los buscó.

## A · La mitad de las funciones de producción no tienen comentarios · P2

Medido en el SQL Editor: **119 de 243 funciones `fn_` (49 %)** no tienen ni una línea de
comentario en producción. El caso que lo destapó fue `fn_tardanzas_resumen`, cuyo md5 de
producción (`49b3cf99…`) no coincidía con el del repositorio (`16f4991a…`).

**No es la 0177 ni son los acentos rotos.** Se comprobó quitándole al cuerpo local todos los
comentarios —líneas enteras y los de final de línea—: el resultado es **1818 caracteres y md5
`49b3cf99111e44a62bbb8b59dde44f3e`**, idéntico a producción al byte. Mismo código, sin una línea
distinta.

Dos consecuencias, y la primera es de método:

1. **Rompe el mecanismo de verificación del propio `CLAUDE.md`.** «Pide el md5 a producción y
   compáralo» no puede funcionar para la mitad de las funciones. Y lo peor no es que no sirva: es
   que el día que de verdad haya una versión distinta, el síntoma será idéntico a este y se va a
   descartar como «serán los comentarios».
2. **La documentación del negocio no está donde se lee.** Este repositorio escribe migraciones que
   se leen como explicación del porqué; en producción la mitad de eso no existe.

**Lo que se propone NO es repegar 119 funciones.** Es arreglar el método: que `donde-vive.sh`
compare el md5 **ignorando comentarios**, y entonces vuelva a servir para las 243. Cuesta unas
líneas en un script y no toca producción.

## B · Cuatro sobrecargas huérfanas, todas alcanzables desde el navegador · P2

| Función | Vieja | Nueva | Qué se salta quien llame a la vieja |
|---|---|---|---|
| `fn_agregar_movimiento` | 5 args | 6 (`p_categoria`) | la categoría del movimiento. **Deliberada**: la 0044 dice que se agregó como sobrecarga a propósito |
| `fn_educacion_cerrar` | 2 args | 3 (`p_motivo`) | el motivo del cierre — el rastro de por qué se cerró |
| `fn_set_datos_personales` | 18 args | 19 (`p_cuspp`) | el CUSPP. **Y es un upsert que reemplaza**, así que llamarla lo borraría |
| `fn_set_meta_cobertura` | 3 args | 4 (mañana/tarde) | la distinción de turno en la meta |

**Nadie las llama.** Medido: cinco llamadas en todo el código y las cinco van a la firma nueva.
El riesgo no es accidental — requiere invocar la RPC vieja a propósito.

Y el repositorio ya conoce el patrón y lo maneja caso por caso: la 0044 la creó a propósito, la
**0204 decidió expresamente no soltar** la de 18 argumentos de `fn_set_datos_personales`, y la
0205 sí soltó la suya *«para no dejar dos sobrecargas conviviendo»*.

Queda como P2 y sin urgencia. Si se cierra, la de `fn_set_datos_personales` es la que más
mordería, y la de `fn_agregar_movimiento` no se toca: es deliberada.

## C · La tardanza falsa no está contando hoy · cierra un P0 del informe

El detector de tardanzas se corrió el 2026-08-18. **Cero filas en la capa B: ningún memo
disciplinario salió con tardanzas falsas.** Dos jornadas mal contadas, las dos por el mismo
motivo —feriado trabajado sin turno explícito—:

- **Rufina Salvatierra**, 06/08, 2 minutos. Ya cesó: no le afecta a nada.
- **Janis Revilla**, 28/07 (Fiestas Patrias), 53 minutos. Vino a trabajar un feriado y entró 53
  minutos después de su hora habitual, cuando en un feriado no hay hora que cumplir.

**Y hoy no le cuenta a nadie**: `fn_tardanzas_resumen` mira el mes en curso, y la de Janis es del
mes pasado — comprobado, no aparece en el resumen. El arreglo sigue haciendo falta, pero el P0 del
informe baja: no hay papel emitido ni escalón movido.


---

# ✅ CERRADO el 2026-08-25 — la 0277 ya está en `main`

**Lo que fue.** El aviso de huecos del hook al empujar la 0285 destapó que la 0277
(`cambiar_el_regimen_de_pension_vuelve_a_mover_el_descuento`) estaba **aplicada en producción
desde el 2026-08-23 y no estaba en `main`**: vivía solo en la rama
`claude/workday-erp-analysis-8c12da`. Es el patrón de la 0177, atenuado porque el archivo sí
estaba en git.

**El peligro, que era concreto:** `donde-vive.sh` mira los archivos del repositorio, así que
señalaba como vigente una versión anterior a la 0277 para `fn_cambiar_regimen_pension`,
`fn_set_regimen_pension` y `fn_regimen_pension_divergentes`. Quien reescribiera cualquiera de las
tres copiando de `main` **habría revertido la 0277 en producción, en silencio**.

**Cómo se cerró.** Fusionando la rama. Y se verificó entero, no de palabra:

| comprobación | resultado |
|---|---|
| 0277 y 0284 en `main` | ✅ |
| Huecos de numeración | ✅ ninguno — «numeración sin novedad» |
| `donde-vive.sh` señala la 0277 como vigente | ✅ |
| **md5 de producción contra el de `main`** | ✅ **`ed01ed0f903bf13800d3cf282919abe8`, idéntico** — y con los comentarios incluidos, así que se pegó entera |

**Lo que este caso deja escrito.** Nadie tuvo que arreglar código: bastó con que el hook avisara,
que alguien lo midiera y que se escribiera qué significaba. Pero el aviso **no distingue** tres
situaciones que no se parecen en nada —un número saltado, uno tomado por otra sesión que aún no
fusiona, y una migración que corre en producción sin estar en `main`—. Hoy las tres salen del
mismo gris. La tercera merece rojo, y se puede distinguir sola cruzando el hueco con
`migraciones_aplicadas`, que es lo que `que_falta_pegar.sql` ya consulta. **Queda propuesto, sin
hacer.**

---

# Las ausencias que el reglamento manda pagar y la planilla no paga · 2026-08-25

**Sin ningún caso real hoy.** Se revisó a fondo y no hay nada que corregir; queda anotado para
que quien lo encuentre no repita el camino.

## El hecho

El artículo **23.4** del Reglamento Interno —«Tiempo que se computa aunque no exista marcación»—
manda computar como tiempo laborado, además de las horas registradas:

| lo que manda computar | ¿el sistema lo hace? |
|---|---|
| a) descanso semanal y feriados | ✅ |
| b) descanso vacacional | ✅ desde la 0177 |
| c) **licencias y permisos con goce de los artículos 22, 31 y 33** | ⚠️ **solo descanso médico y maternidad** |

`fn_planilla_calcular` menciona exactamente dos tipos: `descanso_medico` y `maternidad`. El tipo
`licencia_con_goce`, marcado en el catálogo como que PAGA y activo en el desplegable, **no aparece
en el cálculo ni una vez**. La pantalla avisa al aprobarlo que «esos días entran en su planilla»,
y no entran.

## Y el tipo `duelo`, que es más fino de lo que parece

Está marcado como que **no paga**, y eso es correcto para el caso común. El artículo 31.4.a solo
obliga cuando el fallecido es **cónyuge o conviviente, padres, hijos o hermanos** (Ley 31602:
5 días calendario, no compensables). Para cualquier otro familiar no hay obligación legal.

**El sistema no puede distinguir los dos casos**: `duelo` es siempre no pagado. Así que el día que
fallezca un familiar directo y se registre `duelo`, tampoco se pagará — y ahí sí la ley obliga.

## Lo medido en producción el 2026-08-25

Tres ausencias de tipos no pagados, **ninguna es un incumplimiento**:

- **Carmen Sanándres** · duelo, 24-25/08 · el fallecido **no era familiar directo**, así que la ley
  no obliga y el no-pago es correcto. Confirmado por Felipe.
- **Sandra Ramírez** · estudios, 25-26/08 · el reglamento no lista los estudios entre las licencias
  con goce del art. 31.4. Correcto.
- **Chiara Flores** · salud, 04-09/08 · **COMPROBADO el 2026-08-25: quedó bien.** Se dudó porque
  seis días parecían muchos y, con certificado médico, habría correspondido `descanso_medico`, que
  sí paga los primeros veinte. Medido: **sin documento profesional, sin colegiatura, sin archivo
  subido** — así que `salud` es el tipo correcto, el que no paga pero tampoco cuenta como falta.
  Y el cálculo afinó más de lo que la duda suponía: de los **seis días de calendario, solo cuatro
  eran laborables suyos**. El domingo 9 y el feriado del 6 no se le descontaron. Tampoco fichó
  ninguno de esos días, así que la ausencia fue real.

Y de `licencia_con_goce`: **cero registros en toda la historia**.

## Qué haría falta, si alguna vez se decide

Dos piezas, y ninguna urge:

1. Que `licencia_con_goce` se pague, con el mismo mecanismo que ya usan las vacaciones (0177) y el
   descanso médico (0254): el promedio de lo pagado por día trabajado en el periodo.
2. Distinguir el duelo por familiar directo del resto. Puede ser un tipo nuevo, o un campo en la
   ausencia; es una decisión de negocio antes que de código.

**Anotado y sin hacer.** Nadie está perdiendo dinero hoy.

---

# Producción al día · 2026-08-26

Las tres que faltaban se pegaron y se verificaron una por una contra el md5 que cada migración
declara. No es una impresión: es la cadena completa medida.

| paso | md5 de `fn_provisiones` | quién lo confirmó |
|---|---|---|
| tras la 0302 | `866c0a1664afde204ae6d685760afb84` · 36 518 car. | producción, antes de pegar la 0308 |
| tras la **0308** | `adb0a986b32d26920fb9488a314b4d45` · 38 053 car. | producción al aplicarla — **y es el md5 de partida que la 0310 declaraba** |
| tras la **0310** | `b40ded0faad67ac72625369d22699562` · 39 308 car. | producción, la migración y el Postgres local: **los tres iguales** |

La **0309** la aplicó otra sesión el mismo día. Con eso se cierra el asunto de su intento fallido
del 26, cuando murió a media ejecución por una tabla temporal que el SQL Editor no mantiene entre
sentencias: la versión que entró ya comprueba **antes** de tocar un solo dato.

**Estado al cerrar:**

```
145 de 145 migraciones aplicadas · 0 pendientes
fn_planilla_calcular  → 0306, al día con el repositorio
fn_provisiones        → 0310, al día con el repositorio
Acentos rotos         → ninguno
Frontend              → desplegado
```

Y una comprobación que conviene imitar: la 0310 devolvió además
`la_0308_sigue_en_su_sitio: 14259` — la posición del marcador «CAMBIO 0308» dentro del cuerpo. En
una cadena de dos migraciones sobre la misma función, eso es lo que distingue «se apiló encima» de
«la reescribió y borró la anterior». Sale gratis y responde la única pregunta que importa.
