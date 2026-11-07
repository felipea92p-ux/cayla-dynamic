// Lo mío es una sola dirección con diecisiete secciones (`?tab=`, ver lib/mio-secciones.ts). Medir solo el Resumen dejaba fuera justo las que se
// rompían en el teléfono: la tabla «Día por día» y la de «Tus últimos periodos» se cortaban de lado y ningún medidor lo veía. Cada sección es un
// escenario: se abre su dirección y se mide como se ve.

import { abrirPantalla } from "../../tema/motor/pagina.mjs";

// La lista de `Tab` en lib/mio-secciones.ts, sin «resumen», que es el estado inicial. La prueba de medidores compara las dos.
export const SECCIONES_DE_LO_MIO = [
  "dias", "turnos", "disponibilidad", "ausencias", "boletas", "movilidad", "educacion", "contrato", "firma", "dni", "seguro", "datos",
  "objetivos", "reportes", "disciplina", "historial",
];

/** @type {import('./registro.mjs').PantallaSinModulo} */
const pantallaLoMio = {
  id: "mio",
  nombre: "Lo mío",
  ruta: "/mio",
  cuenta: "integrante",
  escenarios: [
    { id: "inicial", nombre: "Resumen" },
    ...SECCIONES_DE_LO_MIO.map((tab) => ({
      id: tab,
      nombre: `Sección ${tab}`,
      async preparar(pagina) {
        const url = new URL(pagina.url());
        url.searchParams.set("tab", tab);
        const { termino } = await abrirPantalla(pagina, url.href, { esperaMs: 500 });
        if (!termino) throw new Error(`la sección ${tab} seguía en «Cargando…»`);
      },
    })),
  ],
};

export default pantallaLoMio;
