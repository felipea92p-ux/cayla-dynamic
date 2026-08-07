# Guía de pegado

**Sin números en el nombre a propósito.** La primera versión de este archivo se
llamaba `GUIA_pegado_0162_a_0167.md` y quedó desfasada en dos horas, cuando
aparecieron la 0163, la 0164 y la 0168. Es la misma lección que `docs/estado.md`:
un nombre que promete un rango tiene que reescribirse cada vez que el rango
crece, y el día que nadie lo reescriba el archivo miente desde su propio título.

---

## Qué hay esperando

**Dos mueven plata: la 0163 y la 0166.** Las demás cambian lo que una pantalla
muestra, lo que el sistema puede guardar, o solo el registro.

En el orden en que conviene pegarlas:

| Paso | # | Mueve plata | Qué es |
|---|---|---|---|
| 1 | **0162** | no | El tablero no pide el papel a quien no lo firma |
| 2 | **0163** | **sí — corrige un doble pago** | Las truncas descuentan lo ya depositado |
| 3 | **0164** | no | La liquidación por cese, en una cuenta. **Va después de la 0163** |
| 4 | **0165** | no | El bono de onomástico sale de la base |
| 5 | **0166** | **sí** | La movilidad se paga por donde se trabaja |
| 6 | **0167** | no | La liquidación pagada se congela |
| 7 | **0168** | no | La precisión del monto del libro. En producción no cambia nada |

**El orden solo importa en un punto: la 0163 va antes que la 0164.** Fuera de
eso, cada una es independiente y puedes parar donde quieras.

> Si además tienes pendientes la **0160** y la **0161**, van primero: sus scripts
> también están en esta carpeta y son anteriores a todo esto.

---

## Antes de empezar

Ten a mano dos cosas:

- El SQL Editor de Supabase **de producción** (no el local).
- La ventana de resultados donde salen los `NOTICE`. Son la única prueba de que
  la migración hizo lo que dice. **Si un `NOTICE` no coincide con lo que esta
  guía dice que debe salir, para ahí y avisa.**

---

## Paso 1 · `aplicar_0162_tablero_documentacion.sql`

**Mueve plata:** no.
**Qué cambia:** el tablero de Documentación deja de listar a quien firma por
CAYLA y a quien termina contrato este mes.

**Debe salir:**

```
NOTICE:  0162 · el tablero ya no lista a quien firma por CAYLA
NOTICE:  0162 · ni a quien termina contrato este mes o antes
NOTICE:  0162 · ningun pago cambia: el candado de la 0159 sigue apagado
```

**Después, comprueba:** abre Documentación. El tablero debe bajar de 22 a **21**
personas — sales tú y nadie más.

> Si quieres que también salga quien se va a fin de mes, hace falta anotarle su
> último día. Desde el 06/08 eso se hace en **Equipo → Editar**, en el campo
> «Último día que trabaja por contrato». Con eso el tablero baja a 20.

---

## Paso 2 · `aplicar_0163.sql` — corrige un doble pago

**Mueve plata:** sí, y a favor de CAYLA — deja de pagar dos veces.

**Qué cambia:** una liquidación por cese volvía a pagar la CTS y la gratificación
que **ya habían salido del banco**, la ventana entera. `fn_cts_trunca` no miraba
el libro de desembolsos —cero menciones— y `fn_grati_trunca` solo veía lo pagado
por planilla, no lo depositado fuera de ella.

No cambia ninguna boleta ni ningún periodo. Solo lo que responde el cálculo de
liquidación.

**Debe salir:**

```
NOTICE:  0163 · depositos anotados en el libro: N por S/X
```

**⚠️ Si además sale esto, para y anota los depósitos primero:**

```
WARNING: 0163 · el libro esta VACIO: si hubo depositos y no estan anotados,
         las truncas siguen inflandose.
```

El candado no puede descontar un depósito que nadie anotó. Con el libro vacío la
migración se aplica igual y no rompe nada, pero **no protege de nada**.

---

## Paso 3 · `aplicar_0164.sql` — después de la 0163, no antes

