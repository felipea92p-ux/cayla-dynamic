# Easter eggs de Dynamic

Los secretos del sistema, y cómo encontrarlos. Este documento es el catálogo:
si agregas uno, se agrega aquí **en el mismo pull request**. Un secreto que
nadie anotó se vuelve, en un año, un comportamiento raro que nadie se atreve a
quitar.

> **Sistemas cubiertos:** solo **Dynamic**. En CAYLA Retail se buscó el
> 2026-10-13 (`easter`, `konami`) y no hay ninguno. Si se agregan allá, que
> tengan su propia sección en el documento de Retail y se enlacen aquí.

## Las reglas que los hacen «nada invasivos»

Valen para todos los que existen y para los que vengan. Están escritas también
en `apps/web/lib/easter-eggs.ts`, que es donde se decide cuándo se activa cada
uno.

1. **Pasivos.** Ninguno se ve si nadie lo busca. No hay pista en pantalla, ni
   un botón, ni un aviso de «descubriste algo».
2. **Jamás en el terminal de marcaje.** Es el único sitio donde lo que se toca
   decide a quién se le paga qué día, y está a la vista de toda la sede: una
   tecla suelta no puede activar nada. Hay una prueba que lo vigila para el
   service worker (`tests/sin-conexion.test.ts`); para el resto, la regla es
   que no se monta ningún huevo en `app/(terminal)`.
3. **Nunca escriben en la base ni mandan nada a ninguna parte.** El único dato
   que guardan es el mejor puntaje del juego, en el `localStorage` del propio
   navegador.
4. **Nunca mientras alguien escribe.** Un campo de texto enfocado los apaga:
   buscar un huevo no puede costar un dato.
5. **Con «reducir movimiento» no se mueven.** Quien lo tiene activado en su
   sistema no ve vuelos ni revoloteos.
6. **Nunca una regla de negocio.** Un toque de fecha no mueve un feriado, un
   pago ni una tardanza; ver «Toques de fecha».

## Los cinco

| # | Dónde | Cómo se activa | Qué pasa |
|---|---|---|---|
| 1 | Panel (cualquier pantalla) | Escribir el **código Konami** con el teclado: `↑ ↑ ↓ ↓ ← → ← → B A` | Un colibrí rojo cruza la pantalla en 3.4 s |
| 2 | Panel, buscador (`⌘K`) | Escribir **`colibrí`** (con o sin tilde, con o sin mayúscula) y pulsar Enter | Se abre el juego del colibrí en una ventana |
| 3 | Login | **Cinco clics seguidos** (dentro de 2 s) sobre el colibrí | El colibrí revolotea un instante |
| 4 | Login | Entrar en **Navidad** (24 y 25 dic) o **Fiestas Patrias** (28 y 29 jul) | La línea de saludo suma «· Feliz Navidad» / «· Felices Fiestas Patrias» |
| 5 | Cualquier pantalla, **sin internet** | Abrir Dynamic sin conexión | Una página de aviso con el juego del colibrí (no es del todo secreta: ver abajo) |

### 1. El colibrí viajero (código Konami)

- **Dónde está el código:** `components/colibri-viajero.tsx`, montado en el
  marco del panel (`app/(admin)/admin/nav.tsx`). La secuencia y su lógica son
  `CODIGO_KONAMI` y `avanzarKonami` en `lib/easter-eggs.ts`.
- **Detalles:** las letras valen en mayúscula. Un error en medio no obliga a
  empezar de cero si lo último pulsado todavía puede ser el comienzo de un
  intento. No hace nada si hay `⌘`, `Ctrl` o `Alt` apretados, ni si el foco
  está en un campo de texto. No recibe clics: nunca estorba a lo de abajo.
- **Para probarlo:** abrir cualquier pantalla del panel, hacer clic en el fondo
  (no en un campo) y teclear la secuencia.

### 2. El juego, desde el buscador

- Aparece como **«Un secreto → Jugar con el colibrí»** en cuanto la consulta es
  exactamente `colibrí`. Una palabra más (`colibri azul`) o una menos
  (`colibr`) no lo ofrece, para no taparle nada a quien busca a una persona o
  una pantalla.
- **Dónde está el código:** `components/buscador-global.tsx` (la fila) y
  `components/juego-colibri.tsx` (la ventana). El juego es el mismo del #5.
- Se cierra con `Esc`. Al cerrarse, el juego deja de escuchar el teclado.

### 3. El colibrí travieso del login

- **Dónde está el código:** `lib/use-rafaga-de-clics.ts` y `registrarClic` en
  `lib/easter-eggs.ts`; el movimiento es `[data-travieso]` en `app/globals.css`.
- En pantalla ancha es el colibrí grande del panel izquierdo; en celular, el
  chico de arriba del formulario. Los dos cuentan por separado.
- Cinco clics **lentos** (más de 2 s en total) no cuentan: es alguien tocando
  el logo con calma, no buscando nada.

### 4. Toques de fecha en el saludo del login

- **Hoy:** 24 y 25 de diciembre → «Feliz Navidad»; 28 y 29 de julio → «Felices
  Fiestas Patrias». Se ve en la línea de saludo, por ejemplo: *Buenos días ·
  viernes 25 de diciembre · Feliz Navidad*.
