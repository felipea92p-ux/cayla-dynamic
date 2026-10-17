// ============================================================================
// leer-poliza.test.ts — entender el texto de una póliza (0528)
// ============================================================================
// El texto de abajo IMITA la forma de una póliza real de Pacífico —cómo escribe cada dato, con los
// espacios de más que deja pdf.js— pero con datos inventados: ni nombres ni documentos ni números de
// nadie (CLAUDE.md: los datos personales no van a git). Lo que se cuida:
//   · que el DÍA FINAL sea el que dice «AL 01/02/2027 … A LAS 12 M» (el día en que deja de cubrir) y no el
//     «31/01/2027» del aviso de cobranza, que es el último día cubierto: el sistema cuenta el final
//     EXCLUSIVO y tomar el otro dejaría a la persona «sin cubrir» un día;
//   · que lo que no está sea `null` y diga que falta, nunca un valor inventado;
//   · que lo que el papel dice dos veces y distinto genere un AVISO, no se resuelva a escondidas;
//   · que una persona solo se proponga cuando es UNA y es clara: equivocarse de persona es registrarle a
//     otra su seguro.
// ============================================================================
import { describe, it, expect } from "vitest";
import { emparejarPersona, fechaDeTexto, leerPolizas, montoDeTexto, palabrasDeUnNombre } from "@/lib/admin/leer-poliza";

// ── Las páginas, como las saca pdf.js (cada trozo de texto separado por espacios) ──

const PORTADA = (n: string, vigencia = "01/11/2026 - 01/02/2027") => `Señor(a).-
Cayla Sac
Mz Q Lte 26 Urb San Andres V Etapa
Póliza N°: ${n}
Fecha de vigencia: ${vigencia}
Agente: Corredora De Prueba Sac
Estimado(a)
Queremos agradecerle la confianza depositada en Pacifico como su compañía aseguradora y así darnos
la oportunidad de construir una relación de largo plazo con usted.`;

const AVISO = (n: string, asegurado: string, doc: string) => `RUC Nro. 20000000001   AVISO DE COBRANZA N° 90000001
Póliza   : ${n}   SEGURO DE SALUD
PRACTICANTES
Vigencia   :   01/11/2026 - 31/01/2027
Cliente   :   CAYLA SAC   600000001
Asegurado   :   ${asegurado}   ${doc}
Agente   :   CORREDORA DE PRUEBA SAC
Conceptos   Importe
PRIMA COMERCIAL   152.52
INTERESES   0.00
I.G.V.   27.45
S/.   179.97
FORMA DE PAGO
< X - Contado Sin Cupon >
G0000001   Emitido el 14 de Octubre del 2026`;

const CONVENIO = (n: string, cuotas = "1/01   30/11/2026   900000009   179.97", total = "179.97") => `Fecha   :14/10/2026
CONVENIO DE PAGO DE PRIMAS
PACÍFICO COMPAÑÍA DE SEGUROS Y REASEGUROS , con R.U.C. N° 20000000001
una póliza de seguro de Seguro De Salud Practicantes N° ${n}, con vigencia del 01/11/2026 al 31/01/2027 para cubrirse
Forma de pago: Al contado   Emisión : 14/10/2026
Plan de Pago   : X - Contado Sin Cupon   Moneda : Soles(S/)
Cronograma de Pago   Seguro De Salud Practicantes - Póliza N°${n}
Orden   Fec. Vcto.   Cod. Cuota   Monto a Pagar
${cuotas}
Monto total a pagar :   ${total}
Tasa de costo efectivo anual :   0.00 %`;

const CONDICIONES = (n: string, asegurado: string, doc: string, vigencia = "01/11/2026   AL   01/02/2027   92 DIAS   A LAS 12 M", total = "179.97") => `CONDICIONES PARTICULARES DE LA POLIZA
SEGURO DE ASISTENCIA MEDICA
SEGURO DE SALUD PRACTICANTES   Póliza No. ${n}
FECHA DE INGRESO   : 01/11/2026
VIGENCIA   : ${vigencia}
CONTRATANTE   : CAYLA SAC   600000001
ASEGURADO   : ${asegurado}   ${doc}
MONEDA   : SOLES
PRIMA COMERCIAL   152.52
INTERESES   0.00
I.G.V.   27.45
PRIMA COMERCIAL + INT. + I.G.V.   ${total}   SOLES
Emitida en Lima, a los 14 días del mes de Octubre del 2026
Pág. 1 de 1`;

