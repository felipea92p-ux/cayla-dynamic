// Las pantallas que verifica `responsive:check`. Al menos una por cada módulo de la obra, de las que se abren sin parámetros. El módulo no se escribe:
// sale de la ruta (`tema/motor/rutas.mjs`), que es la misma respuesta que usa la auditoría de contraste.
//
// Una pantalla sin nada especial es una línea de esta tabla. Una con escenarios vive en su propio archivo (ver `inicio.dashboard.mjs`) y se importa aquí.

/**
 * @typedef {object} Escenario
 * @property {string} id
 * @property {string} nombre
 * @property {(pagina: import('playwright').Page, ctx: { viewport: {id:string,w:number,h:number}, pantalla: Pantalla, escenario: Escenario }) => Promise<void>} [preparar]
 * @property {undefined | string[] | { excluir: string[] }} [viewports]   si solo existe en algunos anchos; si no, los de la pantalla
 * @property {string[]} [elementosClave]   selectores extra a inspeccionar, solo en este escenario
 * @property {string[]} [exclusiones]      selectores a ignorar, solo en este escenario
 * @property {string} [ambito]             selector que acota QUÉ subárbol se inspecciona
 * @property {string} [limite]             selector cuyo rect reemplaza al viewport como límite
 */

/**
 * @typedef {object} PantallaSinModulo
 * @property {string} id             corto y único (p.ej. "planilla")
 * @property {string} nombre         para el reporte
 * @property {string} ruta           sin baseURL (p.ej. "/admin/planilla")
 * @property {string} cuenta         clave de `tema/cuentas.mjs`: con quién se abre
 * @property {undefined | string[] | { excluir: string[] }} [viewports]   ver `resolverViewports`; por defecto, la matriz completa
 * @property {Escenario[]} [escenarios] por defecto, un único escenario «inicial» sin interacción
 * @property {string[]} [elementosClave]
 * @property {string[]} [exclusiones]
 * @property {string} [ambito]
 * @property {string} [limite]
 * @property {boolean} [soloPorId]   no entra en `all` ni en `--module`: solo se corre pidiéndola
 */

/** @typedef {PantallaSinModulo & { modulo: string }} Pantalla */

import { leerMenu, moduloDeRuta } from "../../tema/motor/rutas.mjs";
import pantallaDashboard from "./inicio.dashboard.mjs";

