// ============================================================================
// enviar-marcaje.test.ts — Un envío que se cuelga no puede colgar la sede
// ============================================================================
// EL CASO, medido el 2026-08-10: en todo el terminal no había ni un
// `AbortSignal`. Con `navigator.onLine` en true y la red muerta —un router que
// responde pero no enruta, que es la forma corriente en que se cae una tienda—
// la promesa del envío no volvía nunca, y se perdían dos cosas a la vez:
//
//   · la marca, porque se encolaba DESPUÉS de intentar enviarla, dentro de un
//     `if (error)` al que no se llegaba; y
//   · el terminal entero, porque `confirmandoRef` se libera en `volverALista()`
//     y a esa función se llega por el temporizador de la pantalla de mensaje.
//     Nadie más en esa sede podía marcar hasta que alguien recargara.
//
// Lo que se prueba aquí es la pieza que lo arregla: que el envío SIEMPRE
// termine, y que sepa decir si el servidor contestó o si no se llegó a él.
//
// POR QUÉ ESA SEGUNDA MITAD IMPORTA
//   La cola aparta una marca tras seis fallos. Seis ticks son minuto y medio:
//   sin distinguir «lo rechazó» de «no llegué», una caída corta de internet
//   apartaría marcas buenas — el mismo error de fondo que ya costó una vez, con
//   el `db.delete()` que borraba marcas atrasadas (ver el comentario de sync.ts).
// ============================================================================
import { describe, expect, it } from "vitest";
import {
  enviarMarcaje,
  esRechazoDeEstado,
  esFalloDeRed,
  esRechazoDeSesion,
  esSesionPerdida,
} from "@/lib/terminal/enviar-marcaje";

type Cliente = Parameters<typeof enviarMarcaje>[0];
type Entrada = Parameters<typeof enviarMarcaje>[1];

const MARCA: Entrada = {
  clientUuid: "11111111-1111-1111-1111-111111111111",
  personaId: "22222222-2222-2222-2222-222222222222",
  terminalId: "33333333-3333-3333-3333-333333333333",
  tipo: "entrada",
  timestampCliente: "2026-08-10T09:00:00.000Z",
  intentos: 0,
};

/** Un cliente de mentira que responde lo que se le diga, y anota qué le pidieron. */
function clienteFalso(responder: (signal: AbortSignal) => Promise<{ error: { message: string } | null }>) {
  const llamadas: { fn: string; args: Record<string, unknown> }[] = [];
  const cliente = {
    rpc(fn: string, args: Record<string, unknown>) {
      llamadas.push({ fn, args });
      return { abortSignal: (signal: AbortSignal) => responder(signal) };
    },
  } as unknown as Cliente;
  return { cliente, llamadas };
}

/** El caso que costó todo esto: nunca responde, solo reacciona al corte. */
const nuncaResponde = (signal: AbortSignal) =>
  new Promise<{ error: { message: string } | null }>((_, reject) => {
    signal.addEventListener("abort", () => reject(signal.reason ?? new Error("abortada")));
  });

/**
 * El caso nuevo, medido el 2026-09-17 con el terminal congelado en
 * "Confirmando en 0s…": ni siquiera escucha el abort. Es lo que pasa de
 * verdad en supabase-js cuando `fetchWithAuth` está resolviendo el token de
 * acceso —`await getAccessToken()`, que puede salir a refrescarlo por red—
 * ANTES de llamar a `fetch`: el `.abortSignal()` de nuestro `.rpc()` solo se
 * conecta a ESE `fetch` final, así que si el atasco está un paso antes, el
 * corte nunca llega a tener a quién avisarle. Sin un segundo cerrojo que no
 * dependa del abort, esto se queda colgado para siempre.
 */
const nuncaEscuchaElAbort = () => new Promise<{ error: { message: string } | null }>(() => {});

