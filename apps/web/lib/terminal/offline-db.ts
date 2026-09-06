import { openDB, type IDBPDatabase } from "idb";
import type { TipoMarca } from "@cayla-dynamic/shared";

const DB_NAME = "cayla-terminal";
const DB_VERSION = 1;

export interface RosterEntry {
  id: string;
  nombres: string;
  apellidos: string;
  sedeCodigo: string;
  sedeNombre: string;
  /** Ruta en el bucket público «fotos-perfil» (0381), o ausente si nunca subió una. */
  fotoUrl?: string | null;
}

export interface OutboxEntry {
  clientUuid: string;
  personaId: string;
  terminalId: string;
  tipo: TipoMarca;
  motivoOtro?: string;
  timestampCliente: string;
  intentos: number;
  ultimoError?: string;
  /** Apartada tras rechazos repetidos. NO se borra: queda recuperable. */
  descartada?: boolean;
  /**
   * El servidor YA contestó que no (`llego && !ok`, una regla de negocio real
   * — no un corte de red). Distinto de `descartada`: sigue en la cola y sigue
   * reintentándose hasta el tope de 6 fallos confirmados de sync.ts, por si el
   * rechazo se debía a un estado transitorio que un reintento sí resuelve.
   * Lo que SÍ cambia de inmediato: mientras esta bandera esté puesta, la
   * marca deja de contar como "de hoy" en `cargarMarcajesHoyPorPersona` —
   * antes de esto, quedaba contando hasta 90 segundos (el tiempo que tarda
   * sync.ts en acumular 6 fallos y recién ahí llamar a `marcarComoDescartada`),
   * y el terminal podía ofrecer una acción sobre una salida que el servidor
   * nunca aceptó.
   */
  rechazadaPorServidor?: boolean;
  /**
   * Solo en un `salida_final` cuando el terminal preguntó por la ambigüedad
   * de "salida a refrigerio sin retorno" (0353). Ausente en todo lo demás.
   */
  confirmoSinRefrigerio?: boolean;
}

let dbPromise: Promise<IDBPDatabase> | null = null;

function getDb() {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        db.createObjectStore("roster", { keyPath: "id" });
        db.createObjectStore("outbox", { keyPath: "clientUuid" });
      },
    });
  }
  return dbPromise;
}

export async function guardarRoster(entries: RosterEntry[]) {
  const db = await getDb();
  const tx = db.transaction("roster", "readwrite");
  await tx.store.clear();
  await Promise.all(entries.map((e) => tx.store.put(e)));
  await tx.done;
}

export async function obtenerRoster(): Promise<RosterEntry[]> {
  const db = await getDb();
  return db.getAll("roster");
}

export async function encolarMarcaje(entry: OutboxEntry) {
  const db = await getDb();
  await db.put("outbox", entry);
}

/**
 * Solo lo que todavía debe intentarse. Lo apartado se conserva, pero no se reintenta.
 *
 * VAN EN ORDEN DE HORA, y eso no es cosmética. `getAll` devuelve por el keyPath
 * del almacén, que es `clientUuid` —un UUID aleatorio—, así que la cola se
 * reenviaba en un orden que no tiene nada que ver con el que ocurrió. Si la
 * salida llega antes que la entrada, fn_registrar_marcaje toma la rama de marca
 * atrasada, fn_dia_incoherente da true y TODAS las marcas de ese día quedan
 * selladas como `pendiente_revision`. Cuando después llega la que faltaba el día
 * vuelve a cuadrar, pero el sello NO se levanta solo: quitarlo es cosa de
 * fn_resellar_dia, y a esa solo la llaman las correcciones manuales.
 *
 * Ordenar no descarta ni retrasa nada: la cola se envía igual de completa.
 *
 * Se comparan como texto porque `timestampCliente` lo escribe `toISOString()`
 * (marcar/page.tsx), que siempre da UTC con `Z` y ancho fijo — ahí el orden
 * alfabético ES el cronológico. Si algún día se guardara con el offset de Lima,
 * esto habría que pasarlo a Date.
 */
export async function obtenerPendientes(): Promise<OutboxEntry[]> {
  const db = await getDb();
  const todas: OutboxEntry[] = await db.getAll("outbox");
  return todas
    .filter((e) => !e.descartada)
    .sort((a, b) => a.timestampCliente.localeCompare(b.timestampCliente));
}

/**
 * El intento INMEDIATO (marcar/page.tsx) ya sabe, en el momento, que el
 * servidor contestó que no — no hace falta esperar a sync.ts para saberlo.
 * Marca la entrada como rechazada sin apartarla: sigue en la cola y sigue
 * reintentándose, pero deja de contar como "de hoy" mientras tanto.
 */
export async function marcarComoRechazadaPorServidor(clientUuid: string, error: string) {
  const db = await getDb();
  const entry: OutboxEntry | undefined = await db.get("outbox", clientUuid);
  if (entry) {
    entry.rechazadaPorServidor = true;
    entry.ultimoError = error;
    await db.put("outbox", entry);
  }
}

/**
 * Una marca que el servidor rechaza una y otra vez NO se borra: se APARTA.
 * Antes se hacía db.delete() y la marca desaparecía del sistema sin dejar rastro
 * — si el rechazo venía de un bug (y venía: marcas atrasadas, ver mig. 0068), se
 * perdía asistencia real en silencio. Ahora queda guardada y recuperable.
 */
export async function marcarComoDescartada(clientUuid: string, error: string) {
  const db = await getDb();
  const entry: OutboxEntry | undefined = await db.get("outbox", clientUuid);
  if (entry) {
    entry.descartada = true;
    entry.ultimoError = error;
    await db.put("outbox", entry);
  }
}

/** Marcas apartadas: sirven para diagnosticar y, si hace falta, reponerlas a mano. */
export async function obtenerDescartadas(): Promise<OutboxEntry[]> {
  const db = await getDb();
  const todas: OutboxEntry[] = await db.getAll("outbox");
  return todas.filter((e) => e.descartada === true);
}

export async function eliminarDeOutbox(clientUuid: string) {
  const db = await getDb();
  await db.delete("outbox", clientUuid);
}

export async function registrarIntentoFallido(clientUuid: string, error: string) {
  const db = await getDb();
  const entry = await db.get("outbox", clientUuid);
  if (entry) {
    entry.intentos += 1;
    entry.ultimoError = error;
    await db.put("outbox", entry);
  }
}
