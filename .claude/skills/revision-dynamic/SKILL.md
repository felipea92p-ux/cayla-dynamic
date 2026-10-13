---
name: revision-dynamic
description: Prompt maestro para revisar Dynamic de punta a punta — estético, intuitivo, optimizado y dinámico — con números reproducibles, verificación en navegador y 12 tareas ordenadas. Orquesta /pantalla, /decide, /backlog, /explica y /examen. Úsala para "revisa el sistema", "cómo mejoramos Dynamic", o con una ruta o grupo (admin|mio|terminal) para una revisión acotada. Solo analiza y propone; no ejecuta.
---

Revisa Dynamic con este método: $ARGUMENTS

**Argumentos:** `todo` (por defecto) · `admin` | `mio` | `terminal` (una superficie) · una ruta (`/admin/horas`) · `rapido` (sin navegador ni subagentes) · `visual` (solo la Fase 3).

> Creada el 2026-10-13 a partir del método de `cayla-retail` (skills `pantalla`, `decide`,
> `backlog`, `explica`, `examen`, ya adaptadas en este repo). Esta skill es el **director de
> orquesta**: no reemplaza a `/pantalla`, la usa.

## Quién eres aquí

Director, arquitecto y experta del dominio a la vez (`~/.claude/CLAUDE.md`). Tres preguntas sobre cada hallazgo: ¿esto acerca al sistema que queremos en 3 años? ¿sobrevive a 10× y a cambiar de framework? ¿es como de verdad funciona CAYLA o como yo lo supuse? Si no coinciden, ese desacuerdo es el hallazgo.

## Reglas inviolables (de `CLAUDE.md`, resumidas)

1. **Solo analizas y propones.** Ni código, ni migraciones, ni `estado.md`, ni commits, ni despliegue. Ejecutar es un paso aparte que Felipe ordena.
2. **Lo que se registra alimenta el pago.** Un defecto que pueda pagar mal o acusar de falta a quien no debía pesa más que cualquier detalle visual. Tope 5 en «Cumple su finalidad».
3. **Medir antes de proponer.** Cada cifra lleva: de dónde sale (comando) y **qué NO cuenta**. El 2026-10-13 una primera pasada afirmó «16 archivos con color suelto» y «foco visible en 7 de 151»; ambas eran falsas (velos de modal intencionales; un `:focus-visible` global). Un hallazgo sin la medición que lo respalde es una hipótesis y se rotula así.
4. **Etiqueta cada afirmación:** `[visto]` navegador/captura · `[código archivo:línea]` · `[medido]` script · `[producción]` SQL de Felipe · `[inferido]` · `[no verificable]`. Nunca mezcles lo visto con lo supuesto.
5. **Producción manda y se pide a Felipe** (él corre los SELECT y pega el JSON; pruébalos antes en el Postgres local). Lo local no es producción.
6. **No re-levantes lo decidido.** Léelo primero: `CLAUDE.md`, `docs/estado.md`, `docs/hallazgos-abiertos.md`, `docs/plan-apariencia-2026-09-06.md`, `docs/criterio-auditoria-pantallas.md`, `docs/auditoria-*-2026-*.md`, `docs/comparacion-workday-oracle-dynamic-2026-09-02.md`.
7. **Pregunta con `AskUserQuestion`** (recomendada primero, «Ganas / Pagas») antes de pasar de analizar a ejecutar y ante cada decisión nueva que aparezca.
8. **Privacidad:** nada de nombres, DNI, correos, sueldos por persona ni fechas de ingreso en lo que escribes a disco (`[integrante]`, `[monto]`).
9. **Vocabulario:** integrante, líder de equipo, sede/tienda, DO, clienta. Nunca empleado/jefe/sucursal/RRHH.

## Lo que NO se propone (ya decidido o ya descartado)

- PIN en el terminal (decisión de Felipe, jul-2026: marcar sin PIN a propósito).
- La paleta «Obsidiana» / Inter / sombras (evaluada y descartada el 2026-09-06). Un cambio de identidad no entra en una revisión; entra solo si Felipe lo pide.
- Más colores: el sistema tiene trece `--color-*` y cada uno nuevo se midió contra WCAG antes de entrar.
- Contar `focus-visible` por archivo (hay uno global) ni `next/image` para firmas/DNI/vistas de blob.
- Renombrar `esEncargada`, `supervisor_sede`, `meta_encargadas` (en pantalla es «líder de equipo»; el código se queda).
- Tocar cálculo de planilla, horas, tardanzas o sobretiempo dentro de una tarea de apariencia o rendimiento.
- Realtime/WebSockets «por dinamismo» sin un número que lo justifique (hoy son ~30 personas y 4 sedes).
- Que Dynamic sancione solo: avisa, nunca decide.

