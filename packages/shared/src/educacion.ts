/**
 * LA CONSTANCIA DE ESTUDIOS — las reglas que no son de una pantalla (0450).
 *
 * PROMETE: los nombres en español de cada tipo, motivo, frecuencia y estado; la
 *   fecha que se sugiere como próximo pago; y si un archivo elegido puede
 *   enviarse. Nada acá toca el navegador ni Supabase.
 * ASUME: las listas de abajo son ESPEJO de los `check` de la 0450. La verdad
 *   está en la base: si un día se agrega un tipo allá, se agrega acá también, y
 *   hasta entonces la base rechaza lo que esta lista no conozca.
 * NO HACE: no decide en qué estado está una constancia. Eso lo contesta
 *   `fn_educacion_situacion` — la pantalla de DO, el portal, la Bandeja y el
 *   contador del menú preguntan lo mismo, y una segunda copia de esa cuenta
 *   acá sería cómo empiezan a discrepar.
 *
 * Lo usan dos superficies —el portal de la integrante y el panel de DO—, por
 * eso vive en packages/shared y no en una de las dos.
 */

/** Espejo de `educacion_entrega_tipo_valido` (0450). */
export const TIPOS_CONSTANCIA = ["cuota_mensual", "matricula", "pago_ciclo", "curso_taller", "otro"] as const;
export type TipoConstancia = (typeof TIPOS_CONSTANCIA)[number];

export const TIPO_CONSTANCIA_LABELS: Record<TipoConstancia, string> = {
  cuota_mensual: "Pensión o cuota mensual",
  matricula: "Matrícula",
  pago_ciclo: "Pago del ciclo",
  curso_taller: "Curso o taller",
  otro: "Otro",
};

/** Espejo de `educacion_entrega_motivo_valido` (0450). */
export const MOTIVOS_RECHAZO = [
  "ilegible", "no_corresponde_al_pago", "a_nombre_de_otra_persona",
  "faltan_paginas_o_datos", "otra_institucion", "otro",
] as const;
export type MotivoRechazo = (typeof MOTIVOS_RECHAZO)[number];

export const MOTIVO_RECHAZO_LABELS: Record<MotivoRechazo, string> = {
  ilegible: "No se lee",
  no_corresponde_al_pago: "No corresponde a ese pago",
  a_nombre_de_otra_persona: "Está a nombre de otra persona",
  faltan_paginas_o_datos: "Faltan páginas o datos",
  otra_institucion: "No es de la institución registrada",
  otro: "Otro motivo",
};

/** Espejo de `asignacion_educacion_frecuencia_valida` (0450). */
export const FRECUENCIAS_PAGO = ["mensual", "ciclo", "unico", "otra"] as const;
export type FrecuenciaPago = (typeof FRECUENCIAS_PAGO)[number];

export const FRECUENCIA_PAGO_LABELS: Record<FrecuenciaPago, string> = {
  mensual: "Mensual",
  ciclo: "Por ciclo",
  unico: "Pago único",
  otra: "Otra",
};

export type EstadoEntrega = "pendiente" | "aprobada" | "rechazada" | "retirada";

/** Los tonos son los de `Insignia`: el estado nunca se dice solo con color. */
export type TonoEstado = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";

export const ESTADO_ENTREGA: Record<EstadoEntrega, { etiqueta: string; tono: TonoEstado }> = {
  pendiente: { etiqueta: "Pendiente de revisión", tono: "informativo" },
  aprobada: { etiqueta: "Aprobada", tono: "positivo" },
  rechazada: { etiqueta: "Rechazada", tono: "alerta" },
  retirada: { etiqueta: "Retirada", tono: "neutral" },
};

/** Lo que devuelve `fn_educacion_situacion().estado_constancia`. */
export type EstadoConstancia =
  | "pendiente_revision" | "rechazada" | "sin_calendario" | "al_dia"
  | "vencida" | "por_vencer" | "falta_enviar";

/**
 * `etiqueta` es cómo se nombra en una insignia; `tono`, cómo se pinta. Rojo
 * solo para lo vencido y lo rechazado: una renovación normal o una constancia
 * por enviar con tiempo no es un error de nadie.
 */
export const ESTADO_CONSTANCIA: Record<EstadoConstancia, { etiqueta: string; tono: TonoEstado }> = {
  pendiente_revision: { etiqueta: "Pendiente de revisión", tono: "informativo" },
  rechazada: { etiqueta: "Rechazada", tono: "alerta" },
  sin_calendario: { etiqueta: "Sin calendario de pagos", tono: "neutral" },
  al_dia: { etiqueta: "Al día", tono: "positivo" },
  vencida: { etiqueta: "Vencida", tono: "alerta" },
  por_vencer: { etiqueta: "Por vencer", tono: "advertencia" },
  falta_enviar: { etiqueta: "Falta enviar", tono: "advertencia" },
};

