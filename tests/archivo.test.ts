// ============================================================================
// archivo.test.ts — lo que la pantalla del Archivo de la empresa decide
// ============================================================================
// Cuida cuatro cosas que, si fallan, la pantalla MIENTE o filtra un dato: que
// un papel vencido no se vea como al día, que la ruta en el almacén nunca lleve
// el nombre del archivo (puede traer un nombre o un DNI), que el buscador no
// esconda un papel por una tilde, y que el historial no pierda versiones.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  agruparPorEntidad, coincide, entidadesUsadas, estadoVencimiento, problemaDeArchivo,
  rutaNuevaArchivo, textoVencimiento, versionesAnteriores, DIAS_AVISO_VENCIMIENTO,
  type FichaArchivo,
} from "@/lib/admin/archivo";

function ficha(o: Partial<FichaArchivo> = {}): FichaArchivo {
  return {
    id: "f1", titulo: "Constancia de inscripción", entidad: "Autoridad Nacional de Protección de Datos Personales",
    numero: "INS-2026-5135", fecha_documento: "2026-09-08", vence_el: null, sede_id: null, sede_nombre: null,
    nota: null, storage_path: "00000000-0000-0000-0000-000000000001.pdf", nombre_archivo: "constancia.pdf",
    mime: "application/pdf", bytes: 32768, reemplaza_a: null, reemplazada_por: null, estado: "vigente",
    subido_por_nombre: "Ana Lab", subido_at: "2026-10-01T15:00:00Z", retirado_at: null,
    retirado_por_nombre: null, retirado_motivo: null, ...o,
  };
}

describe("el vencimiento se cuenta en días, y el último día todavía vale", () => {
  const hoy = "2026-10-01";
  it("sin fecha de vencimiento no avisa nada", () => {
    expect(estadoVencimiento(null, hoy).estado).toBe("sin_vencimiento");
    expect(textoVencimiento(null, hoy)).toBeNull();
  });
  it("el mismo día del vencimiento todavía vale", () => {
    expect(estadoVencimiento("2026-10-01", hoy)).toEqual({ estado: "por_vencer", dias: 0 });
    expect(textoVencimiento("2026-10-01", hoy)).toBe("vence hoy");
  });
  it("al día siguiente ya venció", () => {
    expect(estadoVencimiento("2026-09-30", hoy).estado).toBe("vencido");
    expect(textoVencimiento("2026-09-30", hoy)).toBe("venció ayer");
    expect(textoVencimiento("2026-09-21", hoy)).toBe("venció hace 10 días");
  });
  it(`avisa desde ${DIAS_AVISO_VENCIMIENTO} días antes, y no antes`, () => {
    expect(estadoVencimiento("2026-11-30", hoy)).toEqual({ estado: "por_vencer", dias: 60 });
    expect(estadoVencimiento("2026-12-01", hoy).estado).toBe("al_dia");
    expect(textoVencimiento("2026-12-01", hoy)).toBeNull();
  });
  it("cruza el fin de año y el cambio de mes sin errores de un día", () => {
    expect(estadoVencimiento("2027-01-01", "2026-12-31").dias).toBe(1);
    expect(estadoVencimiento("2028-03-01", "2028-02-28").dias).toBe(2); // 2028 es bisiesto
    expect(textoVencimiento("2027-01-01", "2026-12-31")).toBe("vence mañana");
  });
});

describe("la ruta en el almacén nunca lleva el nombre del archivo", () => {
  const uuid = "0f0e0d0c-0b0a-0908-0706-050403020100";
  it("solo el uuid y la extensión", () => {
    expect(rutaNuevaArchivo("constanciaInscripción videovigilancia.pdf", "application/pdf", uuid)).toBe(`${uuid}.pdf`);
    expect(rutaNuevaArchivo("DNI 12345678 Nombre Apellido.PDF", "application/pdf", uuid)).toBe(`${uuid}.pdf`);
  });
  it("cumple la forma que exige la base", () => {
    for (const nombre of ["a.pdf", "foto.HEIC", "licencia.jpeg", "sin-extension", "raro.docx"]) {
      expect(rutaNuevaArchivo(nombre, "", uuid)).toMatch(/^[0-9a-f-]{36}\.[a-z0-9]{2,5}$/);
    }
  });
  it("si el nombre no trae una extensión aceptada, la saca del tipo", () => {
    expect(rutaNuevaArchivo("escaneo", "image/png", uuid)).toBe(`${uuid}.png`);
    expect(rutaNuevaArchivo("escaneo", "image/jpeg", uuid)).toBe(`${uuid}.jpg`);
  });
});

