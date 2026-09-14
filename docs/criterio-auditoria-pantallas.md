# Criterio de auditoría de pantallas

> Traduce las 12 exigencias de `CLAUDE.md` (nivel sistema, nivel arquitecto) a
> preguntas que se le hacen a UNA pantalla. No es una teoría nueva compitiendo
> con esa: es su misma vara, mirada más de cerca. Por eso vive sin fecha — es
> el criterio, no un hallazgo. Los hallazgos de cada pantalla van en su propio
> informe fechado, `docs/auditoria-pantalla-<nombre>-AAAA-MM-DD.md`.

## Cómo se usa

Por cada pantalla, dos pasadas — nunca una sola:

1. **Con la cuenta de rango más bajo que la usa** (`integrante`, sin panel).
2. **Con la cuenta de rango más alto** (`admin`/`lider_do`).

La mayoría de las pantallas de autoservicio las diseña y las revisa alguien
que las mira desde arriba del escalafón (`packages/shared/src/escalafon.ts`).
El defecto que importa casi siempre vive abajo — y a veces, al revés de lo
esperado, arriba: un texto que asume "todos tienen a alguien por encima" se
rompe justo en la cuenta de quien no lo tiene.

## Las nueve preguntas

1. **¿Responde sola?** — ¿Qué pregunta que hoy alguien le hace por WhatsApp a
   su encargada, esta pantalla ya la contesta sin que tenga que preguntar?
2. **El vacío, ¿explica qué hacer, o solo dice "—"?** (Norman: el error es del
   diseño, no de la persona.) Un estado vacío sin acción sugerida es una
   pantalla que todavía no terminó de diseñarse.
3. **Una cifra, ¿lleva su "de cuánto"?** "Promedio 6h 54m" no dice si va bien
   o mal si no hay con qué compararlo, y quien la ve puede no tener a quién
   preguntarle.
4. **¿Hay una sola forma de decir lo mismo en dos pantallas?** (Brooks:
   integridad conceptual.) Si el panel y el autoservicio pueden llegar a
   contar algo distinto de la misma persona, ya es un defecto, aunque hoy
   coincidan por casualidad.
5. **¿Qué pasa si la fuente de este dato no responde hoy?** (Vogels.) ¿La
   pantalla dice "no se pudo traer" o inventa un cero que se lee como un
   hecho?
6. **¿La acción más importante está a la vista, o detrás de un menú?** (Beck:
   hazlo fácil antes de pedir que lo hagan seguido.)
7. **¿Qué estados imposibles puede mostrar, y qué le pasa a quien los ve?**
   (Lamport.) Incluye el estado "esta persona no tiene a nadie por encima" —
   el escalón más alto del escalafón es un estado real, no un caso de nadie.
8. **Mobile primero.** ¿Se ve y se usa bien en ~375px de ancho, sin hover, con
   el pulgar como único cursor? La mayoría de esta pantalla se abre en el
   celular, no en el panel de escritorio.
9. **Lo que sí vale importar de Workday/BambooHR/Gusto — sin copiar su
   escala** (ver `docs/comparacion-workday-oracle-dynamic-2026-09-02.md`):
   ¿el autoservicio reduce contactos medibles con DO/la encargada, o solo se
   ve más parecido a un ERP grande sin cambiar cuánto le preguntan a otra
   persona?

## Lo que esta rúbrica NO es

No reemplaza `CLAUDE.md` ni compite con él. Si algo de acá contradice una
regla ya escrita ahí, gana `CLAUDE.md`. Y no es una lista de features de otros
ERP: el propio informe de comparación ya advierte contra leerla así.
