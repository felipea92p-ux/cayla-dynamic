// ============================================================================
// ubicacion-cola.ts — guardar, enviar y leer «Voy a almacén» / «Vuelvo a tienda»
// ============================================================================
//
// QUÉ PROMETE
//   Lo mismo que la cola de marcajes, para los cambios de ubicación (0580): se
//   GUARDA antes de enviar, se reintenta sin conexión, el servidor lo reconoce
//   por su `client_uuid` si llega dos veces, y lo que el servidor rechaza una y
//   otra vez se APARTA, nunca se borra.
//
// POR QUÉ UNA BASE INDEXEDDB APARTE (`cayla-terminal-ubicacion`) Y NO UN
// ALMACÉN NUEVO EN `cayla-terminal`
//   Un almacén nuevo exige subir la versión de `cayla-terminal`, y una pestaña
//   vieja del terminal —AQP llegó a tener tres ocultas— mantiene abierta la
//   versión 1 sin saber cerrarla: la apertura de la versión 2 se queda
//   BLOQUEADA, y con ella `encolarMarcaje`, que es lo primero que hace marcar.
//   Ir al almacén no puede arriesgar ni un segundo del marcaje. Con una base
//   propia, lo peor que puede pasar aquí es que este archivo falle solo.
//
//   Por lo mismo, este archivo NO lanza nunca hacia el terminal: cada función
//   devuelve un respaldo, y un error de ubicación jamás interrumpe un marcaje.
//
// QUÉ NO HACE
//   No toca `marcajes`, `fn_registrar_marcaje` ni la cola de marcajes.
// ============================================================================
import { openDB, type IDBPDatabase } from "idb";
import { hoyLima, rangoDelDiaLima } from "@cayla-dynamic/shared";
import { puestoDesdeFilas, type PuestoDelDia } from "@/lib/admin/almacen";
import { createTerminalSupabaseClient } from "@cayla-dynamic/database";
import { conTope, topeDeRed } from "./tope-de-red";
import { esFalloDeRed, esRechazoDeSesion, SEGUNDOS_ESPERA_ENVIO } from "./enviar-marcaje";
import { refrescarInfoTerminal } from "./terminal-info";
import type { CambioUbicacion, Ubicacion } from "./ubicacion";

const DB_NAME = "cayla-terminal-ubicacion";
const STORE = "outbox";
/** Mismo tope que la cola de marcajes: seis rechazos CONFIRMADOS y se aparta. */
const TOPE_RECHAZOS = 6;

export interface CambioEnCola {
  clientUuid: string;
  personaId: string;
  terminalId: string;
  ubicacion: Ubicacion;
  timestampCliente: string;
  vuelvePrevisto: string | null;
  intentos: number;
  ultimoError?: string;
  /** Apartado tras rechazos repetidos del servidor. No se borra. */
  descartada?: boolean;
}

let dbPromise: Promise<IDBPDatabase> | null = null;
function getDb() {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, 1, {
      upgrade(db) {
        if (!db.objectStoreNames.contains(STORE)) db.createObjectStore(STORE, { keyPath: "clientUuid" });
      },
    }).catch((e) => {
      dbPromise = null;
      throw e;
    });
  }
  return dbPromise;
}

export async function encolarCambio(c: CambioEnCola): Promise<boolean> {
  try {
    await (await getDb()).put(STORE, c);
    return true;
  } catch {
    return false;
  }
}

async function todos(): Promise<CambioEnCola[]> {
  try {
    return (await (await getDb()).getAll(STORE)) as CambioEnCola[];
  } catch {
    return [];
  }
}

/** Lo que falta subir, en orden de hora (como la cola de marcajes). */
export async function cambiosPendientes(): Promise<CambioEnCola[]> {
  return (await todos())
    .filter((c) => !c.descartada)
    .sort((a, b) => a.timestampCliente.localeCompare(b.timestampCliente));
}

async function quitar(clientUuid: string) {
  try {
    await (await getDb()).delete(STORE, clientUuid);
  } catch {
    // Se queda en la cola: el reintento lo manda otra vez y el servidor lo
    // reconoce por su client_uuid.
  }
}

