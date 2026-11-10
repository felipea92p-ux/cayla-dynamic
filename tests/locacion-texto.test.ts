import { describe, expect, it } from "vitest";
import {
  construirLocacion,
  etiquetaLocador,
  TEXTO_LOCACION_APROBADO,
  type DatosLocacion,
} from "../apps/web/lib/admin/locacion-texto";
import { MARCADOR_FIRMA_EMPRESA, MARCADOR_FIRMA_PERSONA } from "../apps/web/lib/admin/contrato-texto";

// El contrato de locación de servicios (0612). Lo que se protege: que sea un contrato CIVIL —sin el vocabulario del
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
  it("sin RUC ni ciudad, el contrato lo dice en vez de inventarlo", () => {
    const t = sinEtiquetas(texto({ ruc: null, ciudad: null }));
    expect(t).toContain("[FALTA EL RUC, NECESARIO PARA EMITIR EL RECIBO POR HONORARIOS]");
    expect(t).toContain("[FALTA LA CIUDAD DE LA SEDE]");
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
