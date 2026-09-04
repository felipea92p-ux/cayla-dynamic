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
import {
  construirContrato,
  finDelPeriodoDePrueba,
  numeroALetras,
  tipoQueCorresponde,
  type DatosContrato,
} from "../apps/web/lib/admin/contrato-texto";

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
    practicanteModalidad: null,
    planCapacitacionTexto: "",
    centroFormacionNombre: null,
    centroFormacionRuc: null,
    centroFormacionDomicilio: null,
    centroFormacionRepresentante: null,
    carreraEspecialidad: null,
    cicloAcademico: null,
    gradoTituloTexto: null,
    areaProyecto: "",
    objetivoFormativoGeneral: "",
    supervisorAsignado: "",
    hitoMes3: "",
    hitoMes6: "",
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

// ── El convenio de prácticas (0333) no es un contrato de trabajo ───────────
// La mitad de las cláusulas del contrato de planilla son directamente falsas
// para una practicante (0322: no es relación laboral, no tiene causa
// objetiva, no tiene período de prueba, no se le mide disciplina). Esta
// prueba cuida las dos mitades: que el convenio diga lo que le corresponde, y
// que NO herede por accidente el lenguaje del contrato de trabajo.
describe("documentoConvenio", () => {
  function datosConvenio(cambios: Partial<DatosContrato> = {}): DatosContrato {
    return datos({
      tipo: "convenio_practicas",
      practicanteModalidad: "preprofesional",
      planCapacitacionTexto: "Apoyo en el área de sistemas.",
      ...cambios,
    });
  }

  it("dice modalidad formativa y subvención, nunca contrato de trabajo ni remuneración", () => {
    const html = datosConvenio();
    const texto = construirContrato(html);
    expect(texto).toContain("CONVENIO DE MODALIDAD FORMATIVA");
    expect(texto).toContain("Ley N.° 28518");
    expect(texto).toContain("LA PRACTICANTE");
    expect(texto).toContain("subvención económica");
    expect(texto).not.toContain("CONTRATO DE TRABAJO");
    expect(texto).not.toContain("LA COLABORADORA");
    expect(texto).not.toContain("D.Leg. 728");
  });

  it("no lleva causa objetiva, período de prueba ni régimen disciplinario del contrato de planilla", () => {
    const texto = construirContrato(datosConvenio());
    expect(texto).not.toContain("CAUSA OBJETIVA");
    expect(texto).not.toContain("PERÍODO DE PRUEBA");
    expect(texto).not.toContain("RÉGIMEN DISCIPLINARIO");
    expect(texto).not.toContain("FALTAS GRAVES");
    // La causa objetiva de relleno del formulario (fixture `datos()`, texto
    // literal "causa") no debe colarse ni por accidente: el convenio no lee
    // `causaObjetivaTexto` en absoluto.
    expect(texto).not.toContain(">causa<");
  });

  it("la jornada depende de la modalidad, nunca 48h fijas como en un contrato", () => {
    const preprofesional = construirContrato(datosConvenio({ practicanteModalidad: "preprofesional" }));
    const profesional = construirContrato(datosConvenio({ practicanteModalidad: "profesional" }));
    expect(preprofesional).toContain("treinta (30) horas semanales");
    expect(profesional).toContain("cuarenta y ocho (48) horas semanales");
  });

  it("sin modalidad asignada, avisa en el propio documento en vez de inventar una jornada", () => {
    const texto = construirContrato(datosConvenio({ practicanteModalidad: null }));
    expect(texto).toContain("FALTA ASIGNAR LA MODALIDAD");
  });

  it("firma como LA PRACTICANTE en el cuerpo y en cada anexo — nunca LA COLABORADORA", () => {
    const texto = construirContrato(datosConvenio());
    expect(texto.match(/LA PRACTICANTE/g)!.length).toBeGreaterThan(3);
    expect(texto).not.toContain("LA COLABORADORA");
  });

  it("el Anexo I es el plan específico de aprendizaje, no las funciones del cargo", () => {
    const texto = construirContrato(datosConvenio({ planCapacitacionTexto: "Apoyo específico en X." }));
    expect(texto).toContain("ANEXO I — PLAN ESPECÍFICO DE APRENDIZAJE");
    expect(texto).toContain("Apoyo específico en X.");
    expect(texto).not.toContain("ANEXO I — FUNCIONES DEL CARGO");
  });

  // El objetivo formativo general se escribe en un cuadro de varias líneas
  // (era un renglón y un párrafo entero no se veía). Un Enter ahí tiene que
  // llegar al papel como salto de línea, no colapsar a un espacio dentro
  // del <p>; y vacío sigue diciendo «[completar]», como antes.
  it("el objetivo formativo general conserva sus saltos de línea en el Anexo I", () => {
    const texto = construirContrato(
      datosConvenio({
        objetivoFormativoGeneral: "Al finalizar, desarrolla módulos completos del ERP.\n  Y documenta cada uno.  \n\n",
      }),
    );
    expect(texto).toContain(
      "<strong>Objetivo formativo general:</strong> Al finalizar, desarrolla módulos completos del ERP.<br/>Y documenta cada uno.</p>",
    );
    const vacio = construirContrato(datosConvenio({ objetivoFormativoGeneral: "  \n " }));
    expect(vacio).toContain("<strong>Objetivo formativo general:</strong> [completar]</p>");
  });

  // ── 0348: preprofesional es TRIPARTITO, profesional es BIPARTITO ──────────
  // El modelo de referencia de DO (`CAYLA_CORP_CONT_202609_ConvenioPracticas.
  // docx`) trae la diferencia de fondo que la versión anterior no modelaba:
  // el centro de formación FIRMA en el preprofesional (art. 12 y ss., Ley
  // 28518) y solo REFERENCIA al egresado en el profesional, sin firmar.
  it("el preprofesional es tripartito: firma también el centro de formación", () => {
    const texto = construirContrato(
      datosConvenio({
        practicanteModalidad: "preprofesional",
        centroFormacionNombre: "Universidad de Ejemplo",
        centroFormacionRuc: "20999999999",
      }),
    );
    expect(texto).toContain("EL CENTRO DE FORMACIÓN PROFESIONAL");
    expect(texto).toContain("Universidad de Ejemplo");
    expect(texto).toContain("se suscribe por triplicado");
    expect(texto.match(/class="firmas"/g)!.length).toBeGreaterThanOrEqual(1);
  });

  it("el profesional es bipartito: no lleva al centro de formación como firmante", () => {
    const texto = construirContrato(datosConvenio({ practicanteModalidad: "profesional" }));
    expect(texto).not.toContain("EL CENTRO DE FORMACIÓN PROFESIONAL");
    expect(texto).toContain("se suscribe por duplicado");
  });

  it("las cláusulas se numeran corridas y sin huecos en los dos casos", () => {
    // El preprofesional suma una cláusula (OBLIGACIONES DEL CENTRO DE
    // FORMACIÓN) que el profesional no lleva — por eso termina una posición
    // más adelante en el arreglo de ordinales.
    const preprofesional = construirContrato(datosConvenio({ practicanteModalidad: "preprofesional" }));
    const profesional = construirContrato(datosConvenio({ practicanteModalidad: "profesional" }));
    expect(preprofesional).toContain("NOVENA. OBLIGACIONES DEL CENTRO DE FORMACIÓN PROFESIONAL");
    expect(preprofesional).toContain("DÉCIMA OCTAVA. EXTINCIÓN");
    expect(profesional).not.toContain("OBLIGACIONES DEL CENTRO DE FORMACIÓN");
    expect(profesional).toContain("DÉCIMA SÉTIMA. EXTINCIÓN");
  });
});

