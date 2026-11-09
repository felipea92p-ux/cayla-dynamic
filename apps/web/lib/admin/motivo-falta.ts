// Cómo se nombra el motivo de un día que no se trabajó, tal como lo devuelve `fn_faltas`.
//
// PROMETE: un nombre legible para cualquier `motivo` de fn_faltas. Los tipos de ausencia se nombran desde la
//   tabla `tipos_ausencia` (se le pasa como mapa codigo → nombre); lo que no es un tipo de ausencia —la
//   suspensión (0079) y el descanso sustitutorio (0070)— tiene su nombre aquí.
// ASUME: que quien llama ya leyó `tipos_ausencia`. Si esa lectura falló, el mapa viene vacío y el código se
//   muestra legible («permiso personal»), nunca en blanco.
//
// Vivía dos veces dentro de Incidencias; Inicio (Días perdidos, por motivo) es el tercer lector.

/** Motivos que devuelve fn_faltas y que NO son filas de tipos_ausencia. */
export const MOTIVOS_FUERA_DE_AUSENCIAS: Readonly<Record<string, string>> = {
  suspension: "Suspensión",
  descanso_sustitutorio: "Descanso sustitutorio",
};

/** `permiso_concedido` es el nombre viejo; en tipos_ausencia es `permiso_personal` (0101). */
export function codigoDeMotivo(motivo: string): string {
  return motivo === "permiso_concedido" ? "permiso_personal" : motivo;
}

export function nombreDeMotivo(motivo: string, nombreDeTipo: ReadonlyMap<string, string>): string {
  return nombreDeTipo.get(codigoDeMotivo(motivo)) ?? MOTIVOS_FUERA_DE_AUSENCIAS[motivo] ?? motivo.replaceAll("_", " ");
}