const RELLENO = `Condiciones generales. El asegurado podrá solicitar la cobertura al crédito o por reembolso en cualquier clínica de la red.
La vigencia de la cobertura se rige por lo pactado. Póliza adecuada a la ley 29946 y sus normas reglamentarias.`;

const ANA = ["99000001", "PEREZ GOMEZ ANA MARIA", "900000001"] as const;

/** Un PDF de una póliza: portada, relleno, aviso, convenio, condiciones. */
const pdfDe = (n: string, asegurado: string, doc: string) => [
  PORTADA(n), RELLENO, AVISO(n, asegurado, doc), CONVENIO(n), RELLENO, CONDICIONES(n, asegurado, doc),
];

describe("leer una póliza de Pacífico", () => {
  it("saca número, vigencia, prima con IGV, vencimiento del pago, aseguradora, producto, asegurado y emisión", () => {
    const [p, ...resto] = leerPolizas(pdfDe(...ANA));
    expect(resto).toEqual([]);
    expect(p).toEqual({
      numero: "99000001",
      desde: "2026-11-01",
      hasta: "2027-02-01",
      prima: 179.97,
      primaVenceEl: "2026-11-30",
      aseguradora: "Pacífico Seguros",
      producto: "Seguro de salud practicantes",
      asegurado: { nombre: "PEREZ GOMEZ ANA MARIA", documento: "900000001" },
      emitidaEl: "2026-10-14",
      avisos: [],
    });
  });

  it("el día final es el EXCLUSIVO («AL 01/02/2027 … A LAS 12 M»), no el último día cubierto del aviso (31/01/2027)", () => {
    const [p] = leerPolizas(pdfDe(...ANA));
    expect(p.hasta).toBe("2027-02-01");
    expect(p.hasta).not.toBe("2027-01-31");
  });

  it("sin la portada ni las condiciones, el aviso y el convenio —que dan el último día cubierto— NO se usan: la vigencia queda sin leer", () => {
    const [p] = leerPolizas([AVISO(ANA[0], ANA[1], ANA[2]), CONVENIO(ANA[0])]);
    // Sin ninguna fecha leída no es una póliza que se pueda proponer.
    expect(p).toBeUndefined();
  });

  it("si faltan las condiciones, la portada da la vigencia", () => {
    const [p] = leerPolizas([PORTADA("99000001"), AVISO(ANA[0], ANA[1], ANA[2]), CONVENIO("99000001")]);
    expect(p.desde).toBe("2026-11-01");
    expect(p.hasta).toBe("2027-02-01");
    expect(p.avisos).toEqual([]);
  });

  it("y si faltan las dos, sirve la forma en palabras del resumen informativo", () => {
    const resumen = "Vigencia del seguro: desde el 01 de Noviembre del 2026 hasta el 01 de Febrero del 2027\nPóliza N° 99000001";
    const [p] = leerPolizas([resumen, AVISO(ANA[0], ANA[1], ANA[2])]);
    expect(p.desde).toBe("2026-11-01");
    expect(p.hasta).toBe("2027-02-01");
  });

  it("un papel que dice dos vigencias distintas lo AVISA en vez de elegir a escondidas", () => {
    const [p] = leerPolizas([PORTADA("99000001", "01/11/2026 - 01/03/2027"), CONDICIONES(...ANA)]);
    expect(p.hasta).toBe("2027-02-01");
    expect(p.avisos).toContain("El papel dice dos vigencias distintas: revisa las fechas.");
  });

  it("si dice «92 DIAS» y las fechas no dan 92, avisa", () => {
    const [p] = leerPolizas([CONDICIONES(...ANA, "01/11/2026   AL   01/03/2027   92 DIAS   A LAS 12 M")]);
    expect(p.avisos).toContain("El papel dice 92 días y las fechas que leí dan 120: revisa las fechas.");
  });

  it("una fecha que no existe (31/02) no se convierte en un día de marzo: queda sin leer", () => {
    const [p] = leerPolizas([PORTADA("99000001", "01/02/2027 - 31/02/2027")]);
    expect(p).toBeUndefined();
  });

  it("una vigencia que termina antes de empezar se lee, pero avisa", () => {
    const [p] = leerPolizas([CONDICIONES(...ANA, "01/03/2027   AL   01/02/2027")]);
    expect(p.avisos).toContain("La vigencia que leí termina antes de empezar: revisa las fechas.");
  });
});

