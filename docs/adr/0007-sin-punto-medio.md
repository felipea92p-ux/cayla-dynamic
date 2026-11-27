# ADR 0007 — Ningún dato se separa con «·»: cada dato va en su pieza

**Fecha:** 2026-11-27. **Estado:** aceptado para Asistencia (muestra); el resto de los módulos espera a que Felipe la mire.
**Decide:** Felipe.

## Lo que se pidió

Felipe, el 2026-11-24, en Retail: dejar de usar «·» como separador, porque «no se ve bien, considero que hay mejores
maneras». La tienda online de Retail ya los quitó todos (cayla-retail#2021, con `apps/tienda/lib/sin-punto-medio.test.ts`).
Retail manda en el diseño (ver `docs/familia/`), así que la regla llega a Dynamic. Al medirlo había unas 670 líneas
visibles con «·» en unos 230 archivos. Felipe eligió empezar por el grupo **Asistencia** del menú como muestra y decidir
después si se sigue.

## La regla

El punto amontona datos distintos en una línea y no da jerarquía. **No se cambia por otro signo** («|», «—», «/»): cada
dato va en su pieza, según qué separa.

| Qué separa | Cómo queda | Ejemplo en Asistencia |
|---|---|---|
| Dos partes de una frase | Coma o «y» | «entró a las 9:12, 14 min tarde»; «sobra 2, meta 3»; «lun a vie 08:30–14:00 y sáb 08:30–14:30» |
| Quién y cuándo (o dónde) | El nombre arriba y la fecha o la sede abajo, en letra chica | Incidencias, Correcciones, Desempeño |
| Un dato con su rótulo | «Rótulo: valor», o el rótulo arriba y el valor abajo | «Motivo: Estudios»; «Descanso: sábado, domingo»; «Personas: estado» |
| Varios valores sueltos (conteos, estados) | Chips o etiquetas, con las piezas que ya hay (`<Insignia>`) | «7 casos» en la cabecera de cada sede |
| Un filtro o un botón con su número | El número aparte, más tenue, como en `<Filtro>` | «Equipo 22», «Lun sin meta» |
| Lo vacío de una tabla | «—», como el resto del sistema | La tabla de metas de Turnos |
| El título de la pestaña del navegador | El único lugar donde va un signo: «\|» | — |

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
