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
| **3** | Cerrar las tres fugas de lectura | 🟡 **1 de 3 hecho** | Terminal ✅ (0291, pegada en producción el 2026-08-25) · `SECURITY DEFINER` ⬜ · ascenso a Admin ⬜. Policies y guards; no tocan ningún cálculo. |
| **4** | Las tardanzas dejan de contar feriados y vacaciones | ⬜ | Más grande y necesita pgTAP nuevo. |
| **5** | Terminar la 0240 (el cruce de medianoche) | ⬜ | Cuatro hallazgos de un mismo origen: `fecha_jornada` existe y cinco funciones no la conocen. |
| **6** | El guardián de las reglas del `CLAUDE.md` | ⬜ | **El de mayor retorno.** Veinte líneas que impiden que todo lo demás vuelva. |
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

# Lo del 2026-08-24: una migración corre en producción y no está en `main`

Salió del aviso de huecos del hook al empujar la 0285, y **es el patrón de la 0177**, con un
atenuante y un peligro.

## El hecho

**La 0277 (`cambiar_el_regimen_de_pension_vuelve_a_mover_el_descuento`) está aplicada en
producción desde el 2026-08-23 y NO está en `main`.** Vive solo en la rama
`claude/workday-erp-analysis-8c12da`, commiteada el 22 de agosto y subida a GitHub.

La 0284 de esa misma rama **no** está aplicada. Ese hueco es benigno.

## El atenuante

**El archivo sí está en git y en GitHub.** No se puede perder, que es lo que hacía grave a la
0177. Se recupera con `git show 55042af:supabase/migrations/0277_*.sql`.

## El peligro, que es concreto

`main` no describe lo que corre en producción. Y de ahí salen tres cosas:

1. **`donde-vive.sh` miente** sobre `fn_cambiar_regimen_pension`, `fn_set_regimen_pension` y
   `fn_regimen_pension_divergentes`: mira los archivos del repo, así que señalaría como vigente
   una versión anterior a la 0277.
2. **Quien escriba una migración sobre esas tres copiando de `main` revertiría la 0277 en
   producción**, en silencio. Es exactamente el accidente que `donde-vive.sh` existe para evitar,
   llegando por un camino que el script no ve.
3. **El CI no prueba lo que corre.** Reconstruye el esquema desde `main`, así que para esas tres
   funciones las pgTAP verifican otra cosa.

**Medido: nadie la ha revertido todavía.** Las migraciones que entraron después en `main` —0278 a
0285— no tocan ninguna de esas tres. El cruce no ha ocurrido.

## Y una buena noticia: cierra un P1 del informe

La 0277 **es** el arreglo del hallazgo «el régimen de pensión se cambia por la única puerta sin
candado». Su cabecera describe el mismo defecto con las mismas palabras: `fn_set_regimen_pension`
hacía un `update` y nada más, y `fn_cambiar_regimen_pension` —la que sí escribe el tramo— no la
llamaba nadie. **Ya está resuelto en producción desde el 23 de agosto.**

## Qué lo cierra

Fusionar esa rama a `main`. Medido: **se fusionaría limpio, cero conflictos**, y trae 8 commits.

## Lo que este caso destapa del freno

El hook avisa del hueco, pero **no distingue tres situaciones que no se parecen en nada**:

- un número saltado al numerar (inofensivo),
- un número tomado por otra sesión que aún no fusiona (se resuelve solo),
- **una migración que corre en producción y no está en `main`** (esto).

Hoy las tres dan el mismo aviso gris. La tercera merece otro tono, y se puede distinguir sola:
el hook ya sabe buscar en todas las ramas, y lo único que le falta es cruzar el hueco con lo que
`migraciones_aplicadas` dice en producción — que es justo lo que `que_falta_pegar.sql` ya
consulta.
