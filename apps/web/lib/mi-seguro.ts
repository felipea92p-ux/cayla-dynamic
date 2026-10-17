// ============================================================================
// mi-seguro.ts — lo que «Mi seguro» (Lo mío) decide para dibujar
// ============================================================================
// QUÉ PROMETE
//   Funciones puras sobre las filas de `fn_mi_seguro` (0530): cómo está la
//   cobertura de la practicante hoy, hasta cuándo sigue contando las renovaciones
//   que empalman, qué datos de la póliza ya están confirmados, cómo se rotula y se
//   nombra cada archivo, y el texto fijo de «cómo usarlo». Sin React ni Supabase:
//   se prueba con vitest (`tests/mi-seguro.test.ts`).
//
// SOLO PRACTICANTES (Felipe, 2026-10-17)
//   FOLA es exclusiva de los practicantes y el seguro del resto del equipo (EsSalud,
//   por planilla) se deja como está. Quién es practicante lo dice la base: la
//   función devuelve vacío a quien no lo es, y la sección no se ofrece. Aquí no se
//   vuelve a decidir.
//
// QUÉ NO DECIDE
//   Si una póliza cubre HOY: lo dice la base (`cubre_hoy`), con el mismo cálculo del
//   tablero de DO. Si esto lo recalculara, la practicante y DO leerían dos
//   respuestas a «¿tengo seguro hoy?».
//   Tampoco dice si la prima está pagada ni si la cobertura está suspendida por
//   mora: esos datos no salen de la base hacia la practicante (ver la cabecera de
//   la 0530), y «al día» aquí es que la póliza está vigente.
//
// POR QUÉ SE PARECE A `seguroPorPersona`
//   `lib/admin/seguros.ts` hace esta misma cuenta para el tablero de DO, sobre
//   muchas personas. Aquí es sobre una sola y sin los datos de DO. Las dos tienen
//   que dar la misma respuesta para las mismas pólizas, y
//   `tests/mi-seguro.test.ts` las compara con una batería de casos. Se reutilizan
//   las piezas que no cambian (`cubiertoHasta`, `DIAS_AVISO_RENOVACION`) en vez de
//   escribirlas otra vez.
// ============================================================================
import type { ClienteCayla } from "@cayla-dynamic/database";
import { diasEntre } from "./bandeja-mia";
import { cubiertoHasta, DIAS_AVISO_RENOVACION, loVeLaPracticante } from "./admin/seguros";

export type TipoArchivoMio = "poliza" | "convenio_pago";

/** Un archivo que la practicante puede abrir. No lleva el nombre con que DO lo subió. */
export interface ArchivoMio {
  id: string;
  tipo: TipoArchivoMio;
  storage_path: string;
  mime: string;
  bytes: number;
}

/** Una póliza de la practicante, con sus archivos ya leídos. */
export interface PolizaMia {
  poliza_id: string;
  aseguradora: string;
  numero_poliza: string;
  vigente_desde: string;
  /** EXCLUSIVO: la póliza cubre hasta las 12 M de este día. */
  vigente_hasta: string;
  cubre_hoy: boolean;
  /** null = el corredor todavía no lo confirmó. */
  plan: string | null;
  beneficio_enfermedad: number | null;
  beneficio_accidente: number | null;
  archivos: ArchivoMio[];
}

/** Una fila de `fn_mi_seguro` tal como llega: `archivos` es un json sin tipar. */
export interface FilaMiSeguro extends Omit<PolizaMia, "archivos"> {
  archivos: unknown;
}

// ── Leer lo que manda la base ───────────────────────────────────────────────

/**
 * `archivos` llega como json. Se leen solo las entradas con la forma esperada y se
 * descarta lo demás en vez de reventar: una fila rara no tiene por qué tumbar la
 * sección entera.
 */
export function archivosDe(valor: unknown): ArchivoMio[] {
  if (!Array.isArray(valor)) return [];
  const salida: ArchivoMio[] = [];
  for (const x of valor) {
    if (!x || typeof x !== "object") continue;
    const a = x as Record<string, unknown>;
    if (typeof a.tipo !== "string" || !loVeLaPracticante(a.tipo)) continue;
    if (typeof a.id !== "string" || typeof a.storage_path !== "string") continue;
    salida.push({
      id: a.id,
      tipo: a.tipo as TipoArchivoMio,
      storage_path: a.storage_path,
      mime: typeof a.mime === "string" ? a.mime : "application/pdf",
      bytes: typeof a.bytes === "number" ? a.bytes : 0,
    });
  }
  return salida;
}

export function leerPolizasMias(filas: readonly FilaMiSeguro[]): PolizaMia[] {
  return filas.map((f) => ({ ...f, archivos: archivosDe(f.archivos) }));
}