- **Manda el día de Lima**, no el del aparato ni el de UTC: a las 11 p. m. del
  24 en Lima sigue siendo el 24 aunque en UTC ya sea 25.
- **Dónde está el código:** `TOQUES` y `toqueDeFecha` en `lib/easter-eggs.ts`;
  se suma en `saludoDelDia` (`lib/login-vuelo.ts`).
- **No es el calendario de feriados.** Los feriados que mueven plata viven en
  la tabla `feriados` y se gestionan desde su pantalla; el login ni siquiera
  puede leerla antes de entrar. Esto es un adorno, y por eso es una lista de
  dos fechas y no una consulta. Si un feriado cambia de día, el saludo puede
  quedar un día corrido y no cambia ni un sol de nadie.
- **Para agregar una fecha:** una línea en `TOQUES`, su caso en
  `tests/easter-eggs.test.ts` y una fila en esta tabla.

### 5. Sin internet: el colibrí

No es secreto del todo, porque quien se queda sin internet lo ve sin buscarlo.
Se documenta aquí porque comparte el juego con el #2 y porque es la pieza con
más cuidado del conjunto.

- **Qué ve la persona:** en lugar del error del navegador, una página de Dynamic
  que dice **primero** «Dynamic necesita internet y ahora no hay. Nada de lo que
  hagas en esta pantalla se guarda…», con un botón «Reintentar», y **debajo** el
  juego. El orden es deliberado: un colibrí bonito arriba de todo podría hacer
  creer que algo se guardó.
- **Dónde está:** `public/sin-conexion.html` (la página), `public/sin-conexion-sw.js`
  (el service worker que la sirve) y `components/registrar-sin-conexion.tsx`
  (que lo registra, solo en producción).
- **Para verla sin desconectarte:** abrir `/sin-conexion.html`. Dice «Vista
  previa» arriba. Con `?juego=vuelo`, `?juego=salto` o `?juego=flappy` se fuerza
  uno.
- **Qué NO hace, y es lo más importante:**
  - **No guarda páginas del panel.** Sin red, jamás muestra una planilla de hace
    tres días como si fuera de hoy. Solo guarda tres archivos que no tienen
    ningún dato de nadie.
  - **No toca el terminal.** `/terminal/*` tiene su propio service worker, que
    sí guarda su pantalla de marcar para seguir marcando sin red. Una sede sin
    internet ve SU pantalla, nunca un juego.
  - **No confunde un error del servidor con «sin conexión».** Un 500 pasa tal
    cual.
- **Limitación honesta:** funciona solo en dispositivos que **ya abrieron
  Dynamic al menos una vez con internet** desde que existe este service worker.
  La primera visita sin red ve el error normal del navegador.
- **Si algún día hay que apagarlo:** sustituir `sin-conexion-sw.js` por uno que
  se desregistre (`self.registration.unregister()`) y quitar
  `<RegistrarSinConexion />` de `app/(admin)/layout.tsx` y `app/(mio)/layout.tsx`.
  Los navegadores bajan el archivo en cada visita, así que se propaga solo.

## El juego: tres en uno

Un único motor, `public/colibri/juego.js` (sin dependencias, sin React), usado
por el #2 y el #5. Cada vez que arranca una partida se sortea cuál toca:

| Juego | Probabilidad | Cómo se juega |
|---|---|---|
| **Vuelo** | 50 % | El colibrí vuela: mantén pulsado para subir, suelta para bajar. Esquiva carretes de hilo (en el suelo) y agujas (en el aire). |
| **Salto** | 40 % | El del dinosaurio de Chrome: pulsa para saltar uno, dos o tres carretes pegados. |
| **Flappy** | 10 % | Pulsa para aletear entre columnas de hilo. |

- **Controles:** barra espaciadora, flecha arriba, `W`, o tocar la pantalla.
- **Puntaje:** el mejor de cada juego se guarda en el `localStorage` del
  navegador (`cayla-colibri-mejor-<juego>`). No se envía a ninguna parte y no
  hay tabla de posiciones: si alguien quiere una, es una decisión nueva —y
  tendría que decidirse con cuidado, porque un puntaje en la base es un dato de
  una persona.
- **Las pruebas** (`tests/colibri-juego.test.ts`) incluyen un jugador
  automático que tiene que sobrevivir 90 s a velocidad máxima en cada juego, 40
  partidas por juego. Es lo que garantiza que el generador de obstáculos nunca
  deja un tramo imposible. Si cambias los tiempos entre obstáculos y esa prueba
  falla, no es la prueba: es que dejaste el juego injusto.

## Pendiente

- **Aniversario de CAYLA.** Se pidió y no se hizo porque no hay una fecha que
  copiar. En Retail «Aniversario CAYLA» es una **campaña con ventana de fechas
  editable** (en la maqueta del plan de campañas, del 1 al 14 de octubre), no un
  día. Para sumar el toque falta saber **qué día exacto** se celebra; con eso
  es una línea en `TOQUES`. No se copió la ventana de Retail a propósito: viven
  en una tabla de otro sistema, y una copia aquí se quedaría vieja el día que
  alguien edite las fechas allá.
