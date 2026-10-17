// ============================================================================
// seguros-asegurados.test.ts — la lista de asegurados de un seguro (0528)
// ============================================================================
// Lo que importa cuidar:
//   · que a quien le falta el documento o la fecha de nacimiento salga SEÑALADA —sin
//     esos datos la aseguradora no emite su certificado y la persona queda fuera de
//     la póliza sin que nadie lo note—, y que un hueco no se confunda con un cero;
//   · que la remuneración solo esté en el archivo si se la pidió (es plata por persona);
//   · que el documento viaje como TEXTO: un DNI con cero adelante, en Excel, pierde el
//     cero y el número llega mal al contador (lección del 2026-08-10, `csv.ts`);
//   · que las fechas salgan como las escribe el papel de la aseguradora.
// Quién está en un seguro lo dice la base, no esto: acá solo se da forma a lo que llega.
// ============================================================================
import { describe, it, expect } from "vitest";
import { generarCsv } from "@/lib/admin/csv";
import {
  columnasDeLista, datosQueFaltan, etiquetaDeDocumento, filasDeLista, nombreDeArchivoDeLista, resumenDeLista,
  type Asegurado,
} from "@/lib/admin/seguros-asegurados";

/** Una fila tal como la devuelve `fn_seguro_asegurados`: por defecto, una integrante de planilla con todo completo. */
function asegurado(o: Partial<Asegurado> = {}): Asegurado {
  return {
    persona_id: "p1", apellidos: "Prueba Lopez", nombres: "Ana", nombre_segun_dni: "PRUEBA LOPEZ ANA",
    tipo_documento: "dni", documento: "08817189", fecha_nacimiento: "1990-05-17", fecha_ingreso: "2024-06-01",
    sede: "TRU", tipo_vinculo: "planilla", activa: true, remuneracion: null,
    poliza_id: "z1", numero_poliza: "VL-001", aseguradora: "La Positiva", vigente_desde: "2026-10-01", vigente_hasta: "2027-10-01",
    ...o,
  };
}

describe("qué datos le faltan a cada persona para que la aseguradora la asegure", () => {
  it("con documento y fecha de nacimiento no le falta nada", () => {
    expect(datosQueFaltan(asegurado())).toEqual([]);
  });

  it("sin documento, o con uno en blanco, falta el documento", () => {
    expect(datosQueFaltan(asegurado({ documento: null }))).toEqual(["documento"]);
    expect(datosQueFaltan(asegurado({ documento: "   " }))).toEqual(["documento"]);
  });

  it("sin fecha de nacimiento falta ese dato; sin ninguno de los dos, faltan los dos en orden", () => {
    expect(datosQueFaltan(asegurado({ fecha_nacimiento: null }))).toEqual(["fecha_nacimiento"]);
    expect(datosQueFaltan(asegurado({ documento: null, fecha_nacimiento: null }))).toEqual(["documento", "fecha_nacimiento"]);
  });

  it("la remuneración solo falta si se la pidió", () => {
    expect(datosQueFaltan(asegurado({ remuneracion: null }), false)).toEqual([]);
    expect(datosQueFaltan(asegurado({ remuneracion: null }), true)).toEqual(["remuneracion"]);
    expect(datosQueFaltan(asegurado({ remuneracion: 1130 }), true)).toEqual([]);
  });

  it("el nombre según DNI no es obligatorio: es un dato de cortesía, no frena el certificado", () => {
    expect(datosQueFaltan(asegurado({ nombre_segun_dni: null }))).toEqual([]);
  });
});

describe("el resumen que se ve arriba de la lista", () => {
  it("cuenta a las personas, a las que ya no están activas y a las que tienen datos por completar", () => {
    const filas = [
      asegurado({ persona_id: "a" }),
      asegurado({ persona_id: "b", documento: null }),
      asegurado({ persona_id: "c", activa: false }),
      asegurado({ persona_id: "d", fecha_nacimiento: null, documento: null }),
    ];
    expect(resumenDeLista(filas)).toEqual({ total: 4, activas: 3, inactivas: 1, incompletas: 2 });
  });

  it("una lista vacía es cero en todo, no un error", () => {
    expect(resumenDeLista([])).toEqual({ total: 0, activas: 0, inactivas: 0, incompletas: 0 });
  });

  it("con la remuneración pedida, quien no la tiene cuenta como incompleta", () => {
    const filas = [asegurado({ persona_id: "a", remuneracion: 1130 }), asegurado({ persona_id: "b", remuneracion: null })];
    expect(resumenDeLista(filas, false).incompletas).toBe(0);
    expect(resumenDeLista(filas, true).incompletas).toBe(1);
  });
});

