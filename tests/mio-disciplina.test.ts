// Disciplina vista por la persona: lo que se ordena, se pagina y se dice.
// Lo que importa acá: que lo que pide atención nunca quede en la página 2, que
// el aliento no aparezca delante de algo por leer, y que «cómo vas» no hable
// como si el sistema sancionara.

import { describe, it, expect } from "vitest";
import {
  MENSAJES_DE_ALIENTO, POR_PAGINA, cuantosPiden, hayAliento, mensajeDeAliento, ordenarParaLaPersona, paginar,
  pesa, pideAtencion, porLeer, queFaltaEs, textoComoVas, tituloDe, type DocMio,
} from "@/lib/mio-disciplina";

const doc = (id: string, extra: Partial<DocMio> = {}): DocMio => ({
  id, correlativo: null, nivel: "amonestacion", tipo_causal: "conducta", estado: "entregado", medio_entrega: "fisico",
  entregado_at: "2026-10-01T15:00:00Z", enviado_a_info_at: null, periodo_desde: null, periodo_hasta: null,
  falta: null, abierto_at: null, leido_at: null, firma_confirmada_at: null, rechazo_firma_at: null,
  requiere_lectura: false, vigente_hasta: null, cancelado: false, ...extra,
});

describe("qué pide atención", () => {
  it("lo enviado a su Info y sin recibir la pide", () => {
    expect(pideAtencion(doc("a", { estado: "por_recibir", entregado_at: null, enviado_a_info_at: "2026-10-05T10:00:00Z" }))).toBe(true);
  });
  it("lo entregado en papel que pide lectura, hasta que dice «Lo leí»", () => {
    expect(porLeer(doc("a", { requiere_lectura: true }))).toBe(true);
    expect(porLeer(doc("a", { requiere_lectura: true, leido_at: "2026-10-06T15:42:00Z" }))).toBe(false);
  });
  it("lo que no pide lectura (por Info, ya firmado, de hace más de un año) no pide atención", () => {
    expect(pideAtencion(doc("a", { requiere_lectura: false }))).toBe(false);
  });
  it("cuenta cuántos piden: es el número del menú", () => {
    expect(cuantosPiden([
      doc("a", { requiere_lectura: true }), doc("b", { requiere_lectura: true, leido_at: "2026-10-06T10:00:00Z" }),
      doc("c", { estado: "por_recibir" }), doc("d"),
    ])).toBe(2);
  });
});

describe("pesa", () => {
  it("una amonestación o una suspensión pesan hasta que se cancelan (56.7)", () => {
    expect(pesa(doc("a"))).toBe(true);
    expect(pesa(doc("a", { nivel: "suspension" }))).toBe(true);
    expect(pesa(doc("a", { cancelado: true }))).toBe(false);
  });
  it("la llamada verbal nunca: no es sanción ni antecedente (54.2)", () => {
    expect(pesa(doc("a", { nivel: "verbal" }))).toBe(false);
  });
  it("una imputación o una carta de despido no caducan como antecedente", () => {
    expect(pesa(doc("a", { nivel: "imputacion" }))).toBe(true);
  });
  it("lo que todavía no recibió no pesa: no agrava hasta que se entrega (56.2)", () => {
    expect(pesa(doc("a", { estado: "por_recibir" }))).toBe(false);
  });
});

describe("hayAliento", () => {
  it("sin documentos, sí", () => expect(hayAliento([])).toBe(true));
  it("con algo ya cancelado, sí: el Reglamento ya se lo canceló", () => {
    expect(hayAliento([doc("a", { cancelado: true })])).toBe(true);
  });
  it("con una llamada verbal ya leída, sí: no pesa", () => {
    expect(hayAliento([doc("a", { nivel: "verbal", requiere_lectura: true, leido_at: "2026-10-06T10:00:00Z" })])).toBe(true);
  });
  it("con algo por leer, no: no es momento de un chiste", () => {
    expect(hayAliento([doc("a", { requiere_lectura: true })])).toBe(false);
  });
  it("con algo por recibir, no", () => {
    expect(hayAliento([doc("a", { estado: "por_recibir" })])).toBe(false);
  });
  it("con una amonestación vigente aunque ya la leyó, no", () => {
    expect(hayAliento([doc("a", { requiere_lectura: true, leido_at: "2026-10-06T10:00:00Z" })])).toBe(false);
  });
});