describe("la prima", () => {
  it("sale con IGV, del renglón «PRIMA COMERCIAL + INT. + I.G.V.»", () => {
    expect(leerPolizas(pdfDe(...ANA))[0].prima).toBe(179.97);
  });

  it("sin las condiciones, sale del «Monto total a pagar» del convenio", () => {
    const [p] = leerPolizas([PORTADA("99000001"), CONVENIO("99000001")]);
    expect(p.prima).toBe(179.97);
  });

  it("si las condiciones y el convenio dicen montos distintos, avisa", () => {
    const [p] = leerPolizas([CONDICIONES(...ANA), CONVENIO("99000001", undefined, "190.00")]);
    expect(p.prima).toBe(179.97);
    expect(p.avisos).toContain("La prima dice 179.97 en las condiciones y 190.00 en el convenio de pago: revisa cuál es.");
  });

  it("si comercial + intereses + IGV no dan el total, avisa", () => {
    const [p] = leerPolizas([CONDICIONES(...ANA, undefined, "199.97")]);
    expect(p.avisos).toContain("La prima comercial más el IGV da 179.97 y el total que leí es 199.97: revisa el monto.");
  });

  it("un redondeo de dos céntimos no es un aviso", () => {
    const [p] = leerPolizas([CONDICIONES(...ANA, undefined, "179.98")]);
    expect(p.avisos).toEqual([]);
  });

  it("sin ninguna prima en el papel, queda null y lo dice", () => {
    const [p] = leerPolizas([PORTADA("99000001"), AVISO("99000001", ANA[1], ANA[2]).replace("S/.   179.97", "")]);
    expect(p.prima).toBeNull();
    expect(p.avisos).toContain("No encontré la prima total: escríbela tú.");
  });
});

describe("el vencimiento del pago", () => {
  it("con una sola cuota, es el de esa cuota", () => {
    expect(leerPolizas(pdfDe(...ANA))[0].primaVenceEl).toBe("2026-11-30");
  });

  it("con pago en cuotas se deja en blanco y se explica: el sistema guarda UNA fecha", () => {
    const cuotas = "1/03   30/11/2026   900000009   60.00\n2/03   30/12/2026   900000010   60.00\n3/03   30/01/2027   900000011   59.97";
    const [p] = leerPolizas([CONDICIONES(...ANA), CONVENIO("99000001", cuotas)]);
    expect(p.primaVenceEl).toBeNull();
    expect(p.avisos.some((a) => /3 cuotas/.test(a))).toBe(true);
  });
});

describe("el asegurado", () => {
  it("lo lee del aviso o de las condiciones con su documento", () => {
    expect(leerPolizas([CONDICIONES(...ANA)])[0].asegurado).toEqual({ nombre: "PEREZ GOMEZ ANA MARIA", documento: "900000001" });
    expect(leerPolizas([PORTADA("99000001"), AVISO(...ANA)])[0].asegurado).toEqual({ nombre: "PEREZ GOMEZ ANA MARIA", documento: "900000001" });
  });

  it("«el ASEGURADO» de un párrafo no es el asegurado: pide los dos puntos y un documento", () => {
    const texto = `${PORTADA("99000001")}\nEl CONTRATANTE y/o ASEGURADO contrató con LA COMPAÑÍA una póliza de seguro.`;
    const [p] = leerPolizas([texto]);
    expect(p.asegurado).toBeNull();
    expect(p.avisos).toContain("No encontré a quién asegura: elige a la persona tú.");
  });
});

describe("varias pólizas en un mismo PDF, o ninguna", () => {
  it("cada número es una póliza, con lo suyo y en el orden en que aparecen", () => {
    const juntas = [...pdfDe("99000001", "PEREZ GOMEZ ANA MARIA", "900000001"), ...pdfDe("99000002", "RAMOS DIAZ BETO LUIS", "900000002")];
    const lista = leerPolizas(juntas);
    expect(lista.map((p) => p.numero)).toEqual(["99000001", "99000002"]);
    expect(lista.map((p) => p.asegurado?.nombre)).toEqual(["PEREZ GOMEZ ANA MARIA", "RAMOS DIAZ BETO LUIS"]);
  });

  it("un número suelto entre las condiciones generales no es una póliza: sin ninguna fecha no se devuelve", () => {
    expect(leerPolizas([`${RELLENO}\nVer la póliza N° 12345678 de su corredor.`])).toEqual([]);
  });

  it("un PDF sin texto —una foto escaneada— no devuelve nada, ni lanza", () => {
    expect(leerPolizas([])).toEqual([]);
    expect(leerPolizas(["", "   ", "\n"])).toEqual([]);
  });
});