describe("el archivo", () => {
  it("las columnas van en el orden que usa el papel, y la remuneración solo si se pide", () => {
    const sin = columnasDeLista(false);
    const con = columnasDeLista(true);
    expect(sin).not.toContain("Remuneración asegurable");
    expect(con).toContain("Remuneración asegurable");
    expect(con.filter((c) => c !== "Remuneración asegurable")).toEqual(sin);
    expect(sin.slice(0, 5)).toEqual(["Apellidos", "Nombres", "Nombre según DNI", "Tipo de documento", "Documento"]);
    expect(sin[sin.length - 1]).toBe("REVISAR");
  });

  it("cada fila trae TODAS las columnas, y ninguna de más: lo que no está en la lista no sale", () => {
    for (const conRem of [false, true]) {
      const cols = columnasDeLista(conRem);
      const [fila] = filasDeLista([asegurado({ remuneracion: 1130 })], conRem);
      expect(Object.keys(fila).sort()).toEqual([...cols].sort());
    }
  });

  it("la remuneración NO sale en el archivo si no se la pidió, aunque la fila la trajera", () => {
    const [fila] = filasDeLista([asegurado({ remuneracion: 1130 })], false);
    expect(JSON.stringify(fila)).not.toContain("1130");
  });

  it("con la remuneración pedida sale con dos decimales, como un monto", () => {
    const [fila] = filasDeLista([asegurado({ remuneracion: 1130 })], true);
    expect(fila["Remuneración asegurable"]).toBe("1130.00");
  });

  it("las fechas salen día/mes/año y el tipo de documento con su nombre", () => {
    const [fila] = filasDeLista([asegurado({ tipo_documento: "ce", documento: "144858518" })], false);
    expect(fila["Fecha de nacimiento"]).toBe("17/05/1990");
    expect(fila["Fecha de ingreso"]).toBe("01/06/2024");
    expect(fila["Vigente desde"]).toBe("01/10/2026");
    expect(fila["Vigente hasta"]).toBe("01/10/2027");
    expect(fila["Tipo de documento"]).toBe("Carné de extranjería");
    expect(fila["Vínculo"]).toBe("Planilla");
  });

  it("lo que falta sale VACÍO y señalado en REVISAR, no omitido ni inventado", () => {
    const [fila] = filasDeLista([asegurado({ documento: null, tipo_documento: null, fecha_nacimiento: null, numero_poliza: null, poliza_id: null, vigente_desde: null, vigente_hasta: null, aseguradora: null })], false);
    expect(fila["Documento"]).toBe("");
    expect(fila["Fecha de nacimiento"]).toBe("");
    expect(fila["Póliza"]).toBe("");
    expect(fila["Vigente desde"]).toBe("");
    expect(fila["REVISAR"]).toBe("falta documento · falta fecha de nacimiento");
  });

  it("quien ya no está activa lo dice: es la baja que hay que pedir", () => {
    const [activa] = filasDeLista([asegurado()], false);
    const [baja] = filasDeLista([asegurado({ activa: false })], false);
    expect(activa["Situación"]).toBe("Activa");
    expect(baja["Situación"]).toBe("Ya no está activa: pedir la baja");
  });

  it("el DNI con cero adelante sale protegido como texto en el CSV: Excel no le come el cero", () => {
    const filas = filasDeLista([asegurado({ documento: "08817189" })], false);
    const csv = generarCsv(filas, columnasDeLista(false));
    expect(csv).toContain('"=""08817189"""');
    expect(csv.split("\n")[0]).toBe(columnasDeLista(false).join(","));
  });

  it("los nombres con coma o comillas no parten la fila", () => {
    const filas = filasDeLista([asegurado({ apellidos: 'De la Cruz, "Chola"', nombres: "Ana María" })], false);
    const csv = generarCsv(filas, columnasDeLista(false));
    expect(csv.split("\n")).toHaveLength(2);
    expect(csv).toContain('"De la Cruz, ""Chola"""');
  });
});

describe("el nombre del archivo", () => {
  it("lleva el seguro y el día, y nada que identifique a nadie", () => {
    expect(nombreDeArchivoDeLista("vida_ley", "2026-10-17")).toBe("cayla-asegurados-vida-ley-2026-10-17.csv");
    expect(nombreDeArchivoDeLista("salud_practicantes", "2026-10-17")).toBe("cayla-asegurados-salud-practicantes-2026-10-17.csv");
  });

  it("una clave rara no deja un nombre de archivo roto", () => {
    expect(nombreDeArchivoDeLista("../EPS Pacífico!", "2026-10-17")).toBe("cayla-asegurados-eps-pac-fico-2026-10-17.csv");
    expect(nombreDeArchivoDeLista("***", "2026-10-17")).toBe("cayla-asegurados-seguro-2026-10-17.csv");
  });
});

describe("las etiquetas del documento", () => {
  it("usa las del resto del sistema y deja pasar un tipo que no conoce", () => {
    expect(etiquetaDeDocumento("dni")).toBe("DNI");
    expect(etiquetaDeDocumento("pasaporte")).toBe("Pasaporte / PTP");
    expect(etiquetaDeDocumento("otro")).toBe("otro");
    expect(etiquetaDeDocumento(null)).toBe("");
  });
});
