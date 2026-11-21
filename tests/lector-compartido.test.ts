// ============================================================================
// lector-compartido.test.ts — Una lectura cara se hace una vez por pestaña
// ============================================================================
// Lo que se defiende acá:
//
// 1. DOS QUE PIDEN A LA VEZ COMPARTEN UNA LECTURA. El menú y la pantalla
//    Bandeja pedían cada uno las mismas ~28 consultas.
// 2. QUIEN ACABA DE GUARDAR NO RECIBE UNA LECTURA DE ANTES. Una lectura que
//    salió antes del guardado no sirve aunque llegue después: se espera a la
//    siguiente, y esa siguiente es UNA para todos los que esperan.
// 3. NUNCA HAY DOS EN VUELO, así que la última publicada es la más nueva.
// 4. UN FALLO NO DEJA EL LECTOR TRABADO.
// ============================================================================
import { describe, expect, it } from "vitest";
import { crearLectorCompartido } from "../apps/web/lib/lector-compartido";

/** Una lectura a mano: cada llamada queda pendiente hasta que la prueba la resuelve. */
function lecturaControlada() {
  const pendientes: { resolver: (v: string) => void; rechazar: (e: unknown) => void }[] = [];
  let llamadas = 0;
  const leer = () => {
    llamadas += 1;
    return new Promise<string>((resolver, rechazar) => { pendientes.push({ resolver, rechazar }); });
  };
  return {
    leer,
    llamadas: () => llamadas,
    resolver: (i: number, v: string) => pendientes[i]?.resolver(v),
    rechazar: (i: number, e: unknown) => pendientes[i]?.rechazar(e),
  };
}

/** Un reloj que solo avanza cuando la prueba lo dice. */
function reloj(inicio = 1_000) {
  let t = inicio;
  return { ahora: () => t, avanzar: (ms: number) => { t += ms; } };
}

const respiro = () => new Promise<void>((r) => setTimeout(r, 0));

describe("crearLectorCompartido", () => {
  it("dos que piden a la vez comparten una sola lectura", async () => {
    const c = lecturaControlada();
    const r = reloj();
    const lector = crearLectorCompartido(c.leer, r.ahora);

    const a = lector.pedir();
    const b = lector.pedir();
    expect(c.llamadas()).toBe(1);

    c.resolver(0, "uno");
    expect((await a).valor).toBe("uno");
    expect((await b).valor).toBe("uno");
  });

  it("entrega la guardada si salió después de lo pedido, sin ir a la base", async () => {
    const c = lecturaControlada();
    const r = reloj();
    const lector = crearLectorCompartido(c.leer, r.ahora);

    const primera = lector.pedir();
    c.resolver(0, "uno");
    await primera;

    r.avanzar(30_000);
    const reusada = await lector.pedir(r.ahora() - 60_000); // «me sirve una de hasta un minuto»
    expect(reusada.valor).toBe("uno");
    expect(c.llamadas()).toBe(1);
  });

  it("no entrega una guardada más vieja que lo pedido", async () => {
    const c = lecturaControlada();
    const r = reloj();
    const lector = crearLectorCompartido(c.leer, r.ahora);

    const primera = lector.pedir();
    c.resolver(0, "uno");
    await primera;

    r.avanzar(30_000);
    const nueva = lector.pedir(r.ahora() - 10_000); // la guardada tiene 30 s: no sirve
    expect(c.llamadas()).toBe(2);
    c.resolver(1, "dos");
    expect((await nueva).valor).toBe("dos");
  });

  it("quien acaba de guardar no recibe la lectura que salió antes de su guardado", async () => {
    const c = lecturaControlada();
    const r = reloj();
    const lector = crearLectorCompartido(c.leer, r.ahora);

    const vieja = lector.pedir(); // sale en t=1000
    r.avanzar(200); // … alguien guarda en t=1200 …
    const trasGuardar = lector.pedir(); // quiere una que haya salido en t>=1200
    expect(c.llamadas()).toBe(1); // todavía no sale la segunda: nunca dos en vuelo

    c.resolver(0, "antes del guardado");
    await vieja;
    await respiro();
    expect(c.llamadas()).toBe(2);

    c.resolver(1, "después del guardado");
    const lectura = await trasGuardar;
    expect(lectura.valor).toBe("después del guardado");
    expect(lectura.pedidaEn).toBeGreaterThanOrEqual(1_200);
  });

  it("todos los que esperan mientras hay una en vuelo comparten UNA lectura siguiente", async () => {
    const c = lecturaControlada();
    const r = reloj();
    const lector = crearLectorCompartido(c.leer, r.ahora);

    const primera = lector.pedir();
    r.avanzar(50);
    const b = lector.pedir();
    r.avanzar(50);
    const d = lector.pedir();
    r.avanzar(50);
    const e = lector.pedir();

    c.resolver(0, "uno");
    await primera;
    await respiro();
    expect(c.llamadas()).toBe(2); // una sola siguiente para los tres

    c.resolver(1, "dos");
    expect((await b).valor).toBe("dos");
    expect((await d).valor).toBe("dos");
    expect((await e).valor).toBe("dos");
    expect(c.llamadas()).toBe(2);
  });

  it("publica cada lectura a quien escucha, en el orden en que salieron", async () => {
    const c = lecturaControlada();
    const r = reloj();
    const lector = crearLectorCompartido(c.leer, r.ahora);
    const vistas: string[] = [];
    const dejar = lector.escuchar((l) => vistas.push(l.valor));

    expect(lector.ultima()).toBeNull();
    const a = lector.pedir();
    r.avanzar(10);
    const b = lector.pedir();
    c.resolver(0, "uno");
    await a;
    await respiro();
    c.resolver(1, "dos");
    await b;

    expect(vistas).toEqual(["uno", "dos"]);
    expect(lector.ultima()?.valor).toBe("dos");

    dejar();
    r.avanzar(10);
    const tercera = lector.pedir();
    c.resolver(2, "tres");
    await tercera;
    expect(vistas).toEqual(["uno", "dos"]); // dejó de escuchar
    expect(lector.ultima()?.valor).toBe("tres");
  });

  it("un fallo se le dice a quien esperaba y no deja el lector trabado", async () => {
    const c = lecturaControlada();
    const r = reloj();
    const lector = crearLectorCompartido(c.leer, r.ahora);

    const falla = lector.pedir();
    r.avanzar(10);
    const enCola = lector.pedir(); // esperaba a la que va a fallar
    c.rechazar(0, new Error("sin red"));
    await expect(falla).rejects.toThrow("sin red");

    await respiro();
    expect(c.llamadas()).toBe(2); // la siguiente salió igual
    c.resolver(1, "ya hay red");
    expect((await enCola).valor).toBe("ya hay red");
    expect(lector.ultima()?.valor).toBe("ya hay red");
  });

  it("si leer revienta antes de devolver su promesa, también es un fallo y no una excepción suelta", async () => {
    const lector = crearLectorCompartido<string>(() => { throw new Error("roto"); });
    await expect(lector.pedir()).rejects.toThrow("roto");
    await expect(lector.pedir()).rejects.toThrow("roto"); // sigue respondiendo
  });
});
