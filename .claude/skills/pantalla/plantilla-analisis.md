# Plantilla — `docs/pantallas/<slug>.md`

Se lee en el Paso 5 de `/pantalla`. Un archivo por pantalla; en un re-análisis se reescribe el análisis vigente y solo crece la tabla de Historial. Todo dato personal va enmascarado (`[integrante]`, `[DNI]`, `[monto]`). En modo rápido se omiten la sección 9 y el Inventario.

````markdown
# Pantalla — <nombre> (`<ruta>`)

> Modo: completo | rápido · Fecha: AAAA-MM-DD · Rol/sede: … · Datos: producción | local | vacío | sin SQL
> SHA analizado: `<git rev-parse --short origin/main>` — si esos archivos cambian después, este análisis está vencido
> Archivos: `page.tsx` (N líneas, client|server) · componentes · `lib/…` · `fn_*` · tablas
> Otra sesión tocándola: sí (rama …) | no

## 0 · Veredicto
Dos líneas.
**Cumple su finalidad:** N/10 · **Relevancia:** N/10 — Núcleo | Soporte | Comodidad | Prescindible

## 1 · Finalidad declarada
"Esta pantalla existe para …". Fuente: (CLAUDE.md, estado.md, nav-items.ts — no la captura). ¿Docs y pantalla coinciden? sí / no — si no, cuál manda.

## 2 · Objeción
Lo peor, arriba, con su trade-off. O "sin objeción".

## 3 · Lo que está bien y no se toca
- … `[etiqueta]`

## 4 · Las seis dimensiones
| Dimensión | Puntaje | Hallazgo principal | Evidencia |
|---|---|---|---|
| Estética (incluye movimiento y feedback) | | | |
| Lógica de negocio | | | |
| Arquitectura y rendimiento | | | |
| Funciones | | | |
| Utilidad | | | |
| Conexión con el sistema | | | |

Una subsección por dimensión, con las etiquetas `[visto]` `[código archivo:línea]` `[producción]` `[inferido]` `[no verificable]`.

## 5 · Relevancia
| Criterio | Peso | Puntaje | Por qué (una línea) |
|---|---|---|---|
| Gestión (directo + indirecto) | ×2 | | |
| Dinero y obligación legal que toca | ×1 | | |
| Frecuencia y personas que la usan | ×1 | | |
| Qué se detiene si falla | ×1 | | |

Relevancia = (2·G + D + F + P) / 5 = **N**.

## 6 · Conexión con el sistema
- **Aguas arriba:** …
- **Aguas abajo (planilla, boleta, bandeja, disciplina…):** …
- **Módulos vecinos:** …
- **Si Supabase no responde:** «se degrada así, no pierde este dato» …

## 7 · Las 12 tareas, por importancia
### #1 · [Reconstruir | Corregir | Mejorar | Eliminar/fusionar/conectar | Replantear] Título
- **Dónde:** archivo:línea · tabla · `fn_*`
- **Por qué en este puesto:** impacto, riesgo, gestión; qué pasa si no se hace
- **Cómo lo verificas tú:** algo observable
- **Esfuerzo / dependencias:** S | M | L · no antes de la #n
- *(solo estructurales)* **DECIDÍ:** … **DESCARTÉ:** … porque … **SE ROMPE SI:** …

(… hasta la #12. Las de bajo valor, al final y rotuladas.)

## 8 · Estrategia alternativa *(solo si existe)*
Comparación Ganas / Pagas contra la pantalla actual. Decide Felipe.

## 9 · Referentes y futuro *(omitir en rápido)*
Lo que pasó el filtro «¿le sirve a ~30 personas y 4 sedes hoy?» pero es futuro. Marca lo que viene de memoria y no está verificado.

## 10 · Fuera de esta pantalla
La única cosa de mayor consecuencia que nadie preguntó, y por qué.

## 11 · Líneas propuestas para hallazgos-abiertos.md
- [ ] `[pantalla:<slug>]` #n Título — esfuerzo

## Inventario de elementos *(omitir en rápido)*
| Zona | Elemento | Qué hace | Veredicto (bien / ajustar / sobra / falta) | Evidencia |
|---|---|---|---|---|

## Historial
| Fecha | Modo | Cumplimiento | Relevancia | Tareas cerradas de las 12 anteriores |
|---|---|---|---|---|
````
