// ============================================================================
// archivo.ts — lo que la pantalla del Archivo de la empresa decide para dibujar
// ============================================================================
// QUÉ PROMETE
//   Funciones puras sobre las fichas que devuelve `fn_archivo_empresa` (0503):
//   cuándo un papel está por vencer, cómo se busca, cómo se agrupa, y qué ruta
//   lleva un archivo nuevo en el almacén. Sin React ni Supabase: se prueban con
//   vitest (`tests/archivo.test.ts`).
//
// QUÉ NO DECIDE
//   Qué ficha es «vigente». Eso lo dice la base en la columna `estado` —una
//   ficha reemplazada o retirada deja de serlo—, y aquí solo se lee. Si esta
//   pantalla lo recalculara, habría dos respuestas a la misma pregunta.
// ============================================================================
import { sinTildes } from "@/lib/sin-tildes";
import { tipoDeArchivo } from "@/lib/tipos-archivo";

/** Una fila de `fn_archivo_empresa`. */
export interface FichaArchivo {
  id: string;
  titulo: string;
  entidad: string;
  numero: string | null;
  fecha_documento: string;
  vence_el: string | null;
  sede_id: string | null;
  sede_nombre: string | null;
  nota: string | null;
  storage_path: string;
  nombre_archivo: string;
  mime: string;
  bytes: number;
  reemplaza_a: string | null;
  reemplazada_por: string | null;
  estado: string;
  subido_por_nombre: string | null;
  subido_at: string;
  retirado_at: string | null;
  retirado_por_nombre: string | null;
  retirado_motivo: string | null;
}

export const BUCKET_ARCHIVO = "archivo-empresa";

/** El tope del bucket (0503): 50 MB por archivo, el de los demás papeles. */
export const MAX_BYTES_ARCHIVO = 50 * 1024 * 1024;

/** Lo que acepta el diálogo de archivos. Espeja `allowed_mime_types` del bucket. */
export const TIPOS_ARCHIVO = "application/pdf,image/jpeg,image/png,image/webp,image/heic,image/heif,.pdf,.jpg,.jpeg,.png,.webp,.heic,.heif";

/**
 * Cuántos días antes de vencer un papel empieza a avisar. Dos meses: renovar
 * un certificado de Defensa Civil o una licencia pide una visita de la
 * municipalidad, y eso no se agenda en una semana.
 */
export const DIAS_AVISO_VENCIMIENTO = 60;

export type EstadoVencimiento = "sin_vencimiento" | "al_dia" | "por_vencer" | "vencido";

/** Días de calendario de `desde` a `hasta` (fechas `AAAA-MM-DD`, sin hora ni huso). */
function diasEntre(desde: string, hasta: string): number {
  const a = Date.UTC(+desde.slice(0, 4), +desde.slice(5, 7) - 1, +desde.slice(8, 10));
  const b = Date.UTC(+hasta.slice(0, 4), +hasta.slice(5, 7) - 1, +hasta.slice(8, 10));
  return Math.round((b - a) / 86_400_000);
}

/**
 * Cómo está un papel respecto de su vencimiento, contado en días de Lima.
 * `hoy` llega de fuera (`hoyLima()`) para que la prueba no dependa del reloj.
 * Vence EL día indicado: ese día todavía vale, el siguiente ya no.
 */
export function estadoVencimiento(venceEl: string | null, hoy: string): { estado: EstadoVencimiento; dias: number | null } {
  if (!venceEl) return { estado: "sin_vencimiento", dias: null };
  const dias = diasEntre(hoy, venceEl);
  if (dias < 0) return { estado: "vencido", dias };
  if (dias <= DIAS_AVISO_VENCIMIENTO) return { estado: "por_vencer", dias };
  return { estado: "al_dia", dias };
}

/** El texto corto de la insignia de vencimiento. `null` si no hay nada que avisar. */
export function textoVencimiento(venceEl: string | null, hoy: string): string | null {
  const { estado, dias } = estadoVencimiento(venceEl, hoy);
  if (estado === "vencido") return dias === -1 ? "venció ayer" : `venció hace ${-dias!} días`;
  if (estado === "por_vencer") {
    if (dias === 0) return "vence hoy";
    if (dias === 1) return "vence mañana";
    return `vence en ${dias} días`;
  }
  return null;
}

/**
 * La ruta del archivo en el almacén: `<uuid>.<ext>` y nada más — ni el nombre
 * con que se subió ni nada que identifique a una persona (la base rechaza
 * cualquier otra forma). La extensión sale del nombre si es una de las que el
 * bucket acepta; si no, del tipo de archivo.
 */
