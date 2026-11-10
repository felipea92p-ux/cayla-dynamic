import { describe, expect, it } from "vitest";
import {
  construirLocacion,
  estamparFirmas,
  etiquetaLocador,
  MARCADOR_FECHA_FIRMA_EMPRESA,
  MARCADOR_FECHA_FIRMA_PERSONA,
  TEXTO_LOCACION_APROBADO,
  type DatosLocacion,
} from "../apps/web/lib/admin/locacion-texto";
import { MARCADOR_FIRMA_EMPRESA, MARCADOR_FIRMA_PERSONA } from "../apps/web/lib/admin/contrato-texto";

// El contrato de locación de servicios (0615). Lo que se protege: que sea un contrato CIVIL —sin el vocabulario del
// contrato de trabajo, que es lo que lo desnaturalizaría (art. 4 del D.S. 003-97-TR)—, que todo dato de la persona
// se escape antes de volverse HTML, y que un dato que falta se vea en vez de inventarse. Datos inventados.

const base: DatosLocacion = {
  nombreDni: "Lucía Paredes Ríos",
  documento: "70001234",
  ruc: "10700012345",
  direccion: "Calle Los Pinos 123, Arequipa",
  genero: "femenino",
  servicio: "Asesoría en visual merchandising",
  entregables: "Propuesta de exhibición para cada colección\nRevisión mensual de vitrinas\n\n",
  fechaInicio: "2026-11-10",
  fechaFin: "2027-05-09",
  honorarios: 1500,
  periodicidad: "mensual",
  ciudad: "Arequipa",
  diasAviso: 15,
  firmanteNombre: "Alma Reyes Soto",
  firmanteCargo: "Gerente General",
  firmanteDni: "40000001",
};

const texto = (d: Partial<DatosLocacion> = {}) => construirLocacion({ ...base, ...d });
const sinEtiquetas = (html: string) => html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ");

describe("es un contrato civil, no uno de trabajo", () => {
  it("no trae el vocabulario del contrato de trabajo", () => {
    const t = sinEtiquetas(texto()).toLowerCase();
    for (const palabra of [
      "remuneración", "sueldo", "salario", "jornada", "turno de trabajo", "horario de trabajo", "cargo", "puesto",
      "periodo de prueba", "período de prueba", "colaborador", "trabajador", "empleador", "la empresa",
      "gratificación", "vacaciones", "cts", "planilla", "subordinación", "jefe",
    ]) {
      // Palabra entera: «puesto» no debe cazar «Impuesto a la Renta».
      const entera = new RegExp(`(^|[^a-záéíóúüñ])${palabra}([^a-záéíóúüñ]|$)`);
      expect(entera.test(t), `no debería decir «${palabra}»`).toBe(false);
    }
  });
  it("dice qué es: locación de servicios del Código Civil, con autonomía y sin relación laboral", () => {
    const t = sinEtiquetas(texto());
    expect(t).toContain("CONTRATO DE LOCACIÓN DE SERVICIOS");
    expect(t).toContain("artículos 1764 a 1770 del Código Civil");
    expect(t).toContain("autonomía técnica y organizativa");
    expect(t).toContain("no genera relación laboral");
  });
  it("la autonomía obliga a CAYLA y no hay exclusividad (Sala Plena 014-2024-SUNAFIL/TFL)", () => {
    const t = sinEtiquetas(texto());
    expect(t).toContain("LA COMITENTE no le fija horario ni turnos ni le aplica sanciones o amonestaciones");
    expect(t).toContain("Respetar la autonomía de LA LOCADORA en los términos de la cláusula tercera");
    expect(t).toContain("puede prestar servicios a terceros sin necesidad de autorización de LA COMITENTE");
    expect(t).not.toMatch(/exclusividad|no competencia/i);
  });
});

