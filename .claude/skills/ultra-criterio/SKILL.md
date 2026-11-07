---
name: ultra-criterio
description: Diseña y programa con el criterio de los mejores arquitectos, diseñadores y programadores del mundo, el pedido de Felipe del 2026-08-13. Úsala al diseñar una solución nueva, al analizar un módulo o cuando Felipe pida «como lo harían los mejores del mundo».
---

> El pedido original de Felipe (2026-08-13), palabra por palabra:
> «explicame bien y diseña la solución más óptima, con bastante inteligencia, con buen código, como los mejores arquitectos,
> diseñadores y programadores del mundo. Vamos a trabajar de una forma formidable, ¿de acuerdo? Si tienes preguntas, házmelas
> tipo ask user question.»

Aplica sobre: $ARGUMENTS

Trabaja con el criterio de los mejores arquitectos, diseñadores y programadores del mundo. Vamos a trabajar de una forma formidable.

1. **Entiende antes de diseñar.** Explica bien el problema: qué pasa hoy, a quién le afecta y qué cuesta. Mide contra la base y el
   código antes de proponer; no razones sobre supuestos (`CLAUDE.md`: «medir contra la base antes de proponer»).
2. **Compara con los mejores.** Antes de decidir, di cómo lo resuelven Workday, Oracle, SAP, ADP, QuickBooks, Odoo o Shopify, según
   el caso, y qué copiarías, qué no y por qué. Ya hay una comparación hecha:
   [`docs/comparacion-workday-oracle-dynamic-2026-09-02.md`](../../../docs/comparacion-workday-oracle-dynamic-2026-09-02.md).
3. **La solución más óptima, no la más corta.** Hasta 3 opciones, cada una con lo que se gana y lo que se paga, y una recomendación.
   Para las decisiones estructurales usa `DECIDÍ / DESCARTÉ / SE ROMPE SI`.
4. **Buen código.** Un solo lugar para cada regla, sin copias (`permisos.ts`, `fecha-lima.ts`, `jornada-esperada.ts`). Nombres
   claros. Comentarios solo donde algo no es obvio, en español. Pruebas que fallarían si el diseño se rompe: un freno se prueba con
   un caso que DEBE bloquear.
5. **Rigor donde importa.** Plata en decimal exacto, nunca float. Empates resueltos de forma explícita. Fallos externos modelados
   como un valor que se revisa, no como excepciones. Ojo con la complejidad: cuenta las filas reales.
6. **Diseño de primer nivel.** Que una persona de tienda lo entienda sin explicación. Con contraste medido y que funcione en celular
   y en escritorio, con los trece tokens de color y las piezas de `components/ui`.
7. **Las preguntas, con AskUserQuestion.** Lo que Felipe ya decidió no se reabre.
8. **Al terminar, di qué quedó verificado y qué no**, sin adornos.

Este criterio no está por encima de las reglas de `CLAUDE.md`: el SQL lo pega Felipe, el md5 se pide a producción, fusionar es
publicar. «Los mejores del mundo» también respetan los frenos de la casa.
