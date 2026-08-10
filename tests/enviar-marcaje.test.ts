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
import { enviarMarcaje } from "@/lib/terminal/enviar-marcaje";

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