async function anotarFallo(c: CambioEnCola, error: string, cuenta: boolean, apartarYa = false) {
  const intentos = c.intentos + (cuenta ? 1 : 0);
  try {
    await (await getDb()).put(STORE, {
      ...c,
      intentos,
      ultimoError: error,
      descartada: apartarYa || (cuenta && intentos >= TOPE_RECHAZOS) ? true : c.descartada,
    });
  } catch {
    // Sin almacén local no hay contador que subir.
  }
}

export interface ResultadoEnvioUbicacion {
  ok: boolean;
  /** ¿Contestó el servidor? Igual que en `enviarMarcaje`. */
  llego: boolean;
  error?: string;
}

/** Manda un cambio con tope de tiempo. NUNCA lanza. */
export async function enviarCambio(c: CambioEnCola): Promise<ResultadoEnvioUbicacion> {
  const SIN_RESPUESTA = Symbol("sin respuesta");
  const msEspera = SEGUNDOS_ESPERA_ENVIO * 1000;
  try {
    const r = await conTope(
      createTerminalSupabaseClient()
        // La función es nueva (0580) y los tipos generados todavía no la traen
        // en todos los clones; el nombre y los argumentos son el contrato.
        .rpc("fn_registrar_cambio_ubicacion" as never, {
          p_persona_id: c.personaId,
          p_ubicacion: c.ubicacion,
          p_timestamp_cambio: c.timestampCliente,
          p_client_uuid: c.clientUuid,
          p_origen: "terminal",
          p_terminal_id: c.terminalId,
          p_vuelve_previsto: c.vuelvePrevisto,
        } as never)
        .abortSignal(AbortSignal.timeout(msEspera)),
      SIN_RESPUESTA,
      msEspera / 1000,
    );
    if (r === SIN_RESPUESTA) return { ok: false, llego: false, error: "sin respuesta a tiempo" };
    const { error } = r as { error: { message: string } | null };
    return error ? { ok: false, llego: !esFalloDeRed(error.message), error: error.message } : { ok: true, llego: true };
  } catch (e) {
    return { ok: false, llego: false, error: e instanceof Error ? e.message : "el envío se interrumpió" };
  }
}

/**
 * Guarda y, si hay red, intenta subir YA. Devuelve si quedó confirmado por el
 * servidor y si el servidor lo rechazó (para decirlo en pantalla sin mentir).
 */
export async function registrarCambio(c: CambioEnCola): Promise<{ confirmado: boolean; rechazado: boolean }> {
  const encolado = await encolarCambio(c);
  if (typeof navigator !== "undefined" && !navigator.onLine) return { confirmado: false, rechazado: false };
  const r = await enviarCambio(c);
  if (r.ok) {
    if (encolado) await quitar(c.clientUuid);
    return { confirmado: true, rechazado: false };
  }
  // Un rechazo con la persona delante se APARTA en el acto (no se borra): la
  // pantalla ya le dice que no quedó, y dejarlo en cola la seguiría mostrando
  // en almacén mientras se reintenta algo que el servidor ya dijo que no.
  const rechazado = r.llego && !esRechazoDeSesion(r.error);
  if (encolado) await anotarFallo(c, r.error ?? "sin detalle", rechazado, rechazado);
  return { confirmado: false, rechazado };
}

let sincronizando = false;

/**
 * Sube lo que quedó en cola. La llama el mismo ciclo que la cola de marcajes
 * (sync.ts), DESPUÉS de los marcajes: si una entrada y un «Voy a almacén»
 * esperan juntos, sube primero la entrada. Nunca lanza.
 */
export async function sincronizarCambiosPendientes(): Promise<void> {
  if (sincronizando) return;
  if (typeof navigator !== "undefined" && !navigator.onLine) return;
  sincronizando = true;
  try {
    for (const c of await cambiosPendientes()) {
      let r = await enviarCambio(c);
      // Sesión y ficha del terminal desajustadas: mismo arreglo que la cola de
      // marcajes — se reenvía con el terminal que la sesión dice ser.
      if (!r.ok && r.llego && esRechazoDeSesion(r.error)) {
        const info = await refrescarInfoTerminal();
        if (info && info.id !== c.terminalId) r = await enviarCambio({ ...c, terminalId: info.id });
      }
      if (r.ok) await quitar(c.clientUuid);
      else await anotarFallo(c, r.error ?? "sin detalle", r.llego && !esRechazoDeSesion(r.error));
    }
  } catch {
    // Nada de esto puede tumbar el ciclo de sincronización de los marcajes.
  } finally {
    sincronizando = false;
  }
}

