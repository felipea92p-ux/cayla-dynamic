// ============================================================================
// nombres.ts — Qué nombre va en cada lugar, en un solo sitio
// ============================================================================
// Cada integrante tiene DOS nombres y cada uno sirve a algo distinto:
//
//   · NOMBRE CORTO — `personas.nombres` + `personas.apellidos`. Es el de todos
//     los días: el que se toca en el terminal, el que aparece en el panel, en
//     los filtros y en el buscador. Se cargó con un nombre y un apellido «por
//     practicidad» («Elida Salinas»), y así tiene que seguir: en una pantalla de
//     marcaje que se lee de pie, a un metro, «Elida Lizeth Salinas Mamani» no
//     cabe ni se reconoce más rápido.
//
//   · NOMBRE COMPLETO — `datos_personales.nombre_dni`. Tal como está en el DNI.
//     Es el que identifica a la persona ante un tercero: el contrato, la firma
//     del memo, la boleta, el certificado de trabajo y la constancia de cese.
//     Esta última es la llave con la que alguien retira su CTS del banco, y un
//     banco compara ese nombre contra el DNI.
//
// POR QUÉ NO HAY UNA COLUMNA NUEVA. Los dos ya existían desde la 0001 y la 0061;
// lo que faltaba era que cada papel supiera cuál pedir. Contratos, el memo y
// «Lo mío» ya preguntaban por `nombre_dni`; la boleta y los papeles de cese
// seguían imprimiendo el corto. Eran dos respuestas distintas a «¿cómo se llama
// esta persona en un papel?» dentro del mismo sistema.
//
// POR QUÉ ESTÁ EN `shared` Y NO ESCRITO EN CADA PANTALLA. Aquí ya hubo diez
// copias de `ficha?.nombre_dni || nombre`, y la forma corta tiene un hueco: un
// `nombre_dni` guardado como «   » (espacios) es truthy y habría imprimido un
// papel sin nombre. Esa condición se dice una vez.
//
// EL TERMINAL NO USA NADA DE ESTE ARCHIVO, y es a propósito: nunca pide
// `datos_personales`. Lo vigila `tests/nombres.test.ts`.
// ============================================================================

/** El nombre de todos los días: «Elida Salinas». Terminal, panel, buscadores. */
export function nombreCorto(nombres: string, apellidos: string): string {
  return `${nombres} ${apellidos}`.trim();
}

/**
 * El nombre que va en un papel que sale de la empresa: el completo del DNI.
 *
 * Si la ficha todavía no lo tiene cargado, devuelve el corto en vez de nada: un
 * papel con un nombre incompleto es peor que uno que no se pudo imprimir, pero
 * una pantalla que se rompe por un dato pendiente es peor todavía. El aviso de
 * que falta vive donde se carga —Datos personales ya lo lista en «Pendientes»—
 * y, para los papeles que no se pueden corregir una vez entregados, en la
 * propia pantalla (ver `usaNombreDelDni`).
 */
export function nombreOficial(nombreDni: string | null | undefined, corto: string): string {
  return usaNombreDelDni(nombreDni) ? (nombreDni as string).trim() : corto;
}

/** ¿El papel saldrá con el nombre del DNI, o cayó al corto por falta de dato? */
export function usaNombreDelDni(nombreDni: string | null | undefined): boolean {
  return typeof nombreDni === "string" && nombreDni.trim() !== "";
}