describe("qué archivo se rechaza antes de subirlo", () => {
  it("un PDF y una foto pasan", () => {
    expect(problemaDeArchivo({ name: "c.pdf", type: "application/pdf", size: 1000 })).toBeNull();
    expect(problemaDeArchivo({ name: "foto.heic", type: "", size: 1000 })).toBeNull();
  });
  it("uno vacío, uno de más de 50 MB y uno de Word no", () => {
    expect(problemaDeArchivo({ name: "c.pdf", type: "application/pdf", size: 0 })).toMatch(/vacío/);
    expect(problemaDeArchivo({ name: "c.pdf", type: "application/pdf", size: 51 * 1048576 })).toMatch(/50 MB/);
    expect(problemaDeArchivo({ name: "c.docx", type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", size: 10 }))
      .toMatch(/no es un PDF ni una foto/);
  });
});

describe("el buscador", () => {
  const f = ficha({ sede_nombre: "Tienda Trujillo", nota: "Colgada junto a la caja" });
  it("encuentra sin tildes ni mayúsculas", () => {
    expect(coincide(f, "proteccion")).toBe(true);
    expect(coincide(f, "INSCRIPCION")).toBe(true);
  });
  it("busca en el número, la sede, el nombre del archivo y la nota", () => {
    expect(coincide(f, "5135")).toBe(true);
    expect(coincide(f, "trujillo")).toBe(true);
    expect(coincide(f, "constancia.pdf")).toBe(true);
    expect(coincide(f, "caja")).toBe(true);
  });
  it("vacío no esconde nada, y lo que no está no aparece", () => {
    expect(coincide(f, "   ")).toBe(true);
    expect(coincide(f, "sunat")).toBe(false);
  });
});

describe("agrupar y sugerir entidades", () => {
  const fichas = [
    ficha({ id: "a", entidad: "SUNAT", titulo: "Ficha RUC" }),
    ficha({ id: "b", entidad: "Municipalidad de Trujillo", titulo: "Licencia" }),
    ficha({ id: "c", entidad: "SUNAT", titulo: "Constancia REMYPE" }),
  ];
  it("agrupa por entidad, en orden alfabético por grupo y por título", () => {
    const g = agruparPorEntidad(fichas);
    expect(g.map((x) => x.entidad)).toEqual(["Municipalidad de Trujillo", "SUNAT"]);
    expect(g[1].fichas.map((x) => x.titulo)).toEqual(["Constancia REMYPE", "Ficha RUC"]);
  });
  it("sugiere cada entidad una sola vez", () => {
    expect(entidadesUsadas(fichas)).toEqual(["Municipalidad de Trujillo", "SUNAT"]);
  });
});

describe("el historial de un papel", () => {
  it("recorre la cadena de reemplazos de la más nueva a la más vieja", () => {
    const v1 = ficha({ id: "v1", estado: "reemplazada", reemplazada_por: "v2" });
    const v2 = ficha({ id: "v2", estado: "reemplazada", reemplaza_a: "v1", reemplazada_por: "v3" });
    const v3 = ficha({ id: "v3", reemplaza_a: "v2" });
    const otra = ficha({ id: "x" });
    expect(versionesAnteriores(v3, [v1, otra, v3, v2]).map((f) => f.id)).toEqual(["v2", "v1"]);
    expect(versionesAnteriores(otra, [v1, otra, v3, v2])).toEqual([]);
  });
  it("no se cuelga con un ciclo, aunque la base no lo permita", () => {
    const a = ficha({ id: "a", reemplaza_a: "b" });
    const b = ficha({ id: "b", reemplaza_a: "a" });
    expect(versionesAnteriores(a, [a, b]).length).toBeLessThanOrEqual(2);
  });
});
