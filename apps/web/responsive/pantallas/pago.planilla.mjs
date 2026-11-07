// Planilla en computadora: quien marca el pago de una fila tiene que ver, a la vez, a quién y cuánto. La tabla tiene quince columnas y no cabe
// (a 1440 px sobran ~330), así que el nombre se queda fijo a la izquierda y «Total» · «Pagado» · abrir a la derecha. Hasta el 2026-11-07 no era así:
// para llegar a «Pagado» había que deslizar, y al deslizar el nombre se iba.
//
// El escenario «inicial» no lo habría visto nunca: el medidor se salta lo que vive dentro de una caja que corre de lado, porque ahí «se llega
// deslizando». `limite` apaga ese salto y `ambito` lo acota a la tabla. Y como no todo lo de la tabla tiene que verse —las columnas del medio son
// justamente las que se deslizan—, lo que se mide son solo las celdas que NO pueden irse: la primera de cada fila y las tres últimas.
//
// Dos posiciones, porque cada una prueba un lado: sin deslizar, lo de la derecha tiene que estar a la vista; deslizada hasta el final, el nombre.
// A 768 px lo de la derecha no se fija a propósito (lo fijo se comería la tabla), así que «sin deslizar» empieza en 1024; a 375 px la tabla no
// existe: el teléfono usa tarjetas.

const MARCA = "data-medicion-tabla-planilla";

const CELDAS_FIJAS = [
  ":is(thead, tbody, tfoot) tr > :first-child",
  ":is(thead, tbody, tfoot) tr > :nth-last-child(-n + 3)",
].map((s) => `[${MARCA}] ${s}`);

/** @returns {import('./registro.mjs').Escenario} */
function tablaDeslizada({ id, nombre, alFinal, viewports }) {
  return {
    id,
    nombre,
    viewports,
    ambito: `[${MARCA}]`,
    limite: `[${MARCA}]`,
    elementosClave: CELDAS_FIJAS,
    // La fila vacía («Nadie de este grupo coincide…») ocupa las quince columnas: no es una celda fija.
    exclusiones: [`[${MARCA}] td[colspan="15"]`],
    async preparar(pagina) {
      const tabla = pagina.locator("table:has(th:text-is('Pagado'))").filter({ visible: true }).first();
      await tabla.waitFor({ timeout: 15000 }).catch(() => {
        throw new Error("La tabla de Planilla no apareció: ¿hay un periodo abierto en la base local? Ver scripts/local/LEEME.md.");
      });
      const sobra = await tabla.evaluate((t, { marca, alFinal }) => {
        // La marca la pone la medición, no la pantalla: así se puede medir también una versión vieja de la pantalla.
        const caja = t.parentElement;
        caja.setAttribute(marca, "");
        caja.scrollLeft = alFinal ? caja.scrollWidth : 0;
        return caja.scrollWidth - caja.clientWidth;
      }, { marca: MARCA, alFinal });
      // Si la tabla cupiera entera, el escenario pasaría sin medir nada que se deslice: se dice, no se calla.
      if (sobra <= 0 && alFinal) throw new Error("La tabla de Planilla cabe entera en este ancho: «deslizada al final» no mide nada aquí. Sácale este ancho.");
    },
  };
}

/** @type {import('./registro.mjs').PantallaSinModulo} */
const pantallaPlanilla = {
  id: "planilla",
  nombre: "Planilla",
  ruta: "/admin/planilla",
  cuenta: "do",
  escenarios: [
    { id: "inicial", nombre: "Estado inicial" },
    tablaDeslizada({
      id: "tabla-sin-deslizar",
      nombre: "La tabla sin deslizar: Total y Pagado a la vista",
      alFinal: false,
      viewports: ["1024x768", "1280x800", "1440x900", "1920x1080"],
    }),
    tablaDeslizada({
      id: "tabla-al-final",
      nombre: "La tabla deslizada hasta el final: el nombre a la vista",
      alFinal: true,
      viewports: ["768x1024", "1024x768", "1280x800", "1440x900"],
    }),
  ],
};

export default pantallaPlanilla;
