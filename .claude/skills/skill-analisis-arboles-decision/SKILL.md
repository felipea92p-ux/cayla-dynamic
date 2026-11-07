---
name: skill-analisis-arboles-decision
description: Evalúa la complejidad de la lógica condicional de un archivo, un módulo o todo `apps/web/lib`: profundidad excesiva, escaleras if/else-if, condiciones reevaluadas y falta de salida temprana, y propone el aplanado concreto (guardas, tabla de decisión, condición nombrada). Úsala al tocar o revisar una función con muchos `if`, como las de la Bandeja, incidencias o `jornada-esperada.ts`, o cuando Felipe pregunte por qué una regla es difícil de seguir o de probar. Mide forma (mantenimiento y corrección), no milisegundos.
---

> Adaptada de `skill-analisis-arboles-decision` de `cayla-retail` (2026-11-06). El escáner vive en `scripts/rendimiento/`, igual que allá. Lo que cambió:
> el árbol que más importa aquí es `fn_planilla_calcular`, que el escáner no ve.

Analiza la lógica condicional de: $ARGUMENTS   (un archivo, un directorio o `todo`)

**Regla madre:** con cuatro sedes y unas 30 personas, evaluar 40 reglas cuesta microsegundos. **No se propone un refactor «para que sea más rápido».** El único argumento válido es corrección y mantenimiento: una escalera de 12 `else if` es donde nace el caso que nadie probó, y aquí ese caso es una falta mal contada o un pago mal hecho. Solo analizas y propones; ejecutar es un paso aparte que Felipe ordena.

## Paso 1 — Medir

```bash
node scripts/rendimiento/arboles.mjs --archivo lib/<x>.ts              # un archivo
node scripts/rendimiento/arboles.mjs --dir apps/web/lib --top 20       # el ranking
node scripts/rendimiento/arboles.mjs --dir packages/shared/src --top 20
```

Si el worktree no trae dependencias, el escáner toma `typescript` del checkout principal. Por función da **CC** (complejidad ciclomática), **prof** (anidamiento), **escalera** (largo de la cadena `if/else if`) y banderas: `compleja` (CC ≥ 15) · `profunda` (≥ 4 niveles) · `escalera` (≥ 5 eslabones) · `reevalua` (la misma condición dos o más veces) · `sin-guardas` (CC ≥ 10 y ningún `if (…) return` de primer nivel) · `else-sobra` · `ternario-anidado`. Es AST pero no sabe de negocio: **cada bandera se confirma leyendo la función**.

Medido el 2026-11-06: 170 archivos de `apps/web/lib`, 60 funciones con banderas. Encabezan `armarBandeja` (CC 152), `armarPendientes` (76) y `detectarIncidencias` (62). Una CC alta en una función que solo arma una lista larga de casos paralelos puede no ser un problema: se lee antes de opinar.

## Paso 2 — Diagnóstico por función

| Síntoma | Pregunta que lo confirma | Cura |
|---|---|---|
| `profunda` | ¿Se puede descartar el caso raro ANTES del camino feliz? | **Cláusulas de guarda** arriba; el camino feliz queda sin sangría |
| `escalera` | ¿Cada eslabón compara el mismo sujeto con un valor distinto? | **Tabla de decisión** `[{ cuando, entonces }]` recorrida con `find` |
| `reevalua` | ¿La condición repetida es la misma regla de negocio o coincidencia? | Calcular una vez y **nombrarla** |
| `sin-guardas` | ¿Qué entradas son imposibles o triviales? | Salir temprano, no al final de un `else` gigante |
| `else-sobra` | ¿La rama `if` ya termina en `return` o `throw`? | Quitar el `else` y aplanar |
| `ternario-anidado` | ¿Se lee en voz alta sin perderse? | Sacar a función con nombre o tabla |

**Reordenar por frecuencia solo se propone con datos reales** de qué rama se ejecuta. Si no los hay, dilo en vez de adivinar.

## Paso 3 — Lo que el escáner no ve (decláralo siempre)

- **Las funciones de Postgres.** El árbol real del pago vive en `supabase/migrations/*.sql`: `fn_planilla_calcular` pesa más de 90 000 caracteres. Si la pantalla solo llama una RPC, el árbol está allá. Léelo con `./scripts/donde-vive.sh`, y lee `docs/planilla-anexo-tecnico.md` antes de opinar.
- **Las pruebas.** Un refactor de árbol solo es seguro si la prueba recorre cada rama. Comprueba que `tests/` o `supabase/tests/` cubre todas las salidas; si no, **el primer paso es escribir esa prueba**.
- **La regla escrita.** Una cascada con un orden raro puede ser un orden de negocio: la de *turno del día → `horario_por_dia` → `dias_laborables`* decide si a alguien se le cuenta una falta. Busca el término en `docs/` y en los comentarios de la migración antes de reordenar.

## Paso 4 — Informe

Por cada función confirmada, máximo 12, ordenadas por lo que se arriesga:

```
### <función> — <archivo:línea>   CC <n> · prof <n> · escalera <n>
- Problema (con la bandera y la línea):
- Refactor concreto: <el código resultante en 5 a 15 líneas, o la tabla>
- Prueba que lo protege: <cuál existe / cuál falta>
- Riesgo: <qué cambiaría de comportamiento si se hace mal>
- Ganancia: mantenimiento | corrección | (velocidad: solo si hay medición)
```

Cierra con el trabajo, **la objeción** (qué de lo pedido no vale la pena) y **lo que no pidió** (lo de mayor consecuencia que apareció).

**No hagas:** reordenar sin frecuencia medida · «optimizar» una regla con este volumen · tocar un cálculo de planilla sin auditarlo en `BEGIN … ROLLBACK` · escribir una quinta copia de «qué le tocaba trabajar ese día».
