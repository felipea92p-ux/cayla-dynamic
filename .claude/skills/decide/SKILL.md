---
name: decide
description: Fuerza el protocolo de pregunta de CLAUDE.md sobre una decisión abierta puntual, con hasta 3 opciones comparadas (Ganas/Pagas) y una recomendación.
---

Aplica la sección AUTONOMÍA de `~/.claude/CLAUDE.md` (global) sobre: $ARGUMENTS

Antes de preguntar, pasa este test y dile a Felipe en 1 línea si lo pasó o no:
1. ¿La respuesta no vive en el repo, el schema, los ADRs (`/docs/adr/`) ni
   `/docs/BACKLOG.md`?
2. ¿Elegir mal cuesta más que deshacerlo en menos de 30 minutos?
3. ¿Depende de cómo opera CAYLA, no de cómo funciona Postgres/Next.js?

Si NO lo pasó: no preguntes — cae en "ejecuto sin preguntar". Decide, ejecuta, y
explica en 3 líneas (QUÉ HICE/POR QUÉ ASÍ/QUÉ SE ROMPERÍA SIN ESTO) por qué esto no
era una pregunta para Felipe.

Si SÍ lo pasó: usa el formato exacto de "propongo y espero aprobación" (máx. 3
opciones, cada una con Ganas/Pagas y un ejemplo real de CAYLA, nunca `foo`/`bar`),
termina con tu recomendación y "si no respondes, ejecuto [X]".
