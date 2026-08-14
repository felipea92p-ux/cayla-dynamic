# Cerrar el mes sin pagarle dos veces a quien cesó

Guía corta para el día del cierre. No hace falta acordarse de nada: el sistema
frena solo y te dice qué hacer. Esto explica qué vas a ver y por qué.

**Para quién:** quien cierra la planilla en `/admin/planilla`.
**Cuándo:** cada 28, al cerrar el periodo.

---

## El problema que esto evita, en tres líneas

Cuando alguien cesa a mitad de mes, **su liquidación ya incluye el sueldo de ese
mes**. Si además cierras el periodo con ella dentro, ese mes se paga dos veces.
Pasó en julio de 2026 con seis personas: S/1 381,59 registrados dos veces.

Desde el 2026-08-14 el sistema no deja que ocurra en silencio. Las dos mitades:

- la [`0243`](../supabase/migrations/0243_la_liquidacion_no_vuelve_a_cobrar_el_mes_que_ya_se_pago.sql)
  hace que **la liquidación reste** lo que la planilla ya transfirió;
- la [`0244`](../supabase/migrations/0244_la_0243_deja_de_pagar_de_menos_y_de_atascar_el_cierre.sql)
  hace que **el cierre se frene** cuando la liquidación fue primero, y arregla
  seis bordes de la anterior.

---

## Paso a paso

### 1 · Antes de darle a cerrar, mira la lista

En `/admin/planilla`, junto al nombre de quien cesó a mitad de mes, aparece un
aviso en ámbar:

> ⚠ Ya cobró su liquidación el 07/08 · S/1 106,82 de este mes — si no vas a
> transferirle otra vez, usa «Ya le pagué aparte».

Si el aviso está en gris con un ✓, ya está resuelto y no hay nada que hacer.

**Ojo con el filtro «Mostrar»:** quien ya cesó puede estar oculta. Cámbialo a
**Todos**, o pulsa **«Verlas»** en el aviso de quienes ya no están.

### 2 · Dale a cerrar

Pasa una de dos cosas.

**a) Cierra normal.** No había nadie en esa situación. Terminaste.

**b) Se frena y te nombra a la persona.** El mensaje dice el nombre y el importe
exacto, y termina así:

> El periodo sigue ABIERTO: no se congeló nada.

Eso es literal: **no se guardó nada a medias**. Puedes resolverlo con calma.

### 3 · Si se frenó: registrar lo que ya le pagaste

1. Busca su fila en Planilla (acuérdate del filtro «Mostrar»).
2. Pulsa **«💸 Ya le pagué aparte»**.
3. Pon **el importe que el mensaje te dijo** y **la fecha en que se lo pagaste**.
4. Vuelve a cerrar el periodo.

**Si tras ese descuento le queda un saldo, ese saldo es suyo y se paga con la
planilla.** No hace falta dejar su fila en cero a la fuerza: el sistema deja
cerrar en cuanto el descuento cubre el mes que la liquidación ya pagó, no antes.

### 4 · Caso raro: el periodo ya estaba marcado como pagado

Entonces el descuento no se puede anotar sin reabrirlo. El mensaje te lo dice y
el orden es:

1. **«Revertir pago»**, con su motivo.
   ⚠️ Eso levanta los candados de los marcajes de ese periodo mientras esté
   abierto: no es el momento de corregir marcajes viejos.
2. Registra el descuento con **«💸 Ya le pagué aparte»**.
3. Vuelve a marcarlo como pagado.

La foto anterior del pago sigue intacta todo el rato.

---

## Avisos que NO frenan, y qué significan

| Lo que ves | Qué significa |
|---|---|
| `foto retroactiva de un periodo ya transferido` | Ese dinero salió hace tiempo. No se frena porque no hay nada que evitar ya; conviene mirarlo, no corre prisa |
| `% persona(s) YA tienen el mismo mes en la foto del periodo y en su liquidación` | Son los casos viejos —julio de 2026—. Ninguna migración los arregla: las fotos del pago son inmutables. Se revisan uno por uno |

---

## Lo que no hay que hacer

- **No saltarse el freno.** Si te frena, es porque el dinero **todavía no ha
  salido** y aún se puede evitar el doble pago. Es el único momento en que se
  puede.
- **No corregir la cifra a mano** en la liquidación. El sistema ya resta solo lo
  que consta transferido; tocar el número a mano rompe esa cuenta.

---

## Pendiente concreto de agosto de 2026

**Rufina Salvatierra**, que cesó el 07/08. Su liquidación ya cubre agosto. Al
cerrar el periodo del 28/08 el sistema te va a frenar y a nombrarla: resuélvelo
con el paso 3. Es el único caso vivo — los demás son de julio y ya salieron.

---

Por qué existe todo esto y qué quedó abierto: sección **A.2.b.bis** de
[`estado.md`](estado.md).
