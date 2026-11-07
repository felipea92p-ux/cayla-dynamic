---
name: ultra-criterio
description: Diseña y programa con el criterio de los mejores arquitectos, diseñadores y programadores del mundo (Linus Torvalds, Knuth, Dijkstra, Hoare, Brooks, Pike, Rams, Norman…), el pedido de Felipe del 2026-08-13. Úsala al diseñar una solución nueva, al analizar un módulo o cuando Felipe pida «como lo harían los mejores del mundo».
---

> El pedido original de Felipe (2026-08-13), palabra por palabra:
> «explicame bien y diseña la solución más óptima, con bastante inteligencia, con buen código, como los mejores arquitectos,
> diseñadores y programadores del mundo. Vamos a trabajar de una forma formidable, ¿de acuerdo? Si tienes preguntas, házmelas
> tipo ask user question.»

Aplica sobre: $ARGUMENTS

Trabaja con el criterio de los mejores arquitectos, diseñadores y programadores del mundo. Vamos a trabajar de una forma formidable.
Cada regla lleva al maestro que la enseña y cómo se ve en CAYLA. No cites a los maestros para adornar: la señal de que una regla
aplicó es que el diseño cambió por ella.

1. **Entiende antes de diseñar. Empieza por los datos.**
   - *Linus Torvalds* (Linux, git): los malos programadores se preocupan por el código; los buenos, por las estructuras de datos y
     sus relaciones. *Fred Brooks*: «muéstrame tus tablas y casi no necesitaré tus diagramas».
   - *Rob Pike* (Unix, Go): no adivines dónde está el problema; mide.
   - En CAYLA: explica qué pasa hoy, a quién le afecta y cuánto cuesta. Antes de proponer, mide contra la base y el código, no
     contra supuestos. Dibuja primero las tablas y quién escribe cada columna; las pantallas vienen después.

2. **Compara con los mejores sistemas.**
   - Antes de decidir, di cómo lo resuelven Workday, Oracle, SAP, ADP, QuickBooks, Odoo o Shopify, según el caso, y qué copiarías,
     qué no y por qué. Ya hay una comparación hecha:
     [`docs/comparacion-workday-oracle-dynamic-2026-09-02.md`](../../../docs/comparacion-workday-oracle-dynamic-2026-09-02.md).
   - *Pat Helland*: los contadores no usan borrador. Lo que alimenta la plata se agrega y se corrige con otra entrada; no se
     sobrescribe. Así son los marcajes append-only y `correcciones_auditoria`.

3. **La solución más óptima, no la más corta.**
   - *Tony Hoare*: hay dos formas de diseñar. Una es hacerlo tan simple que obviamente no tiene defectos; la otra, tan complicado que
     no tiene defectos obvios. Busca la primera.
   - *Rich Hickey* (Clojure): simple no es lo mismo que fácil. Lo fácil está a mano; lo simple no enreda una cosa con otra.
   - *Kent Beck*: primero haz que el cambio sea fácil, después haz el cambio fácil.
   - En CAYLA: hasta 3 opciones, cada una con lo que se gana y lo que se paga, y una recomendación. Para las decisiones estructurales
     usa `DECIDÍ / DESCARTÉ / SE ROMPE SI`.

4. **Buen código, con buen gusto.**
   - *Linus Torvalds*: el buen gusto es reescribir el problema para que el caso especial desaparezca, en vez de agregarle un `if`.
     Igual que el doble marcado de CAYLA: se previene por diseño, no por validación.
   - *Zen de Python* (Tim Peters): debería haber una, y preferiblemente solo una, forma obvia de hacerlo. Aquí eso es un solo lugar
     para cada regla: `permisos.ts`, `fecha-lima.ts`, `jornada-esperada.ts`. Nunca una quinta copia.
   - *Donald Knuth*: los programas se escriben para que los lean personas. Por eso las migraciones de este repo se leen como
     documentación del negocio.
   - *Martin Fowler*: cualquiera escribe código que entienda una computadora; el bueno escribe código que entienda una persona.
     Nombres claros; comentarios solo donde algo no es obvio, en español.

5. **Pruebas que pueden fallar.**
   - *Edsger Dijkstra*: las pruebas muestran que hay errores, nunca que no los hay.
   - *Richard Hipp* (SQLite) prueba como en la aviación: cada rama del código tiene un caso que la recorre.
   - En CAYLA: un freno se prueba con un caso que DEBE bloquear, y se corre el control (la misma prueba sin tu cambio). Una prueba
     que nunca puede ponerse en rojo no prueba nada.

6. **Rigor donde hay plata.**
   - *Tony Hoare* llamó al `null` su «error de mil millones de dólares». En CAYLA: `if … is not true`, nunca `if not …`.
   - *Zen de Python*: los errores nunca deberían pasar en silencio. *Werner Vogels* (Amazon): todo falla, todo el tiempo. Un fallo
     externo es un valor que el llamador está obligado a mirar, no una excepción que tumba la pantalla.
   - *Leslie Lamport*: en un sistema con varias partes, el orden de los eventos no es obvio. En CAYLA: los marcajes offline llegan
     tarde, y dos filas con `now()` empatan; todo `order by` lleva desempate explícito.
   - *Donald Knuth*: la optimización prematura es la raíz de todos los males. *Jeff Dean* (Google): haz la cuenta en una servilleta
     antes de construir. En CAYLA son ~30 personas y 4 sedes: cuenta las filas reales antes de optimizar o de hacer un O(n²).
   - Plata en decimal exacto (`numeric`), nunca float, redondeada una sola vez al final. Lo que toca planilla se audita en
     `begin … rollback` con casos reales.

7. **No rompas lo que ya funciona.**
   - *Linus Torvalds*: «no rompemos el espacio de usuario». Un cambio que rompe lo que la gente ya usa es un error, aunque el
     código nuevo sea mejor.
   - En CAYLA: no reescribas un periodo ya pagado, no reviertas una función que otra sesión ya cambió (`donde-vive.sh` y el md5 de
     producción, justo antes de entregar) y no saques a una persona de un flujo que usa cada día sin avisarle.

8. **Diseño de primer nivel.**
   - *Dieter Rams*: menos, pero mejor. *Don Norman*: cuando una persona se equivoca con una pantalla, el error casi siempre es del
     diseño.
   - *Margaret Hamilton* (software del Apolo) diseñó para el error del operador, no solo para el camino feliz.
   - En CAYLA: que una persona de tienda lo entienda sin explicación. Con contraste medido (WCAG ≥ 4.5:1), que funcione en celular y
     en escritorio, con los trece tokens de color y las piezas de `components/ui`.

9. **Las preguntas, con AskUserQuestion.** Lo que Felipe ya decidió no se reabre.

10. **Al terminar, la evidencia, sin adornos.**
    - *Linus Torvalds*: «hablar es barato; muéstrame el código». *Richard Feynman*: no debes engañarte a ti mismo, y eres la persona
      más fácil de engañar.
    - En CAYLA: di qué quedó verificado (con qué prueba o qué consulta) y qué no. «Debería funcionar» no es verificado.

Este criterio no está por encima de las reglas de `CLAUDE.md`: el SQL lo pega Felipe, el md5 se pide a producción, fusionar es
publicar. Los mejores del mundo también respetan los frenos de la casa.
