import { describe, expect, it } from "vitest";
import { compartirMientrasVuela } from "../apps/web/lib/compartir-mientras-vuela";

// Una pregunta idéntica que ya está viajando no se vuelve a hacer; una que ya
// terminó SÍ se vuelve a hacer. Lo segundo es lo que impide que esto sea una caché
// (y que una boleta recién firmada se siga mostrando como pendiente).

function pedidoLento<T>(valor: T) {
  let llamadas = 0;
  let resolver!: (v: T) => void;
  const pedir = () => { llamadas++; return new Promise<T>((r) => { resolver = r; }); };
  return { pedir, llamadas: () => llamadas, responder: () => resolver(valor) };
}

describe("compartirMientrasVuela", () => {
  it("dos peticiones a la vez hacen UN viaje y reciben la misma respuesta", async () => {
    const p = pedidoLento({ n: 1 });
    const a = compartirMientrasVuela("t-comparte", p.pedir);
    const b = compartirMientrasVuela("t-comparte", p.pedir);
    p.responder();
    expect(await a).toBe(await b);
    expect(p.llamadas()).toBe(1);
  });

  it("una vez que llegó la respuesta, la siguiente petición vuelve a preguntar", async () => {
    const p = pedidoLento("x");
    const a = compartirMientrasVuela("t-libera", p.pedir);
    p.responder();
    await a;
    const b = compartirMientrasVuela("t-libera", p.pedir);
    p.responder();
    await b;
    expect(p.llamadas()).toBe(2);
  });

  it("claves distintas no se mezclan", async () => {
    const p1 = pedidoLento(1);
    const p2 = pedidoLento(2);
    const a = compartirMientrasVuela("t-uno", p1.pedir);
    const b = compartirMientrasVuela("t-dos", p2.pedir);
    p1.responder(); p2.responder();
    expect([await a, await b]).toEqual([1, 2]);
  });

  it("si la petición falla, los que esperaban reciben el fallo y la clave se libera", async () => {
    let n = 0;
    const falla = () => { n++; return Promise.reject(new Error("sin red")); };
    const a = compartirMientrasVuela("t-falla", falla);
    const b = compartirMientrasVuela("t-falla", falla);
    await expect(a).rejects.toThrow("sin red");
    await expect(b).rejects.toThrow("sin red");
    expect(n).toBe(1);
    const c = compartirMientrasVuela("t-falla", () => Promise.resolve("ya"));
    expect(await c).toBe("ya");
  });
});
