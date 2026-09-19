// ============================================================================
// boletas.ts — las reglas de la BOLETA OFICIAL que las dos pantallas comparten
// ============================================================================
//
// QUÉ ES ESTO Y QUÉ NO
//   La boleta oficial es la que entrega el contador (foto o PDF, una o varias
//   hojas) y que DO sube y publica: tablas `boletas*` de la migración 0482. NO es
//   la boleta calculada por el sistema (`/mio/boleta`, `BoletaHoja`), que sigue
//   existiendo y solo muestra el periodo en curso.
//
// POR QUÉ ESTÁ AQUÍ Y NO DENTRO DE CADA PANTALLA
//   Dos pantallas —la de DO y la de la persona— tienen que contestar igual a
//   «¿en qué estado está esta boleta?» y a «¿este cambio obliga a avisar?». Es
//   el defecto que este repositorio ya persiguió con «cuál es el vigente» y con
//   «qué le tocaba trabajar ese día»: dos copias de una pregunta acaban
//   contestando distinto. Acá no toca ni React ni Supabase, así que se prueba con
//   `vitest` (tests/boletas.test.ts).
//
// LO QUE ESTO NO DECIDE
//   La base es la que manda. Todo lo que aquí se calcula para DIBUJAR —si la
//   casilla de avisar está bloqueada, si el total pasa el tope— la migración 0482
//   lo vuelve a comprobar y gana: la pantalla que se equivoca muestra un botón
//   que devuelve un error en castellano, que es el lado seguro.
// ============================================================================

export const BUCKET_BOLETAS = "boletas";

/** 500 MB por boleta —la suma de todas sus hojas—. Decisión de Felipe, 2026-09-19. */
export const TOPE_BOLETA_BYTES = 500 * 1024 * 1024;

/** 50 MB por archivo: el techo del bucket (`file_size_limit` de la 0482). */
export const TOPE_ARCHIVO_BYTES = 50 * 1024 * 1024;

/** Las fotos se reducen a este lado mayor antes de subirse (≈ 500 KB cada una). */
export const LADO_MAYOR_FOTO_PX = 2000;
export const CALIDAD_JPEG_FOTO = 0.85;

export type TipoBoleta = "imagen" | "pdf";

/** El estado que guarda la base. «falta» no existe como fila: lo inventa el tablero. */
export type EstadoBoletaBase = "falta" | "borrador" | "publicada" | "papel" | "anulada";

/**
 * El estado con el que se DIBUJA. «vista» y «confirmada» no son estados de la
 * base: salen de las dos fechas del acuse de la versión vigente.
 * «sin_pago» = el grupo de esa persona todavía no está pagado en ese periodo:
 * no hay nada que subir.
 */
export type EstadoVisible =
  | "sin_pago" | "falta" | "borrador" | "publicada" | "vista" | "confirmada" | "papel" | "anulada";

export type FilaDeEstado = {
  estado: string | null;
  grupo_pagado?: boolean | null;
  vista_at?: string | null;
  recibida_at?: string | null;
};

export function estadoVisible(f: FilaDeEstado): EstadoVisible {
  const base = (f.estado ?? "falta") as EstadoBoletaBase;
  if (base === "falta") return f.grupo_pagado === false ? "sin_pago" : "falta";
  if (base === "publicada") {
    if (f.recibida_at) return "confirmada";
    if (f.vista_at) return "vista";
    return "publicada";
  }
  return base;
}

/** Texto y tono de cada estado, en el vocabulario de la casa. */
export const ETIQUETA_ESTADO: Record<EstadoVisible, { texto: string; tono: "neutro" | "info" | "aviso" | "alerta" | "ok" }> = {
  sin_pago:   { texto: "Periodo sin pagar",      tono: "neutro" },
  falta:      { texto: "Falta",                  tono: "alerta" },
  borrador:   { texto: "Subida · sin publicar",  tono: "info" },
  publicada:  { texto: "Publicada · sin abrir",  tono: "aviso" },
  vista:      { texto: "Vista",                  tono: "info" },
  confirmada: { texto: "Confirmada",             tono: "ok" },
  papel:      { texto: "Entregada en papel",     tono: "ok" },
  anulada:    { texto: "Anulada",                tono: "neutro" },
};

// ── El aviso lo manda el contenido ──────────────────────────────────────────

export type CambiosDeVersion = {
  /** Se agregó o se quitó una hoja (o cambió el tipo): es OTRO documento. */
  contenido: boolean;
  /** Las mismas hojas en otro orden. */
  orden: boolean;
  /** Nada cambió: la base lo rechaza. */
  igual: boolean;
};

/**
 * Compara la versión vigente con la que se quiere guardar. Las hojas se
 * identifican por su ruta de Storage: la misma ruta es el mismo archivo, y por
 * eso conservar una hoja no la sube otra vez.
 */
export function cambiosEntreVersiones(vigente: readonly string[], nueva: readonly string[]): CambiosDeVersion {
  const a = [...vigente].sort();
  const b = [...nueva].sort();
  const mismoConjunto = a.length === b.length && a.every((x, i) => x === b[i]);
  const mismoOrden = vigente.length === nueva.length && vigente.every((x, i) => x === nueva[i]);
  return { contenido: !mismoConjunto, orden: mismoConjunto && !mismoOrden, igual: mismoOrden };
}