describe("lo que la segunda revisión legal corrigió (2026-11-10)", () => {
  it("no se fecha al día de inicio: rige desde ahí y se celebra cuando firma la persona", () => {
    const t = sinEtiquetas(texto({ fechaInicio: "2026-08-01" }));
    expect(t).not.toMatch(/el 1 de agosto de 2026, se celebra/);
    expect(t).toContain("Conste por el presente documento el Contrato de Locación de Servicios");
    expect(t).toContain("El presente contrato rige del 1 de agosto de 2026");
    expect(t).toContain("se entiende celebrado en la fecha y la hora en que firma LA LOCADORA");
  });
  it("la resolución es recíproca, por prestaciones precisas (CC 1398 y 1430)", () => {
    const t = sinEtiquetas(texto());
    expect(t).toContain("cualquiera de las partes puede resolverlo de pleno derecho, conforme al artículo 1430");
    expect(t).toContain("LA COMITENTE, el pago de los honorarios dentro de los quince (15) días");
    expect(t).toContain("rige el artículo 1429");
    // La de antes era solo a favor de quien redactó el contrato.
    expect(t).not.toContain("LA COMITENTE puede resolverlo de inmediato");
  });
  it("la cesión de derechos dice qué, en exclusiva, dónde y por cuánto (D. Leg. 822, arts. 89 y 90)", () => {
    const t = sinEtiquetas(texto());
    expect(t).not.toContain("en la medida que lo permita la ley");
    for (const parte of [
      "cede a LA COMITENTE, en exclusiva y desde su creación",
      "meras fotografías del artículo 144",
      "para todo el mundo y por todo el plazo de protección",
      "registrar a su nombre los diseños industriales",
      "artículo 94",
      "a tanto alzado",
    ]) expect(t, `debería decir «${parte}»`).toContain(parte);
  });
  it("los honorarios son brutos y la suspensión de retenciones se acredita antes del pago", () => {
    const t = sinEtiquetas(texto());
    expect(t).toContain("Los honorarios pactados son montos brutos");
    expect(t).toContain("antes del pago, la suspensión de retenciones");
  });
  it("informa qué datos personales trata, para qué y cómo ejercer los derechos (Ley 29733, art. 18)", () => {
    const t = sinEtiquetas(texto());
    expect(t).toContain("UNDÉCIMA. DATOS PERSONALES DE LA LOCADORA");
    expect(t).toContain("acceso, actualización, inclusión, rectificación, supresión y oposición");
    expect(t).toContain("pueden estar ubicados fuera del Perú");
  });
  it("describe el acto de firma como lo hace Dynamic, y la fecha va bajo cada firma", () => {
    const html = texto();
    const t = sinEtiquetas(html);
    expect(t).toContain("con su cuenta personal e intransferible, con el texto completo del contrato a la vista");
    expect(html).toContain(MARCADOR_FECHA_FIRMA_EMPRESA);
    expect(html).toContain(MARCADOR_FECHA_FIRMA_PERSONA);
  });
});

describe("las firmas y sus fechas se estampan al mostrar", () => {
  it("con las dos firmas: las imágenes y cuándo firmó cada parte, en hora de Lima", () => {
    const html = estamparFirmas(texto(), {
      empresa: "data:image/png;base64,EMP",
      persona: "data:image/png;base64,PER",
      empresaAt: "2026-11-10T14:05:00Z",
      personaAt: "2026-11-11T04:30:00Z",
    });
    expect(html).toContain('<img src="data:image/png;base64,EMP"');
    expect(html).toContain('<img src="data:image/png;base64,PER"');
    expect(html).toContain("Firmado electrónicamente el 10 de noviembre de 2026, a las 09:05 (hora de Lima).");
    // 04:30 en UTC todavía es el día anterior en Lima: la fecha es la de Lima, no la del servidor.
    expect(html).toContain("Firmado electrónicamente el 10 de noviembre de 2026, a las 23:30 (hora de Lima).");
    expect(html).not.toContain("<!--");
  });
  it("sin firmar: la línea en blanco y «Pendiente de firma»", () => {
    const html = estamparFirmas(texto(), { empresa: null, persona: null, empresaAt: null, personaAt: null });
    expect(html).toContain("Pendiente de firma.");
    expect(html).not.toContain("<img");
  });
});

