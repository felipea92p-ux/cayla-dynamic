// ============================================================================
// reglas-negocio.test.ts — Reglas de negocio que vive el navegador
// ============================================================================
// Blinda dos cosas que el colaborador VE en pantalla:
//   · lecturaObjetivos — que los objetivos NO nombren ningún monto. Hasta el
//     2026-08-06 esta función era el GEMELO en el navegador de lo que pagaba
//     fn_planilla_calcular (100%→21%, ≥60%→12.6%). La migración 0171 apagó ese
//     plus en SQL y esto lo ancla del lado de la pantalla: si alguien lo
//     reviviera en un solo sitio, la pantalla ofrecería un pago que la boleta
//     no hace, o al revés.
//   · formatSoles — cómo se escribe el dinero. Un formato roto siembra dudas
//     sobre montos que en realidad están bien.
// ============================================================================
import { describe, it, expect } from "vitest";
import { lecturaObjetivos } from "@/lib/objetivos";
import { formatSoles, baseDeclaradaDe, RANGOS } from "@/lib/rangos";
import { NOMBRE_RANGO } from "@/lib/politica-salarial";

describe("lecturaObjetivos — los objetivos no pagan (0171)", () => {
  // Estas tres aserciones decían lo contrario hasta el 2026-08-06: que cumplir
  // el 100% daba «Plus 21%» y el 60% «Plus 12.6%». Se dieron vuelta junto con
  // la migración 0171. El plus era remuneración tratada como si no lo fuera, y
  // contradecía la política salarial firmada bajo la Ley 30709.
  it("cumplir el 100% no nombra ningún monto", () => {
    expect(lecturaObjetivos(10, 10)).toEqual({ etiqueta: "100% cumplido", observacion: false });
  });

  it("cumplir el 60% tampoco", () => {
    expect(lecturaObjetivos(6, 10)).toEqual({ etiqueta: "60% cumplido", observacion: false });
  });

  it("ninguna etiqueta menciona un plus, en ningún tramo", () => {
    for (let c = 0; c <= 10; c++) {
      expect(lecturaObjetivos(c, 10).etiqueta.toLowerCase()).not.toContain("plus");
    }
  });

  it("al 50% no hay observación: el umbral sigue siendo 30%", () => {
    expect(lecturaObjetivos(5, 10).observacion).toBe(false);
  });

  it("por debajo del 30% se marca observación por bajo desempeño", () => {
    // Lo único que sobrevive del mecanismo viejo, y a propósito: nunca fue un
    // pago sino un aviso para conversar, y la decisión es siempre de una persona.
    expect(lecturaObjetivos(2, 10)).toEqual({ etiqueta: "20% cumplido", observacion: true });
  });

  it("sin objetivos cargados no inventa nada", () => {
    expect(lecturaObjetivos(0, 0)).toEqual({ etiqueta: "—", observacion: false });
  });

  it("es proporción y no conteo: una lista corta se lee igual", () => {
    expect(lecturaObjetivos(3, 3).etiqueta).toBe("100% cumplido");
  });
});

describe("formatSoles — cómo se escribe el dinero", () => {
  it("escribe miles con coma y siempre 2 decimales", () => {
    expect(formatSoles(1950)).toContain("1,950.00");
  });

  it("el cero se muestra como 0.00, no vacío", () => {
    expect(formatSoles(0)).toContain("0.00");
  });

  it("redondea a 2 decimales", () => {
    expect(formatSoles(1234.567)).toContain("1,234.57");
  });

  it("lleva el símbolo de soles", () => {
    expect(formatSoles(100)).toMatch(/S\/?/);
  });
});