export type CambiosPorPersona = Map<string, CambioUbicacion[]>;

/**
 * Los cambios de HOY de la sede del terminal (RLS ya la acota), sin anulados,
 * más lo que todavía está en la cola local. Si el servidor no contesta, se
 * queda con lo local: en el peor caso el terminal ofrece «Voy a almacén» a
 * quien ya está allí, y un segundo «almacen» seguido no cambia el tramo.
 */
export async function cargarCambiosDeHoy(): Promise<CambiosPorPersona> {
  const mapa: CambiosPorPersona = new Map();
  const poner = (personaId: string, c: CambioUbicacion) => {
    const lista = mapa.get(personaId) ?? [];
    lista.push(c);
    mapa.set(personaId, lista);
  };
  const vistos = new Set<string>();
  const { inicio, fin } = rangoDelDiaLima();
  const esDeHoy = (iso: string) => {
    const t = new Date(iso).getTime();
    return t >= new Date(inicio).getTime() && t <= new Date(fin).getTime();
  };

  if (typeof navigator === "undefined" || navigator.onLine) {
    try {
      const res = await createTerminalSupabaseClient()
        .from("cambios_ubicacion" as never)
        .select("client_uuid, persona_id, ubicacion, timestamp_cambio, vuelve_previsto")
        .is("anulado_at", null)
        .gte("timestamp_cambio", inicio)
        .lte("timestamp_cambio", fin)
        .abortSignal(topeDeRed());
      const filas = (res.data ?? []) as unknown as Array<{
        client_uuid: string; persona_id: string; ubicacion: Ubicacion;
        timestamp_cambio: string; vuelve_previsto: string | null;
      }>;
      for (const f of filas) {
        vistos.add(f.client_uuid);
        poner(f.persona_id, { ubicacion: f.ubicacion, timestamp: f.timestamp_cambio, vuelvePrevisto: f.vuelve_previsto });
      }
    } catch {
      // Sin respuesta: queda lo local.
    }
  }

  for (const c of await cambiosPendientes()) {
    // Solo lo de hoy: un «hasta que vuelva» de ayer que sigue en cola no puede
    // dejar a nadie en almacén esta mañana.
    if (vistos.has(c.clientUuid) || !esDeHoy(c.timestampCliente)) continue;
    poner(c.personaId, { ubicacion: c.ubicacion, timestamp: c.timestampCliente, vuelvePrevisto: c.vuelvePrevisto });
  }
  return mapa;
}

/**
 * Lo planificado para HOY (0579, `puestos_planificados`): por persona, sus
 * tramos en almacén, sin recortar todavía a su turno. La política
 * `puestos_select_terminal` ya acota a las personas de este terminal.
 *
 * Nunca lanza. Sin red, sin la 0579 pegada o con cualquier error devuelve un
 * mapa vacío, y el terminal se comporta como en la entrega 1: no anuncia nada y
 * solo cuenta lo que se marca. Por eso no hace falta coordinar el despliegue
 * con la migración.
 */
export async function cargarPlanDeHoy(): Promise<Map<string, PuestoDelDia>> {
  const mapa = new Map<string, PuestoDelDia>();
  if (typeof navigator !== "undefined" && !navigator.onLine) return mapa;
  try {
    const res = await createTerminalSupabaseClient()
      .from("puestos_planificados" as never)
      .select("persona_id, desde, hasta")
      .eq("fecha", hoyLima())
      .abortSignal(topeDeRed());
    if (res.error) return mapa;
    const porPersona = new Map<string, { desde: string | null; hasta: string | null }[]>();
    for (const f of (res.data ?? []) as unknown as Array<{ persona_id: string; desde: string | null; hasta: string | null }>) {
      porPersona.set(f.persona_id, [...(porPersona.get(f.persona_id) ?? []), { desde: f.desde, hasta: f.hasta }]);
    }
    for (const [id, filas] of porPersona) mapa.set(id, puestoDesdeFilas(filas));
  } catch {
    // Queda vacío: el terminal sigue igual que sin plan.
  }
  return mapa;
}
