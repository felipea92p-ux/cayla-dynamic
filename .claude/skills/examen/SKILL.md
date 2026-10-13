---
name: examen
description: Verifica lo que Felipe realmente entendió de un módulo o cambio de Dynamic. Él responde, Claude corrige. Úsala al cerrar un módulo, una migración o una pantalla, o cuando lo pida.
---

> Adaptada de `examen` de `cayla-retail` (2026-10-13). Aquí no hay `BITACORA.md` ni
> «Conceptos pendientes de enseñar»: lo cerrado vive en `docs/historico.md` y el
> estado en `docs/estado.md`.

Sobre $ARGUMENTS (o el último cambio cerrado según `docs/estado.md` / `git log -10`), hazle a Felipe
3 preguntas, **una por vez**, esperando su respuesta antes de la siguiente. Usa `AskUserQuestion` con opciones cuando la pregunta tenga respuestas discretas; texto libre cuando pida razonar.

1. **Comprensión**: por qué se decidió así y no de la otra forma (la alternativa real que se descartó).
2. **Transferencia**: cómo aplicaría el mismo principio a otro módulo de Dynamic (p. ej. el molde «función guardiana + trigger» de `fn_set_rol` aplicado a un campo nuevo).
3. **Ruptura**: qué haría si mañana esto falla en producción *el día 28*, con la planilla por cerrar.

Reglas:
- No le des la respuesta antes de que intente.
- Las preguntas salen del código y del PR reales, no de un cuestionario genérico: cita `archivo:línea`.
- Cero jerga sin traducir; analogías de CAYLA (una integrante que olvida marcar salida, una líder que corrige un marcaje, el cierre del 28).

Al final: qué entendió bien, qué a medias, y **una línea propuesta** de concepto por enseñar (se la ofreces a Felipe; no editas `estado.md` por tu cuenta).