**Mueve plata:** no. Agrega una función que responde «¿cuánto se le debe a esta
persona que se va?» en una sola llamada. La ley da **48 horas** desde el cese
para pagar (art. 4 D.S. 001-97-TR).

**⚠️ La 0163 va primero.** Sin ella, esta función presenta muy bien un doble pago.

**Debe salir:**

```
NOTICE:  0164 · personas cesadas en el sistema: N
```

**Y puede salir este aviso, que NO es un error:**

```
WARNING: 0164 · N de ellas ya pasaron las 48 horas del art. 4 D.S. 001-97-TR.
WARNING: 0164 · Si ya se les pago, no hay nada que hacer: el aviso es sobre el
         registro, no sobre el pago.
```

Habla de lo que el sistema tiene **anotado**, no de si la plata se transfirió.

**Después, comprueba:** `select * from fn_liquidaciones_pendientes();`

---

## Paso 4 · `aplicar_0165.sql`

**Mueve plata:** no.
**Qué cambia:** el monto del bono de onomástico sale del código y pasa a vivir en
`parametros_laborales`, versionado. Trae su propia fila de S/ 180 con fecha
29/07/2026. Y el bono deja de reclamarse hacia atrás: quien cumplió años antes de
que la política existiera ya no aparece en rojo.

**Debe salir:**

```
NOTICE:  0165 · el bono de onomastico rige desde 2026-07-29 y vale S/ 180.00
NOTICE:  0165 · quien cumplio anios antes de esa fecha ya NO aparece en rojo: le toca en 2027
NOTICE:  0165 · ningun pago cambia.
```

**⚠️ Esta migración pasó de opcional a necesaria.** La pantalla ya no imprime la
constancia del bono con un monto escrito en el código: si esta fila no existe,
te dice «falta fijar el monto» y no imprime. Antes imprimía 180 igual. Fue una
decisión deliberada —un papel que se firma no puede llevar una cifra que la base
nunca dijo— pero significa que **hasta que pegues esto, no puedes emitir cargos
de cumpleaños**.

---

## Paso 5 · `aplicar_0166.sql` — la otra que mueve plata

**Antes de pegarla, corre `comparar_movilidad_0166.sql`** y guarda el resultado.
Es la foto del «antes». Ese archivo explica solo cómo se usa.

**Qué cambia:**

1. Arregla el respaldo de la tarifa. A la consulta le faltaba `sede_codigo is
   null`: quien está en una sede sin tarifa propia no cobraba S/ 0.00 — cobraba
   el pasaje de una ciudad cualquiera, la que el motor devolviera primero entre
   Arequipa, Lima y Trujillo.
2. Le pone sede física Arequipa a Estefany, así que pasa a cobrar los S/ 10.00
   de Arequipa de forma estable.
3. Apaga tu movilidad, con el motivo escrito: *viaja entre sedes, se cubre por
   viáticos*.

**Debe salir — y estos dos números son lo más importante de toda la guía:**

```
NOTICE:  0166 · sede fisica AQP asignada a 1 persona(s) (esperado: 1)
NOTICE:  0166 · movilidad desactivada a 1 persona(s) (esperado: 1)
NOTICE:  0166 · personas con sede fisica distinta de su area: 1
NOTICE:  0166 · personas que NO devengan movilidad: 1
NOTICE:  0166 · el resto cobra exactamente igual que antes.
```

**Si alguno dice 2 o más, PARA.** La migración busca a esas dos personas **por
nombre** (`ilike '%estefany%'`, `ilike '%felipe%' + '%alvarez%'`). Un 2 significa
que el nombre coincidió con alguien más, y tocar a quien no era es plata mal
pagada a una persona real. La migración ya está aplicada en ese punto: avísame
antes de correr la planilla del mes y lo revertimos por nombre exacto.

**Después, vuelve a correr `comparar_movilidad_0166.sql`** y compara fila por
fila con la foto del «antes». Solo deben cambiar Estefany, tú, y quien esté en
una sede sin tarifa propia. **Cualquier otro cambio es un problema.**