// ── «Nuevo» o «renovación»: lo decide el vínculo, no este sistema ──────────
// El 2026-08-24 Felipe avisó de algo que la pantalla afirmaba y era falso:
// «todo mi personal tiene contrato, solo que aún no se ha escaneado». El
// tablero decía «sin contrato» de veinte personas porque el generador no tenía
// una fila suya —se estrenó en agosto de 2026—, y de esa misma confusión salía
// el tipo del contrato a generar.
//
// El daño no era la palabra: un contrato «nuevo» imprime un período de prueba
// de tres meses en el que cualquiera de las partes puede resolverlo sin causa y
// sin indemnización. Las veinte renovaciones de fin de año habrían salido
// quitándole por escrito, a gente con años de servicio, la estabilidad que el
// artículo 79 del TUO del D. Leg. 728 ya le reconoce.
describe("tipoQueCorresponde", () => {
  it("quien ya ingresó recibe una RENOVACIÓN, aunque no tenga contrato en el sistema", () => {
    expect(tipoQueCorresponde("2024-03-01", "2026-08-24")).toBe("renovacion");
  });

  it("solo es NUEVO cuando el vínculo todavía no empezó", () => {
    expect(tipoQueCorresponde("2026-09-01", "2026-08-24")).toBe("nuevo");
  });

  it("quien ingresa hoy mismo ya tiene vínculo: renovación no, pero nuevo sí", () => {
    expect(tipoQueCorresponde("2026-08-24", "2026-08-24")).toBe("renovacion");
  });

  it("sin fecha de ingreso elige la opción que NO le quita un derecho a nadie", () => {
    expect(tipoQueCorresponde(null, "2026-08-24")).toBe("renovacion");
    expect(tipoQueCorresponde(undefined, "2026-08-24")).toBe("renovacion");
  });

  it("y un contrato de renovación NO abre un período de prueba nuevo", () => {
    const conPrueba = construirContrato(datos({ tipo: "nuevo" }));
    const sinPrueba = construirContrato(datos({ tipo: "renovacion" }));
    expect(conPrueba).toContain("sin expresión de causa");
    expect(sinPrueba).not.toContain("sin expresión de causa");
    expect(sinPrueba).toContain("No aplica un nuevo período de prueba");
  });
});

