// La matriz de anchos de Dynamic, en un solo lugar: 375, 768, 1024, 1280, 1440 y 1920 px. Ninguna pantalla repite esta lista: usa la matriz entera,
// algunos ids o la matriz menos algunos — ver `resolverViewports`.

/** @typedef {{ id: string, w: number, h: number }} Viewport */

/** @type {Viewport[]} */
export const MATRIZ_VIEWPORTS = [
  { id: "375x812", w: 375, h: 812 },
  { id: "768x1024", w: 768, h: 1024 },
  { id: "1024x768", w: 1024, h: 768 },
  { id: "1280x800", w: 1280, h: 800 },
  { id: "1440x900", w: 1440, h: 900 },
  { id: "1920x1080", w: 1920, h: 1080 },
];

const POR_ID = new Map(MATRIZ_VIEWPORTS.map((v) => [v.id, v]));

function porId(id) {
  const v = POR_ID.get(id);
  if (!v) throw new Error(`El viewport «${id}» no está en la matriz. Son: ${[...POR_ID.keys()].join(", ")}.`);
  return v;
}

/**
 * Qué anchos usa una pantalla, según su `viewports`:
 *  - nada → la matriz completa.
 *  - `string[]` → esos ids, en ese orden.
 *  - `{ excluir: string[] }` → la matriz menos esos ids.
 * @param {undefined | string[] | { excluir: string[] }} config
 * @returns {Viewport[]}
 */
export function resolverViewports(config) {
  if (config === undefined) return MATRIZ_VIEWPORTS;
  if (Array.isArray(config)) return config.map(porId);
  if (config && Array.isArray(config.excluir)) {
    config.excluir.forEach(porId);
    return MATRIZ_VIEWPORTS.filter((v) => !config.excluir.includes(v.id));
  }
  throw new Error(`Esta configuración de viewports no existe: ${JSON.stringify(config)}`);
}
