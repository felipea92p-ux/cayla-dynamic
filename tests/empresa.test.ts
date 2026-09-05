// ============================================================================
// empresa.test.ts — El RUC se dice una sola vez, y cada papel a su manera
// ============================================================================
// El 2026-08-19 el RUC y la razón social de CAYLA estaban escritos a mano en
// OCHO documentos: tres hojas de constancias, el memo disciplinario, la
// documentación de conceptos no remunerativos, el generador de contratos y la
// política salarial. Ninguno sabía de los otros. Se unificaron en
// `packages/shared/src/empresa.ts` y esta prueba cuida las DOS mitades del
// arreglo, que son distintas y las dos se pueden perder:
//
//   1. QUE NO VUELVA A HABER UNA NOVENA COPIA. Es la misma historia de
//      `permisos.ts` y de `fecha-lima.ts`: la regla estaba escrita y se volvió
//      a romper, porque un documento es memoria y acá trabajan varias sesiones
//      a la vez. Escribir el número otra vez tiene que fallar en rojo.
//
//   2. QUE CADA DOCUMENTO CONSERVE SU FORMA. Y esta es la que menos se ve
//      venir: los ocho no escriben el RUC igual —«· RUC», «· RUC N.°»,
//      «R.U.C. N.°», «con RUC»— y unificar el DATO invita a unificar de paso
//      la FORMA. No se puede. La política salarial se congela con acuse de
//      recibo firmado (0141) y el contrato se congela en
//      `contratos_generados.documento_html`: cambiarles una palabra es cambiar
//      lo que esas personas firmaron. Se migró el valor; el formato es de cada
//      papel y aquí queda anclado.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { join, relative } from "node:path";
import { EMPRESA, empresaConRuc } from "@cayla-dynamic/shared";
import { construirContrato, type DatosContrato } from "@/lib/admin/contrato-texto";
import { construirDocumento, documentoATexto, type Cuadro } from "@/lib/politica-salarial";

const RAIZ = join(import.meta.dirname, "..");
/** El único archivo con derecho a escribir la identidad de la empresa. */
const LA_FUENTE = join("packages", "shared", "src", "empresa.ts");

function fuentes(dir: string, acc: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name === ".next" || e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) fuentes(p, acc);
    else if (/\.tsx?$/.test(e.name)) acc.push(p);
  }
  return acc;
}

describe("la identidad de la empresa se escribe en un solo sitio", () => {
  const archivos = [join(RAIZ, "apps"), join(RAIZ, "packages")]
    .flatMap((d) => fuentes(d))
    .map((p) => relative(RAIZ, p))
    .filter((p) => p !== LA_FUENTE);

  it("el RUC no aparece literal en ningún otro archivo", () => {
    const culpables = archivos.filter((p) => readFileSync(join(RAIZ, p), "utf8").includes(EMPRESA.ruc));
    expect(culpables).toEqual([]);
  });

  it("la razón social tampoco", () => {
    const culpables = archivos.filter((p) => readFileSync(join(RAIZ, p), "utf8").includes(EMPRESA.nombre));
    expect(culpables).toEqual([]);
  });

  it("`empresaConRuc` es para documentos nuevos, no para los que ya tienen forma", () => {
    // Vive aparte a propósito: ningún papel de los ocho usa esta forma, y
    // aplicarla a uno de ellos le cambiaría el texto. Se ancla su formato para
    // que quien la use sepa exactamente qué va a imprimir.
    expect(empresaConRuc()).toBe("CAYLA S.A.C. — RUC 20605964550");
  });
});

// ── Cada documento, con su forma ────────────────────────────────────────────

const DATOS_CONTRATO: DatosContrato = {
  tipo: "nuevo",
  nombreDni: "Nombre De Prueba",
  documento: "00000000",
  direccion: null,
  cargo: "Asesora de tienda",
  email: null,
  genero: null,
  sedeNombre: "Trujillo",
  sedeCodigo: "TRU",
  ciudad: "Trujillo",
  causaObjetivaTexto: "Incremento de actividad.",
  funcionesTexto: "Atención a clientas.",
  fechaInicio: "2026-09-01",
  fechaFin: "2027-02-28",
  fechaIngresoOriginal: "2026-09-01",
  remuneracionMensual: 1130,
  cobraMovilidad: false,
  movilidadDiaria: null,
  bonoOnomastico: 50,
  ritVersion: "3",
  ritFecha: "10 de agosto de 2026",
  activosPrincipales: "Caja registradora.",
  activosLibre: "",
  adendumTexto: "",
  firmanteNombre: "Quien Firma",
  firmanteDni: "11111111",
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
};

describe("el contrato de trabajo", () => {
  const html = construirContrato(DATOS_CONTRATO);
  /** El contrato se lee impreso, y HTML colapsa los espacios: se compara igual. */
  const texto = html.replace(/\s+/g, " ");

  it("la cabecera escribe «RUC N.°» y a continuación la sede", () => {
    expect(texto).toContain(`RUC N.° ${EMPRESA.ruc} · Sede Trujillo`);
  });

  it("la cláusula I escribe «R.U.C. N.°», con puntos — es la otra forma", () => {
    expect(texto).toContain(`${EMPRESA.nombre}, identificada con R.U.C. N.° ${EMPRESA.ruc},`);
  });

  it("declara el domicilio legal completo, con la etapa de la urbanización", () => {
    // Sin «V Etapa» la dirección está incompleta, y este es el único documento
    // del sistema que la declara. Ver el comentario en `empresa.ts`.
    expect(texto).toContain(`con domicilio legal en ${EMPRESA.domicilio},`);
    expect(EMPRESA.domicilio).toContain("V Etapa");
  });

  it("el bloque de firmas cierra con la razón social", () => {
    expect(texto).toContain(`DNI N.° 11111111<br/>${EMPRESA.nombre}</p>`);
  });
});

describe("la política salarial", () => {
  const cuadro: Cuadro = {
    categorias: [
      {
        rango: "colibri", orden: 1, proposito: null, funciones: null, requisitos: null,
        criterio: null, personas: 1, salario_declarado: 1130, salario_min: 1130,
        salario_max: 1130, tope_educacion: null, factores: [],
      },
    ],
    movilidad: [],
    brecha: null,
  };
  const doc = construirDocumento(cuadro, "2026-08-19");

  it("su pie escribe «— RUC», que es la forma de este documento", () => {
    expect(documentoATexto(doc)).toContain(`${EMPRESA.nombre} — RUC ${EMPRESA.ruc}`);
  });

  it("guarda una FOTO de la empresa, no una referencia", () => {
    // La 0141 congela el documento entero al publicarlo, y los renderizadores
    // leen `doc.empresa`. Si leyeran la constante, cambiar la razón social
    // reescribiría hacia atrás documentos que ya están firmados.
    expect(doc.empresa).toEqual({
      nombre: EMPRESA.nombre,
      ruc: EMPRESA.ruc,
      firmante: "Alvarez Pereyra Felipe Miguel",
      cargo: "Gerencia General",
    });
  });

  it("el firmante NO sale de la constante compartida", () => {
    // Quién suscribe depende del documento —una encargada puede firmar un memo
    // de su sede— y por eso no es identidad de la empresa. Que `EMPRESA` no
    // tenga firmante es la garantía de que nadie lo imprima por descuido.
    expect(EMPRESA).not.toHaveProperty("firmante");
    expect(EMPRESA).not.toHaveProperty("cargo");
  });
});
