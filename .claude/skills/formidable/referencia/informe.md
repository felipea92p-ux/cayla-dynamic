# Plantilla del informe de Formidable

El informe va al chat. Solo si Felipe lo pide se guarda en `docs/pantallas/<slug>-formidable.md` (el `<slug>` es la ruta sin barras: `admin-horas`), sin datos personales: el repo es público. **Si el archivo ya existe es un re-análisis:** léelo, agrega una fila al historial y marca cuáles de los 3 cambios anteriores se cerraron.

**Ningún hallazgo entra sin el veredicto del escéptico** (CONFIRMADO / MATIZADO / REFUTADO / NO VERIFICABLE). Los refutados se listan aparte con la razón: en el piloto
de Retail cayeron o se achicaron 7 de 14.

Cada afirmación lleva su etiqueta: **[Medido]** (script, DOM, código) · **[Observado]** (prueba ciega o persona real) · **[Opinión]** (criterio del
revisor). Nunca las mezcles. Una nota sin evidencia no se pone.

```markdown
# Formidable · <Módulo ▸ Pantalla>   (<ruta>)

- **Fecha / SHA:** AAAA-MM-DD · <git rev-parse --short HEAD>   · **Dispositivo que manda:** terminal · celular · escritorio
- **Pregunta que debería resolver (1 frase):** …            · **Protagonista:** la persona / la jornada / el pago / lo que me toca hoy
- **Veredicto en una línea:** «Se entiende en N s y le falta X.»

## Notas (0–10)
| Eje | Nota | Evidencia |
|---|---|---|
| 1 Sin manual | | [Observado] ciego: …  · real: sin probar |
| 2 Una pregunta, una respuesta | | |
| 3 Simplicidad profunda | | |
| 4 Lenguaje de la casa | | |
| 5 Contenido primero | | |
| 6 Lo difícil, a un toque | | |
| 7 Perdonar antes que preguntar | | |
| 8 Quitar antes de agregar | | |
| 9 De punta a punta | | |
| **Leyes (promedio)** | | |
| **Oficio visual** | | [Medido] N comprobaciones fallan (lista) |

## Los 3 cambios de mayor impacto
Cada uno: **Antes → Después**, **ley que arregla**, **cómo se verifica**, **esfuerzo** (S/M/L) y **quién decide** (presentación: Felipe da el OK;
regla de negocio: marcar si toca pago, asistencia, disciplina, permisos o documentos legales → OK obligatorio).
1. …
2. …
3. …

## Lo que sobra (ley 8)
Una línea por elemento que no ayuda a decidir, con el porqué. Se **propone** esconder o quitar de la vista; nunca borrar datos.

## Lo que no pediste y importa más
Una sola cosa, la de mayor consecuencia, con su porqué.

## Lista aparte (no se ejecuta)
El resto de hallazgos, ordenados. No se hace nada de aquí sin que Felipe lo mande.

## Prueba ciega
Tabla de `prueba-ciega.md` (5 s, primer intento, pasos, dudas, palabras no entendidas, errores). Palabra textual de las dudas.

## Antes de decir «listo»
- Concurrencia: …  · Caída: …  · Persona sin contexto: …

## Historial
| Fecha | SHA | Leyes | Oficio | Cambios cerrados |
|---|---|---|---|---|
```

## Cómo se pone la nota de una ley
- **10** = la prueba pasa sin excepciones y hay evidencia **[Observado]** o **[Medido]**. **7–9** = pasa con fallas menores listadas. **4–6** = falla
  en una parte visible. **0–3** = falla en lo esencial. Sin evidencia: «sin probar», no un número.
- La ley 1 nunca pasa de 8 sin la pasada con una persona real.
- El promedio de leyes no se redondea hacia arriba: si hay una ley en 3, el informe lo dice en la primera línea aunque el promedio sea 7.
