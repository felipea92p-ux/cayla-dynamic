# La familia CAYLA, vista desde Dynamic

Felipe decidió el 2026-11-05: **Retail manda en diseño, y lo que cambie allá llega a Dynamic.** Esta carpeta es la mitad de esa regla que vive en este
repositorio. La mitad de Retail está en su `docs/familia/README.md`.

| Dónde | Qué es |
|---|---|
| `docs/familia/contrato.json` | Lo que es igual en las dos aplicaciones. El mismo archivo, byte por byte, en los dos repositorios. |
| `docs/familia/deuda.json` | Lo que Dynamic todavía no cumple de ese contrato, valor por valor. Solo baja. |
| `docs/familia/compartidos.json` | Qué archivos de Retail le tocan a Dynamic, con la huella de la última versión tomada. |
| `tests/familia.test.ts` | Mide cada valor del contrato contra `globals.css`: cumple, o está en la deuda. |
| `scripts/familia/vigilante.mjs` | Compara con Retail cada hora. |
| `scripts/familia/envolver-recetas.mjs` | Convierte `recetas.css` de Retail en algo que no le haga nada a Dynamic con el vidrio apagado. |
| `tests/familia-vigilante.test.ts` | Prueba los dos scripts sin red, sobre todo los casos que deben frenar. |
| `.github/workflows/vigilante-familia.yml` | La Action que llama al vigilante. Solo existe en GitHub cuando Felipe apruebe subirla. |

## Qué cambió en la versión 4 del contrato

| | Versión 3 | Versión 4 (lo que pinta Retail, medido el 2026-11-05) |
|---|---|---|
| Control | 8 px | Botón **999 px**, campo **14 px** |
| Superficie | 16 px | Tarjeta **22 px**, una sola en los dos sistemas (P10; Retail hoy pinta 20, 22 y 24) |
| Flotante | 20 px | Cajón **28 px**, hoja **32 px** (26 px en el celular, los dos) |
| Luz | no existía | `vidrio`: claro `#ffffff`, oscuro `#33302a` |
| Sombra | no existía | `sombra`: claro `#1a1a18`, oscuro `#000000` |
| S1 | «nunca blanco puro ni negro absoluto» | Nunca como superficie sólida ni como texto; solo como luz y sombra, por sus dos tokens |
| S5 | una tarjeta se separa con la línea sand, sin sombra | Una tarjeta es una placa de vidrio: su filo, su luz y su sombra salen de las recetas |

El oscuro y el borde de control ya estaban en el contrato desde octubre con los valores de Retail y siguen pendientes aquí.

Ojo con `sombra`: en claro es la tinta, no el negro. Retail lo tiene así en `globals.css`, y su `lib/tema-tokens.test.ts` compara ese valor con el de
`.papel-fijo`; poner `#000000` en el contrato deja en rojo su prueba de la familia.

## La deuda

Dynamic no cumple esos valores hasta su Etapa 1, y la prueba no puede ni estar en rojo ni mentir. Por eso cada valor cae en uno de dos lados:

- **Cumple.** Si mañana diverge, falla.
- **Está en `deuda.json`.** Si ya se pagó y sigue anotado, falla. Si Dynamic cambió a otro valor equivocado, falla. Y una deuda que no estaba el 2026-11-05, falla.

Para pagar un valor: se cambia en el código, se borra su línea de `deuda.json` y se baja `TOPE_DEUDA` en `tests/familia.test.ts`. Dos pruebas viejas de
`tests/contraste-controles.test.ts` afirman lo contrario de lo que pide el contrato (que `borde-control` es un alias de `taupe`, y que el rojo del oscuro NO
alcanza sobre papel): al pagar esos valores hay que reescribirlas, no es que algo se rompió.

**Lo que esto no ve:** un archivo se puede editar, y una prueba sin memoria no ve la historia. Volver a meter una deuda obliga a tocar dos líneas de la
prueba, y eso es lo que se busca al revisar un PR; no lo impide nadie más.

**Cuando exista la capa `data-vidrio`:** lo que cuenta es lo que se pinta con el vidrio prendido, así que hay que extender `medirMarca` en la prueba.

```
DECIDÍ:    la deuda vive en un archivo propio, por valor, y la prueba la contrasta con lo que Dynamic pinta de verdad.
DESCARTÉ:  poner cada valor en `aplicacion_pendiente` del contrato, porque ese archivo tiene que ser idéntico en los dos repositorios: cada valor pagado
           obligaría a tocar Retail. Y DESCARTÉ que la prueba solo avise: un aviso que sale siempre se aprende a ignorar.
SE ROMPE SI: Retail publica una v5 con un valor nuevo y Dynamic no lo aplica ese día. La prueba falla al tomarla, que es lo que debe hacer, y ahí hay que
           decidir a la vista: aplicarlo o sumarlo a DEUDA_DIA_UNO.
```

## Qué viaja y qué no

Dos listas en `compartidos.json`:

