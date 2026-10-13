# Verificación visual de Dynamic (Fase 3 de `/revision-dynamic`)

Se lee en la Fase 3. Todo con el navegador integrado (`mcp__Claude_Browser__*`). Solo contra el panel **local**; nunca contra producción.

## 0 · Entorno (lo que cuesta descubrir sin esta guía)

- `apps/web/.env.local` **no viene en el repo** (está en `.gitignore`). Sin él, cualquier pantalla revienta con «supabaseUrl is required» y parece un bug de la pantalla. Se crea con las dos claves públicas locales:
  ```bash
  npx supabase status -o env | grep -E '^(API_URL|ANON_KEY)='
  # → apps/web/.env.local con NEXT_PUBLIC_SUPABASE_URL y NEXT_PUBLIC_SUPABASE_ANON_KEY
  ```
- La pila debe estar **entera** arriba (`curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:54321/rest/v1/` → 200). `npx supabase db start` levanta la base pero **no** la API.
- **El Postgres local es uno solo para todas las sesiones.** Nunca `db reset`. Nunca resetees contraseñas ni crees cuentas ahí para poder entrar: pídele a Felipe una sesión local (o que te diga con qué cuenta entrar). Las claves de `scripts/seed-dev.mjs` pueden estar caducadas (el 2026-10-13 `felipe@cayla.dev` ya no entraba).
- `preview_start` con `{name: "web-dev"}` (el puerto 3000 suele estar ocupado: usa el que devuelva).
- Cuentas de ejemplo por rol existen en el seed (admin / líder / integrante / terminal), pero **no se asume que sirvan**.

## 1 · Matriz mínima

| Superficie | Tamaños | Temas | Extra |
|---|---|---|---|
| Panel `/admin/*` | 1280×800 · 768×1024 · 375×812 | claro y oscuro | teclado: Tab recorre en orden y se ve el foco; ⌘K y `?` |
| «Lo mío» `/mio/*` | 375×812 (principal) · 768×1024 | claro y oscuro | una mano, pulgar: ¿las acciones primarias están al alcance? |
| Terminal `/terminal/*` | 1920×1080 (Mac mini) | el que traiga la sede | distancia: ¿se lee a 1 m?; sin conexión (offline) |

`resize_window` con `preset` o `width/height`, y `colorScheme: "light"|"dark"`. **Restaura `preset: "desktop"` al terminar.**

## 2 · Qué medir en cada pantalla

**Consola y red** — `read_console_messages` (solo errores) y `read_network_requests`: cuántas peticiones al cargar, cuáles van **en serie** (una espera a la otra), cuáles se repiten, cuáles fallan.

**Tiempos y estabilidad** (en `javascript_tool`, recargando antes):
```js
(async () => {
  const nav = performance.getEntriesByType('navigation')[0];
  const paint = Object.fromEntries(performance.getEntriesByType('paint').map(p => [p.name, Math.round(p.startTime)]));
  const lcp = await new Promise(r => { let v = 0; new PerformanceObserver(l => { v = l.getEntries().at(-1)?.startTime ?? v; }).observe({type:'largest-contentful-paint', buffered:true}); setTimeout(() => r(Math.round(v)), 1500); });
  const cls = await new Promise(r => { let s = 0; new PerformanceObserver(l => { for (const e of l.getEntries()) if (!e.hadRecentInput) s += e.value; }).observe({type:'layout-shift', buffered:true}); setTimeout(() => r(+s.toFixed(3)), 1500); });
  const recursos = performance.getEntriesByType('resource');
  const js = recursos.filter(r => r.initiatorType === 'script' || r.name.endsWith('.js'));
  return { domContentLoaded: Math.round(nav.domContentLoadedEventEnd), load: Math.round(nav.loadEventEnd), ...paint, lcp, cls,
           peticiones: recursos.length, jsKB: Math.round(js.reduce((a, r) => a + (r.transferSize || r.encodedBodySize || 0), 0) / 1024) };
})()
```
Ojo: en `next dev` el JS va sin minificar y los tiempos son más lentos que en producción. **Úsalos para comparar pantallas entre sí y para ver cascadas, no como presupuesto absoluto.** El tamaño real por ruta sale de `next build` (First Load JS) — pídeselo a Felipe o a CI y rotula `[sin medir]` mientras tanto.

**Objetivos táctiles (<44 px)**:
```js
[...document.querySelectorAll('button, a, [role=button], input, select, [tabindex]')]
  .map(e => { const r = e.getBoundingClientRect(); return { t: (e.innerText || e.ariaLabel || e.name || e.tagName).slice(0, 28), w: Math.round(r.width), h: Math.round(r.height) }; })
  .filter(x => x.w && x.h && (x.w < 44 || x.h < 44)).slice(0, 25)
```
En celular importa solo lo que se toca con el pulgar; en escritorio, 44 px no es regla (señálalo si es denso a propósito).

**Contraste** — `computer` + `zoom` en 3 zonas: texto secundario, insignias de estado, borde de campo. Los pares de los trece tokens ya se midieron (ver comentarios en `globals.css`); lo que se busca es **uso** fuera de esos pares (p. ej. `text-taupe` sobre `sand`).

**Estados** — para cada pantalla: vacío (sin datos), cargando (¿colibrí a pantalla completa o esqueleto dentro del marco?, ¿el menú lateral se mantiene o se remonta?), error (corta la red con la herramienta de red del navegador o apunta a una ruta rota; ¿el mensaje se entiende y ofrece salida?), y éxito tras guardar (¿hay confirmación visible en <100 ms?).

**Movimiento** — abre y cierra un modal, un cajón y la hoja inferior (celular): ¿entra y sale con `@keyframes` del sistema? ¿Se siente igual en todas las pantallas? Con `emulate_media`/`prefers-reduced-motion: reduce`, ¿se apagan las animaciones decorativas sin perder información?

## 3 · Cómo se anota

Cada fila del informe: `pantalla · tamaño · tema · qué se midió · valor · [visto]/[medido]`. Una captura solo cuando un hallazgo no se entiende sin ella. Si no hubo sesión, escribe en el informe, literal: «Fase 3 NO ejecutada: sin sesión local. Quedan sin verificar: …».

## 4 · Al terminar

`preview_stop` del servidor, `resize_window` a `desktop`, y confirma con `git status --short` que no quedó nada sin querer (`.env.local` está ignorado).