## Fase 0 — Terreno

`git fetch origin`; `git rev-list --left-right --count HEAD...origin/main` (si va detrás, lee con `git show origin/main:<ruta>`); `./scripts/sesiones.sh`; `git log --all --oneline -20`. Dilo en la primera línea si otra sesión está tocando lo que vas a revisar. Declara alcance, dispositivo que se juzga por superficie (terminal = Mac mini a pantalla completa; «Lo mío» = celular de la integrante; panel = escritorio de la líder o de DO) y la finalidad de cada una **leída de los documentos, no de la pantalla**.

## Fase 1 — Medir (siempre, <1 min)

```bash
bash .claude/skills/revision-dynamic/medir.sh
```

Es de solo lectura y reproducible. Cópiale al informe los números **con su columna «qué no cuenta»**. Si una cifra te sorprende, desconfía primero de la medición: ábrela y compruébala a mano antes de convertirla en hallazgo. Lo que `medir.sh` declara que no mide (peso de bundle, LCP) se mide en la Fase 3 o se pide a Felipe/CI (`next build`).

## Fase 2 — Muestreo de pantallas (completo)

Con ~63 pantallas no se analizan todas. Elige **5** por esta puntuación: `frecuencia de uso × dinero/obligación legal × tamaño del archivo`. Punto de partida razonable —confírmalo con la Fase 1—: terminal `/terminal/marcar` · «Lo mío» `/mio` · `/admin/dashboard` · una pantalla que alimente planilla (`/admin/horas` o `/admin/correcciones`) · la de mayor tamaño (`/admin/contratos`). Para cada una corre `/pantalla rapido <ruta>`; si Felipe quiere profundidad en alguna, `/pantalla <ruta>` completo. Los subagentes en paralelo cuestan: **pide OK antes de lanzar más de 2** (`Agent` con `Explore`). Aplica la regla de `/pantalla`: el mismo defecto en 3+ pantallas es **una** tarea raíz.

## Fase 3 — Verificación en navegador

Lee `verificacion-visual.md` (en esta carpeta). Resumen: levanta `web-dev` con `preview_start`, **pide a Felipe una sesión local** (no adivines claves ni resetees cuentas en el Postgres compartido), y mide en tres tamaños (375×812, 768×1024, escritorio), claro/oscuro y con movimiento reducido: consola y red sin errores, cascada de peticiones, tiempo hasta contenido útil, objetivos táctiles <44 px, orden de tabulación, estados vacío/carga/error. Sin sesión, di exactamente qué quedó sin verificar; no lo rellenes con suposiciones.

## Fase 4 — Los cuatro ejes (0–10 cada uno, con evidencia)

| Eje | Pregunta que responde | Qué cuenta como evidencia | Ancla 10 / 5 / 0 |
|---|---|---|---|
| **Estético** | ¿se ve como una sola mano, de CAYLA, y es legible? | adopción de primitivos y tokens, radios/z-index, contraste, tema oscuro, `.hoja` al imprimir | 10 = ninguna divergencia / 5 = convive lo nuevo con lo copiado / 0 = sin sistema |
| **Intuitivo** | ¿una persona sin contexto completa el flujo sin ayuda y sin equivocarse? | recorrido del escenario real paso a paso, jerarquía de acciones, vocabulario, estados vacíos con salida, menú (7 grupos), ⌘K, recorrido guiado | 10 = nadie duda / 5 = duda en un paso / 0 = se equivoca |
| **Optimizado** | ¿es rápida de verdad en el dispositivo que importa, y no cuesta de más? | `[medido]` arquitectura (client vs server, cascadas, tamaño de archivo, carga diferida, `loading.tsx`), `[visto]` tiempos, consultas/min con N pestañas | 10 = medido y dentro de presupuesto / 5 = sin medir / 0 = medido y lento |
| **Dinámico** | ¿el sistema responde y comunica lo que pasa, sin estorbar? | feedback <100 ms al tocar, transiciones (`@keyframes`, `ease-salida`, `useSalidaAnimada`), `prefers-reduced-motion`, frescura de datos (sondeo vs. realtime y su justificación numérica) | 10 = cada acción confirma y nada marea / 5 = confirma pero con saltos / 0 = silencio |

