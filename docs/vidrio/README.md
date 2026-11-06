# El vidrio en Dynamic: el tablero

Felipe decidió el 2026-11-05 que Dynamic se vea y se mueva como Retail. Este archivo dice **qué módulo va por dónde**. Se revisa en local,
módulo por módulo, y el estreno es uno solo. Referencias: [el plan](https://claude.ai/artifact/5CaaTL9SDeggDvPKu792Ce),
[las maquetas](https://claude.ai/artifact/PAmUFtGYwP2kedJ3FDhecE) y [la revisión técnica](https://claude.ai/artifact/Wyum7sSgUEb1tjfcRariqu).

**La regla de Felipe: nada se sube sin que él lo haya visto en local.** Sus palabras: «una vez que se empiece con el diseño, necesito que todo sea
en local para ir viendo antes de realizar cualquier subida». Se construye en local con commits locales, Felipe lo mira corriendo en su computadora,
se ajusta, y solo con su aprobación se hace `git push` y se abre el PR. También vale para lo que no se ve, como medidores, contrato y vigilante.

**Cómo entra sin frenar el día a día:** lo aprobado se guarda en `main` en cambios chicos, **apagado**. En su computadora está encendido; en
producción, apagado. El día del estreno se enciende un interruptor y todos lo ven a la vez. El terminal tiene el suyo. Una rama larga no
sirve: Dynamic recibe unos 49 commits al día. Ver «El vidrio» en [`CLAUDE.md`](../../CLAUDE.md).

**Para mirarlo en local:** `node scripts/local/web.mjs`. Las cuentas están en [`scripts/local/LEEME.md`](../../scripts/local/LEEME.md).

## Lo decidido, que no se reabre

| Tema | Decisión |
|---|---|
| Aspecto | El de Retail: vidrio, botones en píldora, pestañas en pozo y gota, su cabecera, letra de lectura desde 14 px y cifras que pueden llevar color. |
| Modo oscuro | Los colores de Retail. Arranca en claro y cada quien lo cambia con su botón. `/admin/apariencia` se retira, porque el tema pasa a ser de cada aparato. |
| Lo que no se deshace | Botón negro con el aviso «No se puede deshacer», en una sola hoja de vidrio. También cambia en Retail. Junto a «Guardar», el botón peligroso es gota con letra roja. |
| Boleta, contrato y memo | Papel en su bandeja, en claro y en oscuro. |
| Terminal | Último módulo, con su botón de tema y fuera del loader. Ningún botón cambia lo que hace ni cómo se marca. |
| Movimiento, espera, listas y desenfoque | Como Retail, también en el teléfono. Lo que Retail no tiene se muestra con imagen antes de decidirlo. |
| Barra del teléfono | Como Retail: menú sin relleno y lupa suelta a la derecha. Lo mío conserva la palabra «Menú»: en septiembre, con gente real, el ícono suelto no se encontraba. |
| Guía de foco | Después del aspecto. |
| Cambios futuros | Retail manda. Ver «La regla de los dos sistemas» en `CLAUDE.md`. |

## Etapa 0: preparar

No se ve nada en producción, salvo la firma.

| Pieza | Estado |
|---|---|
| La firma visible en oscuro ([#680](https://github.com/felipea92p-ux/cayla-dynamic/pull/680)) | Publicada; no es parte del rediseño |
| Dynamic en local con login real (`scripts/local/`) | Aprobado por Felipe para subir |
| El interruptor | Aprobado por Felipe para subir, apagado en producción |
| Los medidores de contraste y responsive | Aprobado por Felipe para subir |
| El contrato v4 y el vigilante (`docs/familia/`) | Aprobado por Felipe para subir; el vigilante solo avisa |
| Lado Retail del contrato | Pendiente, en la sesión de Retail |

Felipe lo aprobó el 2026-11-05: cuatro PR separados, cada uno se fusiona con sus pruebas en verde.

**Comprobado con el interruptor encendido y apagado:** 24 capturas de Dashboard, Bandeja, Equipo, Lo mío, ingreso y terminal, en claro y oscuro, a 1440 y 375 px. Salieron 23 idénticas píxel por píxel y una distinta en 1 píxel, el mismo ruido que da la misma pantalla entre dos fotos sin cambiar nada.

**La línea base de los medidores (2026-11-05, con datos inventados):**

| Medidor | Alcance | Resultado |
|---|---|---|
| Contraste a 1440 px | 31 vistas, 6 cuentas | 19 hallazgos, solo en oscuro |
| Contraste a 375 px | 13 vistas, 3 cuentas | 12 hallazgos, solo en oscuro |
| Responsive | 7 pantallas, 49 casos en los 6 anchos | Todo pasa; ninguna página se mueve de lado |

Los hallazgos son un solo defecto: el rojo del oscuro de hoy (`#d4634a`) da 4.28:1 sobre papel y 3.95:1 en el buscador abierto. Los colores de Retail deberían corregirlo; se vuelve a medir en la Etapa 1. **Faltan por medir** 7 de las 14 pantallas registradas y la cuenta de DO.

**Una trampa para la Etapa 1:** `tema:auditar` solo suma colores planos, así que un texto sobre vidrio saldría «bien» con un número que no vale. La columna «Sobre degradado» de su reporte tiene que contar como «sin medir», y esos casos se miden con `tests/vidrio-contraste.test.ts`.

## Etapa 1: lo general

Es lo primero que Felipe revisa. Como casi todo usa estas piezas, al terminar cada pantalla ya se verá en buena parte como Retail.

**Lo que Felipe decidió el 2026-11-05 mirando [las láminas](https://claude.ai/artifact/8ahbY3zPky2HeY5dzemkon):**

| Pregunta | Decisión |
|---|---|
| Menú | Módulos que se abren, como Retail, con Info, Dashboard y Bandeja sueltos arriba. Con un módulo cerrado, sus números suben a su fila. |
| Selector de sede en la cabecera | No por ahora. Líder de equipo e integrante ven su sede como etiqueta; DO y administración, nada. Los filtros siguen dentro de cada pantalla. |
| Saludo y hora | Se van de la cabecera. La hora sube a la línea de arriba del título. |
| «Cerrar sesión» y el nombre | Bajan al pie del menú, en una placa con foto, nombre, rol y sede. Tocarla lleva a Lo mío. |
| Lo mío | Entra en la Etapa 1: misma cabecera y misma placa, con su propio menú. |
| Esquina de las tarjetas | Una sola, de 22 px, en Dynamic y en Retail. |

**Antes de retirar `/admin/apariencia`:** fijar el terminal en claro y limpiar la copia local del tema en cada Mac mini, o se quedan con el último que les llegó.

**Las recetas de vidrio vienen de `main` de Retail, con su bloque para quien pide menos transparencia o más contraste (#1650).** Sus variables viajan; sus reglas, una lista exacta, las escribe `estilos/vidrio/piezas.css` solo para el panel, porque apuntan a clases de Retail. Si Retail cambia esa lista, la copia se detiene y el vigilante avisa.

**`tema:auditar` no alcanza con vidrio:** casi todo el texto va sobre un degradado, y ahí solo suma colores planos. Se mide también con los píxeles de cada pantalla: se saca una captura sin letras y se compara cada texto contra lo que de verdad tiene detrás.

| Pieza | Estado |
|---|---|
| Colores, modo oscuro, fondo y botón de tema | Felipe lo miró y dijo «sigue». Sigue en local |
| Menú de la izquierda: abierto, plegado y cajón del celular | Felipe lo miró y dijo «sigue». Sigue en local |
| Cabecera: buscador, tema, avisos y título de cada pantalla | Felipe lo miró y dijo «sigue». Sigue en local |
| Piezas: botones, campos, listas, hojas, tablas, tarjetas, insignias, avisos, filtros, pestañas y estados vacíos | Felipe lo miró y dijo «sigue». Sigue en local |
| Lo que se mueve: movimiento, loader, «atrás» que cierra la hoja y botones a la vista en hojas largas | En local, esperando que Felipe lo mire |

## Etapa 2: módulo por módulo

Este es el orden. «A mano» es cuántas piezas siguen escritas fuera del sistema, contadas con `receta-suelta`; es una medida aproximada del
trabajo propio de cada módulo. Documentos va antes que Personas y Pago porque los dos lo usan.

| # | Módulo | Pantallas | A mano | Lo que Retail no tiene: se muestra con imagen | 1 Inventario | 2 Aplicar | 3 Medir | 4 Recorrer | 5 Mostrar | 6 Cerrar |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Inicio:** Dashboard y Bandeja | 2 | 7 | Gráficos de jornada y tendencias | | | | | | |
| 2 | **Asistencia:** Incidencias, Correcciones, Turnos, Disponibilidad, Cambios de horario, Horarios, Desempeño y Ausencias | 9 | 4 | Grilla de turnos, calendario y línea del día | | | | | | |
| 3 | **Documentos:** boleta, contrato, memo y bono | Dentro de otras | Exentos | Papel en su bandeja y su impresión | | | | | | |
| 4 | **Personas:** Equipo, ficha, Datos personales, Contratos, Documentación, Seguros, Objetivos, Casos y Disciplina | 12 | 23 | Ficha de la persona y editor de firma | | | | | | |
| 5 | **Pago:** Planilla, Boletas, Provisiones, Costos, Liquidaciones, Educación y Feriados | 8 | 38 | Tablas muy anchas de Planilla | | | | | | |
| 6 | **Publicaciones:** Política salarial, Normas y Anuncios | 9 | 3 | Lectura de documentos y acuses | | | | | | |
| 7 | **Reportes:** Hoja de sede y Exportar | 2 | 3 | Hoja de sede impresa | | | | | | |
| 8 | **Empresa y Configuración:** Archivo, Áreas, Sedes, Cuentas y Parámetros | 6 | 13 | Casi nada | | | | | | |
| 9 | **Entrada:** login, nueva clave y olvidé mi clave | 3 | 4 | Compararlo con «El vuelo vivo» de Retail | | | | | | |
| 10 | **Lo mío:** lo que cada integrante ve en su teléfono | 12 | 46 | Casi todo: Retail no tiene un espacio personal así | | | | | | |
| 11 | **Terminal de marcaje** | 3 | Exento | Casillas, reloj y marcar sin conexión | | | | | | |

Se marca cada casilla con la fecha en que quedó. Un módulo está **Cerrado** cuando tiene las seis.

## Los seis pasos de cada módulo

1. **Inventario.** Todas las pantallas, hojas, pestañas y estados (vacío, error y carga), y qué roles ve cada uno.
2. **Aplicar.** Poner las piezas de Retail y quitar lo escrito a mano. Solo cambia cómo se ve: ningún botón cambia lo que hace, y no se toca planilla, horas ni cálculos.
3. **Medir el responsive y el contraste.** En claro y oscuro, a 375, 768, 1024, 1280, 1440 y 1920 px: `tema:auditar` y `responsive:check`. Cómo se corren: `apps/web/tema/README.md` y `apps/web/responsive/README.md`.
4. **Recorrer como la gente.** Con la cuenta de menor rango y con la de mayor rango, porque suelen fallar cosas distintas.
5. **Mostrárselo a Felipe.** Capturas de antes y después en el chat, y en vivo en su computadora. Si algo no calza con ninguna pieza de Retail, se le pregunta con imagen, con la pieza más cercana al lado. No se inventa.
6. **Cerrar.** Se hacen sus ajustes, se marca aquí y, **solo con su aprobación**, se sube apagado. Antes de eso, nada de `git push` ni de PR.

## Cuándo un módulo «se ve bien»

- La página nunca se desplaza de lado. Una tabla ancha corre dentro de su propio espacio.
- Con el dedo, todo lo que se toca mide 44 px o más. Los campos miden 16 px de letra en el teléfono, para que no se agrande la página.
- En computadora usa todo el ancho. En el teléfono, nada queda tapado por el teclado ni por una barra.
- Texto con 4.5:1 o más y borde de un control con 3:1 o más, en los dos temas. Sobre vidrio se mide con el degradado real.
- Alguien sin formación técnica la entiende sin que le expliquen.
- **Responsive:** se mide en cada parada a 375, 768, 1024, 1280, 1440 y 1920 px. Nada se sale, se corta ni queda apretado, sobre todo el menú, la cabecera y las tablas. Las capturas para Felipe van a 1440 y 375 px, más cualquier ancho donde algo se vea mal.
- **Pocas palabras:** títulos, botones y etiquetas dicen la palabra exacta. Una explicación larga se recorta a una línea a la vista, y lo que de verdad necesite más va detrás del «?» de vidrio. No se tocan los textos de boletas, contratos, memos y bonos ni lo que tenga valor legal, no se quita un aviso que la persona necesita para decidir, como «No se puede deshacer», y no cambia qué hace ningún botón.
- **Los textos recortados se muestran:** en cada parada, Felipe los ve antes y después. Si una palabra deja dudas, se le pregunta con la pantalla a la vista.

## Etapa 3: el estreno

1. Revisión final en local y pruebas completas.
2. Se avisa al equipo con su novedad, se enciende el interruptor y se mira en producción con datos reales.
3. Se comprueba en una tienda real que el terminal marca bien, con su propio interruptor.
4. Cuando pasan unos días sin problemas, se borra el diseño viejo y el interruptor.

## Etapa 4: después

La guía de foco, empezando por solicitudes y contratos, y lo que haya quedado de letra bajo 14 px.

## Riesgos que se miden, no se suponen

| Riesgo | Qué se hace |
|---|---|
| El desenfoque y el loader en un teléfono barato, que se eligieron igual que Retail y no se han medido | Medirlo al revisar «Lo mío», en el teléfono más barato del equipo. Si va a tirones, se le muestra a Felipe: el desenfoque se apaga con una línea. |
| Los datos inventados no muestran todo | Tienen casos extremos, y cada módulo se vuelve a mirar con datos reales el día del estreno. |
| Otras sesiones crean pantallas con piezas viejas | `receta-suelta` sigue activo, y la regla está en `CLAUDE.md`. |
