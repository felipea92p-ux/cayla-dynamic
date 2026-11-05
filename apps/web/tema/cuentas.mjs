// Las cuentas con las que se mide Dynamic. Todas son del entorno LOCAL, con datos inventados: en producción no existen, y `sesion.mjs` se
// niega a usarlas contra algo que no sea esta computadora. Cada una ve pantallas distintas, porque el rol decide el menú.
//
// `almacen` es la clave de localStorage donde la app busca la sesión: el panel y el terminal guardan cada uno la suya, a propósito (ver
// `packages/database/src/client.ts`). `alcance` dice qué rutas son de esa cuenta: una ruta fuera de su alcance no se visita, y una que sí es
// suya y la manda a una pantalla de entrada significa que la sesión no valió —no que «no tenga acceso»—, y eso detiene la medición.

import { ENTRADA } from "./motor/rutas.mjs";

export const CLAVE_LOCAL = process.env.TEMA_CLAVE_LOCAL || "Colibri-Local-2026";

const PANEL_Y_LO_MIO = (ruta) => /^\/(admin|mio)(\/|$)/.test(ruta) && !ENTRADA.includes(ruta);

export const CUENTAS = [
  { clave: "anonima", correo: null, inicio: "/admin/login", alcance: (ruta) => ENTRADA.includes(ruta), descripcion: "Sin sesión: las pantallas de entrada" },
  { clave: "admin", correo: "admin@dynamic.local", inicio: "/admin/dashboard", alcance: PANEL_Y_LO_MIO, descripcion: "Admin: ve todo el panel" },
  { clave: "do", correo: "do@dynamic.local", inicio: "/admin/dashboard", alcance: PANEL_Y_LO_MIO, descripcion: "Desarrollo Organizacional" },
  { clave: "lider", correo: "lider@dynamic.local", inicio: "/admin/dashboard", alcance: PANEL_Y_LO_MIO, descripcion: "Líder de equipo: el panel de su sede" },
  { clave: "integrante", correo: "integrante@dynamic.local", inicio: "/mio", alcance: PANEL_Y_LO_MIO, descripcion: "Integrante: Lo mío y las publicaciones" },
  { clave: "nombre-largo", correo: "nombre.largo@dynamic.local", inicio: "/mio", alcance: PANEL_Y_LO_MIO, descripcion: "Integrante con un nombre muy largo: lo que se sale de su caja" },
  { clave: "sin-datos", correo: "sin.datos@dynamic.local", inicio: "/mio", alcance: PANEL_Y_LO_MIO, descripcion: "Integrante recién llegada: las pantallas vacías" },
  { clave: "terminal-tru", correo: "terminal-tru@dynamic.local", almacen: "cayla-auth-terminal", inicio: "/terminal/marcar", alcance: (ruta) => /^\/terminal(\/|$)/.test(ruta) && !ENTRADA.includes(ruta), descripcion: "El terminal de marcaje de Trujillo" },
];

export const porClave = (clave) => CUENTAS.find((c) => c.clave === clave);
