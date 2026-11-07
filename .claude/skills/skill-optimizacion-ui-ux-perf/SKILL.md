---
name: skill-optimizacion-ui-ux-perf
description: Diagnostica cuellos de botella de velocidad percibida en una pantalla, un módulo o todo Dynamic: cascadas de `await`, falta de `Suspense`, JS de cliente excesivo, modales pesados cargados siempre, imágenes sin optimizar y candidatos legítimos a actualización optimista, respetando las reglas del repo. Úsala al construir o revisar una pantalla lenta, antes de dar por terminada una pantalla pesada, o cuando Felipe diga que «se siente lenta».
---

> Adaptada de `skill-optimizacion-ui-ux-perf` de `cayla-retail` (2026-11-06). El escáner vive en `scripts/rendimiento/`. Lo que cambió: casi todas las
> pantallas de Dynamic son cliente y piden datos en el navegador, así que las cascadas del servidor pesan menos y las de `useEffect` más.

Diagnostica la velocidad percibida de: $ARGUMENTS   (una ruta como `/admin/planilla`, un fragmento como `admin` o `mio`, o `todo`)

**Regla madre:** la velocidad percibida se gana con mostrar algo útil pronto y no esperar lo que no hace falta esperar. No se gana con animación ni con otro cargador. Y **se mide antes de optimizar**: este escáner mide estructura; los milisegundos los da el navegador. Solo analizas y propones.

## Reglas del repo que esta skill NO puede contradecir

1. **«Cargando» es `<Cargando />`** (`components/cargando.tsx`); `receta-suelta` frena el texto a mano. Un `Suspense` de sección dentro de la pantalla sí es válido.
2. **Nada optimista en marcajes, planilla, pagos ni firmas.** Son todo o nada: el aviso de éxito sale después de que Postgres confirma. El optimismo vale solo para estado de interfaz: selección, orden, filtros, «marcar visto».
3. **Marcar es instantáneo, y el terminal funciona sin internet.** Cualquier cambio ahí se mide en la Mac mini y sin red.
4. **Todo modal es `<Modal>`** (`components/ui/modal.tsx`): carga diferida con `next/dynamic` sí; otra animación de entrada no.
5. **Colores y piezas: los trece tokens y `components/ui`.** Esta skill no toca estética.

## Paso 1 — Medir la estructura

```bash
node scripts/rendimiento/ui.mjs --ruta <fragmento>   # una pantalla o módulo
node scripts/rendimiento/ui.mjs --top 25             # el ranking
```

Banderas por pantalla: `cascada` (≥ 3 `await` seguidos fuera de `Promise.all`) · `sin-streaming` · `peso-cliente` · `modales-fijos` · `img-cruda` · `img-sin-sizes` · `pagina-cliente` · `sin-loading`. `loading: hereda` **no es problema**. Todas son pistas: **se confirman leyendo la página**.

Medido el 2026-11-06: 68 pantallas, 66 con banderas. Encabezan `/admin/disciplina` (19 `await` seguidos), `/mio` (9 678 líneas de cliente) y `/admin/planilla`. Con 66 de 68, una bandera sola no distingue nada: lo que manda es el Paso 3.

## Paso 2 — Confirmar y clasificar

| Bandera | Cómo se confirma | Cura |
|---|---|---|
| `cascada` | ¿El segundo `await` usa el resultado del primero? Si no, es paralelizable | `Promise.all([...])`; si depende, ¿una sola función SQL que devuelva todo? |
| `sin-streaming` | ¿Qué parte tarda más? | `<Suspense>` solo en esa parte; la cabecera sale primero |
| `modales-fijos` | ¿El modal se ve al cargar? Casi nunca | `next/dynamic(() => import(...))` |
| `peso-cliente` | ¿Qué parte es solo mostrar, sin clic ni estado? | Dejarla como Server Component; `"use client"` solo en la hoja que interactúa |
| `img-cruda` | ¿Dónde está en la pantalla? ¿Es una URL firmada? | `next/image` con `sizes` cuando se pueda |
| `pagina-cliente` | ¿Por qué el `page.tsx` es cliente? | Pasar la lectura al servidor; es un cambio grande: se propone, no se asume |

**Candidatos a optimismo:** para cada uno, escribe «esto es estado de interfaz» o descártalo por la regla 2.

Y lo que el escáner no ve: `useEffect` que piden datos en serie, peticiones repetidas y RPC lentas. Eso se mira con `read_network_requests`.

## Paso 3 — Priorizar por dolor real, no por puntaje

Ordena por: (1) el terminal y marcar, con la fila detrás; (2) «Lo mío» en el celular, con datos móviles; (3) lo que DO usa todo el día y en los días de cierre: Horas, Planilla, Bandeja; (4) el resto. Una pantalla de configuración con `cascada` no es prioridad.

## Paso 4 — Informe

```
### <ruta> — prioridad <alta|media|baja> (quién la usa y cuándo)
- Hallazgo (bandera + archivo:línea):
- Confirmado leyendo: sí/no, y qué vi
- Cambio concreto: <el diff en 5 a 15 líneas>
- Cómo se verifica: <medida antes y después en el navegador; tiempo de la RPC>
- Riesgo: <qué podría romperse>
```

Cierra con la objeción y con lo que no pidió. **Verifica en el navegador antes de afirmar una mejora** (`preview_start` con `dynamic-local`): sin medida es «propuesta», no «mejora». Y recuerda que `scripts/local` no tiene el volumen ni la latencia de producción.