describe("ordenarParaLaPersona", () => {
  it("lo que pide atención va primero, aunque sea más viejo: nunca en la página 2", () => {
    const viejoPorLeer = doc("viejo", { requiere_lectura: true, entregado_at: "2026-08-01T10:00:00Z" });
    const nuevoLeido = doc("nuevo", { entregado_at: "2026-10-05T10:00:00Z" });
    expect(ordenarParaLaPersona([nuevoLeido, viejoPorLeer]).map((d) => d.id)).toEqual(["viejo", "nuevo"]);
  });
  it("el resto, de la más reciente a la más vieja", () => {
    const l = [doc("a", { entregado_at: "2026-07-01T10:00:00Z" }), doc("b", { entregado_at: "2026-09-01T10:00:00Z" }), doc("c", { entregado_at: "2026-08-01T10:00:00Z" })];
    expect(ordenarParaLaPersona(l).map((d) => d.id)).toEqual(["b", "c", "a"]);
  });
  it("no modifica la lista que recibe", () => {
    const l = [doc("a", { entregado_at: "2026-07-01T10:00:00Z" }), doc("b", { entregado_at: "2026-09-01T10:00:00Z" })];
    ordenarParaLaPersona(l);
    expect(l.map((d) => d.id)).toEqual(["a", "b"]);
  });
  it("con la misma fecha, un orden fijo: una fila no sale dos veces ni ninguna se pierde entre páginas", () => {
    const l = [doc("b"), doc("a"), doc("c")];
    expect(ordenarParaLaPersona(l).map((d) => d.id)).toEqual(["a", "b", "c"]);
  });
});

describe("paginar: solo 10 y el resto en páginas", () => {
  const veinticuatro = Array.from({ length: 24 }, (_, i) => i + 1);
  it("son 10 por página", () => expect(POR_PAGINA).toBe(10));
  it("la primera trae 10 y dice «1–10 de 24»", () => {
    const p = paginar(veinticuatro, 0);
    expect(p.items).toHaveLength(10);
    expect([p.desde, p.hasta, p.total, p.paginas]).toEqual([1, 10, 24, 3]);
  });
  it("la última trae lo que sobra", () => {
    const p = paginar(veinticuatro, 2);
    expect(p.items).toEqual([21, 22, 23, 24]);
    expect([p.desde, p.hasta]).toEqual([21, 24]);
  });
  it("exactamente 10 es una sola página: no hay nada que paginar", () => {
    expect(paginar(veinticuatro.slice(0, 10), 0).paginas).toBe(1);
  });
  it("11 son dos páginas", () => {
    expect(paginar(veinticuatro.slice(0, 11), 1).items).toEqual([11]);
  });
  it("una página fuera de rango se acerca a la última, no revienta ni queda vacía", () => {
    expect(paginar(veinticuatro, 99).pagina).toBe(2);
    expect(paginar(veinticuatro, -3).pagina).toBe(0);
  });
  it("una lista vacía: una página sin nada, y «0 de 0»", () => {
    const p = paginar([], 0);
    expect([p.items.length, p.paginas, p.desde, p.hasta]).toEqual([0, 1, 0, 0]);
  });
  it("recorrer todas las páginas devuelve cada fila exactamente una vez", () => {
    const vistas = [0, 1, 2].flatMap((n) => paginar(veinticuatro, n).items);
    expect(vistas).toEqual(veinticuatro);
  });
});

describe("cómo se llama cada documento", () => {
  it("nivel y causal, en palabras de la casa", () => {
    expect(tituloDe({ nivel: "amonestacion", tipo_causal: "conducta" })).toBe("Amonestación escrita · conducta");
    expect(tituloDe({ nivel: "verbal", tipo_causal: "tardanza" })).toBe("Llamada verbal · tardanzas");
  });
  it("la falta por su nombre corto, o por su número si todavía no hay nombre", () => {
    expect(queFaltaEs({ tipo_causal: "conducta", falta: { numeral: "53.2", literal: "h", rotulo: "Trato descortés", gravedad: "significativa" } })).toBe("Trato descortés");
    expect(queFaltaEs({ tipo_causal: "conducta", falta: { numeral: "53.2", literal: "h", rotulo: null, gravedad: "significativa" } })).toBe("53.2 h)");
    expect(queFaltaEs({ tipo_causal: "tardanza", falta: null })).toBe("Tardanzas reiteradas");
  });
});

