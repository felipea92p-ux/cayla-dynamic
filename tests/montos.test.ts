// ============================================================================
// montos.test.ts — que «8,500» nunca vuelva a valer 8.50
// ============================================================================
// El caso que fija esta prueba costó, medido, S/8,491.50: DO teclea en «Ya le
// pagué aparte» la misma cifra que la app le acaba de imprimir —8,500— y el
// sistema registra un descuento de S/8.50, así que la planilla vuelve a pagar
// los S/8,500 completos.
//
// Las dos mitades importan igual:
//   · que las formas reales se lean bien —incluida «850,50», que ya funcionaba
//     y no se puede romper—,
//   · y que lo ambiguo se RECHACE en vez de elegir una lectura. Un parser de
//     dinero que ante la duda se decide se equivoca en silencio.
// ============================================================================
import { describe, expect, it } from "vitest";
import { parsearMontoSoles } from "../packages/shared/src/montos";

/** Atajo: el monto, o `null` si fue rechazado. */
function monto(texto: string): number | null {
  const r = parsearMontoSoles(texto);
  return r.ok ? r.monto : null;
}

describe("el defecto que la trajo", () => {
  it("«8,500» son ocho mil quinientos, no ocho con cincuenta", () => {
    expect(monto("8,500")).toBe(8500);
  });

  it("«8,500.00» se lee, y antes daba NaN", () => {
    expect(monto("8,500.00")).toBe(8500);
  });

  it("«1,130» y «2,000» — los dos sueldos que más se teclean acá", () => {
    expect(monto("1,130")).toBe(1130);
    expect(monto("2,000")).toBe(2000);
  });

  it("y el resultado NO es el que daba el replace de una sola coma", () => {
    // Number("8,500".replace(",", ".")) === 8.5
    expect(monto("8,500")).not.toBe(8.5);
    expect(monto("1,130")).not.toBe(1.13);
  });
});

describe("lo que ya funcionaba sigue funcionando", () => {
  it("la coma como decimal, cuando la siguen 1 o 2 dígitos", () => {
    expect(monto("850,50")).toBe(850.5);
    expect(monto("850,5")).toBe(850.5);
  });

  it("el punto como decimal, que es la notación peruana", () => {
    expect(monto("850.50")).toBe(850.5);
    expect(monto("1130.5")).toBe(1130.5);
  });

  it("una cifra pelada", () => {
    expect(monto("1130")).toBe(1130);
    expect(monto("0")).toBe(0);
  });

  it("miles largos", () => {
    expect(monto("1,234,567.89")).toBe(1234567.89);
  });
});

describe("lo que se copia de la propia pantalla", () => {
  it("con el símbolo de moneda y su espacio delante", () => {
    expect(monto("S/ 8,500.00")).toBe(8500);
    expect(monto("S/8,500.00")).toBe(8500);
    expect(monto("s/. 1,130")).toBe(1130);
  });

  it("con el espacio duro que mete Intl al formatear", () => {
    // El resultado real de Intl.NumberFormat("es-PE", {style:"currency",currency:"PEN"})
    // lleva U+00A0 entre el símbolo y la cifra.
    expect(monto("S/ 8,500.00")).toBe(8500);
  });
});

describe("lo ambiguo se rechaza, y el mensaje dice qué escribir", () => {
  it("«8.500» no se adivina: son dos lecturas y ninguna pista", () => {
    const r = parsearMontoSoles("8.500");
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.motivo).toContain("8.50");
      expect(r.motivo).toContain("8500");
    }
  });

  it("un texto que no es una cifra", () => {
    expect(monto("ochocientos")).toBeNull();
    expect(monto("preguntar a Rosa")).toBeNull();
  });

  it("comas mal puestas", () => {
    expect(monto("1,23,456")).toBeNull();
    expect(monto("8,")).toBeNull();
    expect(monto(",50")).toBeNull();
  });

  it("vacío, nulo y espacios", () => {
    expect(monto("")).toBeNull();
    expect(monto("   ")).toBeNull();
    expect(parsearMontoSoles(null).ok).toBe(false);
    expect(parsearMontoSoles(undefined).ok).toBe(false);
  });

  it("con signo, porque un descuento se escribe sin el menos", () => {
    expect(monto("-850.50")).toBeNull();
    expect(monto("+850.50")).toBeNull();
  });

  it("más de dos decimales en soles", () => {
    expect(monto("850.505")).toBeNull();
  });
});

describe("el motivo siempre es una frase que se puede mostrar", () => {
  it("nunca queda vacío", () => {
    for (const malo of ["", "ochocientos", "8.500", "1,23,456", "-5"]) {
      const r = parsearMontoSoles(malo);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.motivo.length).toBeGreaterThan(10);
    }
  });
});
