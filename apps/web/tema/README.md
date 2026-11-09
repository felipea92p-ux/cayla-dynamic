# Auditoría de contraste

Corre en **LOCAL** contra un servidor ya levantado, abre Chrome real con Playwright, entra con cada cuenta, recorre las pantallas en claro y en oscuro, **mide** y
deja un reporte con capturas. Hermana de `responsive/`: mismo Playwright, misma sesión, misma idea de medir el DOM en vez de mirar. Traída de CAYLA Retail.

Lo que encuentra no se arregla en automático ni frena nada: es un medidor que se corre a mano. Ninguna de estas herramientas está en el CI.

## Qué mide

| Detector | Qué es | Por qué importa |
|---|---|---|
| **Contraste** | El contraste WCAG de cada texto contra su fondo REAL, compuesto capa por capa con su transparencia: mínimo 4.5:1, 3:1 si es grande. Un símbolo que el código le ocultó al lector (`aria-hidden="true"`) y que no tiene letras ni dígitos («›», «·», «×») es un **gráfico**: se mide contra 3:1 (WCAG 1.4.11). Una tecla (`<kbd>`) sigue siendo texto. Los controles deshabilitados quedan exentos. | Un texto que se pierde en un tema. |
| **Mancha clara** | Solo en oscuro: una superficie grande y opaca que sigue clara y no es un token del sistema. También una **tarjeta invertida** (`bg-tinta`, que en oscuro es casi blanca) desde 30 000 px², y una tarjeta de **vidrio** clara: lee el degradado con que el vidrio la pinta. Un botón invertido no cuenta, y la crema fija (la firma) tampoco. | Un `bg-white` o un hex que no cambió con el tema, o un bloque que encandila aunque sea un token (Provisiones, 2026-11-09). |
| **Velo claro** | Solo en oscuro: una capa fija que cubre la pantalla y la **aclara** en vez de oscurecerla. | Un `bg-tinta/30` que se volvió crema. |

Cada pantalla se mide en **los dos temas** y el reporte separa lo que falla solo en oscuro, solo en claro o en los dos: lo de un solo tema suele ser un token de ese
tema. Retail solo daba por hallazgo lo de oscuro porque su obra era el modo oscuro; aquí un texto ilegible en claro también cuenta. El reporte agrupa además **los pares
de color que más fallan**, porque casi siempre se arreglan en un token y no pantalla por pantalla.

### Lo que es claro a propósito

Lo dice `app/globals.css`, y la mancha clara lo respeta:

- El recuadro de la firma: `.firma-tinta`. La imagen de `.contrato .linea img` ya queda fuera por ser una imagen.
- El recuadro con `--color-crema-fija`: pasa por ser un token del sistema, como cualquier relleno que use uno.

Lo de `.firma-tinta` no cuenta como hallazgo, pero **se anota aparte** en el reporte en vez de callarlo.

**Los documentos (`.hoja`, `.contrato`) ya no son excepción.** Hasta el 2026-11-09 se anotaban aparte, porque con el vidrio el papel se quedaba claro
también en oscuro. Ese día Felipe decidió que el papel siga el tema en pantalla, con y sin vidrio (`piezas.css`, «El papel en su bandeja»): una superficie
clara dentro de un documento es ahora un defecto como cualquier otro.

### Lo que este escáner NO ve

- **Degradados e imágenes.** Solo suma colores planos. El reporte cuenta cuántos textos no pudo medir de verdad, en la columna «Sobre degradado», incluida una letra recortada
  de un degradado (`background-clip: text`, el «transforma.» del login). Esos los mide `tests/vidrio-contraste.test.ts` con `contraste-calculado.ts`, sobre el CSS: 4.5:1 para
  la letra y 3:1 para el borde de un control, en los dos temas.
- **Marcadores de posición (`::placeholder`) e íconos** (SVG, máscaras): solo mide nodos de texto.
- **`backdrop-filter`.** El vidrio desenfoca lo de atrás; aquí se compone como si fuera transparente.

## Correr

```bash
# con el servidor arriba (si no es el :3000, --base-url o TEMA_BASE_URL)
npx pnpm --filter @cayla-dynamic/web tema:auditar --cuenta admin --ruta /admin/dashboard,/admin/bandeja
npx pnpm --filter @cayla-dynamic/web tema:auditar --cuenta integrante                         # su pantalla de inicio
npx pnpm --filter @cayla-dynamic/web tema:auditar --cuenta admin,lider --modulo asistencia
npx pnpm --filter @cayla-dynamic/web tema:auditar --cuenta admin --ruta /admin/dashboard --escenarios   # + modales y cajones
npx pnpm --filter @cayla-dynamic/web tema:auditar --ancho 375 --alto 812 --cuenta integrante  # celular
npx pnpm --filter @cayla-dynamic/web tema:auditar --listar                                    # cuentas, rutas por módulo, escenarios
```

Salida: `tema/.salida/<fecha>/` con `reporte.md`, `reporte.json` y `capturas/<cuenta>/*.png` (fuera de git; se regenera).