describe("lo que dice el contrato sale de los datos", () => {
  it("el servicio, los entregables (sin líneas vacías), el plazo y los honorarios en número y en letras", () => {
    const html = texto();
    const t = sinEtiquetas(html);
    expect(t).toContain("Asesoría en visual merchandising");
    expect((html.match(/<li>/g) ?? []).filter(Boolean).length).toBeGreaterThanOrEqual(2);
    expect(html).toContain("<li>Propuesta de exhibición para cada colección</li><li>Revisión mensual de vitrinas</li>");
    expect(t).toContain("del 10 de noviembre de 2026 al 9 de mayo de 2027");
    expect(t).toContain("S/ 1,500.00 (Mil quinientos y 00/100 soles) por cada mes de servicio");
  });
  it("en proporción a las horas se dice así, sin volverse un sueldo", () => {
    const t = sinEtiquetas(texto({ periodicidad: "por_horas" }));
    expect(t).toContain("por un mes completo de servicio, que se pagan en proporción a las horas de servicio efectivamente prestadas");
  });
  it("un pago único se dice como pago único", () => {
    expect(sinEtiquetas(texto({ periodicidad: "total" }))).toContain("por la totalidad del servicio");
  });
  it("las dos firmas van como marcas: se estampan al mostrar, nunca se guardan dentro", () => {
    const html = texto();
    expect(html).toContain(MARCADOR_FIRMA_EMPRESA);
    expect(html).toContain(MARCADOR_FIRMA_PERSONA);
  });
  it("el término definido sigue el género del DNI; sin dato, el femenino de siempre", () => {
    expect(etiquetaLocador({ genero: "masculino" })).toBe("EL LOCADOR");
    expect(etiquetaLocador({ genero: "femenino" })).toBe("LA LOCADORA");
    expect(etiquetaLocador({ genero: null })).toBe("LA LOCADORA");
  });
});

describe("lo que falta se ve, y lo que entra se escapa", () => {
  it("sin RUC, ciudad ni domicilio, el contrato lo dice en vez de inventarlo", () => {
    const t = sinEtiquetas(texto({ ruc: null, ciudad: null, direccion: null }));
    expect(t).toContain("[FALTA EL RUC, NECESARIO PARA EMITIR EL RECIBO POR HONORARIOS]");
    expect(t).toContain("[FALTA LA CIUDAD DE LA SEDE]");
    // Las comunicaciones van a los domicilios de la cláusula primera: uno que falta tiene que verse.
    expect(t).toContain("con domicilio en [FALTA EL DOMICILIO]");
  });
  it("sin DNI, también: un contrato sin DNI no identifica a nadie", () => {
    const t = sinEtiquetas(texto({ documento: "  " }));
    expect(t).toContain("D.N.I. N.° [FALTA EL DNI]");
  });
  it("sin entregables, también lo dice", () => {
    expect(sinEtiquetas(texto({ entregables: "  \n " }))).toContain("[FALTA DESCRIBIR QUÉ COMPRENDE EL SERVICIO]");
  });
  it("un nombre, un servicio o un entregable con HTML no rompe el documento", () => {
    const html = texto({ nombreDni: "Ana <b>X</b>", servicio: "Fotos & <script>alert(1)</script>", entregables: "<img src=x>" });
    expect(html).not.toContain("<script>");
    expect(html).not.toContain("<img src=x>");
    expect(html).toContain("Ana &lt;b&gt;X&lt;/b&gt;");
    expect(html).toContain("Fotos &amp; &lt;script&gt;");
  });
});

describe("mientras el abogado no lo apruebe, es un borrador y lo dice", () => {
  it("cada documento lleva el aviso de borrador arriba", () => {
    if (TEXTO_LOCACION_APROBADO) return;
    expect(sinEtiquetas(texto())).toContain("BORRADOR — pendiente de revisión legal. No firmar.");
  });
});
