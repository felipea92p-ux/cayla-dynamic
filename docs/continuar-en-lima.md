# Traspaso — dónde se quedó todo el 27-07-2026

Escrito para retomar sin la conversación en la que se hizo. Si vas a seguir tú
sola, o con otra sesión, esto es lo único que hace falta leer. El estado general
del proyecto sigue en [`estado.md`](estado.md); esto es **lo de este día y lo que
queda a medias**.

---

## 1 · Lo primero que hay que saber

**El repositorio no describía tu producción, y durante meses nadie lo supo.**

El registro `migraciones_aplicadas` decía que la 0089 estaba aplicada y su
contenido no estaba en la base. Un hueco en el registro se ve —así apareció que
faltaba la 0083—; una migración registrada que nunca corrió, no.

Se midió comparando la huella del texto de las 155 funciones de producción
contra una base construida desde cero con todas las migraciones en orden. Salieron
**24 diferencias**, que no eran una sola cosa:

| Qué eran | Cuántas | Estado hoy |
|---|---|---|
| Producción atrasada, tocan dinero o asistencia | 5 | ✅ **arreglado** (migración 0102) |
| Producción atrasada, no urgentes | 7 | 🔸 pendiente de revisar |
| Solo texto corrompido en mensajes de error | 4 | 🔸 cosmético |
| Producción **adelantada** — tiene mejoras que el repo no conoce | 4 | 🔴 **rescatado, sin reconciliar** |
| Legado que ya nadie llama | 1 | 🔸 `fn_proyeccion_planilla` |
| El repositorio tiene más código que producción | 2 | 🔸 `fn_crear_periodo`, `fn_eliminar_periodo` |
| Sobrecargas viejas que conviven con las nuevas | 1 | 🔸 `fn_agregar_movimiento` |

**Las herramientas para volver a medirlo, cuando quieras:**

- [`scripts/sql-manual/comparar_funciones.sql`](../scripts/sql-manual/comparar_funciones.sql)
  — dice qué funciones difieren. Solo lee.
- [`scripts/sql-manual/huellas_produccion.sql`](../scripts/sql-manual/huellas_produccion.sql)
  — da la huella de cada una, para saber si está atrasada o adelantada.

**Al 27-07 por la noche el comparador devuelve 19 filas.** Ninguna es un fallo
conocido: son las categorías 🔸 y 🔴 de arriba. Si algún día devuelve algo que no
esté en esa lista, algo se aplicó a mano y hay que investigarlo.

> ⚠️ El comparador cubre **funciones**. No cubre tablas, columnas, índices,
> constraints, triggers ni políticas de seguridad. Extenderlo es el mismo método
> y es lo que convierte «creo que el repo describe mi producción» en «lo sé».
> **Es lo más importante que queda pendiente.**

---

## 2 · La decisión que hay que tomar antes de tocar nada más

**`fn_resellar_dia` y `fn_levantar_sello_si_el_dia_cuadra` hacen lo mismo.**

Dos implementaciones de la misma regla —«levanta el sello de revisión cuando el
día vuelve a cuadrar»— con nombres distintos, y cada una cableada a una familia
distinta de funciones:

```
fn_resellar_dia                     ← fn_agregar_marcaje, fn_corregir_marcaje,
   (solo en producción)               fn_eliminar_marcaje
fn_levantar_sello_si_el_dia_cuadra  ← fn_corregir_marca, fn_anular_marcaje,
   (migración 0084, en ambas)         fn_reactivar_marcaje
```

Arreglar una deja la otra rota y nada avisa. Es el **cuarto caso del mismo patrón
en dos días** (ver `estado.md`, sección del patrón que se repite).

El código de producción está rescatado literalmente en
[`rescatado-de-produccion.sql`](rescatado-de-produccion.sql) — **ese archivo no se
pega en ningún sitio**, es una copia para no perderlo.

Y ahí hay algo que el repositorio no tiene y que sí hace falta: en
`fn_agregar_marcaje`, **la sede de una corrección la manda el día, no el
escritorio**. Si la persona ya marcó ese día en otra tienda, la corrección se
graba en esa misma sede. Sin eso, la jornada queda partida entre dos sedes.

---

## 3 · Lo que se construyó el 27-07

Todo aplicado en producción y publicado, salvo lo que se indique.

| # | Qué |
|---|---|
| 0096 | **La foto del pago.** Al marcar pagado se congela el desglose de cada persona. No se edita ni se borra |
| 0097 | **Costos.** Pantalla nueva que suma lo pagado, separando lo transferido de lo que le cuesta a CAYLA |
| 0098 | **Volver a pagar sin abrir la puerta.** Recalcula un periodo pagado sin que pase por «abierto» |
| 0099 | **Tipo de sede** (central/taller/tienda) y costos comparables por persona y por hora |
| 0100 | **Un cero no explica nada.** La planilla dice por qué alguien está en S/0 |
| 0101 | **Ausencias.** Absorbe Vacaciones y `justificaciones_asistencia`. Nueve tipos |
| 0102 | **Poner al día lo que el registro decía que ya estaba.** Las cinco funciones atrasadas |
| 0085–0087 | Tipo de vínculo · fecha de cese · truncos al cesar *(se aplicaron hoy, llevaban días escritas)* |