export function rutaNuevaArchivo(nombre: string, tipoDeclarado: string, uuid: string): string {
  const deNombre = nombre.includes(".") ? nombre.split(".").pop()!.toLowerCase() : "";
  if (/^(pdf|jpg|jpeg|png|webp|heic|heif)$/.test(deNombre)) return `${uuid}.${deNombre}`;
  const tipo = tipoDeArchivo(nombre, tipoDeclarado);
  const porTipo: Record<string, string> = {
    "application/pdf": "pdf", "image/jpeg": "jpg", "image/png": "png",
    "image/webp": "webp", "image/heic": "heic", "image/heif": "heif",
  };
  return `${uuid}.${porTipo[tipo] ?? "pdf"}`;
}

/**
 * Por qué un archivo no puede subirse, antes de intentarlo. `null` si puede.
 * La base y el bucket lo rechazarían igual; esto solo evita esperar la subida
 * entera para enterarse.
 */
export function problemaDeArchivo(archivo: { name: string; type: string; size: number }): string | null {
  if (archivo.size === 0) return `«${archivo.name}» está vacío.`;
  if (archivo.size > MAX_BYTES_ARCHIVO) {
    return `«${archivo.name}» pesa ${(archivo.size / 1048576).toFixed(1)} MB y el máximo es 50 MB.`;
  }
  const tipo = tipoDeArchivo(archivo.name, archivo.type);
  if (tipo !== "application/pdf" && !tipo.startsWith("image/")) {
    return `«${archivo.name}» no es un PDF ni una foto. Guárdalo como PDF y vuelve a intentarlo.`;
  }
  return null;
}

/** ¿La ficha coincide con lo que se escribió en el buscador? Sin tildes ni mayúsculas. */
export function coincide(f: FichaArchivo, texto: string): boolean {
  const q = sinTildes(texto.trim());
  if (!q) return true;
  return [f.titulo, f.entidad, f.numero, f.sede_nombre, f.nombre_archivo, f.nota]
    .some((campo) => campo != null && sinTildes(campo).includes(q));
}

/**
 * Las fichas vigentes agrupadas por quién emite el papel, que es como lo pide
 * quien inspecciona («los papeles de la ANPD»). Grupos y fichas en orden
 * alfabético, para que un papel no cambie de lugar cada vez que se sube otro.
 */
export function agruparPorEntidad(fichas: readonly FichaArchivo[]): Array<{ entidad: string; fichas: FichaArchivo[] }> {
  const grupos = new Map<string, FichaArchivo[]>();
  for (const f of fichas) {
    const lista = grupos.get(f.entidad) ?? [];
    lista.push(f);
    grupos.set(f.entidad, lista);
  }
  const porNombre = (a: string, b: string) => a.localeCompare(b, "es", { sensitivity: "base" });
  return [...grupos.entries()]
    .sort(([a], [b]) => porNombre(a, b))
    .map(([entidad, lista]) => ({ entidad, fichas: lista.sort((a, b) => porNombre(a.titulo, b.titulo) || (a.id < b.id ? -1 : 1)) }));
}

/**
 * Las entidades ya usadas, para sugerirlas al escribir una nueva: así no
 * aparecen «ANPD» y «Autoridad Nacional de Protección de Datos» como dos grupos.
 * Se cuentan todas las fichas, también las retiradas: el nombre sigue siendo bueno.
 */
export function entidadesUsadas(fichas: readonly FichaArchivo[]): string[] {
  return [...new Set(fichas.map((f) => f.entidad))].sort((a, b) => a.localeCompare(b, "es", { sensitivity: "base" }));
}

/**
 * La cadena de versiones de un papel, de la más nueva a la más vieja, partiendo
 * de la ficha vigente. Sirve para el historial: «antes decía esto».
 */
export function versionesAnteriores(vigente: FichaArchivo, todas: readonly FichaArchivo[]): FichaArchivo[] {
  const porId = new Map(todas.map((f) => [f.id, f]));
  const cadena: FichaArchivo[] = [];
  let actual = vigente.reemplaza_a ? porId.get(vigente.reemplaza_a) : undefined;
  // El tope corta un ciclo que la base no permite pero que un dato roto podría traer.
  while (actual && cadena.length < todas.length) {
    cadena.push(actual);
    actual = actual.reemplaza_a ? porId.get(actual.reemplaza_a) : undefined;
  }
  return cadena;
}
