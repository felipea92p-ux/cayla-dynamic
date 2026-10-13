# ADR 0004 — Una sola forma para cada pieza del panel

Fecha: 2026-10-13. Estado: **decidido; en implementación** (fundamentos y piloto en el Dashboard;
el resto de pantallas se migra de una en una).

Cómo se decidió: un artefacto con las variantes reales del código, dibujadas con los tokens de
Dynamic, donde se eligió una por familia. Las cantidades salen de buscar clases en el código y
pueden dejar copias sin contar. Nueve de las diez coinciden con la recomendación; la 2 no.

## El problema

El sistema de diseño ya tenía tokens y primitivos (`Boton`, `Insignia`, `Tabla`, `Modal`, `Campo`),
pero varias piezas se seguían escribiendo a mano en cada pantalla: seis formas de «un número y su
etiqueta», cuatro de tabla, cuatro tamaños de título, y unos 130 recuadros de tarjeta contra 9 usos
del componente. Cada copia hereda el margen que le tocó y nadie la ve hasta que se comparan dos
pantallas.

## Las diez decisiones

| # | Familia | Se eligió | Componente |
|---|---|---|---|
| 1 | Cifras e indicadores | Casilla papel, etiqueta arriba, número serif 24 px; activa = borde taupe + fondo hueso | `Cifra` (nuevo) |
| 2 | Color del número | Número siempre tinta; el significado va en un **punto de color** junto a la etiqueta | `Cifra` (`tono`) |
| 3 | Tarjeta | 16 px de margen en celular, 20 px desde 640 px | `TarjetaInfo` |
| 4 | Tabla | La estándar (celdas de 16 px, encabezado normal) | `Tabla` / `Th` / `Fila` |
| 5 | Franjas alternas | **Sin** franjas; línea superior y resalte al pasar el cursor | `Fila` |
| 6 | Título de pantalla | 28 px, peso medio | `CabeceraPagina` |
| 7 | Título de sección | Serif 18 px | `TarjetaInfo` (`titulo`) |
| 8 | Estado vacío | Caja centrada, con una acción cuando haya un siguiente paso | `EstadoVacio` (nuevo) |
| 9 | Avisos | Dos tamaños: con título y en línea | `BannerAviso` (`enLinea`) |
| 10 | Filtros y pestañas | Esquina de botón (8 px), activo en tinta | `Filtro` (nuevo) |

### Lo que se descartó y por qué

- **#1 y #2:** el número gigante de Dashboard e Incidencias (30 y 36 px) pasa a 24 px; se acepta.
  Se descartó el color en el número porque el color solo no comunica a quien no distingue verde
  de rojo, y el rojo es el acento escaso del sistema. La recomendación era «siempre tinta»; se
  eligió además el punto de color, que **no existía en ninguna pantalla**: es diseño nuevo.
- **#3:** un solo valor fijo (16 o 20 px). Se eligió el responsivo porque en «Lo mío» cada tarjeta
  regala 8 px de ancho útil.
- **#5:** las franjas. `Fila` traía tres señales a la vez (franja, línea y resalte) y en modo
  oscuro `--color-hueso` es más negro que la página. No se vio en vivo con datos reales.
- **#10:** la píldora. La píldora queda para las insignias de estado: lo que se toca tiene forma
  de botón y lo que informa tiene forma de píldora.

### SE ROMPE SI

- Una pantalla necesita una cifra más grande que las demás para ser «el número» de la pantalla
  (ver «Fuera de la decisión»): se vuelve a abrir la #1 en vez de agregarle un tamaño a `Cifra`.
- El punto de color se usa solo, sin que la etiqueta diga lo mismo con palabras.
- Alguien agrega una tarjeta, cifra o filtro escrito a mano porque el componente «casi sirve»: el
  componente se corrige, no se copia (el freno en el push está pendiente, PR aparte).

## Excepciones escritas (decididas el 2026-10-13)

- **Franja de cuatro números del Dashboard** (`dashboard/page.tsx`, «resumen»): **no se toca.**
  Es un diseño de celular hecho a propósito —una fila de ~75 px en vez de un 2×2 de ~230 px— y se
  expande para mostrar el detalle. La casilla de `Cifra` en 2×2 le devolvería un cuarto de pantalla.
- **`TileCobertura`** (Dashboard): **no se toca.** Pinta toda la caja según el significado, que la
  decisión #2 descartó para el número. Mismo asunto que la franja.
- Si una tercera pantalla pide lo mismo (una cifra «principal» que no cabe en la casilla), no se
  le agrega un tamaño a `Cifra`: se abre esta decisión de nuevo.

## Pendiente de decidir
- **Incidencias** (franja segmentada con número de 36 px): pasa a `Cifra` con la migración de esa
  pantalla; se anota aquí porque es el cambio visual más grande de la familia.
- **La clase `.etiqueta`** (mayúsculas con espaciado, 46 usos en 26 archivos) no estaba en el
  inventario de la #7. Se decide con otro artefacto antes de tocarla; mientras tanto **no se
  cambia en ningún sitio**: las tres tarjetas del piloto conservan su rótulo.

## Orden de trabajo

1. **Fundamentos + piloto (este cambio):** `Cifra`, `EstadoVacio`, `Filtro`, `BannerAviso`
   (`enLinea`), `TarjetaInfo` responsiva y `Fila` sin franjas. Piloto: las cifras de las tarjetas
   Personal, Pendientes de acción y Casos del Dashboard (con el margen responsivo de la #3, pero
   con su rótulo `.etiqueta` original) y los filtros de «Indicadores».
2. **Freno en el push** (PR aparte, justo después): que un push no pueda agregar la receta suelta
   de tarjeta, cifra o filtro. Solo mira lo que el push agrega, como `reglas-de-la-casa`.
3. **Migración por pantalla**, las más vistas primero, un PR cada una. Horarios (#456) y Turnos
   (#455) tienen PR abiertos: se migran cuando se fusionen.

## Efectos que se sienten en cuanto se fusiona

- `Fila` pierde las franjas alternas en las ~41 tablas que la usan.
- `TarjetaInfo` pasa a 16 px de margen en celular en sus 9 usos.
- `BannerAviso` no cambia salvo que se pida `enLinea`.