**Pantallas nuevas o cambiadas:** Costos · Ausencias (absorbe Vacaciones) ·
Planilla (filtros, aviso de pendiente de pago, «ya le pagué aparte», razón del
cero) · Equipo (buscador y tres filtros) · Sedes (tipo).

**Pruebas:** 253 aserciones en 28 suites. Las nuevas del día: 97 (foto del pago),
98 (costos), 99 (repago), 100 (tipo de sede), 101 (razón del cero), 102
(ausencias), 103 (truncos).

---

## 4 · Lo que quedó a medias

### 🔴 Nunca se ha cerrado un periodo de planilla

`periodos_pagados = 0`. **Costos está vacío porque no ha entrado nada**, no
porque falle. Todo lo del punto 3 depende de que se cierre el primero.

Antes de marcar PAGADO, revisar en Planilla:
1. **Días pendientes** — horas que inventó el auto-cierre. Se resuelven en Correcciones.
2. **Filas en rojo** — alguien con horas y sin salario asignado: se congela cobrando cero.
3. **Bono de puntualidad** — si va, calcularlo *antes*.

### 🔴 La liquidación por cese no tiene pantalla

Las tres funciones existen y **ahora sí están probadas** (19 casos, prueba 103):
`fn_grati_trunca`, `fn_cts_trunca`, `fn_vacaciones_truncas`. Falta la pantalla
que las use y congele el resultado.

La ley da **48 horas desde el cese** para pagar (art. 4 D.S. 001-97-TR). Hasta
que exista la pantalla, ese cálculo se hace a mano con el plazo corriendo.

> Antes de pagar la primera liquidación real, enseñarle una salida de esas
> funciones al contador. Las pruebas verifican que hacen lo que la ley dice; no
> verifican que la ley leída sea la vigente.

### 🔴 Al dar de baja no se pide fecha de cese ni motivo

Decidido el 27-07 y **sin construir**: al desactivar a alguien, proponer la fecha
del último día marcado (el sistema ya la sabe) para que solo haya que confirmar,
y pedir el motivo. Sin esa fecha no hay liquidación posible.

### 🟡 Ausencias: lo que falta

- **Registrar la ausencia no rebaja el pago todavía.** Un permiso sin goce hoy no
  cobra por una razón indirecta —no marcó, no hay horas— no porque el sistema
  sepa que es permiso. El día que haga falta pagar un descanso médico aprobado,
  **la planilla no lo va a pagar**: nadie le enseñó a pagar días sin horas.
- El botón que genera la carta de preaviso **no mira si esas faltas se
  justificaron después**. El conteo sí las excluye (probado), pero un borrador ya
  impreso sigue diciendo lo que decía. Nada avisa de que quedó desactualizado.

### 🟡 Decisiones de negocio pendientes

- **Cuando la foto del pago y el cálculo en vivo difieren**, el sistema solo lo
  dice. Ya existe el botón «Recalcular y volver a pagar»; falta decidir cuándo se
  usa y cuándo se ajusta en el siguiente periodo.
- **El contador y el descanso médico.** Se acordó que el tipo decide si paga:
  médico y maternidad pagan porque lo manda la ley; el resto no, porque en CAYLA
  no existe el permiso con goce. Conviene confirmarlo con él.
- **Costos no sabe cuánto vende cada tienda.** El número que decide —«¿esta
  tienda se paga sola?»— es costo contra ventas, y las ventas están en retail,
  que no está conectado. La función ya devuelve el dato en formato estable para
  cuando exista el puente.

---

## 5 · Cómo retomar

```bash
cd ~/Developer/cayla-dynamic
git pull
npx pnpm install
npx pnpm typecheck && npx pnpm test
```

Para publicar, nunca `npx vercel` directo:

```bash
./scripts/desplegar.sh prod
```

**Lo primero que conviene hacer al volver:** correr el comparador y confirmar que
sigue devolviendo esas 19 filas y ninguna más. Si aparece algo nuevo, alguien
tocó producción a mano mientras tanto.

---

## 6 · Las tres cosas que este día enseñó

Están aquí porque son método, no anécdota, y evitan repetir lo caro.

**Una verificación que no puede fallar no es una verificación.** *Success. No
rows returned* solo dice que Postgres no se atragantó con el texto. Ese mismo día
una instrucción de permisos se aceptó sin error y no hizo absolutamente nada.
Si no puedes escribir la consulta que demuestra que funcionó, no sabes qué pediste.

**Escribe el resultado esperado ANTES de correr nada.** En las pruebas de los
truncos, una expectativa falló y la función tenía razón: se esperaban S/1 300 de
CTS dando por hecho que el periodo era anual, y es semestral. Ese momento solo
existe si la expectativa se escribió primero. Leer el código y anotar lo que
devuelve produce una prueba que certifica que la función hace lo que hace.

**Copiar una versión correcta pero antigua es la forma más fácil de romper algo.**
Pasó dos veces el mismo día: la migración 0100 se escribió copiando el cuerpo de
`fn_planilla_calcular` de una versión anterior al arreglo de seguridad de la 0090,
y el guard desapareció sin que fallara nada salvo una prueba. Y estuvo a punto de
recomendarse pegar la 0083, que habría devuelto cuatro funciones a su versión
vieja. **Cuando hay muchos lectores de un dato, se mueve el dato debajo de ellos
en vez de reescribirlos** — es lo que hizo la 0101 convirtiendo dos tablas en
vistas, y por eso nueve funciones no se enteraron.
