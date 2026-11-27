# ADR 0007 — Ningún dato se separa con «·»: cada dato va en su pieza

**Fecha:** 2026-11-27. **Estado:** aceptado para Asistencia (muestra); el resto de los módulos espera a que Felipe la mire.
**Decide:** Felipe.

## Lo que se pidió

Felipe, el 2026-11-24, en Retail: dejar de usar «·» como separador, porque «no se ve bien, considero que hay mejores
maneras». La tienda online de Retail ya los quitó todos (cayla-retail#2021, con `apps/tienda/lib/sin-punto-medio.test.ts`).
Retail manda en el diseño (ver `docs/familia/`), así que la regla llega a Dynamic. Al medirlo había unas 670 líneas
visibles con «·» en unos 230 archivos. Felipe eligió empezar por el grupo **Asistencia** del menú como muestra y decidir
después si se sigue.

## La regla aprobada: once casos, para Retail y Dynamic

**Aprobada por Felipe el 2026-11-27**, después de pedir que se investigaran «mejores maneras» y no solo quitar el signo.
La propuesta completa, con maquetas y fuentes, está en el artifact «Separar sin punto»
(https://claude.ai/artifact/WXzKXUXxn8wzt17nuib4aH).

**La idea:** antes de separar, preguntar qué relación tienen los datos. Si se pueden decir en voz alta, van en una frase.
Si son atributos sueltos de una misma cosa, van como piezas con espacio. Si son de distinta clase (un nombre y una
cuenta), van en zonas distintas. Un signo entre ellos solo esconde que nadie tomó esa decisión.

**Por qué no otro signo:** los sistemas de diseño grandes (BBC, GOV.UK, Atlassian, Primer, Stripe, Carbon, Fluent) separan
con estructura, no con un carácter. Y un signo se oye distinto en cada lector de pantalla: NVDA calla el «·» sin pausa,
así que «Ana Torres · TRU · lun 3 nov» suena como una sola tira (pruebas de Deque y Eleven Ways, 2023). El «|» igual.

| # | Caso | En lugar del «·» | Ejemplo |
|---|---|---|---|
| 1 | Quién, dónde, cuándo | Frase con la palabra que une («en», «el», «por»); rangos con «de… a…» | «Ana Torres en TRU, el lun 3 nov» |
| 2 | Datos sueltos de una fila | **Línea de datos**: piezas con espacio y **ícono** (decidido), rótulo solo para el lector | `<LineaDeDatos>`: 📍 AQP  💼 Calidad & servicio  ⏳ 1 a. 7 m. |
| 3 | Un nombre y una cuenta | Nombre a la izquierda; la cuenta a la derecha **como frase** (decidido), lo urgente en rojo | «Tienda Arequipa AQP … 7 casos, todos de prioridad alta» |
| 4 | Un dato con su rótulo | Rótulo arriba y valor abajo; en una línea, «Rótulo: valor» | «Sede: todas» |
| 5 | Un valor con una nota | Paréntesis | «llegó 08:50 (plan 08:30)» |
| 6 | Un estado con su tiempo, en una etiqueta | Frase corta | «En pausa hace 12 min» |
| 7 | Una lista armada en código (`join(" · ")`) | «a, b y c» (`Intl.ListFormat`) | «3 negro, 2 beige y 1 crudo» |
| 8 | Un paso numerado | El número como pieza aparte | «4  Precio y cantidad» |
| 9 | Una celda vacía | «—» | — |
| 10 | Un papel que se imprime | Cada dato en su pieza, con espacio | el pie legal de la tienda |
| 11 | El título de la pestaña | «\|», el único signo que queda | «Blusa Emma \| CAYLA» |

**El orden para llevarla:** primero Retail, porque manda en el diseño: la regla y las tres piezas compartidas (línea de
datos, cabecera con cuenta, la lista dicha en castellano). Las piezas viajan a Dynamic por `docs/familia/`, y después se
limpia módulo por módulo en los dos, con la prueba de cada sistema. Para la muestra de Asistencia, las dos primeras piezas
se hicieron en Dynamic (`components/ui/linea-de-datos.tsx` y `cuentaDeCasos` en `lib/admin/incidencias.ts`); la versión
que quede en Retail las reemplaza con la misma forma.

### La primera versión de Asistencia, y por qué cambió

Se hizo dos veces antes de llegar a la regla. La primera puso casi todo con comas y bajó datos a una segunda línea en letra
chica. Felipe pidió decirlo como lo dice la tienda de Retail (palabra que une, paréntesis, dos puntos, piezas con espacio),
y después, al ver «AQP 7 casos» suelto en Incidencias, pidió investigar formas mejores para los dos sistemas. De ahí salió
la tabla de arriba.

La línea de arriba del título (`lib/admin/sobretitulo.ts`) queda en dos piezas: la sección con más peso y el día aparte
(«ASISTENCIA» y «VIERNES, 27 DE NOVIEMBRE, 11:20 A. M.»). En un teléfono, el día baja a su propia línea en vez de partirse
a la mitad. Es compartida por todas las pantallas del panel y se cambió para todas, porque el cambio es igual de bueno en
cualquiera.

## El nombre de las sedes

«Tienda · Trujillo» y «Taller · Lima» pasan a «Tienda Trujillo» y «Taller Lima» (Felipe lo marcó en Incidencias el
2026-11-27). Es el nombre de la sede, no dos datos, y así lo escribe Retail («Pedido de Tienda Trujillo»). Sale de una
sola función, `etiquetaDeSede` (`packages/shared/src/sedes.ts`), así que cambia igual en todo el sistema: cabeceras,
desplegables («Tienda Trujillo (TRU)») y CSV. Nadie partía ese texto por el punto; se comprobó antes de cambiarlo.

## Lo que queda fuera

- **Los comentarios de código y el texto que no se ve.** Ahí el «·» no lo lee nadie.
- **Los documentos legales que se imprimen o descargan** (constancias, boletas, contratos): son papeles y se tratan
  aparte. Asistencia no tiene ninguno.
- **Lo que la base ya guarda con «·»** se lee tal cual (`historial-correcciones.ts` parte `valor_anterior` por « · »
  porque así lo escribe la 0304/0376). Al **mostrarlo**, el libro de correcciones lo dice con coma
  («S/2535.54, version 1»). Cambiar lo que escriben las funciones de la base sería otra migración, y no hace falta para
  la pantalla.

## El freno

`tests/sin-punto-medio.test.ts` lee con el analizador de TypeScript lo que el código **dibuja o escribe** (textos entre
comillas, plantillas y texto de JSX, sin comentarios) en las rutas de cada módulo, y falla si aparece «·», `·` o
`&middot;`. Se comprobó con el control: con la versión vieja de Horarios se pone en rojo en sus cuatro líneas.

- **`MODULOS` es una lista que solo crece.** Para sumar un grupo del menú se agregan sus carpetas y lo que solo él usa.
  Quitar una ruta es apagar el freno para esa pantalla, y la prueba también falla si una ruta deja de existir.
- **La salida legítima** es declarar la línea, en ella o en la de arriba:
  `// punto-medio-permitido: <por qué>`. El motivo es obligatorio. Hoy hay una sola, la lectura de `valor_anterior`.

## Lo que queda pendiente

1. **El resto de los módulos.** Medido el 2026-11-27 con el mismo analizador de la prueba: 693 líneas visibles en 140
   archivos fuera de Asistencia (cuenta también los papeles que se imprimen), entre ellas la bienvenida del ingreso
   («BUENOS DÍAS · VIERNES…»), Bandeja, Pago y «Lo mío».
2. **Lo que escriben las funciones de la base** con « · » (por ejemplo, la liquidación pagada en `correcciones_auditoria`).
   Hoy se muestra con coma en Correcciones; en otra pantalla que lo lea crudo seguiría saliendo el punto.
3. **Lo compartido con otros módulos que no se tocó:** `lib/admin/pruebas.ts` (preselección, también en Equipo, Planilla
   y Contratos), `lib/terminal/ubicacion.ts` (el terminal) y `components/jornada/panel-jornada.tsx` (Dashboard). Entran
   con su módulo.
