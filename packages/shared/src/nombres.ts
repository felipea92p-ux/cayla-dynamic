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

/**
 * Para una hoja con muchas personas —las constancias de Normas y de Política
 * salarial—: el aviso, solo en pantalla, de a cuántas les falta el nombre
 * completo. `null` si a todas les consta.
 *
 * Está acá y no escrito en cada hoja porque las dos tienen que decir lo mismo,
 * y porque la cuenta de «quién cuenta como faltante» es `usaNombreDelDni`: un
 * `nombre_dni` de puros espacios no está cargado.
 *
 * Quien lo muestra debe callarlo si la lectura de `datos_personales` falló: ahí
 * faltarían todas y el aviso mentiría. Ese caso ya lo cubre el aviso rojo de
 * «no se pudo traer», que además apaga «Imprimir».
 */
export function avisoNombresDelDni(nombresDni: ReadonlyArray<string | null | undefined>): string | null {
  const faltan = nombresDni.filter((n) => !usaNombreDelDni(n)).length;
  if (faltan === 0) return null;
  const quienes =
    faltan === 1
      ? `1 de ${nombresDni.length} integrantes no tiene cargado su nombre completo del DNI; en esta hoja sale solo con el nombre corto.`
      : `${faltan} de ${nombresDni.length} integrantes no tienen cargado su nombre completo del DNI; en esta hoja salen solo con el nombre corto.`;
  return `${quienes} Se carga en Datos personales.`;
}

// ── EL NÚMERO NO VA EN EL NOMBRE ─────────────────────────────────────────────
//
// El 2026-10-06 apareció en el panel una integrante con su DNI escrito dentro
// del apellido corto. Ningún código lo pegó; se tecleó a mano, porque el
// alta no tiene dónde poner el DNI y desde la 0506 un nombre parecido a otro pide
// confirmación — escribir el número es la forma «natural» de distinguir a dos
// personas cuando el formulario no ofrece otra. El resultado es un DNI a la vista
// de cualquiera que abra una lista, y en el terminal de la sede, que marca sin PIN.
//
// La regla es UNA y la base la tiene igual (`personas_nombre_sin_documento`,
// 0512): seis o más dígitos seguidos. Ahí cae cualquier documento —DNI 8, carné
// de extranjería 9, RUC 11, un celular 9— y ningún nombre real ni ninguna
// estación de retail. Si se cambia aquí, se cambia allá.
export const PATRON_DOCUMENTO_EN_NOMBRE = /[0-9]{6,}/;

/**
 * El aviso para quien da de alta o edita, o `null` si el nombre está bien.
 * Dice adónde va el número, no solo que está mal: sin eso se vuelve a escribir.
 */
export function avisoDocumentoEnNombre(nombres: string, apellidos: string): string | null {
  if (!PATRON_DOCUMENTO_EN_NOMBRE.test(nombres) && !PATRON_DOCUMENTO_EN_NOMBRE.test(apellidos)) return null;
  return "El nombre y el apellido corto van sin números: se ven en el terminal y en todas las listas. El DNI se guarda en Datos personales.";
}