Cada puntaje lleva **la evidencia más débil que lo sostiene** y **qué lo subiría un punto**. Si el eje no se pudo verificar (p. ej. «Optimizado» sin build ni navegador), el puntaje se escribe como rango y se rotula `[sin medir]`: un número sin medición es opinión.
Aparte, el **veredicto global** y la **madurez por superficie** (terminal · Lo mío · panel).

## Fase 5 — Costuras (flujos entre pantallas)

Dos o tres recorridos de punta a punta, p. ej.: *integrante marca entrada en terminal → la líder lo ve en Dashboard → corrige un olvido en Correcciones → llega a la planilla del 28*; *DO publica una novedad → la integrante la ve en «Lo mío» → la entiende*. Qué dato viaja, cuál se pierde, cuánto tarda en aparecer (sondeo de 30 s vs. al instante) y qué pasa si Supabase no responde («se degrada así, no pierde este dato»; el terminal ya guarda marcas offline en `idb`: compruébalo, no lo supongas).

## Fase 6 — Las 12 tareas

Siempre 12, ordenadas por **impacto en el negocio + riesgo**, con la causa raíz arriba y dependencias marcadas. Etiqueta cada una con su eje (E/I/O/D). Tipos: Reconstruir · Corregir · Mejorar · Eliminar/fusionar/conectar · Replantear. Cada una: **dónde** (archivo:línea / tabla / `fn_*`) · **por qué en ese puesto** · **cómo lo verificas tú** (algo observable, nunca «compila») · **esfuerzo S/M/L** · **dependencias**. Las estructurales llevan `DECIDÍ / DESCARTÉ / SE ROMPE SI` con un escenario concreto («si dos líderes corrigen el mismo marcaje en el mismo segundo»), jamás «hay que pensar en escalabilidad».
Regla de orden de ejecución que debe respetar el plan: **medir → estructura → pulido → movimiento.** Animar una pantalla lenta la hace sentir más lenta.
Cada tarea que implique SQL lo dice, y recuerda: md5 de producción antes de escribir y antes de entregar, auditoría en `BEGIN … ROLLBACK`, migración pegada **antes** de fusionar. Cada tarea que el equipo vaya a notar lleva su entrada en `apps/web/lib/novedades.ts` en el mismo PR.

## Salida

- **Informe fechado:** `docs/analisis-sistema-AAAA-MM-DD.md` (en `todo`), o `docs/pantallas/<slug>.md` por pantalla. **No** edites `estado.md` (es el único archivo de estado y otras sesiones lo escriben) ni `hallazgos-abiertos.md`: deja «Líneas propuestas» al final para que Felipe apruebe.
- **Al chat**, con los tres movimientos de `~/.claude/CLAUDE.md`: **EL TRABAJO** (veredicto en 3 líneas + los cuatro puntajes + las 3 primeras tareas + enlace) · **LA OBJECIÓN** (lo que está mal en lo que se pidió, o «sin objeción») · **LO QUE NO PIDIÓ** (una sola cosa, la de mayor consecuencia).
- Sugiere commitear el informe con `git commit -o <ruta>`: en este árbol compartido un archivo sin commitear se pierde con el siguiente `checkout` de otra sesión. Commitear lo decide Felipe.

## Antes de decir «listo» (con evidencia, no con «debería»)

1. **Concurrencia:** ¿qué pasa si dos líderes o dos pestañas tocan el mismo registro al mismo tiempo? ¿alguna tarea propuesta lo empeora (p. ej. más estado en el cliente)?
2. **Caída externa:** ¿qué pasa si Supabase no responde hoy? ¿se ve un error entendible o una pantalla en blanco?
3. **Persona sin contexto:** ¿una integrante nueva, en su celular, en hora pico, completa el flujo sin que nadie le explique?

Si no puedes responder las tres con evidencia, el informe está «escrito», no «listo».

## Después del informe

Para pasar a ejecutar, Felipe ordena («haz de la #1 a la #4»). Entonces: una tarea = un PR; `AskUserQuestion` antes de lo estructural; el primer commit de cada tarea es el refactor que vuelve trivial el cambio, el segundo es el cambio; fusionar un PR **es** desplegar a producción (lo decide Felipe). Para entender lo que quedó construido: `/explica`; para comprobar que Felipe lo entendió: `/examen`.
