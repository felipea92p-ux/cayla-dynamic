# Análisis del sistema — estético, intuitivo, optimizado, dinámico

**Informe fechado, como `auditoria-dashboard-2026-09-13.md` o `plan-apariencia-2026-09-06.md`.
No es estado:** `docs/estado.md` sigue siendo el único archivo de estado y este informe
no lo toca. Se rehace corriendo `/revision-dynamic` (ver `.claude/skills/revision-dynamic/`).

> Modo: **estático + login en navegador.** Se midió el código con
> `.claude/skills/revision-dynamic/medir.sh` (reproducible) y se vio en el navegador
> integrado **solo la pantalla de login** (oscuro, claro y 375×812). El panel, «Lo mío» y
> el terminal **no se vieron en vivo**: la contraseña de desarrollo del seed ya no entra
> en la base local compartida y no se adivinan claves ni se resetean cuentas ahí.
> SHA analizado: `39d1cae9` (= `origin/main`, verificado con `git fetch` el 2026-10-13).
> Etiquetas: `[medido]` script · `[código archivo:línea]` · `[visto]` navegador ·
> `[inferido]` · `[sin medir]`.

---

## 0 · Veredicto

Un sistema con **identidad visual madura y movimiento cuidado, cuyo crecimiento ya va
más rápido que su capacidad de medirse.** Las 63 pantallas suman 51 391 líneas; el
dashboard pasó de 836 a 1 971 líneas en un mes `[código]`; y hoy no existe ninguna
herramienta que avise si una pantalla se vuelve lenta o inaccesible (sin Lighthouse, axe,
analizador de bundle ni prueba en navegador: los 76 archivos de prueba corren en Node) `[medido]`.

