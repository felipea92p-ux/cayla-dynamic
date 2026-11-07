# Oficio visual: el eje que se mide, no se opina

«Estética impecable, visual y alineada» deja de ser gusto cuando se convierte en cosas que el navegador puede medir. Este eje tiene **su propia nota de 0 a 10**, separada de las 9 leyes: una pantalla puede ser clara y estar mal alineada, o preciosa e incomprensible.

**Cómo se mide:** pega `medir-oficio.js` en `javascript_tool` con la pantalla cargada y el panel visible (oculto mide 0). Empieza por el tamaño que manda según la superficie (ver `SKILL.md`).

| # | Comprobación | Umbral | Evidencia |
|---|---|---|---|
| 1 | **Blancos con mouse.** Excepción: un enlace o botón en línea dentro de una frase no cuenta | ≥ 24 × 24 px; objetivo **32 px** de alto en filas | Verificado, WCAG 2.2 · 2.5.8 (AA) |
| 2 | **Blancos con dedo** (`pointer: coarse`, «Lo mío») | ≥ **44 × 44 px** | Verificado, guías de Apple para iOS |
| 3 | **Contraste del texto** contra su fondo real | ≥ 4,5 : 1 (texto grande ≥ 3 : 1) | Verificado, WCAG 1.4.3 |
| 4 | **Contraste de controles y del foco** | ≥ 3 : 1 | Verificado, WCAG 1.4.11 |
| 5 | **Foco visible** con Tab, en todo control | visible siempre (WCAG 2.4.7, AA) | Verificado |
| 6 | **Texto mínimo** | nada que importe bajo 12 px; cuerpo de 14 px o más. En el terminal, que se lea a 1 m | Opinión |
| 7 | **Alineación:** bordes que casi coinciden | un desvío de 1 a 3 px falla | Medido |
| 8 | **Espaciado** entre bloques hermanos | múltiplos de 2 px; impares o fraccionarios fallan | Medido |
| 9 | **Jerarquía tipográfica** | ≤ 4 tamaños visibles; el título es el más grande | Opinión |
| 10 | **Radios y alturas** | misma altura en una fila; ≤ 3 radios por pantalla | Medido |
| 11 | **Color** | solo los trece `--color-*`; **rojo ≤ 2 por pantalla** («acento sagrado» en `globals.css`) | Medido y lectura |
| 12 | **Teclado** | Tab en orden visual; Enter confirma, Esc cierra | Observado |
| 13 | **Piezas** | `components/ui` y no recetas a mano (`RECETA_TODO=1 RECETA_RESUMEN=1 python3 scripts/hooks/receta-suelta.py`) | Medido |

Los documentos `.hoja` y la vista previa de la firma tienen excepciones: léelas en `CLAUDE.md` antes de marcar un color suelto.

## Cómo se califica

- Cada fila se marca pasa, falla o no aplica. La nota es `10 × pasa / (pasa + falla)`, redondeada, **con la lista de qué falló**.
- Un **blocker** (texto bajo 3 : 1, un blanco menor a 24 px que lleva a una acción irreversible, foco invisible) baja la nota a un máximo de 5.
- **Lo global** (menú, buscador, cabecera) se reporta aparte y no baja la nota de la pantalla: se arregla una vez para todas.
- Los tamaños que no mandan se miden siempre, pero pesan menos.

## Lo que este eje NO decide

Los tokens y las piezas no se negocian aquí. Si una comprobación choca con un token, **no se cambia el token**: se reporta y se propone en Retail, que manda en el diseño.