- **Viajan** (`viajan`): cambiarlos no cambia cómo funciona nada. Hoy son dos: `recetas.css`, el material del vidrio, y `contrato.json`.
- **Se miran** (`se_miran`): no se pueden copiar. `apps/web/app/estilos/vidrio/` son reglas sobre clases que el HTML de Dynamic no tiene, y
  `apps/web/components/ui/` son piezas sobre Radix, que Dynamic no usa. Si cambian, se abre una tarea en el aviso.

No está `tema.css` ni `globals.css`: traen tokens de datos propios de Retail (medios de pago, sedes, gráficos). Los valores de marca llegan por el contrato.

## Las recetas y `data-vidrio`

En Dynamic todo el CSS nuevo cuelga de `data-vidrio` en `<html>`, para que apagado no cambie nada: el 2026-09-07 se quitó de `globals.css` una regla sin
capa que se había colado al terminal. Las recetas de Retail no saben de ese atributo.

Medido el 2026-11-05 en `recetas.css`: 204 variables, ninguna regla de clase, ningún `@keyframes`, ningún `@layer`; tres formas de bloque (`:root`, el oscuro
dentro de `@media screen`, y `prefers-reduced-transparency`), ningún nombre que choque con Dynamic, y dos dependencias que Dynamic no tiene: `--color-vidrio`
y `--color-sombra`. O sea que no hay nada que aislar hoy; hay una diferencia que sí muerde:

**Retail arranca siempre en claro y solo conoce `[data-tema="oscuro"]`. Dynamic, sin atributo, sigue al aparato.** Copiado tal cual, quien tenga el teléfono
en oscuro vería las recetas claras: vidrio blanco al 70 % sobre una página negra. Apagado no se nota; se nota el día del estreno, y solo en esos teléfonos.

```
DECIDÍ:    recetas.css no se copia: se genera `apps/web/app/estilos/vidrio/recetas.generado.css` con `envolver-recetas.mjs`, que cuelga cada selector de
           `:root[data-vidrio]`, agrega la rama del oscuro del aparato y se niega a generar si encuentra algo que no sea variables en esas tres formas.
           En esta etapa el archivo no existe: solo se guarda la huella (`en_el_arbol: false`).
DESCARTÉ:  copiarlo tal cual, porque se vería mal en todo teléfono en oscuro y porque la primera regla de clase que Retail agregue entraría al terminal sin
           que nada avise. DESCARTÉ pedirle a Retail que cuelgue sus recetas del atributo, porque le cambia el código por algo que en Dynamic muere el
           día del estreno. DESCARTÉ envolver también clases y `@keyframes`: una clase apunta al HTML de Retail, y un `@keyframes` tiene nombre global y
           pisaría al de Dynamic aunque el vidrio esté apagado.
           Desde el #1650 de Retail hay dos formas más: `prefers-reduced-transparency` o `prefers-contrast`, y `prefers-contrast` sola. Sus variables viajan; sus reglas,
           una lista exacta, no: Dynamic las escribe en `estilos/vidrio/piezas.css`, solo para el panel. Si Retail cambia esa lista, la copia se detiene.
SE ROMPE SI: Retail agrega a recetas.css una forma nueva (`@media (min-width…)`, una clase, un `@keyframes`). La copia se detiene y el aviso lo dice; lo que
           cambie después tampoco llega hasta resolverlo. Es a propósito, y por eso la regla de Retail debe decir que ese archivo es solo variables.
           También, ya con vidrio, si una pieza usa `var(--gota-fondo)` sin colgar ella misma del atributo: apagado, esa propiedad queda en nada.
```

Medido en Chromium el 2026-11-05 con la receta real: apagado, las 204 variables no existen, también con `data-tema="oscuro"`, y una pieza conserva su color.
Prendido: sin tema, el aparato decide (70 % en claro, 82 % en oscuro); `data-tema="claro"` gana al aparato en oscuro, y `data-tema="oscuro"` al aparato en claro.
No se pudo emular `prefers-reduced-transparency` en ese navegador: ahí queda solo el orden del archivo y su prueba.

El día del estreno, cuando `data-vidrio` deje de existir, se cambia una sola constante del generador (`ATRIBUTO` / `RAIZ`).

## El vigilante

Cada hora, en el minuto 17. Una corrida normal lee Retail (2 s medidos), compara y termina. No instala nada.

| Qué pasa en Retail | Qué hace |
|---|---|
| Nada que le toque a Dynamic, aunque haya cien commits | Nada. Cero escrituras. |
| Cambió una receta o el contrato | Prepara el cambio en el disco de la corrida, corre `pnpm typecheck` y `pnpm test`, y lo cuenta en el aviso. |
| Cambió una pieza | Abre la tarea en el aviso, con los archivos. No corre pruebas: no hay nada que probar. |
| Recetas con algo que no es variable, o que piden un color que Dynamic no tiene | No instala nada y lo dice en el aviso. |
| El contrato de Retail es más viejo que el de aquí | Lo dice. Nunca pisa una versión nueva con una vieja. |
| Un archivo de la lista desaparece, con Retail arriba | Lo dice enseguida. No es una caída: si lo fuera, quedaría ciego para siempre. |
| Retail no responde | Calla, no falla, y reintenta a la hora siguiente. A las 24 h avisa una sola vez. |

