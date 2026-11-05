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
| Guía de foco | Después del aspecto. |
| Cambios futuros | Retail manda. Ver «La regla de los dos sistemas» en `CLAUDE.md`. |

## Etapa 0: preparar

No se ve nada en producción, salvo la firma.

| Pieza | Estado |
|---|---|
| La firma visible en oscuro ([#680](https://github.com/felipea92p-ux/cayla-dynamic/pull/680)) | Aprobada por Felipe, no es parte del rediseño |
| Dynamic en local con login real (`scripts/local/`) | En local, esperando su OK |
| El interruptor | En local, esperando su OK |
| Los medidores de contraste y responsive | En local, esperando su OK |
| El contrato v4 y el vigilante (`docs/familia/`) | En local, esperando su OK |
| Lado Retail del contrato | Pendiente, en la sesión de Retail |

Al terminar la Etapa 0 se le muestra Dynamic corriendo en local y se le pide el OK para subirla.

## Etapa 1: lo general

Es lo primero que Felipe revisa. Como casi todo usa estas piezas, al terminar cada pantalla ya se verá en buena parte como Retail.

| Pieza | Estado |
|---|---|
| Colores, modo oscuro, fondo y botón de tema | Pendiente |
| Menú de la izquierda: abierto, plegado y cajón del celular | Pendiente |
| Cabecera: buscador, tema, avisos y título de cada pantalla | Pendiente |
| Piezas: botones, campos, listas, hojas, tablas, tarjetas, insignias, avisos, filtros, pestañas y estados vacíos | Pendiente |
| Lo que se mueve: movimiento, loader, «atrás» que cierra la hoja y botones a la vista en hojas largas | Pendiente |

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
3. **Medir el responsive y el contraste.** En claro y oscuro, a 375, 768, 1024, 1280, 1440 y 1920 px: `tema:auditar` y `responsive:check`.
4. **Recorrer como la gente.** Con la cuenta de menor rango y con la de mayor rango, porque suelen fallar cosas distintas.
5. **Mostrárselo a Felipe.** Capturas de antes y después en el chat, y en vivo en su computadora. Si algo no calza con ninguna pieza de Retail, se le pregunta con imagen, con la pieza más cercana al lado. No se inventa.
6. **Cerrar.** Se hacen sus ajustes, se marca aquí y, **solo con su aprobación**, se sube apagado. Antes de eso, nada de `git push` ni de PR.

## Cuándo un módulo «se ve bien»

- La página nunca se desplaza de lado. Una tabla ancha corre dentro de su propio espacio.
- Con el dedo, todo lo que se toca mide 44 px o más. Los campos miden 16 px de letra en el teléfono, para que no se agrande la página.
- En computadora usa todo el ancho. En el teléfono, nada queda tapado por el teclado ni por una barra.
- Texto con 4.5:1 o más y borde de un control con 3:1 o más, en los dos temas. Sobre vidrio se mide con el degradado real.
- Alguien sin formación técnica la entiende sin que le expliquen.

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
