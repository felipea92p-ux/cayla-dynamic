# Verificación de responsive

Corre en **LOCAL** contra un servidor ya levantado, abre Chrome real con Playwright, navega cada pantalla registrada en los seis anchos de la matriz y mide con
`getBoundingClientRect()` si algo se corta de verdad. No le importa si una fila usa Flexbox o Grid: solo si lo que se dibujó deja algo fuera de alcance. Traída de CAYLA Retail.

Motor genérico (`motor/`) + registro de pantallas (`pantallas/`) + matriz (`matriz-viewports.mjs`). La sesión y el candado que le impide salir de esta computadora son los de
`tema/motor/sesion.mjs`: ver [`tema/README.md`](../tema/README.md). Se corre a mano; no está en el CI.

## Correr

```bash
# con el servidor arriba (si no es el :3000, --base-url o TEMA_BASE_URL)
npx pnpm --filter @cayla-dynamic/web responsive:check dashboard
npx pnpm --filter @cayla-dynamic/web responsive:check dashboard bandeja mio marcar
npx pnpm --filter @cayla-dynamic/web responsive:check --module asistencia
npx pnpm --filter @cayla-dynamic/web responsive:check all
npx pnpm --filter @cayla-dynamic/web responsive:check dashboard --capturas-todas   # guarda también lo que pasa
npx pnpm --filter @cayla-dynamic/web responsive:check dashboard --headed           # Chrome visible, para depurar
```

Salida: `responsive/.salida/<fecha>/` con `reporte.md`, `reporte.json` y `capturas/*.png` (fuera de git; se regenera).

| Sale con | Quiere decir |
|---|---|
| `0` | Todo cabe. |
| `1` | Algo se sale, o una pantalla no se pudo abrir. |
| `2` | **La medición no vale:** no es local, una sesión no entró, la app quiso hablar con otro Supabase, o no se pudo abrir ninguna pantalla. |

Una pantalla que redirige no pasa en verde: es un ERROR. Sin eso, una sesión que no valió mediría el login, y en un formulario de dos campos nada se sale.

## La matriz

Exactamente **375, 768, 1024, 1280, 1440 y 1920 px**, en `matriz-viewports.mjs` y en ningún otro lado. Una pantalla usa la matriz entera si no dice nada,
`viewports: ["375x812", "768x1024"]` para esos ids, o `viewports: { excluir: ["375x812"] }` para la matriz menos esos. A 375 px se emula un celular de verdad: pantalla táctil
y `isMobile`.

## Registrar una pantalla

Una pantalla sin nada especial es una línea en `pantallas/registro.mjs`:

```js
{ id: "planilla", nombre: "Planilla", ruta: "/admin/planilla", cuenta: "do" },
```

Eso basta para `responsive:check planilla`, con un único escenario «inicial» sobre toda la matriz. `cuenta` es una clave de `tema/cuentas.mjs`. El módulo no se escribe: sale de
la ruta, y el id completo queda `pago.planilla`. Se puede pedir por `planilla` si no hay otra que se llame igual.

Hay al menos una por módulo de la obra (`entrada`, `inicio`, `asistencia`, `documentos`, `personas`, `pago`, `publicaciones`, `reportes`, `empresa-y-configuracion`, `lo-mio`,
`terminal`), y `/mio` además con las cuentas de nombre largo y sin datos, que es donde una caja se rompe.

## Escenarios

Una pantalla con escenarios vive en su propio archivo y se importa en el registro. El ejemplo es `pantallas/inicio.dashboard.mjs`: abre el buscador en todos los anchos y el menú
solo donde es un cajón. Un escenario que solo existe en un ancho lo declara con `viewports`: si corriera en los otros, repetiría el estado inicial y sumaría verdes que no midieron nada.

```js
escenarios: [
  { id: "inicial", nombre: "Estado inicial" },
  {
    id: "menu",
    nombre: "El menú del celular abierto",
    viewports: ["375x812"],
    async preparar(pagina) {
      await pagina.getByRole("button", { name: "Abrir menú", exact: true }).click();
    },
  },
],
```

Si un escenario necesita un estado, lo arma con clics en su `preparar`; no depende de que exista una fila concreta por azar.

## Cómo decide

- **Lo que decide es el elemento que se sale.** Por cada elemento clave compara su rectángulo contra el viewport, con 1 px de tolerancia. Claves por defecto (`SELECTORES_POR_DEFECTO`
  en `motor/deteccion.mjs`): botones, enlaces, campos, `h1`-`h3`, `label`, `dl` y `[data-critico]`. Una pantalla suma más con `elementosClave: [...]`.
- **«La página se mueve de lado» es una señal, no un veredicto.** Se anota en el reporte cuando `scrollWidth` supera al ancho, pero no da FAIL por sí sola.
- **Scroll horizontal legítimo:** lo que vive dentro de un contenedor con `overflow-x: auto|scroll` que de verdad desborda se salta: se llega desplazando ESE contenedor. El contenedor
  mismo sí se compara.
- **Límite propio:** `limite: "<selector>"` compara contra ese elemento en vez del viewport, y `ambito: "<selector>"` acota qué subárbol se recorre. Sirve para mirar solo un modal.

## Lo que NO ve

Que pase quiere decir una sola cosa: ningún elemento clave se sale de la pantalla por los lados. **No** quiere decir que se vea bien. No ve un texto cortado dentro de una caja
con `overflow: hidden` o con puntos suspensivos, ni dos cosas encimadas, ni lo que se sale por abajo, ni una tabla cuya columna importante solo aparece desplazando. Para eso, las
capturas (`--capturas-todas`) y mirar.

## Exclusiones

Un elemento se salta si está oculto, o si cuelga de `[aria-hidden="true"]`, `[hidden]`, `[data-state="closed"]`, `[inert]` o `[data-fuera-de-pantalla]`. Para algo que SIEMPRE está
fuera de pantalla por diseño, ese último atributo va en el componente. Para algo de una sola pantalla, `exclusiones: ["<selector>"]` en su registro.

## El caso que debe fallar

Un freno se prueba con algo que debe bloquear:

```bash
npx pnpm --filter @cayla-dynamic/web responsive:check debe-fallar   # tiene que dar FAIL y salir con 1
npx pnpm --filter @cayla-dynamic/web medidores:autoprueba           # el detector, sin servidor
```

## Si algo da raro

Lo mismo que en `tema/README.md`: la primera corrida tarda porque `next dev` compila cada ruta, y todas las pantallas juntas dejan ~10 GB de caché en `apps/web/.next`. Seis anchos no
compilan seis veces: lo que multiplica es la cantidad de rutas distintas.
