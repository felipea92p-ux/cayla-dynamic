// ============================================================================
// sync-terminal.test.ts — Cuándo la cola aparta una marca y cuándo la espera
// ============================================================================
// EL CASO, medido el 2026-10-06 en marcas_apartadas: seis marcas de almuerzo de
// Oficina TRU (tres personas, salida y regreso) quedaron apartadas con
// «TypeError: Load failed». Eso es Safari diciendo que la petición no llegó al
// servidor; postgrest-js lo devuelve como `error` en vez de lanzarlo, y la cola
// lo contaba como un rechazo: seis ticks de 15 s —minuto y medio sin internet—
// y la marca se apartaba. Había además cinco de TRU del 24-sep con
// «TimeoutError: signal timed out», la misma clase.
//
// Lo que se prueba es la decisión de `sincronizarPendientes`, con la cola y el
// envío de mentira: es lo único que cambia el destino de una marca real.
import { beforeEach, describe, expect, it, vi } from "vitest";

const m = vi.hoisted(() => ({
  pendientes: [] as unknown[],
  enviar: vi.fn(),
  intento: vi.fn(),
  descartar: vi.fn(),
  eliminar: vi.fn(),
}));

vi.mock("@cayla-dynamic/database", () => ({ createTerminalSupabaseClient: () => ({}) }));
vi.mock("@/lib/terminal/terminal-info", () => ({ refrescarInfoTerminal: async () => null }));
vi.mock("@/lib/terminal/offline-db", () => ({
  obtenerPendientes: async () => m.pendientes,
  eliminarDeOutbox: m.eliminar,
  registrarIntentoFallido: m.intento,
  marcarComoDescartada: m.descartar,
}));
vi.mock("@/lib/terminal/enviar-marcaje", async (original) => ({
  ...(await original<typeof import("@/lib/terminal/enviar-marcaje")>()),
  enviarMarcaje: m.enviar,
}));

import { sincronizarPendientes } from "@/lib/terminal/sync";

const marca = (intentos: number) => ({
  clientUuid: "11111111-1111-1111-1111-111111111111",
  personaId: "22222222-2222-2222-2222-222222222222",
  terminalId: "33333333-3333-3333-3333-333333333333",
  tipo: "salida_almuerzo",
  timestampCliente: "2026-10-06T18:28:00.000Z",
  intentos,
});

async function sincronizarCon(entry: ReturnType<typeof marca>, respuesta: object) {
  m.pendientes = [entry];
  m.enviar.mockResolvedValue(respuesta);
  await sincronizarPendientes();
}

beforeEach(() => {
  vi.clearAllMocks();
  // Node trae `navigator` sin `onLine`, y sync.ts lo lee: sin esto sale en la primera línea.
  vi.stubGlobal("navigator", { onLine: true });
});

describe("sincronizarPendientes — qué hace con una marca que falló", () => {
  it("un corte de red NO aparta la marca, aunque ya lleve cinco intentos", async () => {
    await sincronizarCon(marca(5), { ok: false, error: "TypeError: Load failed", llego: false });
    expect(m.descartar).not.toHaveBeenCalled();
    expect(m.eliminar).not.toHaveBeenCalled();
  });

  it("y un fallo de red no suma al tope: el siguiente rechazo real no la aparta de golpe", async () => {
    await sincronizarCon(marca(0), { ok: false, error: "TypeError: Load failed", llego: false });
    expect(m.intento).toHaveBeenCalledWith(marca(0).clientUuid, "TypeError: Load failed", false);
  });

  it("un rechazo confirmado sí suma, y al sexto aparta la marca", async () => {
    await sincronizarCon(marca(5), { ok: false, error: "no se pudo", llego: true });
    expect(m.intento).toHaveBeenCalledWith(marca(5).clientUuid, "no se pudo", true);
    expect(m.descartar).toHaveBeenCalledTimes(1);
  });

  it("un rechazo confirmado que aún no llega a seis la deja en cola", async () => {
    await sincronizarCon(marca(2), { ok: false, error: "no se pudo", llego: true });
    expect(m.descartar).not.toHaveBeenCalled();
  });

  it("un rechazo de estado se aparta de inmediato, sin esperar los seis", async () => {
    await sincronizarCon(marca(0), {
      ok: false,
      error: "tipo salida_almuerzo no válido en el estado actual (se esperaba entrada)",
      llego: true,
    });
    expect(m.descartar).toHaveBeenCalledTimes(1);
  });

  it("sin sesión la marca espera en cola, nunca se aparta, y no suma al tope", async () => {
    const error = "permission denied for function fn_registrar_marcaje";
    await sincronizarCon(marca(5), { ok: false, error, llego: true });
    expect(m.descartar).not.toHaveBeenCalled();
    expect(m.intento).toHaveBeenCalledWith(marca(5).clientUuid, error, false);
  });

  it("lo que el servidor aceptó sale de la cola", async () => {
    await sincronizarCon(marca(0), { ok: true, llego: true });
    expect(m.eliminar).toHaveBeenCalledWith(marca(0).clientUuid);
  });
});
