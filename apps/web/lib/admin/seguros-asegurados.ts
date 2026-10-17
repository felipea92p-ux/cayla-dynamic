// ============================================================================
// seguros-asegurados.ts — la lista de asegurados de un seguro, lista para el contador
// ============================================================================
// QUÉ PROMETE
//   Tomar lo que devuelve `fn_seguro_asegurados` (0528) y dejarlo en dos formas: el
//   resumen y los datos que faltan, para la pantalla; y las filas de un CSV, para la
//   aseguradora y el contador. Funciones puras: se prueban con vitest
//   (`tests/seguros-asegurados.test.ts`).
//
// QUÉ NO DECIDE
//   Quién está en un seguro. Eso lo dice la base (`fn_seguro_asegurados`): el seguro
//   principal de hoy de cada persona, o su póliza vigente. Aquí no se vuelve a
//   calcular, igual que `seguros.ts` no recalcula el hueco.
//
// POR QUÉ EXISTE (Felipe, 2026-10-17): «que el propio sistema lo jale y no se tenga que
//   rellenar los datos de nuevo». Para el Seguro de Vida Ley el contador pide la «lista
//   nominal exacta» de quiénes están en planilla (docs/movilidad-y-codigos-plame-para-el-contador.md)
//   y hasta hoy se armaba con una consulta a mano (`scripts/sql-manual/quienes_van_al_seguro_de_vida_ley.sql`).
//
// ES INFORMACIÓN PERSONAL: documento y fecha de nacimiento (y, si se pide, la remuneración).
//   Que el archivo salga del sistema es otro permiso que verlo en pantalla:
//   `puedeExportarListaDeAsegurados` (hoy DO y la dirección, decisión de Felipe; el padrón completo
//   sigue solo para la dirección).
// ============================================================================
import { TIPO_DOCUMENTO_LABEL, type TipoDocumento } from "@cayla-dynamic/shared";
import { etiquetaVinculo } from "./seguros";

/** Una fila de `fn_seguro_asegurados` (0528). */
export interface Asegurado {
  persona_id: string;
  apellidos: string;
  nombres: string;
  nombre_segun_dni: string | null;
  tipo_documento: string | null;
  documento: string | null;
  fecha_nacimiento: string | null;
  fecha_ingreso: string | null;
  sede: string;
  tipo_vinculo: string;
  activa: boolean;
  /** Solo viene si se pidió (`p_con_remuneracion`): la remuneración asegurable del seguro de vida. */
  remuneracion: number | null;
  poliza_id: string | null;
  numero_poliza: string | null;
  aseguradora: string | null;
  vigente_desde: string | null;
  vigente_hasta: string | null;
}

/**
 * Lo que la aseguradora no emite sin tener: sin documento o sin fecha de nacimiento no hay certificado
 * individual, y esa persona queda fuera de la póliza sin que nadie lo note hasta que haga falta
 * (la misma lección de `quienes_van_al_seguro_de_vida_ley.sql`, consulta 3).
 */
export type DatoFaltante = "documento" | "fecha_nacimiento" | "remuneracion";

export const ETIQUETA_DATO_FALTANTE: Record<DatoFaltante, string> = {
  documento: "documento",
  fecha_nacimiento: "fecha de nacimiento",
  remuneracion: "remuneración",
};

const vacio = (t: string | null | undefined) => t == null || t.trim() === "";

/** Qué datos le faltan a esta persona para que la aseguradora emita su certificado. */
export function datosQueFaltan(a: Asegurado, conRemuneracion = false): DatoFaltante[] {
  const faltan: DatoFaltante[] = [];
  if (vacio(a.documento)) faltan.push("documento");
  if (vacio(a.fecha_nacimiento)) faltan.push("fecha_nacimiento");
  if (conRemuneracion && a.remuneracion == null) faltan.push("remuneracion");
  return faltan;
}

export interface ResumenDeLista {
  total: number;
  activas: number;
  /** Ya no están activas y la aseguradora todavía las cubre: hay que pedir su baja. */
  inactivas: number;
  /** A cuántas les falta algún dato. */
  incompletas: number;
}

export function resumenDeLista(filas: readonly Asegurado[], conRemuneracion = false): ResumenDeLista {
  let activas = 0;
  let incompletas = 0;
  for (const a of filas) {
    if (a.activa) activas += 1;
    if (datosQueFaltan(a, conRemuneracion).length > 0) incompletas += 1;
  }
  return { total: filas.length, activas, inactivas: filas.length - activas, incompletas };
}

/** «DNI», «Carné de extranjería»…; un tipo que el código no conoce se escribe tal cual. */
export function etiquetaDeDocumento(tipo: string | null): string {
  if (!tipo) return "";
  return TIPO_DOCUMENTO_LABEL[tipo as TipoDocumento] ?? tipo;
}


/** Las columnas del archivo, en este orden. La remuneración solo está si se la pidió. */
export function columnasDeLista(conRemuneracion: boolean): string[] {
  return [
    "Apellidos", "Nombres", "Nombre según DNI", "Tipo de documento", "Documento",
    "Fecha de nacimiento", "Fecha de ingreso", "Sede", "Vínculo", "Situación",
    ...(conRemuneracion ? ["Remuneración asegurable"] : []),
    "Póliza", "Aseguradora", "Vigente desde", "Vigente hasta", "REVISAR",
  ];
}

/**
 * Las filas del CSV. `REVISAR` dice qué le falta a cada una —como el padrón—: una columna que falta
 * se pasa por alto, una vacía se ve y se llena. Las fechas van en ISO (2026-10-17), como el padrón y
 * el resto de las exportaciones: «05/10/2026» se lee como 10 de mayo en una computadora con Excel en
 * inglés, y aquí cada fecha decide si una persona está cubierta. El documento viaja como texto:
 * `generarCsv` lo protege de que Excel le coma el cero de adelante.
 */
export function filasDeLista(filas: readonly Asegurado[], conRemuneracion: boolean): Record<string, unknown>[] {
  return filas.map((a) => ({
    "Apellidos": a.apellidos,
    "Nombres": a.nombres,
    "Nombre según DNI": a.nombre_segun_dni ?? "",
    "Tipo de documento": etiquetaDeDocumento(a.tipo_documento),
    "Documento": a.documento ?? "",
    "Fecha de nacimiento": a.fecha_nacimiento ?? "",
    "Fecha de ingreso": a.fecha_ingreso ?? "",
    "Sede": a.sede,
    "Vínculo": etiquetaVinculo(a.tipo_vinculo),
    "Situación": a.activa ? "Activa" : "Ya no está activa: pedir la baja",
    ...(conRemuneracion ? { "Remuneración asegurable": a.remuneracion == null ? "" : a.remuneracion.toFixed(2) } : {}),
    "Póliza": a.numero_poliza ?? "",
    "Aseguradora": a.aseguradora ?? "",
    "Vigente desde": a.vigente_desde ?? "",
    "Vigente hasta": a.vigente_hasta ?? "",
    "REVISAR": datosQueFaltan(a, conRemuneracion).map((d) => `falta ${ETIQUETA_DATO_FALTANTE[d]}`).join(" · "),
  }));
}

/** `cayla-asegurados-vida-ley-2026-10-17.csv`: el seguro y el día, sin nada que identifique a nadie. */
export function nombreDeArchivoDeLista(claveDelSeguro: string, hoy: string): string {
  const seguro = claveDelSeguro.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "seguro";
  return `cayla-asegurados-${seguro}-${hoy}.csv`;
}