El aviso es un único issue: se actualiza, se cierra solo cuando ya no hay diferencias y se reabre si vuelve a haberlas. Editarlo no le manda correo a nadie.

| Variable del repositorio | Valor | Efecto |
|---|---|---|
| `FAMILIA_VIGILANTE` | `apagado` | Apaga el vigilante. No se pide nada a la red. |
| `FAMILIA_PUBLICAR` | `si` (sin tilde) | Enciende la publicación. Cualquier otro valor la deja apagada. |

**Minutos de Actions.** Los dos repositorios son públicos (comprobado el 2026-11-05): los runners estándar no consumen minutos. Si Dynamic volviera a
privado, serían ~720 minutos al mes solo por el vigilante, porque cada corrida se redondea a un minuto. Si Retail volviera a privado, el vigilante no lo
podría leer: a las 24 h lo avisa, y lo primero a mirar es eso.

```
DECIDÍ:    lo que el vigilante necesita recordar (la última firma, desde cuándo Retail no responde, si ya avisó) vive en un comentario oculto en el cuerpo del
           mismo issue. En lo normal no escribe nada.
DESCARTÉ:  un archivo en el repositorio, porque cada escritura sería un push a `main` y `main` se publica sola. DESCARTÉ la caché de Actions, porque vence
           a los 7 días sin uso y justo se usaría en una caída larga, y agrega dos pasos a cada corrida.
SE ROMPE SI: alguien borra o reescribe el cuerpo del issue a mano. Pierde la memoria: a la hora siguiente vuelve a probar y a escribir. Se recupera solo.
```

## El día que se encienda la publicación

Está escrita y apagada: el trabajo `publicar` no arranca ni recibe permiso de escribir mientras `FAMILIA_PUBLICAR` no sea `si`. Solo publica si tocó únicamente
archivos de la lista, las pruebas dieron verde y las tiendas cerraron (22:00 a 05:00 de Perú, UTC-5 fijo). Una tarea de pieza pendiente no frena: una receta
no necesita que la pieza haya llegado.

Hoy **no funcionaría** sin esto, y hay que decidirlo antes:

1. **Fusionar es publicar.** `main` se publica sola, y `--auto` hoy se arma solo cuando Felipe lo pide para ESE PR. Encender la variable es dar ese permiso por adelantado para todos los que cumplan las tres condiciones. Lo decide Felipe.
2. **GitHub no deja a la Action abrir un PR.** El repositorio tiene `can_approve_pull_request_reviews: false`. Se cambia en Settings → Actions → General («Allow GitHub Actions to create and approve pull requests»).
3. **Un PR abierto con `GITHUB_TOKEN` no dispara `db-tests` ni `ui-tests`,** y el ruleset de `main` los exige. Por eso el trabajo llama a `gh workflow run tests.yml --ref <rama>`: un `workflow_dispatch` sí se dispara con `GITHUB_TOKEN`, y el ruleset pide esas dos comprobaciones de la aplicación GitHub Actions (`integration_id` 15368) sobre el commit. **Sin probar:** solo se puede comprobar con esto en `main`. Si no alcanza, hace falta un token propio (una GitHub App o un token personal), que es un secreto con vencimiento: hoy no se crea ninguno.
4. **Lo que se prueba es la rama, no su mezcla con `main`,** y por el token, el merge no debería volver a correr `tests.yml` sobre `main`. Vercel debería publicar igual, porque no depende de Actions. Tampoco esto se pudo probar.
5. **Las pruebas no miden un texto sobre el vidrio.** El contraste de `tests/familia.test.ts` mide la paleta del contrato. Lo que se lee sobre una receta depende de lo que haya detrás y solo se mide en un navegador; Retail lo hace con `tema:auditar`, y Dynamic todavía no tiene nada parecido. Antes de encender esto, Dynamic necesita su medida, o una receta que baje el contraste llega sola a las pantallas.
6. **Hoy nada comprueba que una variable que Dynamic consume siga existiendo.** Una receta renombrada dejaría esa propiedad en nada, sin error. Hay que agregarlo cuando Dynamic empiece a consumir recetas.

## Cómo se lleva un cambio a mano

```bash
node scripts/familia/vigilante.mjs mirar --seco      # qué ve, sin escribir nada
node scripts/familia/vigilante.mjs tomar viajan      # trae las recetas y el contrato, y actualiza las huellas
node scripts/familia/vigilante.mjs tomar piezas      # ya atendí las tareas de las piezas
```

`tomar` sale con error si algo frenó, y el commit sigue el camino de siempre.