// La función se llamaba `salarioSugerido` y devolvía el monto que cada rango
// *debería terminar recibiendo* (1,320 · 1,450 · 1,650 · 1,890 · 2,250 · 3,000).
// Pasó a ser `baseDeclaradaDe`: el monto que se DECLARA en el PLAME y que el
// sistema paga. No es un renombre cosmético — cambió lo que el número significa,
// y por eso estas pruebas cambiaron con él.
describe("baseDeclaradaDe — el monto que declara cada rango", () => {
  it("un rango real trae un monto positivo", () => {
    const monto = baseDeclaradaDe("cayla");
    expect(typeof monto).toBe("number");
    expect(monto as number).toBeGreaterThan(0);
  });

  it("un rango inexistente no inventa un monto (devuelve indefinido)", () => {
    expect(baseDeclaradaDe("rango-que-no-existe")).toBeUndefined();
  });

  // Ninguna base puede quedar por debajo de la RMV: sería declarar menos que el
  // mínimo legal. Colibrí y cayla están clavados en ella a propósito, así que este
  // es el guardián de que nadie las baje por descuido — y el recordatorio de que
  // hay que subirlas cuando la RMV suba.
  it("ninguna base declarada cae por debajo de la RMV vigente", () => {
    const RMV = 1130; // D.S. 006-2024-TR, vigente al 2026-08-03
    for (const r of RANGOS) {
      expect(r.baseDeclarada, `${r.label} declara menos que la RMV`).toBeGreaterThanOrEqual(RMV);
    }
  });

  // Las bandas tienen que subir con el rango, o el rango no ordena nada.
  it("las bases no bajan al subir de rango", () => {
    const porOrden = [...RANGOS].sort((a, b) => a.orden - b.orden);
    for (let i = 1; i < porOrden.length; i++) {
      expect(
        porOrden[i].baseDeclarada,
        `${porOrden[i].label} declara menos que ${porOrden[i - 1].label}`,
      ).toBeGreaterThanOrEqual(porOrden[i - 1].baseDeclarada);
    }
  });
});

// ── Los rangos se llaman igual en los dos sitios donde el código los nombra ──
//
// Acá vivía un bloque que blindaba los techos de educación contra un campo
// `topeEducacion` en `rangos.ts`. Se borró el 2026-08-06 con el campo, y cómo
// falló vale más que lo que probaba:
//
// El bloque comparaba `rangos.ts` contra los montos de la MIGRACIÓN 0132 —un
// mapa escrito a mano acá dentro— y no contra la tabla `topes_educacion_rango`,
// que es donde los techos se editan. Cuando la 0140 retiró «caylo» de la tabla,
// este mapa siguió diciendo `caylo: 180` y las cuatro aserciones siguieron
// verdes durante toda la divergencia. Un espejo de un espejo no vigila al
// original: da la calma de que algo lo está mirando.
//
// Los techos los vigila ahora la prueba pgTAP 139, que compara contra la tabla.
// Acá queda lo único que vitest SÍ puede vigilar sin base de datos: que las dos
// listas de rangos que existen en el código digan lo mismo.
describe("los dos sitios que nombran los rangos no se contradicen", () => {
  // `RANGOS` pinta el desplegable de Equipo; `NOMBRE_RANGO` pone los títulos en
  // la política salarial que se le entrega al equipo. Hasta el 2026-08-06 el
  // rango tope era «ArchiCaylo» en el desplegable y «ArchiCayla» en el documento
  // firmado: la misma persona con dos nombres según qué pantalla la mirara.
  it("cada rango tiene un solo nombre en pantalla", () => {
    for (const r of RANGOS) {
      expect(
        NOMBRE_RANGO[r.codigo],
        `«${r.label}» se llama distinto en la política salarial`,
      ).toBe(r.label);
    }
  });

  it("las dos listas tienen exactamente los mismos rangos", () => {
    expect([...RANGOS].map((r) => r.codigo).sort()).toEqual(Object.keys(NOMBRE_RANGO).sort());
  });

  // Si dos rangos comparten `orden`, el desplegable los muestra en un orden que
  // cambia entre recargas — y el orden ES la jerarquía.
  it("ningún rango comparte el lugar de otro", () => {
    const ordenes = RANGOS.map((r) => r.orden);
    expect(new Set(ordenes).size, "hay dos rangos con el mismo orden").toBe(ordenes.length);
  });

  // El rango retirado no puede volver por la puerta de la pantalla: la migración
  // 0178 lo sacó del CHECK, así que elegirlo daría un error al guardar.
  it("«caylo» no se ofrece: la base lo rechaza desde la 0178", () => {
    expect(RANGOS.some((r) => r.codigo === "caylo")).toBe(false);
  });
});