// ── El período de prueba se afirma solo cuando de verdad corrió ────────────
// La auditoría del 2026-08-24 (229 agentes) encontró que `tipoQueCorresponde`
// devuelve «renovacion» para CUALQUIER fecha de ingreso pasada — también la de
// quien entró hace tres semanas —, y la rama de renovación afirmaba como hecho
// que «ya superó el período de prueba». Eso es una declaración falsa en un
// documento firmado, y regala la estabilidad del art. 79 antes de que la ley la
// reconozca. El art. 10 de la LPCL cuenta tres meses desde el INICIO DEL
// VÍNCULO: renovar no lo reinicia, pero tampoco lo completa.
describe("período de prueba", () => {
  it("a quien lleva años, el contrato le reconoce que ya lo superó", () => {
    const html = construirContrato(
      datos({ tipo: "renovacion", fechaIngresoOriginal: "2022-03-01", fechaInicio: "2027-01-01" }),
    );
    expect(html).toContain("ya superó el período");
    expect(html).not.toContain("sin expresión de causa");
  });

  it("a un ingreso reciente NO le declara superado lo que no ha corrido", () => {
    const html = construirContrato(
      datos({ tipo: "renovacion", fechaIngresoOriginal: "2026-08-01", fechaInicio: "2026-09-01" }),
    );
    expect(html).not.toContain("ya superó el período");
    expect(html).toContain("NO se reinicia con la celebración del presente contrato");
    // Y dice CUÁNDO termina, que es el dato que hace verificable la cláusula.
    expect(html).toContain("1 de noviembre de 2026");
    // Sigue sin abrirle un período nuevo de tres meses sin causa.
    expect(html).not.toContain("sin expresión de causa");
  });

  it("justo el día en que se cumplen los tres meses, ya está superado", () => {
    const html = construirContrato(
      datos({ tipo: "renovacion", fechaIngresoOriginal: "2026-06-01", fechaInicio: "2026-09-01" }),
    );
    expect(html).toContain("ya superó el período");
  });

  it("un contrato nuevo sí abre período de prueba", () => {
    const html = construirContrato(datos({ tipo: "nuevo" }));
    expect(html).toContain("sin expresión de causa");
  });
});

describe("finDelPeriodoDePrueba", () => {
  it("suma tres meses de calendario, no noventa días", () => {
    expect(finDelPeriodoDePrueba("2026-01-15")).toBe("2026-04-15");
    expect(finDelPeriodoDePrueba("2026-08-01")).toBe("2026-11-01");
  });

  it("un día que no existe en el mes destino cae al último de ese mes", () => {
    // 31 de agosto + 3 meses = 30 de noviembre, no 1 de diciembre.
    expect(finDelPeriodoDePrueba("2026-08-31")).toBe("2026-11-30");
  });

  it("cruza el año sin perderse", () => {
    expect(finDelPeriodoDePrueba("2026-11-20")).toBe("2027-02-20");
  });
});