describe("enviarMarcaje", () => {
  it("cuando el servidor acepta, dice que llegó y que salió bien", async () => {
    const { cliente } = clienteFalso(async () => ({ error: null }));
    expect(await enviarMarcaje(cliente, MARCA)).toEqual({ ok: true, llego: true });
  });

  it("cuando el servidor RECHAZA, dice que llegó — ese intento sí cuenta", async () => {
    const { cliente } = clienteFalso(async () => ({ error: { message: "tipo no válido" } }));
    const r = await enviarMarcaje(cliente, MARCA);
    expect(r.ok).toBe(false);
    expect(r.llego).toBe(true);
    expect(r.error).toBe("tipo no válido");
  });

  it("cuando el envío se cuelga, TERMINA por tope de tiempo en vez de esperar para siempre", async () => {
    const { cliente } = clienteFalso(nuncaResponde);
    const r = await enviarMarcaje(cliente, MARCA, 20);
    expect(r.ok).toBe(false);
    // Que esta prueba termine ya es media prueba: sin el tope se quedaría
    // colgada hasta que vitest la matara, que es justo lo que le pasaba a la
    // Mac mini de la tienda.
  });

  it("un envío que no llegó NO cuenta para apartar la marca", async () => {
    const { cliente } = clienteFalso(nuncaResponde);
    expect((await enviarMarcaje(cliente, MARCA, 20)).llego).toBe(false);
  });

  it("cuando el colgado ni siquiera escucha el abort, TERMINA igual por el segundo cerrojo", async () => {
    const { cliente } = clienteFalso(nuncaEscuchaElAbort);
    const r = await enviarMarcaje(cliente, MARCA, 20);
    // Sin `conTope` esta prueba se queda colgada hasta que vitest la mate —
    // igual que el terminal se quedaba en "Confirmando en 0s…" para siempre.
    expect(r).toEqual({ ok: false, error: "el envío no obtuvo respuesta a tiempo", llego: false });
  });

  it("nunca lanza: una excepción escapada volvería a colgar el terminal", async () => {
    const { cliente } = clienteFalso(async () => {
      throw new Error("el almacén explotó");
    });
    await expect(enviarMarcaje(cliente, MARCA, 20)).resolves.toMatchObject({ ok: false });
  });

  it("manda los siete argumentos con el nombre exacto que espera fn_registrar_marcaje", async () => {
    // Un renombre aquí no rompe el typecheck ni la pantalla: la marca
    // simplemente deja de registrarse, en silencio y en producción.
    const { cliente, llamadas } = clienteFalso(async () => ({ error: null }));
    await enviarMarcaje(cliente, { ...MARCA, motivoOtro: "cita médica" });

    expect(llamadas).toHaveLength(1);
    expect(llamadas[0].fn).toBe("fn_registrar_marcaje");
    expect(llamadas[0].args).toEqual({
      p_persona_id: MARCA.personaId,
      p_tipo: MARCA.tipo,
      p_timestamp_cliente: MARCA.timestampCliente,
      p_client_uuid: MARCA.clientUuid,
      p_origen: "terminal",
      p_terminal_id: MARCA.terminalId,
      p_motivo_otro: "cita médica",
    });
  });
});

// ============================================================================
// Qué hace la cola con cada texto de rechazo
// ============================================================================
// Los tres textos son los que producción devolvió de verdad (marcas_apartadas,
// 2026-10-06). Cada uno decide algo distinto en sync.ts, y un texto que cae en
// la casilla equivocada o aparta una marca buena o la deja reintentándose
// para siempre:
//
//   «no coincide con p_terminal_id»   → la marca está bien, el vínculo de la Mac no
//   «permission denied for function»  → lo mismo: la Mac llamó SIN sesión (anon)
//   «tipo … no válido»                → la marca no corresponde: se aparta ya
describe("clasificar el rechazo de una marca", () => {
  const SESION_DESAJUSTADA = "el terminal autenticado no coincide con p_terminal_id";
  const SIN_SESION = "permission denied for function fn_registrar_marcaje";
  const DE_ESTADO = "tipo salida_almuerzo no válido en el estado actual (se esperaba entrada)";

  it("sin sesión (anon) es un problema de la Mac, no de la marca: la cola la espera", () => {
    expect(esSesionPerdida(SIN_SESION)).toBe(true);
    expect(esRechazoDeSesion(SIN_SESION)).toBe(true);
  });

  it("el desajuste de terminal sigue esperando en cola, pero NO es sesión perdida", () => {
    // La franja roja y el mensaje «perdió su vínculo» son solo para quien se
    // quedó sin sesión: a una Mac desajustada se la arregla sola la cola.
    expect(esRechazoDeSesion(SESION_DESAJUSTADA)).toBe(true);
    expect(esSesionPerdida(SESION_DESAJUSTADA)).toBe(false);
  });

  it("un rechazo de estado NO es de sesión: se aparta en el primer intento", () => {
    expect(esRechazoDeEstado(DE_ESTADO)).toBe(true);
    expect(esRechazoDeSesion(DE_ESTADO)).toBe(false);
    expect(esSesionPerdida(DE_ESTADO)).toBe(false);
  });

  it("el permiso de OTRA función no se confunde con el de marcar", () => {
    // Si mañana otra función devuelve «permission denied», no debe apartarse
    // ni quedar esperando como si fuera un problema de vínculo.
    expect(esSesionPerdida("permission denied for function fn_planilla_calcular")).toBe(false);
  });

  it("sin texto de error no hay nada que clasificar", () => {
    expect(esSesionPerdida(undefined)).toBe(false);
    expect(esRechazoDeSesion(undefined)).toBe(false);
  });
});

describe("un fallo de red que supabase-js devuelve como error", () => {
  // postgrest-js no lanza cuando fetch falla: arma `${nombre}: ${mensaje}`.
  it.each([
    "TypeError: Load failed",
    "TypeError: Failed to fetch",
    "TypeError: NetworkError when attempting to fetch resource.",
    "TimeoutError: signal timed out",
    "AbortError: The operation was aborted.",
    "FetchError: fetch failed",
  ])("«%s» NO es una respuesta del servidor", async (mensaje) => {
    expect(esFalloDeRed(mensaje)).toBe(true);
    const { cliente } = clienteFalso(async () => ({ error: { message: mensaje } }));
    const r = await enviarMarcaje(cliente, MARCA);
    expect(r).toEqual({ ok: false, error: mensaje, llego: false });
  });

  it("un rechazo de la base sigue siendo una respuesta: llego es true", () => {
    expect(esFalloDeRed("tipo salida_almuerzo no válido en el estado actual")).toBe(false);
    expect(esFalloDeRed("permission denied for function fn_registrar_marcaje")).toBe(false);
    expect(esFalloDeRed("el terminal autenticado no coincide con p_terminal_id")).toBe(false);
    expect(esFalloDeRed(undefined)).toBe(false);
  });
});
