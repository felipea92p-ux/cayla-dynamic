# Guía de pegado — de la 0162 a la 0167

Cinco migraciones esperando. **Una sola mueve plata: la 0166.** Las otras cuatro
cambian lo que una pantalla muestra o lo que el sistema puede guardar.

El orden importa en un solo punto, y está señalado abajo. Fuera de eso, cada una
es independiente y puedes parar en cualquiera.

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
> fecha de fin de contrato: eso es `poner_fin_de_contrato.sql`, que no es una
> migración y se usa cada vez que alguien se va. Con eso el tablero baja a 20.

---

## Paso 2 · `aplicar_0165.sql`

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

## Paso 3 · `aplicar_0166.sql` — la única que mueve plata

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

## Paso 4 · `aplicar_0167.sql` — solo si vas a liquidar a alguien

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

## Resumen

| | Mueve plata | Se puede pegar sola |
|---|---|---|
| 0162 | no | sí |
| 0165 | no | sí — **necesaria para imprimir cargos de bono** |
| 0166 | **sí** | sí, con la comparación antes y después |
| 0167 | no | sí |

Ninguna depende de otra para aplicarse. El orden de arriba es el que va de menos
riesgo a más.