describe("fechas y montos sueltos", () => {
  it("fechaDeTexto: día/mes/año; lo imposible, null", () => {
    expect(fechaDeTexto("01/10/2026")).toBe("2026-10-01");
    expect(fechaDeTexto("1/2/2027")).toBe("2027-02-01");
    expect(fechaDeTexto("29/02/2028")).toBe("2028-02-29");
    expect(fechaDeTexto("29/02/2027")).toBeNull();
    expect(fechaDeTexto("31/04/2026")).toBeNull();
    expect(fechaDeTexto("2026-10-01")).toBeNull();
    expect(fechaDeTexto("")).toBeNull();
  });

  it("montoDeTexto: con punto o coma decimal, y miles", () => {
    expect(montoDeTexto("179.97")).toBe(179.97);
    expect(montoDeTexto("179,97")).toBe(179.97);
    expect(montoDeTexto("1,179.97")).toBe(1179.97);
    expect(montoDeTexto("1.179,97")).toBe(1179.97);
    expect(montoDeTexto("1,179")).toBe(1179);
    expect(montoDeTexto("1,121,316,750.00")).toBe(1121316750);
    expect(montoDeTexto("152.5")).toBe(152.5);
    expect(montoDeTexto("0.00")).toBe(0);
    expect(montoDeTexto("179")).toBe(179);
    expect(montoDeTexto("S/ 179.97")).toBeNull();
    expect(montoDeTexto("")).toBeNull();
  });
});

describe("a qué persona corresponde un nombre del papel", () => {
  const equipo = [
    { id: "a", nombre: "Ana María Pérez Gómez" },
    { id: "b", nombre: "Beto Luis Ramos Díaz" },
    { id: "c", nombre: "Carla Soto" },
    { id: "d", nombre: "Ana Pérez" },
  ];

  it("el papel escribe apellidos primero: el orden de las palabras no importa", () => {
    expect(emparejarPersona("PEREZ GOMEZ ANA MARIA", equipo.slice(0, 3))?.persona.id).toBe("a");
    expect(emparejarPersona("RAMOS DIAZ BETO LUIS", equipo)?.persona.id).toBe("b");
  });

  it("sin tildes ni mayúsculas, y sin «de la»", () => {
    expect(emparejarPersona("DE LA CRUZ SANTOS MARIA", [{ id: "x", nombre: "María De la Cruz Santos" }])?.persona.id).toBe("x");
    // La ñ cuenta como n, igual que en el buscador del sistema: «NUÑEZ» y «Nunez» son la misma persona.
    expect(palabrasDeUnNombre("DE LA CRUZ  Pérez-Ñañez")).toEqual(["cruz", "perez", "nanez"]);
    expect(emparejarPersona("NUÑEZ RIOS LUZ", [{ id: "y", nombre: "Luz Nunez Rios" }])?.persona.id).toBe("y");
  });

  it("le basta con faltar una palabra de cuatro (un segundo nombre que el papel no trae)", () => {
    const r = emparejarPersona("PEREZ GOMEZ ANA", [equipo[0], equipo[1]]);
    expect(r?.persona.id).toBe("a");
    expect(r!.puntaje).toBeGreaterThanOrEqual(0.8);
  });

  it("un nombre de dos palabras NO se toma por uno de cuatro que lo contiene: «Ana Pérez» no es «Ana María Pérez Gómez»", () => {
    expect(emparejarPersona("PEREZ ANA", [equipo[0]])).toBeNull();
  });

  it("si dos personas casi empatan, no se elige a ninguna", () => {
    const gemelas = [{ id: "a", nombre: "Ana Pérez Gómez" }, { id: "b", nombre: "Ana Pérez Gómez" }];
    expect(emparejarPersona("PEREZ GOMEZ ANA", gemelas)).toBeNull();
  });

  it("una persona parecida pero distinta no alcanza", () => {
    expect(emparejarPersona("ROJAS QUISPE ELENA", equipo)).toBeNull();
    expect(emparejarPersona("", equipo)).toBeNull();
    expect(emparejarPersona("PEREZ GOMEZ ANA MARIA", [])).toBeNull();
  });
});
