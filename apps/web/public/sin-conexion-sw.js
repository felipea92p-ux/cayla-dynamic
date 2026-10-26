// ============================================================================
// sin-conexion-sw.js — cuando no hay internet, una página de Dynamic en vez del error del navegador
// ============================================================================
// QUÉ PROMETE
//   Que quien abre el panel, «Lo mío» o el login sin conexión vea
//   `/sin-conexion.html` (un aviso claro y un colibrí que juega) en lugar del
//   dinosaurio y el error crudo del navegador. Solo eso.
//
// QUÉ NO HACE, Y ES LO IMPORTANTE
//   NO GUARDA PÁGINAS DE LA APP. Ni el panel, ni la planilla, ni «Lo mío». Lo
//   único que entra a la caché son los tres archivos de ACTIVOS, que no
//   contienen ningún dato de nadie. Si este service worker guardara el panel,
//   sin internet podría mostrar una planilla de hace tres días como si fuera de
//   hoy, y esta aplicación alimenta el pago de personas reales: preferimos
//   mostrar un colibrí que mostrar un número viejo.
//
//   NO TOCA EL TERMINAL. `/terminal/*` tiene su propio service worker
//   (`/terminal/sw.js`, alcance `/terminal/`), que sí guarda la pantalla de
//   marcaje para seguir marcando sin red. Dos cosas lo mantienen aparte:
//   el alcance más específico gana, y además este archivo ignora a propósito
//   cualquier navegación a /terminal. Una sede sin internet tiene que seguir
//   viendo SU pantalla de marcar, nunca un juego.
//
//   NO INTERCEPTA NADA QUE NO SEA UNA NAVEGACIÓN QUE FALLÓ. Las llamadas a
//   Supabase son de otro origen y ni pasan por aquí; las rutas de la API y los
//   POST son `fetch`, no navegaciones, y siguen su camino. Con red, esto se
//   comporta como si no existiera: pide la página a la red y devuelve lo que
//   la red contesta — también si contesta con un error del servidor, que NO es
//   «sin conexión» y no merece el colibrí.
//
// SI ESTE ARCHIVO FALLA
//   Un service worker roto afecta a todos los dispositivos hasta que se
//   desinstale, y el único modo de «desplegar un arreglo» es que el navegador
//   vuelva a bajar este archivo (lo hace en cada visita, y Vercel lo sirve sin
//   caché larga). Por eso es corto, sin dependencias y sin decisiones: cada
//   rama termina en «dejar pasar» o en «servir el aviso».
//
// LOS ACTIVOS NO SE ACTUALIZAN SOLOS CON ESTE ARCHIVO
//   Si cambia `sin-conexion.html` o `colibri/juego.js` y este archivo no, la
//   caché seguiría con la versión vieja. Por eso: (1) la respuesta de red de
//   cualquiera de los tres reemplaza a la guardada, y (2) la app, en cada
//   sesión, los vuelve a pedir una vez (`registrar-sin-conexion.tsx`).
// ============================================================================

const CACHE = "cayla-sin-conexion-v1";
const PAGINA = "/sin-conexion.html";
const ACTIVOS = [PAGINA, "/colibri/juego.js", "/colibri.png"];

self.addEventListener("install", (event) => {
  // `cache: "reload"` salta la caché HTTP: lo que se guarda es lo que hay en el servidor ahora, no lo que el navegador recordaba.
  event.waitUntil(
    caches
      .open(CACHE)
      .then((cache) => cache.addAll(ACTIVOS.map((ruta) => new Request(ruta, { cache: "reload" }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((claves) =>
        Promise.all(claves.filter((c) => c.startsWith("cayla-sin-conexion-") && c !== CACHE).map((c) => caches.delete(c))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Los tres archivos de la página: primero la red (y se guarda lo nuevo), y si no hay red, lo guardado.
  if (ACTIVOS.includes(url.pathname)) {
    event.respondWith(
      fetch(request)
        .then((respuesta) => {
          if (respuesta.ok) {
            const copia = respuesta.clone();
            caches.open(CACHE).then((cache) => cache.put(url.pathname, copia));
          }
          return respuesta;
        })
        .catch(() => caches.match(url.pathname).then((guardada) => guardada || Response.error())),
    );
    return;
  }

  // Una navegación (abrir una página). El terminal tiene su propio service worker y no se toca.
  if (request.mode === "navigate" && url.pathname !== "/terminal" && !url.pathname.startsWith("/terminal/")) {
    event.respondWith(
      fetch(request).catch(() => caches.match(PAGINA).then((guardada) => guardada || Response.error())),
    );
  }
  // Todo lo demás: sin respondWith, el navegador hace lo que habría hecho de todos modos.
});
