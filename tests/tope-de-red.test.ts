// ============================================================================
// tope-de-red.test.ts — Que «no contestó» no se confunda con «contestó que no»
// ============================================================================
// `conTope` existe para las promesas que NO aceptan una señal de aborto: hoy
// `auth.getSession()`, que cuando el token guardado está vencido sale a la red a
// renovarlo sin dar ninguna forma de cancelarlo. Es la PRIMERA llamada de red
// del arranque del terminal, por delante incluso de la ficha del dispositivo.
//
// LO QUE ESTE ARCHIVO DEFIENDE, y no es el tope en sí:
//
//   Que el respaldo se pueda DISTINGUIR de una respuesta real. En el arranque,
//   «no hay sesión» y «no hubo respuesta» llevan a sitios opuestos: la primera
//   manda a vincular el dispositivo, la segunda tiene que seguir con la caché.
//   Si `conTope` devolviera algo indistinguible de una sesión vacía, un corte de
//   red mandaría a la sede a una pantalla de vinculación con el terminal ya
//   vinculado — y ahí no se marca, que es justo lo que veníamos a evitar.
//
//   Por eso page.tsx usa un Symbol como respaldo y compara por identidad. Las
//   pruebas de abajo fijan esa propiedad, no la implementación.
// ============================================================================
import { describe, expect, it, vi } from "vitest";
import { SEGUNDOS_ESPERA_RED, conTope, topeDeRed } from "@/lib/terminal/tope-de-red";

describe("conTope", () => {
  it("deja pasar el valor real cuando la promesa contesta a tiempo", async () => {
    const RESPALDO = Symbol("sin respuesta");
    const r = await conTope(Promise.resolve({ session: "viva" }), RESPALDO, 5);
    expect(r).toEqual({ session: "viva" });
  });

  it("devuelve el respaldo cuando no contesta — y TERMINA, que es el punto", async () => {
    const RESPALDO = Symbol("sin respuesta");
    const nuncaContesta = new Promise<string>(() => {});
    // 0.02 s en vez de los 8 reales: lo que se prueba es la decisión, no la espera.
    expect(await conTope(nuncaContesta, RESPALDO, 0.02)).toBe(RESPALDO);
  });

  it("el respaldo se distingue de una respuesta vacía real", async () => {
    // Las dos cosas que el arranque tiene que separar, uno al lado del otro.
    const RESPALDO = Symbol("sin respuesta");
    const sinRespuesta = await conTope(new Promise<unknown>(() => {}), RESPALDO, 0.02);
    const sesionVacia = await conTope(Promise.resolve({ session: null }), RESPALDO, 5);

    expect(sinRespuesta).toBe(RESPALDO);
    expect(sesionVacia).not.toBe(RESPALDO);
    expect(sesionVacia).toEqual({ session: null });
  });

  it("una promesa que revienta sigue reventando: no la disfraza de respaldo", async () => {
    // Un fallo real tiene que llegar a quien llama. Tragárselo aquí convertiría
    // un error con causa en un «no contestó» sin causa, que se diagnostica peor.
    const RESPALDO = Symbol("sin respuesta");
    await expect(conTope(Promise.reject(new Error("token inválido")), RESPALDO, 5)).rejects.toThrow(
      "token inválido",
    );
  });

  it("no deja el temporizador vivo cuando gana la promesa", async () => {
    // Sin el clearTimeout, cada llamada deja un temporizador de 8 s colgando.
    // En el terminal eso es una pestaña que tarda en cerrarse; en las pruebas, un
    // proceso que no termina — y esa es la forma en que esto se nota primero.
    const limpiar = vi.spyOn(globalThis, "clearTimeout");
    await conTope(Promise.resolve("ya"), Symbol("no"), 5);
    expect(limpiar).toHaveBeenCalled();
    limpiar.mockRestore();
  });
});

describe("topeDeRed", () => {
  it("entrega una señal que aún no está abortada", () => {
    expect(topeDeRed(5).aborted).toBe(false);
  });

  it("la señal se aborta sola al agotarse el tiempo", async () => {
    const señal = topeDeRed(0.02);
    await new Promise((r) => setTimeout(r, 60));
    expect(señal.aborted).toBe(true);
  });

  it("ocho segundos, y el mismo número para todo el terminal", () => {
    // El valor concreto importa menos que el hecho de que sea UNO: antes cada
    // llamada de red tenía su propia respuesta a «cuánto espero», y la mayoría
    // respondía «para siempre».
    expect(SEGUNDOS_ESPERA_RED).toBe(8);
  });
});
