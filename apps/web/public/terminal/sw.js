// ============================================================================
// sw.js — el terminal sobrevive a un reinicio sin internet
// ============================================================================
// QUÉ PROMETE
//   Que un Mac mini que se reinicia (corte de luz, el navegador se cerró, un
//   `sudo reboot` de mantenimiento) sin conexión pueda volver a abrir
//   `/terminal/marcar` y seguir marcando. Hoy, sin esto, ese reinicio deja a
//   la sede entera sin poder marcar hasta que vuelva la red — el HTML/JS del
//   terminal se pide a la red antes de que React pueda arrancar, y una vez
//   arrancado sí sabe trabajar offline (ver `lib/terminal/offline-db.ts`).
//
// QUÉ NO HACE, A PROPÓSITO
//   No toca ninguna marca. Las marcas viajan por la cola de IndexedDB
//   (`offline-db.ts` + `sync.ts`), que ya sabía trabajar sin red antes de que
//   este archivo existiera — este service worker resuelve un problema
//   DISTINTO: que la propia app pueda arrancar sin red. Por eso el `fetch`
//   handler de abajo ignora todo lo que no sea GET: una marca es un POST a
//   Supabase, nunca pasa por acá.
//
//   No cachea nada fuera de `/terminal/`: se registra con `scope: '/terminal/'`
//   desde `registrar-service-worker.tsx`, y vivir en `/terminal/sw.js` (no en
//   la raíz) hace que ese alcance sea el máximo posible — ni un error de
//   configuración futura podría ampliarlo a `/admin` o a `/mio` sin mover el
//   archivo de sitio.
//
// LA ESTRATEGIA: red primero, caché de respaldo
//   Con red, siempre se sirve y se guarda la versión de la red — el terminal
//   nunca muestra una versión vieja a propósito mientras hay internet. Sin
//   red, se sirve lo último que se guardó. Para una navegación (abrir la
//   página) que no tiene nada guardado, cae al último `/terminal/marcar`
//   cacheado: es la única pantalla que hace falta para volver a marcar.
//
//   No hay una lista de archivos a precachear: Next.js nombra sus paquetes
//   con un hash por build, y precachear una lista fija se desactualiza en el
//   próximo despliegue. En vez de eso, la caché se llena SOLA con lo que el
//   terminal ya pide en el uso normal — quien hoy prende el Mac mini con
//   internet ya está dejando lista la caché para el próximo corte.
// ============================================================================

const CACHE = "cayla-terminal-v1";
const RESPALDO_DE_NAVEGACION = "/terminal/marcar";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((claves) =>
        Promise.all(
          claves
            .filter((c) => c.startsWith("cayla-terminal-") && c !== CACHE)
            .map((c) => caches.delete(c)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;

  // Solo GET. Una marca es un POST a Supabase — nunca debe cachearse ni
  // servirse desde caché, y si fallara acá en vez de en `enviarMarcaje` la
  // cola de IndexedDB nunca se enteraría de que hizo falta reintentarla.
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return; // Supabase, fuentes, etc. — no es de este service worker.

  event.respondWith(
    (async () => {
      try {
        const respuesta = await fetch(request);
        if (respuesta.ok) {
          const cache = await caches.open(CACHE);
          cache.put(request, respuesta.clone());
        }
        return respuesta;
      } catch {
        const cacheada = await caches.match(request);
        if (cacheada) return cacheada;
        if (request.mode === "navigate") {
          const respaldo = await caches.match(RESPALDO_DE_NAVEGACION);
          if (respaldo) return respaldo;
        }
        throw new Error(`sw.js: sin red y sin caché para ${request.url}`);
      }
    })(),
  );
});
