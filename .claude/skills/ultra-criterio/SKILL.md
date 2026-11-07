---
name: ultra-criterio
description: Diseña y programa con el criterio de los mejores arquitectos, diseñadores y programadores del mundo (Linus Torvalds, Knuth, Dijkstra, Hoare, Brooks, Pike, Rams, Norman, Kleppmann, Pólya…) y con prácticas modernas de élite, el pedido de Felipe del 2026-08-13. Doce reglas, la última de juicio y creatividad. Úsala al diseñar una solución nueva, al analizar un módulo o cuando Felipe pida «como lo harían los mejores del mundo».
---

> El pedido original de Felipe (2026-08-13), palabra por palabra:
> «explicame bien y diseña la solución más óptima, con bastante inteligencia, con buen código, como los mejores arquitectos,
> diseñadores y programadores del mundo. Vamos a trabajar de una forma formidable, ¿de acuerdo? Si tienes preguntas, házmelas
> tipo ask user question.»
>
> El curso que explica cada regla con ejemplos, casos de CAYLA y ejercicios:
> [Ultra criterio, versión 2](https://claude.ai/artifact/PBjJT4opUs88ULfCYmRkxz) (noviembre de 2026). Las doce reglas de esta skill
> y las del curso son las mismas y van en el mismo orden: si cambias una, cambia la otra.

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

9. **Software moderno, de élite, sin caer en la moda.**
   El software de élite de hoy no se mide por usar lo último. Se mide por lo que hace imposible equivocarse. Primero el freno:
   - *Dan McKinley* (Etsy), «Choose Boring Technology»: cada equipo tiene pocas «fichas de innovación»; gástalas donde CAYLA gana
     algo que se pueda medir, no en cambiar de herramienta. Una tecnología nueva tiene que pagar su costo de mantenerla durante años.

   Lo que sí es de élite, y cómo está CAYLA (medido el 2026-11-06 en los `package.json`):

   | Práctica | Maestro | En CAYLA hoy |
   |---|---|---|
   | **Estados imposibles que no se pueden escribir**: uniones discriminadas en TypeScript, `CHECK` y `NOT NULL` en Postgres | *Yaron Minsky* (Jane Street) | Parcial: la base tiene `CHECK`; usarlo también en los tipos de TS |
   | **Parsear, no validar**: el dato que entra se convierte una vez, en el borde, en un tipo que ya es correcto | *Alexis King* | No hay librería de esquemas (ni zod ni valibot); proponerla al tocar un formulario que mueve plata |
   | **Pruebas por propiedades**: miles de casos generados contra una invariante («ninguna planilla da negativo», «la suma de las partes es el total») | *John Hughes* (QuickCheck) | No está `fast-check`; es la candidata más fuerte para el cálculo de planilla |
   | **Pruebas de mutación**: se rompe el código a propósito y la prueba tiene que ponerse en rojo | *Richard DeMillo* | El repo ya lo hace a mano con los frenos (receta-suelta se rompió de ocho maneras); `Stryker` lo haría sistemático |
   | **Eventos como fuente de verdad**: se guarda lo que pasó y lo demás se deriva | *Greg Young*, *Martin Kleppmann* | Ya está: marcajes append-only y `jornadas` derivadas por trigger |
   | **Local-first**: la app sigue andando sin internet y reconcilia después | *Martin Kleppmann* (Ink & Switch) | Ya está en el terminal, con la reconciliación de marcajes offline en `fn_registrar_marcaje` |
   | **Métodos formales** para lo crítico: especificar la máquina de estados antes de programarla | *Leslie Lamport* (TLA+, lo usa AWS) | Candidato: la máquina de estados del marcaje en `packages/shared` |
   | **Observabilidad**: preguntas nuevas sin desplegar código nuevo | *Charity Majors* | Sentry ya está (`@sentry/nextjs`); falta mirar los errores por sede y por pantalla |
   | **Entrega progresiva**: lo nuevo entra apagado, detrás de un interruptor | Google SRE | Ya está: el interruptor de vidrio |
   | **Seguridad por mínimo privilegio** en la base, no en la pantalla | *Saltzer y Schroeder* | Ya está: RLS y funciones guardián `SECURITY DEFINER` |
   | **Plataforma al día**: Next 16, React 19, TypeScript 5, Vitest 4 | — | Ya está |

   La regla: cuando propongas algo «moderno», di en qué fila de esta tabla cae, qué falla de CAYLA evita y cuánto cuesta
   mantenerlo. Si no evita una falla concreta, es moda.

10. **Las preguntas, con AskUserQuestion.**
    - Una a una, con dos o tres opciones, lo que se gana y se paga en cada una, y tu recomendación. La respuesta a la primera cambia
      la segunda.
    - Lo que Felipe ya decidió no se reabre, salvo que aparezca información nueva y real (una medición, una ley que cambió, un caso
      que nadie consideró). Ejemplos: el terminal sin PIN, el régimen MYPE y la base de 6.5 h.

11. **Al terminar, la evidencia, sin adornos.**
    - *Linus Torvalds*: «hablar es barato; muéstrame el código». *Richard Feynman*: no debes engañarte a ti mismo, y eres la persona
      más fácil de engañar.
    - En CAYLA: di qué quedó verificado (con qué prueba o qué consulta) y qué no. «Debería funcionar» no es verificado.

12. **Amplitud de criterio, juicio y creatividad.**
    - Las reglas sirven para pensar, no para dejar de pensar. Cuando dos chocan (medir contra decidir a tiempo, rediseñar contra no
      romper, rigor contra simpleza), di cuál pesa más aquí y por qué.
    - *George Pólya* (How to Solve It, 1945): si no ves cómo atacar el problema, resuelve primero uno relacionado: más pequeño (una
      sede), más general o parecido a uno ya resuelto.
    - Entre tus opciones, incluye una que nadie pidió. *Christopher Alexander* (A Pattern Language): un buen diseño resuelve las
      fuerzas en tensión del lugar; de los mejores se copia el principio, no la forma.
    - *Daniel Kahneman*: desconfía de la respuesta que llega rápida y segura. *Gary Klein*: antes de entregar algo importante, haz el
      premortem: imagina que ya falló y escribe por qué.
    - *Richard Hamming*: trabaja en el problema importante, no en el cómodo.
    - En CAYLA: pon precio a cada tipo de error, porque casi nunca cuestan lo mismo; los falsos positivos son el peor (acusar de
      falta a quien no la cometió). Y elegir qué NO hacer también es criterio: el freno que buscaba `horario_por_dia` fuera de
      `jornada-esperada.ts` se descartó porque daba 28 aciertos, casi todos legítimos, y un guardián con ruido se desactiva a la semana.

Este criterio no está por encima de las reglas de `CLAUDE.md`: el SQL lo pega Felipe, el md5 se pide a producción, fusionar es
publicar. Los mejores del mundo también respetan los frenos de la casa.