/** Pide `fn_mi_seguro`. Nunca lanza: si falla, `error` trae un texto para leerse. */
export async function traerMiSeguro(
  supabase: ClienteCayla,
): Promise<{ polizas: PolizaMia[]; error: string | null }> {
  const { data, error } = await supabase.rpc("fn_mi_seguro");
  if (error) return { polizas: [], error: "No pudimos leer tu seguro. Vuelve a intentarlo en un momento." };
  return { polizas: leerPolizasMias((data ?? []) as unknown as FilaMiSeguro[]), error: null };
}

// ── Cómo está la cobertura hoy ──────────────────────────────────────────────

/**
 * al_dia ......... cubierta hoy, con margen (o con una renovación que empalma).
 * por_vencer ..... cubierta hoy, pero se queda sin póliza en `DIAS_AVISO_RENOVACION`
 *                  días o menos y no hay una renovación registrada que siga.
 * sin_cobertura .. tiene pólizas registradas pero ninguna cubre hoy.
 * sin_poliza ..... no hay ninguna póliza registrada a su nombre.
 *
 * Las tres primeras son las mismas de `SituacionSeguro` en el tablero de DO
 * (`al_dia`, `por_vencer`, `hueco`); aquí `hueco` se llama `sin_cobertura` porque
 * lo lee ella, no DO.
 */
export type SituacionMiSeguro = "al_dia" | "por_vencer" | "sin_cobertura" | "sin_poliza";

export interface MiSeguro {
  situacion: SituacionMiSeguro;
  /** La que habla por ella: la que cubre hoy; si ninguna, la próxima en empezar; si ninguna, la última que venció. */
  actual: PolizaMia | null;
  /** Las demás, la más reciente primero. */
  otras: PolizaMia[];
  /** Hasta cuándo sigue cubierta sin interrupción (EXCLUSIVO), contando las renovaciones que empalman. Null si hoy no cubre. */
  cubiertoHasta: string | null;
  /** Días que faltan para quedar sin póliza, contados desde hoy. Null si hoy no cubre. */
  diasParaQuedarSinSeguro: number | null;
  /** Si hoy no cubre y hay una póliza que empieza más adelante: cuándo. */
  empiezaEl: string | null;
  /** Si hoy no cubre y la última ya venció: hace cuántos días terminó. */
  diasDesdeQueVencio: number | null;
}

export function resolverMiSeguro(polizas: readonly PolizaMia[], hoy: string): MiSeguro {
  // Más reciente primero; `poliza_id` desempata para que el orden no dependa de
  // cómo llegaron las filas.
  const ordenadas = [...polizas].sort(
    (a, b) => b.vigente_desde.localeCompare(a.vigente_desde) || b.poliza_id.localeCompare(a.poliza_id),
  );

  if (ordenadas.length === 0) {
    return {
      situacion: "sin_poliza", actual: null, otras: [], cubiertoHasta: null,
      diasParaQuedarSinSeguro: null, empiezaEl: null, diasDesdeQueVencio: null,
    };
  }

  const cubre = ordenadas.find((p) => p.cubre_hoy) ?? null;
  const proxima = ordenadas.filter((p) => p.vigente_desde > hoy)
    .sort((a, b) => a.vigente_desde.localeCompare(b.vigente_desde))[0] ?? null;
  const ultimaVencida = ordenadas.find((p) => p.vigente_hasta <= hoy) ?? null;
  const actual = cubre ?? proxima ?? ultimaVencida ?? ordenadas[0];
  const otras = ordenadas.filter((p) => p.poliza_id !== actual.poliza_id);

  if (!cubre) {
    return {
      situacion: "sin_cobertura", actual, otras, cubiertoHasta: null, diasParaQuedarSinSeguro: null,
      empiezaEl: proxima?.vigente_desde ?? null,
      diasDesdeQueVencio: ultimaVencida ? diasEntre(ultimaVencida.vigente_hasta, hoy) : null,
    };
  }

  const hasta = cubiertoHasta(cubre, ordenadas);
  const dias = diasEntre(hoy, hasta);
  return {
    situacion: dias <= DIAS_AVISO_RENOVACION ? "por_vencer" : "al_dia",
    actual, otras, cubiertoHasta: hasta, diasParaQuedarSinSeguro: dias, empiezaEl: null, diasDesdeQueVencio: null,
  };
}

// ── Lo que la póliza ya tiene confirmado ────────────────────────────────────

export interface DatoConfirmado {
  etiqueta: string;
  valor: string;
}

/**
 * El plan y los beneficios máximos que el corredor ya confirmó, y NADA de lo que
 * no. Un dato sin confirmar (null) no se muestra ni como «pendiente»: el convenio
 * ya promete 14 y 30 subvenciones, y una cifra equivocada —o un «sin confirmar» que
 * se lee como «no cubre»— es peor que callar. `dinero` formatea los soles.
 */
