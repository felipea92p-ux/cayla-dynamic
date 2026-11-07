---
name: formidable
description: Lleva una pantalla o un modal de Dynamic al nivel «el iPhone llevado al sistema»: que una integrante o una líder de equipo la entienda en 5 segundos, sin manual, y que además esté impecable y alineada. Califica contra 9 leyes de comprensión y un eje aparte de oficio visual que se mide en el navegador, la hace recorrer a un agente ciego sin contexto, y propone los 3 cambios de mayor impacto antes de tocar nada. Úsala al terminar o rediseñar una pantalla o modal, y cuando Felipe diga «formidable», «no se entiende», «muy cargada» o «que sea como un iPhone». Con `rapido` solo mide.
---

> Adaptada de `formidable` de `cayla-retail` (2026-11-06). Lo que cambió: los protagonistas son la persona, su jornada y su pago; el dispositivo depende de
> la superficie; los ejemplos del piloto de Retail salieron porque eran de sus pantallas; y `/focus` y `/sugerir` no se orquestan porque Dynamic no tiene
> esas guías. Las leyes son las mismas: lo aprobado en Retail manda en el diseño, y lo que nazca aquí se propone primero allá.

Lleva a nivel Formidable: $ARGUMENTS   (una ruta como `/admin/horas`, un modal, un módulo, o sin argumento = lo que estás construyendo)

**Una pantalla Formidable se entiende en 5 segundos sin que nadie la explique: la persona sabe qué es, qué pasa y qué le toca hacer.** Se juzga por lo que la persona **hace**, nunca por si «le gusta». Fundamento y fuentes: `referencia/fuentes.md`.

**Qué dispositivo manda:**

| Superficie | Manda | Cómo se juzga |
|---|---|---|
| Terminal | Mac mini a pantalla completa, 1920 × 1080 | se lee a 1 metro, con prisa, de pie |
| «Lo mío» | celular, 375 × 812 | una mano, con el pulgar |
| Panel | escritorio, 1440 × 900 | mouse y teclado; 1024 y 375 se adaptan |

## Candados (no se negocian)

1. **Presentación y lenguaje: analiza → propone → espera el OK de Felipe → implementa.** Nada cambia sin que lo vea.
2. **Lo de diseño se ve en local antes de subir.** Se construye con `dynamic-local`, con commits locales, y solo con su aprobación se hace `git push`. Lo que venga de vidrio cuelga de `[data-vidrio="panel"]` o `[data-vidrio="terminal"]` y no se imprime.
3. **Las reglas de negocio se pueden proponer con justificación, pero pago, asistencia, disciplina, permisos y documentos legales esperan SIEMPRE a Felipe.** Las reglas de planilla ya decididas no se reabren.
4. **Nunca borra datos ni historial.** Quitar es esconder o mover, y solo si la ley 8 lo prueba.
5. **Respeta los trece tokens y `components/ui`.** Si algo no encaja, se propone un cambio en Retail; no se inventa un estilo local.
6. **Nada optimista en marcajes, pagos ni firmas.** Deshacer vale solo para estado de interfaz.

## Las 9 leyes (el orden es la prioridad cuando dos chocan)

1. **Sin manual.** Alguien nuevo la completa a la primera, sin preguntar a nadie.
2. **Una pregunta, una respuesta.** Un protagonista, una acción principal; lo demás espera.
3. **Simplicidad profunda.** La complejidad real se traduce a un veredicto («va bien», «revísalo»), no se esconde ni se muestra cruda.
4. **Lenguaje de la casa.** «Tú», español neutro peruano, frases cortas, el vocabulario de `CLAUDE.md`; cero jerga interna a la vista.
5. **Contenido primero.** La interfaz se retira: la persona (Equipo), su jornada (Asistencia) y su pago (Planilla) pesan más que los marcos.
6. **Lo difícil, a un toque.** El «¿Por qué?» existe, vive bajo un toque (nunca solo con hover) y no está a la vista por defecto.
7. **Perdonar antes que preguntar.** Se confirma solo lo irreversible; lo reversible ofrece Deshacer.
8. **Quitar antes de agregar.** Si un elemento no ayuda a decidir, se propone esconderlo o quitarlo.
9. **De punta a punta, hasta el último detalle.** Vacíos, errores, primer uso, cargando y modo oscuro se cuidan como la pantalla principal.

Cada ley, con su prueba: `referencia/leyes.md`. **Oficio visual** (eje aparte, nota propia): `referencia/oficio-visual.md` y `referencia/medir-oficio.js`.

## Método (cada paso deja evidencia: **Medido** / **Observado** / **Opinión**; sin evidencia no hay nota)

0. **Terreno.** `git fetch origin`, `./scripts/sesiones.sh`, `docs/vidrio/README.md` (¿ese módulo ya está decidido?) y `docs/pantallas/<slug>.md` si existe. La finalidad sale de `docs/` y del código, nunca de la captura.
1. **Medir.** `preview_start` con `dynamic-local`. `referencia/medir-oficio.js` con `javascript_tool`, primero en el tamaño que manda y luego en los otros dos, en claro y oscuro. Y lo que ya existe: `responsive:check`, `tema:auditar`, `node scripts/rendimiento/ui.mjs --ruta <x>`.
2. **Prueba ciega.** Un agente sin contexto recorre la pantalla; después, si Felipe puede, una persona real: `referencia/prueba-ciega.md`.
3. **Calificar.** 0 a 10 por ley y por oficio. Plantilla: `referencia/informe.md`.
4. **Proponer los 3 cambios de mayor impacto** (no 12), con antes → después, qué ley arreglan y cómo se verifica; una línea de lo que sobra y una de lo que Felipe no pidió y más importa. El resto va a una lista aparte.
5. **Esperar el OK** con `AskUserQuestion`. Con él: implementa, vuelve a medir y entrega capturas antes y después al mismo ancho, con las dos notas.

**Costo: hasta 4 agentes, y dile la escala a Felipe antes de lanzarlos:** medidor, ciego, revisor de leyes y escéptico que intenta refutar cada hallazgo. Con `rapido`: solo el paso 1, sin agentes. Usa `Agent`, no `Workflow`, salvo que Felipe lo pida.

## Antes de decir «listo»

Responde con evidencia: **concurrencia** (dos personas, el mismo registro), **caída** (qué se ve si la base no responde) y **persona sin contexto** (la prueba ciega lo respondió, o dilo: «sin probar»).
