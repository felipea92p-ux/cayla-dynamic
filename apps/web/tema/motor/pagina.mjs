// Abrir una pantalla y esperar a que tenga algo que medir. Casi todo Dynamic se dibuja en el navegador con datos que llegan después, así que
// medir justo al cargar mide el colibrí de «Cargando…» y da un verde que no significa nada.

export const rutaDe = (url) => new URL(url).pathname.replace(/\/$/, "") || "/";

/** El colibrí también aletea en un botón ocupado y en el panel del login: solo cuenta si es la espera de una pantalla. */
const sinCargando = () =>
  ![...document.querySelectorAll(".colibri.aletea")].some((el) => el.closest('[role="status"]') || /^cargando/i.test((el.parentElement?.textContent ?? "").trim()));

export async function abrirPantalla(pagina, url, { esperaMs = 1200 } = {}) {
  // La primera vez, `next dev` compila la ruta: puede tardar minutos.
  await pagina.goto(url, { waitUntil: "domcontentloaded", timeout: 240_000 });
  await pagina.waitForLoadState("networkidle", { timeout: 20_000 }).catch(() => {});
  const termino = await pagina.waitForFunction(sinCargando, null, { timeout: 45_000 }).then(
    () => true,
    () => false,
  );
  await pagina.evaluate(() => document.fonts?.ready);
  await pagina.waitForTimeout(esperaMs);
  return { ruta: rutaDe(pagina.url()), termino };
}
