// ============================================================================
// contrato-texto.test.ts — el monto en letras del contrato, y la numeración
// ============================================================================
// EL MONTO EN LETRAS NO ES DECORACIÓN. En un contrato de trabajo, si la cifra
// en números y la cifra en letras discrepan, manda la de letras. Y estaba mal
// justo en el rango donde caen los sueldos de CAYLA: S/ 1,125.00 salía como
// «Mil ciento veinte y cinco» en vez de «Mil ciento veinticinco».
//
// El 21 al 29 se escriben en UNA palabra. Es la clase de error que nadie ve al
// revisar un PDF por encima —se lee casi bien— y que queda firmado.
//
// La segunda mitad fija la numeración del Anexo I: se numera para poder
// citarlo («la función 14 del Anexo I») el día que haya que sustentar un
// incumplimiento, y las secciones no pueden reiniciar la cuenta.
// ============================================================================
import { describe, expect, it } from "vitest";
import { construirContrato, numeroALetras, type DatosContrato } from "../apps/web/lib/admin/contrato-texto";

describe("numeroALetras", () => {
  it("escribe el 21–29 en una sola palabra", () => {
    // El caso que motivó la prueba: un sueldo real.
    expect(numeroALetras(1125)).toBe("Mil ciento veinticinco y 00/100");
    expect(numeroALetras(1122)).toBe("Mil ciento veintidós y 00/100");
    expect(numeroALetras(1129)).toBe("Mil ciento veintinueve y 00/100");
    expect(numeroALetras(21)).toBe("Veintiuno y 00/100");
  });

  it("apocopa el uno delante de «mil»", () => {
    expect(numeroALetras(21000)).toBe("Veintiún mil y 00/100");
    expect(numeroALetras(31500)).toBe("Treinta y un mil quinientos y 00/100");
    // Pero NO cuando el uno es la última palabra del número.
    expect(numeroALetras(1001)).toBe("Mil uno y 00/100");
  });

  it("mantiene lo que ya funcionaba", () => {
    expect(numeroALetras(1130)).toBe("Mil ciento treinta y 00/100");
    expect(numeroALetras(1360)).toBe("Mil trescientos sesenta y 00/100");
    expect(numeroALetras(100)).toBe("Cien y 00/100");
    expect(numeroALetras(1000)).toBe("Mil y 00/100");
    expect(numeroALetras(1450.5)).toBe("Mil cuatrocientos cincuenta y 50/100");
  });
});

/** Los datos mínimos de un contrato, para que cada prueba cambie solo lo suyo. */
function datos(cambios: Partial<DatosContrato> = {}): DatosContrato {
  return {
    tipo: "nuevo",
    nombreDni: "Nombre Apellido",
    documento: "12345678",
    direccion: null,
    cargo: "Asesora",
    email: null,
    sedeNombre: "Trujillo",
    sedeCodigo: "TRU",
    ciudad: "Trujillo",
    causaObjetivaTexto: "causa",
    funcionesTexto: "una función",
    fechaInicio: "2026-08-01",
    fechaFin: "2026-12-31",
    fechaIngresoOriginal: "2025-08-01",
    remuneracionMensual: 1130,
    cobraMovilidad: true,
    movilidadDiaria: 10,
    bonoOnomastico: 180,
    ritVersion: "1",
    ritFecha: "11 de agosto de 2026",
    activosPrincipales: "Caja registradora.",
    activosLibre: "",
    adendumTexto: "",
    firmanteNombre: "Firmante Apellido",
    firmanteDni: "87654321",
    firmanteCargo: "Gerencia General",
    ...cambios,
  };
}

describe("construirContrato", () => {
  it("numera las funciones y no reinicia la cuenta en cada sección", () => {
    const html = construirContrato(
      datos({ funcionesTexto: "PRIMERA PARTE:\nfunción A\nfunción B\nSEGUNDA PARTE:\nfunción C" }),
    );
    // La segunda sección arranca en 3, no vuelve a 1: si reiniciara, habría dos
    // «función 1» y citar una sería ambiguo.
    expect(html).toContain('<ol start="1">');
    expect(html).toContain('<ol start="3">');
  });

  it("firma el contrato Y cada uno de los cuatro anexos", () => {
    const html = construirContrato(datos());
    // Un anexo que se separa de su contrato sin firma no es atribuible a nadie.
    expect(html.match(/class="firmas"/g)).toHaveLength(5);
    expect(html.match(/<section class="anexo">/g)).toHaveLength(4);
  });

  it("deja el hueco de la firma como marcador, nunca como imagen", () => {
    const html = construirContrato(datos());
    // La 0272 congela el borrador SIN firmar: una imagen dentro del texto
    // congelado haría que un borrador pareciera un documento ya firmado.
    expect(html).toContain("<!--FIRMA_EMPRESA-->");
    expect(html).not.toContain("<img");
  });

  it("dice que falta la ciudad en vez de inventarla", () => {
    const html = construirContrato(datos({ ciudad: null }));
    expect(html).toContain("FALTA LA CIUDAD");
    expect(html).not.toContain("En la ciudad de ,");
  });

  it("incorpora el Anexo IV al contrato desde una cláusula", () => {
    // Sin esta incorporación, el anexo que sostiene el reclamo de devolución de
    // los equipos no forma parte de lo pactado.
    // Se compara con los espacios colapsados: el HTML parte la frase en dos
    // líneas y el texto impreso no.
    const texto = construirContrato(datos()).replace(/\s+/g, " ");
    expect(texto).toContain(
      "se detallan en el ANEXO IV — Constancia de Recepción y Responsabilidad de Activos, el cual forma parte integrante del presente contrato",
    );
  });

  it("el adendum no repite el contrato ni sus anexos", () => {
    const html = construirContrato(datos({ tipo: "adendum", adendumTexto: "Se modifica la Cláusula Sexta." }));
    expect(html).toContain("ADENDUM AL CONTRATO DE TRABAJO");
    expect(html).toContain("Se modifica la Cláusula Sexta.");
    // Dos documentos que dicen ser el mismo vínculo con plazos distintos se
    // contradicen: el adendum no lleva ni período de prueba ni anexos.
    expect(html).not.toContain("PERÍODO DE PRUEBA");
    expect(html).not.toContain("ANEXO I");
  });

  it("escapa el texto que viene de datos de la persona", () => {
    const html = construirContrato(datos({ cargo: 'Asesora <script>alert("x")</script>' }));
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });
});