| Sale con | Quiere decir |
|---|---|
| `0` | Se midió y no hay hallazgos. |
| `1` | Hay hallazgos, en cualquiera de los dos temas. |
| `2` | **La medición no vale:** no es local, una sesión no entró, la app quiso hablar con otro Supabase, o no se pudo medir ninguna pantalla. Cero hallazgos sin haber medido no es un verde. |

Usa el Chrome del sistema (`channel: "chrome"`). Para otro navegador: `NAVEGADOR_CANAL=chrome-beta`.

## Solo contra esta computadora

- Se niega a una app o a una API que no estén en `http://localhost`, `127.0.0.1` o `[::1]`.
- Una app en localhost podría estar configurada contra el Supabase de producción, y eso una URL no lo muestra. Por eso **el navegador tiene la red cerrada**: todo pedido a
  otro host se aborta sin salir, y si era un Supabase u otro puerto local la medición sale con `2`.
- Las cuentas y su clave son del entorno local, con datos inventados. La sesión se pide a la API local y **no se guarda en disco**.

La API se toma de `--api-url` o `TEMA_API_URL` (por defecto `http://127.0.0.1:55892`, el entorno de `scripts/local`). Con `supabase start`, además, la llave anónima en
`TEMA_ANON_KEY`.

## Las cuentas (`cuentas.mjs`)

| Clave | Quién |
|---|---|
| `anonima` | Sin sesión: las pantallas de entrada |
| `admin` | Admin: ve todo el panel |
| `do` | Desarrollo Organizacional |
| `lider` | Líder de equipo: el panel de su sede |
| `integrante` | Integrante: Lo mío y las publicaciones |
| `nombre-largo` | Integrante con un nombre muy largo |
| `sin-datos` | Integrante recién llegada: las pantallas vacías |
| `terminal-tru` | El terminal de Trujillo, con su propia sesión (`cayla-auth-terminal`) |

Una ruta fuera del alcance de una cuenta no se visita. Una que sí es suya y la manda a otra pantalla queda «sin medir»; si la manda a una entrada, la sesión no valió y la
corrida sale con `2`.

## Módulos (`motor/rutas.mjs`)

Las rutas salen de las carpetas de `app/` y los grupos del menú real (`nav-items.ts`): una pantalla nueva entra sola. Módulos: `entrada`, `inicio`, `asistencia`, `documentos`,
`personas`, `pago`, `publicaciones`, `reportes`, `empresa-y-configuracion`, `lo-mio`, `terminal`, y `fuera-del-menu` para lo que no cuelga de ningún renglón.

## Escenarios (`escenarios/registro.mjs`)

Lo que no se ve al cargar —un modal abierto, el cajón del celular, el buscador— se audita con un escenario: `{ id, ruta, nombre, preparar(pagina), abre }`. La forma completa
está en la cabecera del archivo. Son pocos a propósito: **cada obra agrega los de lo que toca.** Se corren con `--escenarios` (los de las rutas elegidas) o `--escenario <id>`.

Una pantalla con parámetro (`/admin/personas/[id]`) también se mide por escenario: se llega a ella con clics, no con un id escrito a mano.

## Los colores sueltos (`colores-sueltos.mjs`)

```bash
npx pnpm --filter @cayla-dynamic/web tema:colores            # los archivos y cuántos
npx pnpm --filter @cayla-dynamic/web tema:colores --lineas   # además, cada línea
```

**Solo informa, y no tiene prueba que falle.** En Retail es un candado en el CI; aquí Dynamic ya tiene su regla (CLAUDE.md: solo los `--color-*` de `globals.css`) y una deuda
vieja, y un freno que falla el primer día se aprende a ignorar. Cuenta aparte las clases de la paleta de Tailwind, que son lo que la regla prohíbe, y los colores crudos (hex,
`rgb()`), que no siempre son defecto. No cuenta `bg-black/NN`, el velo de un modal, que CLAUDE.md pide así.

## La autoprueba

```bash
npx pnpm --filter @cayla-dynamic/web medidores:autoprueba
```

Un freno se prueba con un caso que debe bloquear. Esta da a cada detector una página de mentira con defectos y excepciones conocidos, y exige que encuentre **exactamente**
esos. No toca ningún servidor. **Córrela después de cambiar `motor/escaner-en-pagina.js` o `responsive/motor/deteccion.mjs`.** Y para probar el camino completo, contra el
servidor: `tema:auditar --escenario prueba.debe-fallar` tiene que salir con `1`.

## Si algo da raro

- **El disco se llena.** Compilar todas las pantallas en desarrollo deja ~10 GB de caché de Turbopack en `apps/web/.next`. Para una corrida con `--todas`, prueba primero con
  pocas rutas, o apaga la caché en disco solo mientras corre (`experimental.turbopackFileSystemCacheForDev: false` en `next.config.ts`, sin commitear).
- **La primera corrida tarda.** `next dev` compila cada ruta la primera vez.
- **«Seguía en Cargando…»** La pantalla no terminó de cargar en 45 s, y no se midió: medir el colibrí daría un verde falso.
- **«No entró …»** La cuenta no existe en la base local, o la clave no es esa (`TEMA_CLAVE_LOCAL`).
- **Abrir una pantalla la ejecuta.** El medidor no hace clics salvo en un escenario, pero lo que una pantalla haga sola al abrirse pasa de verdad en la base local.