describe("el mensaje de aliento", () => {
  it("son dieciséis", () => expect(MENSAJES_DE_ALIENTO).toHaveLength(16));
  it("ninguno es un texto vacío ni se repite", () => {
    expect(MENSAJES_DE_ALIENTO.every((m) => m.trim().length > 10)).toBe(true);
    expect(new Set(MENSAJES_DE_ALIENTO).size).toBe(16);
  });
  it("el mismo todo el día para la misma persona: no cambia cada vez que abre la pantalla", () => {
    expect(mensajeDeAliento("persona-1", "2026-10-06")).toBe(mensajeDeAliento("persona-1", "2026-10-06"));
  });
  it("cambia de un día a otro", () => {
    const dias = Array.from({ length: 10 }, (_, i) => mensajeDeAliento("persona-1", `2026-10-${String(i + 1).padStart(2, "0")}`));
    expect(new Set(dias).size).toBeGreaterThan(4);
  });
  it("«ver otro mensaje» da uno distinto, y recorre la lista sin salirse de ella", () => {
    const base = mensajeDeAliento("persona-1", "2026-10-06");
    expect(mensajeDeAliento("persona-1", "2026-10-06", 1)).not.toBe(base);
    for (let s = 0; s < 40; s++) expect(MENSAJES_DE_ALIENTO).toContain(mensajeDeAliento("persona-1", "2026-10-06", s));
  });
  it("ninguno afirma nada sobre cómo se porta: lo lee también quien tuvo una tardanza ayer", () => {
    for (const m of MENSAJES_DE_ALIENTO) expect(m).not.toMatch(/puntual|buena conducta|te portas|cumples/i);
  });
});

describe("textoComoVas", () => {
  const cuenta = (n: number, minimo: number | null, nivel = "amonestacion") => ({ mes: "2026-10-01", tardanzas_mes: n, minimo, nivel_siguiente: nivel });

  it("sin cuenta —a quien no se le mide— no dice nada", () => {
    expect(textoComoVas(null)).toBeNull();
  });
  it("sin mínimo —hay un procedimiento abierto— tampoco: no es un contador", () => {
    expect(textoComoVas(cuenta(2, null))).toBeNull();
  });
  it("cero tardanzas: una frase corta, sin advertencias", () => {
    const t = textoComoVas(cuenta(0, 3))!;
    expect(t.titulo).toBe("No llevas tardanzas en octubre.");
    expect(t.detalle).toBe("");
  });
  it("antes del umbral dice cuántas le faltan en condicional, y cómo justificar", () => {
    const t = textoComoVas(cuenta(2, 3))!;
    expect(t.titulo).toBe("Llevas 2 tardanzas en octubre.");
    expect(t.detalle).toContain("Con 3, la Empresa podría emitir una amonestación escrita (RIT 19.2 b)");
    expect(t.detalle).toContain("RIT 18.2");
    expect(t.casillas).toEqual({ de: 3, llenas: 2 });
  });
  it("jamás habla como si el sistema sancionara: nada de «te corresponde»", () => {
    for (const n of [0, 1, 2, 3, 5]) {
      const t = textoComoVas(cuenta(n, 3))!;
      expect(`${t.titulo} ${t.detalle}`).not.toMatch(/te corresponde|corresponde(rá)?|serás sancion|te sancion/i);
    }
  });
  it("en el umbral no dice que ya pasó algo: dice que la decisión es de una persona", () => {
    const t = textoComoVas(cuenta(3, 3))!;
    expect(t.detalle).toContain("la Empresa puede emitir una amonestación escrita");
    expect(t.detalle).toContain("La decisión es siempre de una persona");
  });
  it("el paso cambia con el escalón: con una amonestación vigente, la siguiente es una suspensión", () => {
    expect(textoComoVas(cuenta(1, 2, "suspension"))!.detalle).toContain("una suspensión sin goce de haber (RIT 19.2 c o d)");
  });
  it("una sola tardanza se dice en singular", () => {
    expect(textoComoVas(cuenta(1, 3))!.titulo).toBe("Llevas 1 tardanza en octubre.");
  });
  it("las casillas no pasan de seis aunque el mínimo sea mayor, ni se llenan de más", () => {
    expect(textoComoVas(cuenta(9, 8))!.casillas).toEqual({ de: 6, llenas: 6 });
  });
  it("un escalón que no conoce no inventa un texto", () => {
    expect(textoComoVas(cuenta(2, 3, "despido"))).toBeNull();
  });
});