/** Los estados que piden algo a la integrante. */
export function constanciaPideAlgoALaIntegrante(estado: EstadoConstancia): boolean {
  return estado === "rechazada" || estado === "vencida" || estado === "por_vencer" || estado === "falta_enviar";
}

/**
 * Lo que pide una integrante que todavía no tiene un apoyo educativo (0461):
 * el mismo formulario que usa DO para dar de alta, pero sin el monto —eso lo
 * sigue calculando el sistema al aprobar—. Espejo de
 * `educacion_solicitud_estado_valido`.
 */
export type EstadoSolicitud = "pendiente" | "aprobada" | "rechazada" | "retirada";

export const ESTADO_SOLICITUD: Record<EstadoSolicitud, { etiqueta: string; tono: TonoEstado }> = {
  pendiente: { etiqueta: "Pendiente de revisión", tono: "informativo" },
  aprobada: { etiqueta: "Aprobada", tono: "positivo" },
  rechazada: { etiqueta: "Rechazada", tono: "alerta" },
  retirada: { etiqueta: "Retirada", tono: "neutral" },
};

// Espejo de los límites que valida `fn_educacion_enviar_entrega` contra el
// almacén. Acá solo sirven para avisar ANTES de subir; si discrepan, manda la base.
export const ARCHIVOS_POR_ENTREGA = 10;
export const BYTES_POR_ARCHIVO = 10 * 1024 * 1024;

/**
 * ¿Se puede enviar este archivo? `null` si sí; si no, el motivo en palabras de
 * quien lo eligió.
 *
 * Las fotos no se miden por su peso original: se comprimen a JPG en el
 * navegador antes de subir (así llega también la HEIC de un iPhone, que el
 * almacén no acepta tal cual). Un PDF no se puede comprimir, así que ese sí se
 * mide.
 */
export function problemaDeArchivo(archivo: { nombre: string; tipo: string; bytes: number }): string | null {
  const tipo = archivo.tipo || tipoPorExtension(archivo.nombre);
  if (tipo === "application/pdf") {
    return archivo.bytes > BYTES_POR_ARCHIVO
      ? `«${archivo.nombre}» pesa ${(archivo.bytes / 1048576).toFixed(1)} MB y el máximo por archivo es 10 MB. Si es un escaneo, vuelve a escanearlo en menor calidad o súbelo como fotos.`
      : null;
  }
  if (tipo.startsWith("image/")) return null;
  return `«${archivo.nombre}» no es un PDF ni una foto. Sube la constancia en PDF, JPG o PNG.`;
}

function tipoPorExtension(nombre: string): string {
  const ext = nombre.split(".").pop()?.toLowerCase() ?? "";
  if (ext === "pdf") return "application/pdf";
  if (["jpg", "jpeg", "png", "heic", "heif", "webp"].includes(ext)) return "image/*";
  return "";
}

/**
 * La próxima fecha de pago que se SUGIERE después de pagar. Solo la mensual se
 * puede adivinar (mismo día del mes siguiente); las demás las escribe quien
 * sabe cuándo cobra su institución.
 *
 * Aritmética de texto, sin `Date` local: una fecha de Lima construida con el
 * huso del navegador puede correrse un día.
 */
export function sugerirProximaFecha(fechaPago: string, frecuencia: string | null): string | null {
  if (frecuencia !== "mensual") return null;
  const [y, m, d] = fechaPago.split("-").map(Number);
  if (!y || !m || !d) return null;
  const anio = m === 12 ? y + 1 : y;
  const mes = m === 12 ? 1 : m + 1;
  // El día 0 del mes siguiente es el último de este: así el 31 de enero pasa
  // al 28 (o 29) de febrero, y no al 3 de marzo.
  const ultimo = new Date(Date.UTC(anio, mes, 0)).getUTCDate();
  return `${anio}-${String(mes).padStart(2, "0")}-${String(Math.min(d, ultimo)).padStart(2, "0")}`;
}

/**
 * Un nombre de archivo que se puede poner en una ruta del almacén: sin
 * acentos, sin espacios ni símbolos, con su extensión. El nombre original se
 * guarda aparte (`educacion_entrega_archivos.nombre`) para mostrarlo tal cual.
 */
export function nombreDeArchivoSeguro(nombre: string, extension?: string): string {
  const partes = nombre.split(".");
  // La extensión original se quita SIEMPRE del nombre, aunque se fuerce otra:
  // una HEIC convertida no puede llamarse «IMG_0001.HEIC.jpg».
  const original = partes.length > 1 ? partes.pop()! : "bin";
  const ext = (extension ?? original).toLowerCase().replace(/[^a-z0-9]/g, "") || "bin";
  const base = partes.join(".")
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "")
    .slice(0, 60) || "archivo";
  return `${base}.${ext}`;
}
