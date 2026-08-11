// ============================================================================
// csv.test.ts — El DNI que Excel se comía camino al T-Registro
// ============================================================================
// Seis pantallas exportan CSV con el mismo helper, y una de ellas es el PADRÓN:
// el archivo que sale del sistema hacia el contador y de ahí al T-Registro de
// SUNAT. Lleva DNI, cuentas bancarias, celulares y direcciones.
//
// Un CSV no tiene tipos. Quien decide qué es cada celda es Excel, y adivina mal
// justo en lo que aquí importa. Medido el 2026-08-10 con el helper anterior,
// que solo escapaba comillas, comas y saltos de línea:
//
//     "08817189"              → salía al crudo → Excel: 8817189  (pierde el cero)
//     "19419112345678"        → al crudo       → Excel: 1.94191E+13
//     "00219411234567890123"  → al crudo       → Excel trunca a 15 cifras
//     "-Av. Grau 100"         → al crudo       → Excel: #NAME?
//     "Av. Sol\rMz. B"        → al crudo       → el retorno parte la fila
//
// Y en producción, ese mismo día: UNA persona del equipo tiene el documento
// empezando en cero. No era hipotético.
//
// LA TRAMPA QUE ESTE ARCHIVO CUIDA. Entrecomillar no protege de una fórmula:
// Excel quita las comillas del CSV y DESPUÉS evalúa lo de dentro. Si alguien
// «arregla» esto ampliando el regex de escapado, las pruebas de fórmula siguen
// pasando en verde mientras el agujero sigue abierto. Por eso se comprueba la
// forma ="..." y no solo que la celda esté entrecomillada.
//
// Y LA OTRA MITAD, que es la que de verdad puede romper plata: un número
// negativo TIENE que seguir siendo número. Los descuentos de planilla y
// provisiones son «-150.00». Convertirlos en texto por empezar en «-» dejaría
// esas columnas sin poder sumarse en Excel — se habría arreglado un dato y roto
// seis pantallas. Es el caso que separa el arreglo bueno del apresurado.
// ============================================================================

import { describe, expect, it } from "vitest";
import { generarCsv } from "@/lib/admin/csv";

/**
 * Atajo: una fila, una columna, y devuelve solo la celda ya escapada.
 *
 * Se queda con TODO lo que hay tras el primer salto en vez de partir por «\n»
 * y tomar el trozo [1]: una celda con salto de línea dentro ocupa dos líneas a
 * propósito, y aquel atajo la habría cortado por la mitad — haciendo fallar la
 * prueba del escapado correcto.
 */
function celda(valor: unknown): string {
  const csv = generarCsv([{ v: valor }], ["v"]);
  return csv.slice(csv.indexOf("\n") + 1);
}

describe("lo que Excel destruiría si se le deja al crudo", () => {
  it("un DNI con cero adelante conserva el cero", () => {
    // El caso real: una persona del equipo, agosto 2026.
    expect(celda("08817189")).toBe('"=""08817189"""');
  });

  it("una cuenta bancaria de 14 dígitos no cae en notación científica", () => {
    expect(celda("19419112345678")).toBe('"=""19419112345678"""');
  });

  it("un CCI de 20 dígitos no se trunca", () => {
    // Pasando de 15 cifras la pérdida es REAL, no cosmética: Excel rellena el
    // resto con ceros y la cuenta deja de existir.
    expect(celda("00219411234567890123")).toBe('"=""00219411234567890123"""');
  });

  it("un celular con prefijo de país conserva el +", () => {
    expect(celda("+51987654321")).toBe('"=""+51987654321"""');
  });
});

describe("fórmulas: lo que entrecomillar NO resuelve", () => {
  // Cada uno de estos, al crudo, Excel lo ejecuta.
  const arranques = ["=1+1", "-Av. Grau 100", "+Casa 4", "@casa"];

  for (const entrada of arranques) {
    it(`neutraliza «${entrada}»`, () => {
      const salida = celda(entrada);
      // Lo que importa NO es que esté entrecomillada —Excel quita esas comillas
      // y evalúa igual—, sino que llegue envuelta en ="...".
      expect(salida).toContain('=""');
      expect(salida).toContain(entrada.replace(/"/g, '""'));
    });
  }

  it("una fórmula peligrosa deja de ser fórmula", () => {
    const salida = celda('=HYPERLINK("http://x.pe","clic")');
    // Con el helper anterior esta celda SÍ se entrecomillaba —lleva comas— y
    // aun así Excel la ejecutaba. Ese es el falso verde que cuida esta prueba.
    expect(salida.startsWith('"=""=HYPERLINK')).toBe(true);
  });
});

describe("lo que NO se toca, y es deliberado", () => {
  it("un descuento negativo sigue siendo número y se puede sumar", () => {
    // Si esto se rompe, las columnas de descuentos de planilla, provisiones y
    // costos dejan de sumarse en Excel. Es el caso que separa el arreglo bueno
    // del apresurado.
    expect(celda("-150.00")).toBe("-150.00");
  });

  it("un monto normal se queda como está", () => {
    expect(celda("1129.55")).toBe("1129.55");
  });

  it("un DNI de ocho dígitos sin cero adelante no necesita blindaje", () => {
    // Excel lo muestra entero. Blindarlo sería ruido en el archivo.
    expect(celda("10817189")).toBe("10817189");
  });

  it("un año se queda como número", () => {
    expect(celda(2026)).toBe("2026");
  });

  it("un conteo pequeño se queda como número", () => {
    expect(celda(3)).toBe("3");
  });

  it("un nombre corriente no se toca", () => {
    expect(celda("Ana Perez")).toBe("Ana Perez");
  });

  it("una celda vacía sigue vacía", () => {
    expect(celda("")).toBe("");
    expect(celda(null)).toBe("");
    expect(celda(undefined)).toBe("");
  });
});

describe("el escapado de siempre, que no se puede haber perdido", () => {
  it("una dirección con coma va entrecomillada", () => {
    expect(celda("Av. Larco 123, Miraflores")).toBe('"Av. Larco 123, Miraflores"');
  });

  it("una comilla dentro se duplica", () => {
    expect(celda('Jr. "El Sol" 45')).toBe('"Jr. ""El Sol"" 45"');
  });

  it("un salto de línea va entrecomillado", () => {
    expect(celda("Ana\nPerez")).toBe('"Ana\nPerez"');
  });

  it("un retorno de carro también — antes partía la fila", () => {
    // Este es el que faltaba: una dirección pegada desde Windows llevaba \r,
    // el regex no lo miraba y la fila se cortaba por la mitad.
    expect(celda("Av. Sol\rMz. B")).toBe('"Av. Sol\rMz. B"');
  });
});

describe("la forma del archivo entero", () => {
  it("el encabezado sale primero y las filas debajo", () => {
    const csv = generarCsv(
      [
        { DNI: "08817189", Nombre: "Ana", Monto: "-150.00" },
        { DNI: "10817189", Nombre: "Luis", Monto: "1129.55" },
      ],
      ["DNI", "Nombre", "Monto"],
    );
    expect(csv.split("\n")).toEqual([
      "DNI,Nombre,Monto",
      '"=""08817189""",Ana,-150.00',
      "10817189,Luis,1129.55",
    ]);
  });

  it("una columna que no existe en la fila sale vacía, no como undefined", () => {
    const csv = generarCsv([{ a: "1" }], ["a", "b"]);
    expect(csv.split("\n")[1]).toBe("1,");
  });

  it("sin filas devuelve solo el encabezado", () => {
    expect(generarCsv([], ["a", "b"])).toBe("a,b");
  });
});
