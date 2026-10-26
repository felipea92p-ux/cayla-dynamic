"use client";

import { useEffect } from "react";

// Registra `/sin-conexion-sw.js`, el que muestra la página del colibrí cuando se
// abre Dynamic sin internet. Qué hace y, sobre todo, qué NO hace (no guarda
// ninguna página del panel) está en ese archivo; léelo antes de tocar esto.
//
// Se monta en los layouts del panel y de «Lo mío» y NO en el del terminal, y a
// propósito: el terminal tiene su propio service worker, con alcance
// `/terminal/`, para seguir marcando sin red. Registrar este con alcance `/`
// desde una pantalla del terminal no lo rompería —el alcance más específico
// gana, y el archivo ignora /terminal—, pero dejaría dos service workers
// compitiendo en una Mac mini de sede donde ya hay uno que funciona.
//
// Solo en producción, por la misma razón que el del terminal y por una más:
// en `localhost` el origen se comparte con cualquier otro proyecto que corra
// en ese mismo puerto, y un service worker de alcance `/` se queda ahí aunque
// este servidor se apague — el siguiente proyecto mostraría «Sin conexión» al
// primer error.
const CLAVE_REFRESCADO = "cayla-sin-conexion-refrescado";

export function RegistrarSinConexion() {
  useEffect(() => {
    if (process.env.NODE_ENV !== "production") return;
    if (!("serviceWorker" in navigator)) return;
    navigator.serviceWorker
      .register("/sin-conexion-sw.js", { scope: "/" })
      .then(() => navigator.serviceWorker.ready)
      .then(() => refrescarActivos())
      .catch(() => {
        // Sin service worker, sin internet se ve el error del navegador, igual que siempre.
        // No hay nada que avisarle a quien está trabajando.
      });
  }, []);
  return null;
}

// La página y el juego se guardan al instalar el service worker, pero una mejora
// posterior a ellos no reinstalaría nada si el service worker no cambió. Una vez por
// sesión se piden de nuevo —pasan por el service worker, que guarda lo nuevo— para
// que la copia de la caché no quede detrás de lo publicado. Son dos archivos chicos.
function refrescarActivos() {
  if (!navigator.onLine) return;
  try {
    if (sessionStorage.getItem(CLAVE_REFRESCADO)) return;
    sessionStorage.setItem(CLAVE_REFRESCADO, "1");
  } catch {
    // Sin sessionStorage se refresca en cada visita: cuesta dos peticiones chicas, no rompe nada.
  }
  for (const ruta of ["/sin-conexion.html", "/colibri/juego.js"]) {
    void fetch(ruta, { cache: "no-cache" }).catch(() => {});
  }
}