/**
 * ¿Esta edición avisa a la persona (y le reinicia la confirmación)?
 * Espeja `fn_boleta_guardar_version` (0482): si cambió el contenido, SIEMPRE;
 * si solo se reordenó, lo que diga DO. Un borrador no avisa a nadie.
 */
export function editaAvisa(opts: { publicada: boolean; cambios: CambiosDeVersion; quiereAvisar: boolean }): boolean {
  if (!opts.publicada) return false;
  return opts.cambios.contenido || opts.quiereAvisar;
}

/** ¿DO puede elegir no avisar? Solo cuando únicamente se reordenó. */
export function puedeElegirNoAvisar(opts: { publicada: boolean; cambios: CambiosDeVersion }): boolean {
  return opts.publicada && opts.cambios.orden;
}

// ── Hojas y topes ───────────────────────────────────────────────────────────

export type Hoja = { bytes: number; mime: string };

export function sumaDeBytes(hojas: readonly Pick<Hoja, "bytes">[]): number {
  return hojas.reduce((t, h) => t + h.bytes, 0);
}

/**
 * Lo que la pantalla puede decidir antes de llamar a la base: que haya hojas,
 * que sean del tipo elegido y que el total no pase el tope. `null` = todo bien.
 * La base repite estas tres comprobaciones y gana.
 */
export function problemaConLasHojas(tipo: TipoBoleta, hojas: readonly Hoja[]): string | null {
  if (hojas.length === 0) return tipo === "imagen" ? "Agrega al menos una foto." : "Agrega al menos un PDF.";
  const malas = hojas.filter((h) => (tipo === "imagen" ? !h.mime.startsWith("image/") : h.mime !== "application/pdf"));
  if (malas.length > 0) return "Todas las hojas de una boleta tienen que ser del mismo tipo (fotos o PDF).";
  if (hojas.some((h) => h.bytes > TOPE_ARCHIVO_BYTES)) return "Una de las hojas pesa más de 50 MB.";
  if (sumaDeBytes(hojas) > TOPE_BOLETA_BYTES) return "La boleta pasa el tope de 500 MB. Quita alguna hoja.";
  return null;
}

/** «3 fotos», «1 PDF». */
export function etiquetaDeHojas(tipo: TipoBoleta, cuantas: number): string {
  if (tipo === "pdf") return cuantas === 1 ? "1 PDF" : `${cuantas} PDF`;
  return cuantas === 1 ? "1 foto" : `${cuantas} fotos`;
}

const EXTENSION_POR_MIME: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heif",
  "application/pdf": "pdf",
};

/** La extensión con la que se guarda un archivo de ese tipo, o `null` si el bucket no lo admite. */
export function extensionPorMime(mime: string): string | null {
  return EXTENSION_POR_MIME[mime] ?? null;
}

const FORMATO_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * La ruta de una hoja en el bucket: `<periodo>/<persona>/<uuid>.<ext>`.
 * Solo ids, nunca DNI ni nombre. Es la forma que la política de Storage y la
 * columna `boletas_partes.storage_path` exigen (0482): si no calza, la base la
 * rechaza. El uuid es nuevo por hoja: un archivo que ya es parte de una boleta
 * NUNCA se sobrescribe.
 */
export function rutaDeHoja(periodoId: string, personaId: string, extension: string, uuid: string = crypto.randomUUID()): string {
  if (!FORMATO_UUID.test(periodoId) || !FORMATO_UUID.test(personaId)) {
    throw new Error("La ruta de una boleta se arma con los ids del periodo y de la persona.");
  }
  return `${periodoId}/${personaId}/${uuid}.${extension.replace(/^\./, "").toLowerCase()}`;
}

// ── El tablero de DO ────────────────────────────────────────────────────────

export type ContadoresTablero = {
  total: number;
  conBoleta: number;     // publicada, vista, confirmada o entregada en papel
  sinPublicar: number;   // borrador
  faltan: number;        // falta o anulada, con el grupo ya pagado
  confirmadas: number;
};

export function contarTablero(filas: readonly FilaDeEstado[]): ContadoresTablero {
  const c: ContadoresTablero = { total: filas.length, conBoleta: 0, sinPublicar: 0, faltan: 0, confirmadas: 0 };
  for (const f of filas) {
    const e = estadoVisible(f);
    if (e === "publicada" || e === "vista" || e === "confirmada" || e === "papel") c.conBoleta++;
    if (e === "confirmada") c.confirmadas++;
    if (e === "borrador") c.sinPublicar++;
    if (e === "falta" || e === "anulada") c.faltan++;
  }
  return c;
}

// ── Lo de la persona ────────────────────────────────────────────────────────

/** ¿Esta fila de `fn_mis_boletas` es una boleta nueva —publicada y aún sin abrir—? */
export function esBoletaNueva(f: { estado: string | null; vista_at: string | null }): boolean {
  return f.estado === "publicada" && !f.vista_at;
}