/** @type {PantallaSinModulo[]} */
const PANTALLAS = [
  { id: "login", nombre: "Entrar al panel", ruta: "/admin/login", cuenta: "anonima" },
  pantallaDashboard,
  { id: "bandeja", nombre: "Bandeja", ruta: "/admin/bandeja", cuenta: "admin" },
  { id: "incidencias", nombre: "Incidencias", ruta: "/admin/incidencias", cuenta: "admin" },
  { id: "contratos", nombre: "Contratos", ruta: "/admin/contratos", cuenta: "do" },
  { id: "equipo", nombre: "Equipo", ruta: "/admin/equipo", cuenta: "admin" },
  { id: "datos-personales", nombre: "Datos personales", ruta: "/admin/datos-personales", cuenta: "do" },
  { id: "documentacion", nombre: "Documentación", ruta: "/admin/documentacion", cuenta: "do" },
  { id: "seguros", nombre: "Seguros", ruta: "/admin/seguros", cuenta: "do" },
  { id: "objetivos", nombre: "Objetivos", ruta: "/admin/objetivos", cuenta: "do" },
  { id: "casos", nombre: "Casos", ruta: "/admin/casos", cuenta: "lider" },
  { id: "disciplina", nombre: "Disciplina", ruta: "/admin/disciplina", cuenta: "do" },
  { id: "planilla", nombre: "Planilla", ruta: "/admin/planilla", cuenta: "do" },
  { id: "boletas", nombre: "Boletas", ruta: "/admin/planilla/boletas", cuenta: "do" },
  { id: "provisiones", nombre: "Provisiones", ruta: "/admin/provisiones", cuenta: "do" },
  { id: "costos", nombre: "Costos", ruta: "/admin/costos", cuenta: "do" },
  { id: "educacion", nombre: "Educación", ruta: "/admin/educacion", cuenta: "do" },
  { id: "feriados", nombre: "Feriados", ruta: "/admin/feriados", cuenta: "do" },
  { id: "liquidaciones", nombre: "Liquidaciones", ruta: "/admin/liquidaciones", cuenta: "do" },
  { id: "normas", nombre: "Normas", ruta: "/admin/normas", cuenta: "integrante" },
  { id: "normas-do", nombre: "Normas (DO)", ruta: "/admin/normas", cuenta: "do" },
  { id: "politica-salarial", nombre: "Política salarial", ruta: "/admin/politica-salarial", cuenta: "do" },
  { id: "politica-categorias", nombre: "Categorías", ruta: "/admin/politica-salarial/categorias", cuenta: "do" },
  { id: "politica-versiones", nombre: "Versiones y publicación", ruta: "/admin/politica-salarial/versiones", cuenta: "do" },
  { id: "politica-version", nombre: "Una versión de la política", ruta: "/admin/politica-salarial/versiones/2", cuenta: "do" },
  { id: "politica-constancias", nombre: "Constancias de la política", ruta: "/admin/politica-salarial/constancias", cuenta: "do" },
  { id: "anuncios", nombre: "Anuncios", ruta: "/admin/anuncios", cuenta: "do" },
  { id: "reporte-sede", nombre: "Hoja de sede", ruta: "/admin/reporte-sede", cuenta: "lider" },
  { id: "sedes", nombre: "Sedes", ruta: "/admin/sedes", cuenta: "do" },
  { id: "mio", nombre: "Lo mío", ruta: "/mio", cuenta: "integrante" },
  { id: "mio-nombre-largo", nombre: "Lo mío, con un nombre muy largo", ruta: "/mio", cuenta: "nombre-largo" },
  { id: "mio-sin-datos", nombre: "Lo mío, sin datos todavía", ruta: "/mio", cuenta: "sin-datos" },
  { id: "marcar", nombre: "Terminal de marcaje", ruta: "/terminal/marcar", cuenta: "terminal-tru" },
  // El caso que DEBE fallar: un botón más ancho que el celular, pintado solo en el navegador de la corrida. Si esto pasa en verde, el medidor está roto.
  {
    id: "debe-fallar",
    nombre: "Un botón que se sale, a propósito",
    ruta: "/admin/dashboard",
    cuenta: "admin",
    viewports: ["375x812"],
    soloPorId: true,
    escenarios: [
      {
        id: "boton-ancho",
        nombre: "Tiene que dar FAIL",
        async preparar(pagina) {
          await pagina.evaluate(() => {
            const boton = document.createElement("button");
            boton.textContent = "Botón que se sale";
            boton.style.cssText = "display:block;width:900px";
            document.body.appendChild(boton);
          });
        },
      },
    ],
  },
];

const menu = leerMenu();

/** @type {Pantalla[]} */
export const TODAS_LAS_PANTALLAS = PANTALLAS.map((p) => {
  const modulo = moduloDeRuta(p.ruta, menu);
  return { ...p, modulo, id: `${modulo}.${p.id}` };
});

const NORMALES = TODAS_LAS_PANTALLAS.filter((p) => !p.soloPorId);

export const PANTALLAS_POR_ID = new Map(TODAS_LAS_PANTALLAS.map((p) => [p.id, p]));

/** módulo → ids de pantalla que lo componen. */
export const MODULOS = NORMALES.reduce((mapa, p) => {
  if (!mapa.has(p.modulo)) mapa.set(p.modulo, []);
  mapa.get(p.modulo).push(p.id);
  return mapa;
}, new Map());

/** Resuelve la selección del CLI a una lista de pantallas. */
export function resolverSeleccion({ ids, modulo, todas }) {
  if (todas) return NORMALES;
  if (modulo) {
    const delModulo = MODULOS.get(modulo);
    if (!delModulo) throw new Error(`No existe el módulo «${modulo}». Son: ${[...MODULOS.keys()].join(", ")}.`);
    return delModulo.map((id) => PANTALLAS_POR_ID.get(id));
  }
  if (!ids || !ids.length) throw new Error("No diste ninguna pantalla, módulo (--module) ni «all». Ver responsive/README.md.");
  return ids.map((id) => {
    const pantalla = PANTALLAS_POR_ID.get(id) ?? buscarPorNombreCorto(id);
    if (!pantalla) throw new Error(`No existe la pantalla «${id}». Son: ${[...PANTALLAS_POR_ID.keys()].join(", ")}.`);
    return pantalla;
  });
}

/** Permite pedir «planilla» en vez de «pago.planilla». */
function buscarPorNombreCorto(corto) {
  const candidatas = TODAS_LAS_PANTALLAS.filter((p) => p.id.endsWith(`.${corto}`));
  return candidatas.length === 1 ? candidatas[0] : undefined;
}
