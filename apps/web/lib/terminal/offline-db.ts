import { openDB, type IDBPDatabase } from "idb";
import type { TipoMarca } from "@cayla-dynamic/shared";

const DB_NAME = "cayla-terminal";
const DB_VERSION = 1;

export interface RosterEntry {
  id: string;
  nombres: string;
  apellidos: string;
  pinHash: string;
  sedeCodigo: string;
  sedeNombre: string;
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

/** Solo lo que todavía debe intentarse. Lo apartado se conserva, pero no se reintenta. */
export async function obtenerPendientes(): Promise<OutboxEntry[]> {
  const db = await getDb();
  const todas: OutboxEntry[] = await db.getAll("outbox");
  return todas.filter((e) => !e.descartada);
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