export function datosConfirmados(
  p: Pick<PolizaMia, "plan" | "beneficio_enfermedad" | "beneficio_accidente">,
  dinero: (n: number) => string,
): DatoConfirmado[] {
  const datos: DatoConfirmado[] = [];
  if (p.plan && p.plan.trim() !== "") datos.push({ etiqueta: "Plan", valor: p.plan.trim() });
  if (p.beneficio_enfermedad !== null) datos.push({ etiqueta: "Máximo anual por enfermedad", valor: dinero(p.beneficio_enfermedad) });
  if (p.beneficio_accidente !== null) datos.push({ etiqueta: "Máximo anual por accidente", valor: dinero(p.beneficio_accidente) });
  return datos;
}

// ── Los archivos ────────────────────────────────────────────────────────────

const ROTULO: Record<TipoArchivoMio, string> = { poliza: "Tu póliza", convenio_pago: "Convenio de pago" };

/**
 * Cómo se llama un archivo en pantalla: por su TIPO, nunca por el nombre con que DO
 * lo subió (esa palabra la escribe otra persona y la base ni siquiera la manda).
 * Si hay varios del mismo tipo se numeran: «Tu póliza (2)».
 */
export function rotuloDeArchivo(archivo: ArchivoMio, de: readonly ArchivoMio[]): string {
  const base = ROTULO[archivo.tipo];
  const mismos = de.filter((a) => a.tipo === archivo.tipo);
  if (mismos.length <= 1) return base;
  return `${base} (${mismos.findIndex((a) => a.id === archivo.id) + 1})`;
}

const EXTENSION_POR_MIME: Record<string, string> = {
  "application/pdf": "pdf",
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heif",
};

/**
 * El nombre con que se guarda al descargar: `Poliza-FOLA-<número>.pdf`. Solo
 * letras, cifras y guiones: el número lo tecleó DO y podría traer espacios o una
 * barra, que en un nombre de archivo rompen o se leen mal. Sin el nombre de la
 * persona: el archivo queda en sus descargas, a la vista de quien use ese equipo.
 */
export function nombreDeDescarga(archivo: ArchivoMio, numeroPoliza: string): string {
  const numero = numeroPoliza.replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "sin-numero";
  const extension = EXTENSION_POR_MIME[archivo.mime] ?? archivo.storage_path.split(".").pop() ?? "pdf";
  return `${archivo.tipo === "poliza" ? "Poliza-FOLA" : "Convenio-de-pago-FOLA"}-${numero}.${extension}`;
}

// ── El texto fijo: cómo usar el seguro ──────────────────────────────────────
// Sale del resumen informativo de la póliza FOLA de Pacífico (páginas 2 a 5 del
// PDF que tiene Felipe). NO es la póliza: lo que vale es el PDF, y la pantalla lo
// dice. Si el producto cambia en una renovación hay que volver a leer ese resumen
// y corregir esto; no hay otra copia del texto.

export interface PasoDeUso {
  clave: string;
  titulo: string;
  texto: string;
}

export const COMO_USARLO: readonly PasoDeUso[] = [
  {
    clave: "credito",
    titulo: "Atención al crédito",
    texto: "En la red de Pacífico, la atención es al crédito: basta con mostrar tu DNI.",
  },
  {
    clave: "hospitalizacion",
    titulo: "Si te van a hospitalizar",
    texto:
      "Hace falta una carta de garantía de Pacífico. El proveedor (la clínica) la solicita con 3 días útiles " +
      "de anticipación, salvo en una emergencia: avísale apenas sepas la fecha.",
  },
  {
    clave: "domicilio",
    titulo: "Médico a domicilio",
    texto: "Para un médico a domicilio, usa Pacífico Asiste.",
  },
  {
    clave: "reembolso",
    titulo: "Si pagaste tú una atención cubierta",
    texto: "Puedes pedir el reembolso dentro de 90 días, presentando los documentos originales.",
  },
];

/** Los dos teléfonos de Pacífico, tal cual. No se les asigna un uso (cuál es cuál) porque la nota de donde salen no lo distingue. */
export const TELEFONOS_PACIFICO: readonly string[] = ["(01) 415-1515", "(01) 513-5000"];

/**
 * Un teléfono de Lima escrito «(01) 415-1515» como enlace para llamar desde el
 * teléfono: `tel:+5114151515` (51 es Perú; el 1, Lima). Si la cuenta saliera mal,
 * tocar el número marcaría OTRO: por eso está aquí y con su prueba.
 */
export function enlaceTelefono(telefono: string): string {
  const cifras = telefono.replace(/\D/g, "").replace(/^0/, "");
  return `tel:+51${cifras}`;
}

export const NO_CUBRE: readonly string[] = [
  "Gestación",
  "Odontología, salvo por accidente",
  "Salud mental",
  "Preexistencias: lo que ya tenías antes de entrar a la póliza",
];