### Lo que esta migración NO toca

Los meses **ya pagados no cambian**. Está verificado contra la base:
`planilla_pagada_detalle` congela `monto_movilidad` como columna propia y su
regla de cuadre lo incluye. Recalcular un mes ya pagado no reescribe lo que salió
del banco.

**El mes abierto sí cambia**, y esa es la intención. Si agosto no está pagado, el
cálculo de agosto se mueve para esas dos personas.

---

## Paso 6 · `aplicar_0167.sql`

**Mueve plata:** no. Crea la tabla donde se congela la liquidación con la que se
pagó, para que esa cifra no cambie sola después.

**Debe salir:**

```
NOTICE:  0167 · liquidaciones congeladas: 0 (la tabla nace vacia)
NOTICE:  0167 · esta migracion no cambia ningun calculo: solo permite guardar el que se pago.
```

**Después, comprueba:**

```sql
select * from fn_liquidaciones_pendientes();
```

Debe listar a las personas cesadas con `pagada = false` y `descuadra = false`.
Ninguna cifra cambia respecto de lo que ya veías.

### Un caso que se corrigió antes de aplicarla

`fn_liquidacion_diferencias` comparaba contra la **fecha de cese congelada**, así
que era ciega al motivo más frecuente de que una liquidación deje de cuadrar:
que alguien corrija el último día que la persona trabajó.

Medido contra el Postgres local:

| | Antes | Ahora |
|---|---|---|
| Se paga con cese el 15/06 | S/ 3,444.31 | S/ 3,444.31 |
| Se corrige: trabajó hasta el 20/06 | | |
| Lo que de verdad le toca | S/ 3,465.60 | S/ 3,465.60 |
| Lo que reporta la función | *nada* | **S/ 21.29**, desglosado |
| Lo que muestra la pantalla | `descuadra = false` | `descuadra = true` |

La foto **sigue guardando la fecha con la que se pagó** — eso no se corrige, se
conserva, porque es lo que hay que poder reimprimir. Lo que cambió es contra qué
se compara: para responder «¿cuánto le debemos hoy?», la fecha buena es la de
hoy. Fijado por la prueba 133.

---

## Paso 7 · `aplicar_0168.sql`

**Mueve plata:** no. **En producción no cambia absolutamente nada:** la columna
ya es `numeric(12,2)` allí.

**Entonces ¿para qué se pega?** Para que quede anotada en `migraciones_aplicadas`
y el registro no muestre un hueco. Su valor real es que una base reconstruida
desde el repositorio se comporte igual que la de verdad: la 0155 declaró la
columna como `numeric` a secas, y `numeric` sin precisión guarda todos los
decimales que le den mientras `numeric(12,2)` redondea a céntimos. En una tabla
que registra plata entregada a personas, esa es la diferencia entre S/ 141,254 y
S/ 141,25.

**No emite ningún `NOTICE`.** Para comprobar que quedó bien:

```sql
select numeric_precision, numeric_scale
from information_schema.columns
where table_name = 'desembolsos_beneficios' and column_name = 'monto';
```

Debe devolver **12** y **2**.

---

## Resumen

| Paso | # | Mueve plata | Qué mirar al pegarla |
|---|---|---|---|
| 1 | 0162 | no | el tablero baja de 22 a 21 |
| 2 | **0163** | **sí** | que el libro **no** esté vacío |
| 3 | 0164 | no | va después de la 0163 |
| 4 | 0165 | no | **necesaria para imprimir cargos de bono** |
| 5 | **0166** | **sí** | los dos `esperado: 1`, y la comparación antes/después |
| 6 | 0167 | no | — |
| 7 | 0168 | no | en producción no cambia nada |

**El único orden obligatorio es 0163 → 0164.** Todo lo demás es independiente y
puedes parar donde quieras.

**Si solo vas a pegar una hoy, que sea la 0166:** es la que está pagando mal
ahora mismo. Y si vas a imprimir declaraciones de ruta o cargos de bono esta
semana, la 0165 también, o la pantalla no te deja imprimir.