| Eje | Puntaje | Confianza | Lo más débil que lo sostiene | Qué lo subiría un punto |
|---|---|---|---|---|
| **Estético** | 8–9 | media | solo el login se vio en vivo | cerrar la escala de radios y de `z-index` (tarea #6) |
| **Intuitivo** | 6–8 | **baja — sin persona real** | ningún recorrido hecho con alguien sin contexto | recorrer 3 flujos con una integrante nueva en su celular (Fase 3/5) |
| **Optimizado** | 5–7 | **baja — sin build ni navegador** | no hay medida de peso ni de tiempos | #1: medir; luego #3 y #2 |
| **Dinámico** | 7–8 | media | movimiento verificado en CSS, no a la vista | #5 confirmación inmediata y #8 frescura del tablero |

Un número sin medición es opinión: los rangos son a propósito. **Cumple su finalidad: no
se calcula global** (es por pantalla, con `/pantalla`); ningún defecto hallado aquí puede
pagar mal ni acusar de falta, así que no hay tope de 5.

**Madurez por superficie:** terminal — la más cuidada para su uso (guarda marcas sin
conexión con `idb`, repasa pendientes cada 4 s, sincroniza cada 2 min) `[código
terminal/marcar/page.tsx:417,434]`; «Lo mío» — la más pesada para el dispositivo que
importa (3 299 líneas, en el celular de todo el equipo); panel — el más grande y el más
consistente en diseño.

## 1 · Objeción

**Lo que se pidió como «analiza lo estético» apunta al eje que menos lo necesita.** El
diseño ya está bien: la adopción del sistema de diseño pasó de 7-8 pantallas de ~40 el
2026-09-06 a 78 archivos con `Boton`, 52 con `Insignia` y 31 con `Modal` `[medido]`, y el
color suelto real es **cero** fuera de la vista previa de la firma (excepción escrita en
`CLAUDE.md`). Pulir más lo estético tiene retorno bajo. El retorno está en **Optimizado y
en poder medirlo**.

Y hay que decir cuánto vale lo que **no** se midió: sin `next build` ni navegador,
«Optimizado 5–7» es una sospecha informada, no un diagnóstico. Lo que sí está claro es
que **nadie lo sabría si empeorara**.

## 2 · Lo que está bien y no se toca

- **Tokens y tema oscuro.** Trece `--color-*` (el catorceavo es el alias `--color-borde-control`),
  cada uno medido contra WCAG; modo oscuro por redefinición, sin tocar componentes `[código globals.css:7-84,152-164]`.
  Login en oscuro/claro/celular con jerarquía clara y error en lenguaje humano `[visto]`.
- **Foco de teclado:** hay un `:focus-visible` global `[código globals.css:228]`. El
  «7 de 151 archivos» que aparece si se cuenta por archivo es un **falso hallazgo**.
- **Movimiento:** 16 `@keyframes` con curva compartida (`ease-salida`), entradas y salidas
  de cajón/hoja/modal, `useSalidaAnimada`, y `prefers-reduced-motion` respetado en CSS (3
  bloques) y en 9 archivos `[medido]`. `Boton` ya trae estado `cargando` (138 usos) `[código boton.tsx:44]`.
- **El Dashboard está bien cargado.** Una lectura de sesión local y luego ~11 consultas
  **en paralelo** con caché de catálogos y banderas de «no respondió» para no confundir
  vacío con falla `[código dashboard/page.tsx:560-640]`. No hay cascada que arreglar ahí.
- **El marco del panel se monta una vez** y no bloquea a su hijo mientras averigua quién
  eres `[código (admin)/layout.tsx; admin/nav.tsx:391]`.
- **Hex sueltos (4 archivos) son legítimos:** `theme-color` del manifiesto, `global-error`
  (que no puede leer variables CSS) y el canvas de la firma. **`<img>` sin `next/image` (30)
  tampoco es hallazgo:** son firmas, DNI y vistas de blob.
- **Menú con razón escrita** (7 grupos, y por qué cada ítem está donde está), buscador
  ⌘K, atajos y recorrido guiado `[código nav-items.ts]`.

## 3 · Los números, con su «qué no cuenta»

| Medida | Valor | Qué NO cuenta / cuidado |
|---|---|---|
| Pantallas (`page.tsx`) | 63: admin 48 · mío 11 · terminal 3 | `api/` aparte |
| Líneas en pantallas | 51 391; las 5 mayores: contratos 3 934 · mío 3 299 · documentación 2 534 · equipo 2 442 · dashboard 1 971 | las líneas no son bytes; el bundle real se mide con `next build` |
| `"use client"` | 60 de 63 | no es malo por sí mismo (auth Supabase es de cliente); es lo que hace que cada pantalla pida su JS **y después** sus datos |
| Piden datos en `useEffect` | 56 de 63 | aproximación; confirmar con `supabase.rpc/from` dentro |
| `loading.tsx` / `error.tsx` por segmento | **0 / 0** en admin y mío; 1 / 1 en terminal (solo error); uno global en la raíz | el global cubre, pero ver tarea #2 |
| Carga diferida (`next/dynamic`) | **0** | los modales de una pantalla de 3 900 líneas viajan siempre |
| Realtime / sondeo | 0 canales · sondeo cada 30 s (dashboard) y 5 min (bandeja, casos) | al menos 11 consultas × 2/min ≈ 22/min por pestaña abierta; con 10 pestañas ≈ 4/s: **no es problema de capacidad** |
| Primitivos | Boton 78 · Insignia 52 · Modal 31 · Campo 49 · Tabla 25 | `<button>` crudos: 236 de 888 (legítimos: íconos, pestañas); `hoja-inferior` solo 1 |
| Radios | control 305 · superficie 112 · flotante 11 · píldora 46 · `rounded-lg` 196 · `rounded-2xl` 132 · **`rounded-xl` 45 · `rounded-md` 14** | `lg` = control y `2xl` = superficie **son el mismo valor con otro nombre** (visualmente consistente); solo `xl`(12 px) y `md`(6 px) están fuera de escala |
| `z-index` | `z-10/20/30/40/50` + `z-[60]` sin escala nombrada | solo importa si dos capas se pelean |
| Movimiento | 16 keyframes · 59 archivos con `transition` · 0 `useOptimistic/useTransition` | |
| A11y | `aria-` en 87 de 151 `.tsx` · responsivo en 78 | no hay prueba automática de accesibilidad |

## 4 · Los cuatro ejes, con evidencia

**Estético (8–9).** Una sola mano: tokens, primitivos y tema oscuro. El resto es limpieza
de escala (`xl`/`md`, `z-index`). **Hallazgo propio, retirado:** mi primera pasada contó
«16 archivos con color suelto»; eran velos `bg-black/NN` (intencionales: en oscuro el
velo debe oscurecer), `print:bg-white` (papel) y un comentario. Quedó la firma.

**Intuitivo (6–8, sin medir).** Fortalezas por diseño: menú agrupado con razón escrita,
⌘K, recorrido guiado, vocabulario unificado. Riesgo: densidad. Pantallas de 2 000–4 000
líneas casi seguro concentran decenas de acciones; sin recorrer el flujo con alguien sin
contexto no se sabe si estorba `[inferido]`. **Esta es la nota que más cambiaría al ver
a una persona usándolo.**

**Optimizado (5–7, sin medir).** A favor: consultas en paralelo, caché de catálogos,
sondeo con refresco al volver a la pestaña. En contra: ninguna carga diferida, 60/63
pantallas en cliente, 0 `loading.tsx` por segmento `[medido]`, y **el sondeo del dashboard
no se pausa por sí mismo**: su comentario asume que «los navegadores pausan el interval
en segundo plano», pero lo habitual es que lo **frenen** (≈1/min), no que lo paren
`[código dashboard/page.tsx:778-790]` `[inferido]`. En el celular de una líder con la
pestaña abierta eso es batería, no capacidad. Y la señal de fondo: **no hay forma de
detectar una regresión**.

**Dinámico (7–8).** Entradas/salidas coherentes, estados de carga con el colibrí,
`reduced-motion` respetado. Huecos: ninguna confirmación optimista (0 `useOptimistic`), y
la frescura depende de sondeo: una marca del terminal puede tardar hasta 30 s en
reflejarse en el tablero «quién trabaja ahora». Con ~30 personas y 4 sedes **no es
urgente**; es una decisión de producto (tarea #8).

## 5 · Costuras (dos recorridos, sin ejecutar en vivo)

1. **Marca → tablero → corrección → planilla del 28.** El terminal guarda sin conexión y
   sincroniza (`lib/terminal/sync.ts:89`); el tablero lo ve en ≤30 s; la corrección deja
   rastro en `correcciones_auditoria`. *Si Supabase cae:* el terminal no pierde la marca
   (queda en `idb`) y repasa pendientes cada 4 s `[código]`. **Sin verificar en vivo.**
2. **DO publica una novedad → «Lo mío» → «Entendido».** Está en código (`novedades.ts`
   + `novedades_vistas`, 0480) y su degradación es explícita en `CLAUDE.md`
   (sin leer marcas, «Lo mío» calla). **Sin verificar en vivo.**

## 6 · Las 12 tareas

Orden: **medir → estructura → pulido → movimiento** (animar una pantalla lenta la hace
sentir más lenta). Ejes: E estético · I intuitivo · O optimizado · D dinámico.

### #1 · [Mejorar · O] Medir antes de tocar nada
- **Dónde:** `next build` (tabla First Load JS por ruta) y la pestaña *Web Vitals* de Sentry
  (`instrumentation-client.ts:12` ya tiene `tracesSampleRate: 1` **[inferido: el rastreo del
  navegador suele recoger LCP/CLS; Felipe confirma abriendo Sentry → Performance]**).
- **Por qué primero:** sin esto, las tareas #2–#4 son opinión. Barato y no instala nada.
- **Cómo lo verificas:** una tabla `ruta → KB` y, de Sentry, LCP de `/mio`, `/admin/dashboard`
  y `/terminal/marcar` en celular real.
- **Esfuerzo:** S · sin dependencias · **lo corre Felipe o CI** (el build necesita las claves).

### #2 · [Corregir · O/I] `loading.tsx` dentro del marco para `admin` y `mio`
- **Dónde:** crear `app/(admin)/admin/loading.tsx` y `app/(mio)/mio/loading.tsx`; hoy solo
  existe `app/loading.tsx`, que pinta el colibrí **a pantalla completa**.
- **Por qué aquí:** si al navegar entre pantallas el fallback raíz envuelve el marco, el
  menú lateral desaparece un instante `[inferido — no verificado: el comentario de 2026-09-07 en
  (admin)/layout.tsx dice que se evitó el remontaje, pero eso no prueba lo que hace el Suspense]`.
- **Cómo lo verificas:** en el navegador, con sesión, navega Dashboard → Horas con la red
  en «3G lento»: ¿el menú se queda o parpadea? **Si se queda, esta tarea se tacha.**
- **Esfuerzo:** S · no antes de #1 (ver si el problema existe).

### #3 · [Reconstruir · O] Partir las cinco pantallas gigantes y cargar bajo demanda lo que no se ve al abrir
- **Dónde:** `contratos/page.tsx` (3 934), `mio/page.tsx` (3 299), `documentacion` (2 534),
  `equipo` (2 442), `dashboard` (1 971). Empezar por **`/mio`**: es el celular de todo el equipo.
- **Por qué:** cada modal/panel de esas pantallas viaja siempre aunque no se abra, y el dashboard
  creció 2.4× en un mes. Kent Beck: **el primer commit es el refactor** (extraer a archivos sin
  cambiar comportamiento), **el segundo** agrega `next/dynamic`.
- **DECIDÍ:** partir por modal/panel y cargar bajo demanda, empezando por «Lo mío».
- **DESCARTÉ:** migrar las pantallas a Server Components: la sesión de Supabase vive en el
  cliente (`getSession` en cada pantalla) y tocar la autenticación de 63 pantallas con la
  planilla en producción cuesta más riesgo que beneficio.
- **SE ROMPE SI:** un modal extraído pierde el estado que comparte con su pantalla (guardar →
  refrescar la lista) y la lista queda vieja o se pide dos veces.
- **Cómo lo verificas:** el KB de `/mio` en la tabla de #1 **baja**, y cada modal sigue guardando.
- **Esfuerzo:** L por pantalla · no antes de #1 · una pantalla = un PR.

### #4 · [Mejorar · O/E/I] Herramientas de medición permanentes
- **Dónde:** un reporte de tamaño por ruta en CI y una prueba axe sobre 5 pantallas.
- **Por qué:** hoy el sistema crece sin freno de rendimiento ni de accesibilidad (mismo patrón que
  el linter apagado de julio: instalado y sin que lo ejecute nadie).
- **Cómo lo verificas:** un PR que sube `/mio` en 100 KB hace fallar el check.
- **Esfuerzo:** M · **dependencia nueva → propone y espera tu aprobación**, no se instala sin ella.
- **Dependencias:** #1 (el presupuesto sale de lo medido).

### #5 · [Mejorar · D/I] Confirmación visible en menos de 100 ms al guardar
- **Dónde:** `Boton` ya tiene `cargando` (138 de 652 usos). Auditar los otros 514 en acciones que
  escriben: ¿muestran «guardando…» y luego «guardado»?
- **Por qué:** en celular con señal de sede, el silencio hace tocar dos veces (doble envío).
- **Cómo lo verificas:** con red lenta, tocar «Guardar» una vez y ver el estado inmediato.
- **Esfuerzo:** M · independiente.

### #6 · [Corregir · E] Cerrar la escala de radios y de capas
- **Dónde:** 45 `rounded-xl` y 14 `rounded-md` fuera de escala; `z-index` 10–50 y `z-[60]` sin nombres
  (como `radius-flotante`, tokens de capa: `--z-modal`, `--z-menu`).
- **Por qué en este puesto:** es lo único estético con fallo real, y es barato; el resto no.
- **Cómo lo verificas:** `medir.sh` baja `xl`/`md` a 0 salvo excepción comentada.
- **Esfuerzo:** S · independiente · bajo valor relativo.

### #7 · [Corregir · O] Pausar el sondeo del dashboard con la pestaña oculta
- **Dónde:** `dashboard/page.tsx:778-790`; ya existe `use-refresco-lento.ts` que lo hace bien.
- **Por qué:** consume batería en el celular de la líder; no es de capacidad (≈4 consultas/s con
  10 pestañas). **Primero comprobar** cuántas veces dispara en segundo plano.
- **Cómo lo verificas:** con la pestaña oculta 3 min, `read_network_requests` no muestra consultas.
- **Esfuerzo:** S.

### #8 · [Replantear · D] ¿Tiempo real solo para «quién trabaja ahora»?
- **Dónde:** Dashboard y `fn_jornadas_extra`; hoy sondeo de 30 s.
- **Por qué es decisión tuya:** cambia lo que ve una líder ante una marca, pero cuesta una
  suscripción realtime por pestaña.
- **DECIDÍ:** no hacerlo por ahora y dejar el sondeo.
- **DESCARTÉ:** Supabase Realtime en el dashboard: ~30 personas y 4 sedes no justifican otra
  dependencia y otra superficie de RLS que auditar; 30 s es suficiente para decidir.
- **SE ROMPE SI:** una sede con mucho flujo (hora pico de apertura, 5+ marcas en un minuto) necesita
  ver la cola en vivo y la líder se queda mirando un tablero atrasado.
- **Esfuerzo:** M si se decide · **decide Felipe**.

### #9 · [Mejorar · I] Recorrer tres flujos con una persona sin contexto
- **Dónde:** marcar entrada (terminal) · pedir un permiso (Lo mío) · corregir un olvido (líder).
- **Por qué:** es lo único que mueve el 6–8 de «Intuitivo» a un número real.
- **Cómo lo verificas:** tiempo y errores de una integrante nueva que no recibió explicación.
- **Esfuerzo:** S · no es código.

### #10 · [Mejorar · E] `hoja-inferior` adoptada en el celular
- **Dónde:** el primitivo se usa en 1 archivo; en celular, los modales centrados son más difíciles de
  alcanzar con el pulgar que una hoja inferior (patrón que `/mio` ya usa).
- **bajo valor / opcional:** `[inferido]` sin ver las pantallas en vivo.
- **Esfuerzo:** M.

### #11 · [Eliminar/fusionar · E] Revisar `<button>` crudos de acción primaria
- **Dónde:** 236 `<button>`; la mayoría legítimos (íconos, pestañas, filas clicables).
- **bajo valor / opcional:** solo los de acción primaria deberían ser `Boton`; no vale un barrido.

### #12 · [Mejorar · O] `tracesSampleRate: 1` y replay en el bundle del cliente
- **Dónde:** `instrumentation-client.ts:12-22`: rastro al 100 % y `replayIntegration` cargada para
  todos aunque solo se grabe el 10 %.
- **bajo valor / futuro:** el 100 % es útil mientras se mide (#1); bajarlo a ~10 % y cargar el
  replay en diferido es una optimización que **solo se decide con el KB de #1 delante**.

## 7 · Fuera de esta pantalla (lo que no se preguntó)

**Los 76 archivos de prueba corren en Node: ninguna prueba abre un navegador.** Todo lo de este
informe —foco, contraste, capas, un modal que no abre, un botón fuera de pantalla en 375 px— solo lo
caza una persona mirando, como ya pasó con la 0404 y la 0407. Hoy la red de seguridad es
excelente para plata y base de datos, y casi nula para interfaz. Eso, más que cualquier
pantalla, es lo que haría que este análisis se pudiera repetir en una semana sin esfuerzo.

## 8 · Lo que NO se verificó (para no darlo por visto)

- **Panel, «Lo mío» y terminal en vivo** (sin sesión local válida): estéticas, tiempos y estados
  vacío/error quedan en `[inferido]` o `[sin medir]`.
- **Peso real del bundle y LCP** (necesita `next build` y un celular).
- **Si el menú lateral parpadea al navegar** (tarea #2).
- **Producción:** ningún SQL se pidió a Felipe; este informe no toca datos.

## 9 · Líneas propuestas para `hallazgos-abiertos.md` (Felipe aprueba antes de anexar)

- [ ] `[sistema:2026-10-13]` #1 Medir First Load JS por ruta y Web Vitals de Sentry — S
- [ ] `[sistema:2026-10-13]` #2 `loading.tsx` dentro del marco (condicionada a que el menú parpadee) — S
- [ ] `[sistema:2026-10-13]` #3 Partir las cinco pantallas gigantes y diferir modales; empezar por `/mio` — L
- [ ] `[sistema:2026-10-13]` #4 Reporte de tamaño por ruta en CI y axe en 5 pantallas (dependencia nueva) — M
- [ ] `[sistema:2026-10-13]` #7 Pausar el sondeo del dashboard con pestaña oculta — S

## Historial

| Fecha | Modo | Cambios |
|---|---|---|
| 2026-10-13 | rápido, estático + login | primer análisis del sistema entero; las skills de `cayla-retail` se adaptaron a Dynamic |
