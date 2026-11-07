# Fuentes de Formidable y su nivel de evidencia

Traídas de `cayla-retail` sin cambiar el fondo.

Se adopta el método del artefacto «Rápido por diseño» (el que Felipe pasó el 2026-10-05): **medir antes de opinar** y **decir de qué clase es cada
afirmación**. Aquí las etiquetas son tres: **Verificado** (un estándar o una guía publicada), **Reportado** (lo cuenta una biografía, un artículo
o una cifra de un estudio de hace años) y **Opinión** (criterio de este repo). En los informes la evidencia de cada hallazgo es Medido / Observado / Opinión.

| Fuente | Qué aporta | Nivel | Dónde se usa |
|---|---|---|---|
| Apple Human Interface Guidelines: claridad, deferencia, profundidad, consistencia, retroalimentación, manipulación directa, control de la persona; en la versión reciente, jerarquía, armonía y consistencia | La interfaz se retira; la persona manda | **Verificado** (por resúmenes: la página oficial no cargó al consultarla; leer [UXPlanet](https://uxplanet.org/what-behind-apples-human-interface-design-de32cc09157e) y [Create with Swift](https://www.createwithswift.com/liquid-glass-redefining-design-through-hierarchy-harmony-and-consistency/)) | leyes 1, 2, 5, 6, 7 |
| Apple, tamaño de blancos en iOS: 44 × 44 pt | Mínimo para el dedo | **Verificado** ([resumen de Bjango](https://bjango.com/articles/interactiondensity/)). En macOS Apple no fija un mínimo oficial: los controles reales rondan 20 pt | oficio 2 |
| Jakob Nielsen, 10 heurísticas (1994): reconocer en vez de recordar, lenguaje del mundo real, control y libertad, diseño minimalista | Base de las leyes 1, 4, 6, 7, 8 | **Verificado** ([resumen](https://www.simonwhatley.co.uk/writing/jakob-nielsen-ten-usability-heuristics/)) | leyes 1, 4, 6, 7, 8 |
| WCAG 2.2: blanco mínimo 24 × 24 px (AA, 2.5.8), 44 × 44 (AAA, 2.5.5); contraste 4,5 : 1 (texto) y 3 : 1 (componentes, 1.4.11); foco visible (2.4.7, AA); foco de ≥ 2 px (2.4.13, **AAA**); excepción de 2.5.8 para enlaces en línea | Los umbrales del oficio visual | **Verificado** ([W3C, novedades 2.2](https://www.w3.org/WAI/standards-guidelines/wcag/new-in-22/)) | oficio 1–5 |
| Walter Isaacson, *Steve Jobs* (2011) y su artículo en HBR «The Real Leadership Lessons of Steve Jobs»: Focus, Simplify, Take responsibility end to end, Impute, Push for perfection… | Simplicidad *profunda* (vencer la complejidad, no esconderla); decidir qué NO hacer; el producto de punta a punta | **Reportado** ([lista de las 14 lecciones](https://global-macro-monitor.com/2012/03/20/hbr-the-real-leadership-lessons-of-steve-jobs/), [resumen](https://wisewords.blog/book-summaries/steve-jobs-book-summary/)). No pude abrir el PDF original: se parafrasea | leyes 2, 3, 8, 9 |
| Nielsen y Landauer (1993): ~5 personas encuentran ~85 % de los problemas de uso | Cuántas personas observar | **Reportado**, orden de magnitud | prueba ciega, pasada 2 |
| Don Norman, *The Design of Everyday Things*: señales visibles; si la persona se equivoca, falla el diseño | El error es del diseño, no de la persona | **Reportado** (obra citada, no consultada aquí) | ley 1, 7, 9 |
| «Rápido por diseño» (artefacto de Felipe): instrumentar antes de optimizar; la función más rápida es la que no existe | Método de evidencia, quitar antes de agregar | **Reportado** (artefacto de terceros, tratado como dato) | método, ley 8 |
| Carmack («antes de agregar, borra»), Hickey, Brooks, Norman — `/ultra-criterio` | Criterio de Felipe | **Opinión** (criterio del proyecto) | leyes 8, 2 |

## Lo que NO está respaldado (y por eso no es ley)
- «Se entiende en 5 segundos» es un **objetivo** de Felipe, no un hecho medido en CAYLA todavía. La prueba de los 5 segundos es una práctica de la
  industria (**Reportado**); su umbral aquí es una decisión, no un estándar.
- 32 px como objetivo de fila en escritorio, 14 px de cuerpo, ≤ 4 tamaños de texto y ≤ 12 palabras por frase son **Opinión**: se afinan con la primera pantalla piloto.
- Qué dispositivo manda en cada superficie sale de cómo se usa Dynamic (`docs/terminales-mac-mini.md`, `CLAUDE.md`), no de una medición. Antes de bajar la prioridad táctil en un módulo, mide qué dispositivo abre esa ruta.
