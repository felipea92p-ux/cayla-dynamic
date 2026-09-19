// ============================================================================
// novedades.test.ts — La lista de novedades del sistema, comprobada
// ============================================================================
// La lista la escribe una persona a mano, en cada pull request, durante años.
// Lo que no se comprueba aquí se descubre cuando el equipo ya lo leyó: por eso
// las reglas de «qué NO va» (montos, nombres de rol prohibidos, fechas del
// futuro) están como pruebas y no solo como comentario.
// ============================================================================
import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { hoyLima } from "@cayla-dynamic/shared";
import {
  DIAS_COMO_NUEVA, FORMATO_ID_NOVEDAD, LARGO_MAXIMO_ID_NOVEDAD, NOVEDADES,
  esNovedadNueva, esNovedadPendiente, fechaDeNovedad, novedadesPara, novedadesPendientes,
  primerParrafo, tieneMasQueElPrimerParrafo,
  type Novedad,
} from "@/lib/novedades";

function nov(parcial: Partial<Novedad> & Pick<Novedad, "id" | "fecha">): Novedad {
  return { titulo: "T", queMejoro: "Q", audiencia: "todos", ...parcial };
}

describe("la lista real de novedades: lo que no debe existir", () => {
  it("no hay dos con el mismo id — es la llave con que se dibujan", () => {
    const ids = NOVEDADES.map((n) => n.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("el id empieza por su fecha, así un id repetido salta a la vista al escribirlo", () => {
    for (const n of NOVEDADES) expect(n.id.startsWith(`${n.fecha}-`)).toBe(true);
  });

  it("la fecha es un día real de Lima y no del futuro: no se anuncia lo que aún no llegó", () => {
    const hoy = hoyLima();
    for (const n of NOVEDADES) {
      expect(n.fecha).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      const d = new Date(`${n.fecha}T12:00:00Z`);
      expect(Number.isNaN(d.getTime())).toBe(false);
      expect(d.toISOString().startsWith(n.fecha)).toBe(true);
      expect(n.fecha <= hoy).toBe(true);
    }
  });

  it("el id tiene la forma que la base acepta: si no, esa novedad nunca podría marcarse como entendida", () => {
    for (const n of NOVEDADES) {
      expect(n.id).toMatch(FORMATO_ID_NOVEDAD);
      expect(n.id.length).toBeLessThanOrEqual(LARGO_MAXIMO_ID_NOVEDAD);
    }
  });

  it("el primer párrafo existe y es corto: es lo único que «Lo mío» muestra", () => {
    for (const n of NOVEDADES) {
      expect(primerParrafo(n).length).toBeGreaterThan(0);
      expect(primerParrafo(n).length).toBeLessThanOrEqual(420);
    }
  });

  it("tiene título y cuerpo, y el título cabe en una línea de tarjeta", () => {
    for (const n of NOVEDADES) {
      expect(n.titulo.trim().length).toBeGreaterThan(0);
      expect(n.titulo.length).toBeLessThanOrEqual(90);
      expect(n.queMejoro.trim().length).toBeGreaterThan(0);
    }
  });

  it("nunca lleva un monto de plata: una regla de pago no se avisa por este canal", () => {
    for (const n of NOVEDADES) {
      const texto = `${n.titulo} ${n.queMejoro}`;
      expect(texto).not.toMatch(/S\/\s?\d/);
      expect(texto).not.toMatch(/\bsoles\b/i);
    }
  });

  it("nunca lleva un DNI (ocho cifras seguidas) ni un correo", () => {
    for (const n of NOVEDADES) {
      const texto = `${n.titulo} ${n.queMejoro}`;
      expect(texto).not.toMatch(/\b\d{8}\b/);
      expect(texto).not.toMatch(/\S+@\S+\.\S+/);
    }
  });

  it("respeta el vocabulario de la casa: ni empleado, ni jefe, ni sucursal, ni RRHH", () => {
    for (const n of NOVEDADES) {
      expect(`${n.titulo} ${n.queMejoro}`).not.toMatch(/\b(emplead[oa]s?|jef[ea]s?|sucursal(es)?|rrhh)\b/i);
    }
  });
});

describe("novedadesPara: cada rol ve lo suyo, lo más reciente primero", () => {
  const lista: Novedad[] = [
    nov({ id: "2026-09-10-a", fecha: "2026-09-10", audiencia: "todos" }),
    nov({ id: "2026-09-12-b", fecha: "2026-09-12", audiencia: "panel" }),
    nov({ id: "2026-09-11-c", fecha: "2026-09-11", audiencia: "do" }),
    nov({ id: "2026-09-12-d", fecha: "2026-09-12", audiencia: "todos" }),
  ];
  const ids = (rol: string | null | undefined) => novedadesPara(rol, lista).map((n) => n.id);

  it("una integrante solo ve lo que es para todos", () => {
    expect(ids("integrante")).toEqual(["2026-09-12-d", "2026-09-10-a"]);
  });

  it("la líder de equipo ve lo de todos y lo del panel, pero no lo de planilla", () => {
    expect(ids("supervisor_sede")).toEqual(["2026-09-12-b", "2026-09-12-d", "2026-09-10-a"]);
  });

  it("DO ve todo", () => {
    expect(ids("lider_do")).toHaveLength(4);
    expect(ids("admin")).toHaveLength(4);
  });

  it("sin rol cargado, un rol vacío o desconocido: solo lo de todos — null nunca abre más", () => {
    for (const rol of [null, undefined, "", "contador"]) {
      expect(ids(rol)).toEqual(["2026-09-12-d", "2026-09-10-a"]);
    }
  });

  it("el mismo día conserva el orden en que están escritas, y no reordena la lista original", () => {
    expect(ids("admin").slice(0, 2)).toEqual(["2026-09-12-b", "2026-09-12-d"]);
    expect(lista.map((n) => n.id)).toEqual(["2026-09-10-a", "2026-09-12-b", "2026-09-11-c", "2026-09-12-d"]);
  });

  it("con la lista real, una integrante siempre ve al menos una (la de bienvenida)", () => {
    expect(novedadesPara("integrante").length).toBeGreaterThan(0);
  });
});

describe("esNovedadNueva: por fecha, sin guardar nada por persona", () => {
  const n = nov({ id: "2026-09-10-x", fecha: "2026-09-10" });

  it("el mismo día y hasta el límite es nueva", () => {
    expect(esNovedadNueva(n, "2026-09-10")).toBe(true);
    expect(esNovedadNueva(n, "2026-09-24")).toBe(true);
  });

  it("el día siguiente al límite ya no", () => {
    expect(DIAS_COMO_NUEVA).toBe(14);
    expect(esNovedadNueva(n, "2026-09-25")).toBe(false);
  });

  it("cruza el cambio de mes sin equivocarse", () => {
    expect(esNovedadNueva(nov({ id: "2026-08-28-y", fecha: "2026-08-28" }), "2026-09-05")).toBe(true);
    expect(esNovedadNueva(nov({ id: "2026-08-28-y", fecha: "2026-08-28" }), "2026-09-12")).toBe(false);
  });

  it("una fecha del futuro no se marca «nueva»: sería anunciar lo que no llegó", () => {
    expect(esNovedadNueva(n, "2026-09-09")).toBe(false);
  });
});

describe("fechaDeNovedad: el día que se escribió es el que se ve", () => {
  it("no se corre un día hacia atrás en la zona horaria de Lima", () => {
    // `new Date("2026-09-18")` es medianoche UTC = 19:00 del 17 en Lima.
    expect(fechaDeNovedad("2026-09-18")).toMatch(/^18\b/);
    expect(fechaDeNovedad("2026-09-01")).toMatch(/^1\b/);
    expect(fechaDeNovedad("2026-12-31")).toMatch(/^31\b/);
  });
});

describe("el formato del id es UNO: el de la lista y el check de la base no se separan", () => {
  it("el patrón de FORMATO_ID_NOVEDAD está, tal cual, en la migración vigente de novedades_vistas", () => {
    // Por CONTENIDO y no por nombre de archivo; y la última que lo define, no
    // cualquiera: si un día otra migración cambia el `check`, esa es la que manda.
    const carpeta = path.resolve(import.meta.dirname, "../supabase/migrations");
    const definen = readdirSync(carpeta)
      .filter((f) => f.endsWith(".sql"))
      .sort()
      .filter((f) => readFileSync(path.join(carpeta, f), "utf8").includes("novedad_id ~"));
    expect(definen.length).toBeGreaterThan(0);
    const sql = readFileSync(path.join(carpeta, definen[definen.length - 1]), "utf8");
    expect(sql).toContain(`'${FORMATO_ID_NOVEDAD.source}'`);
    expect(sql).toContain(`char_length(novedad_id) <= ${LARGO_MAXIMO_ID_NOVEDAD}`);
  });

  it("y lo que la base rechaza, el patrón también", () => {
    for (const malo of ["", "Sin-Fecha", "2026-09-19", "2026-09-19-", "2026-09-19-Con-Mayus", "2026-09-19-con espacio", "2026-09-19--doble"]) {
      expect(FORMATO_ID_NOVEDAD.test(malo)).toBe(false);
    }
    expect(FORMATO_ID_NOVEDAD.test("2026-09-19-anuncios-cuenta-que-mejora")).toBe(true);
  });
});

describe("esNovedadPendiente / novedadesPendientes: lo que le falta a ESTA persona", () => {
  const hoy = "2026-09-19";
  const lista: Novedad[] = [
    nov({ id: "2026-09-18-a", fecha: "2026-09-18", audiencia: "todos" }),
    nov({ id: "2026-09-17-b", fecha: "2026-09-17", audiencia: "panel" }),
    nov({ id: "2026-09-16-c", fecha: "2026-09-16", audiencia: "todos" }),
    nov({ id: "2026-08-01-vieja", fecha: "2026-08-01", audiencia: "todos" }),
  ];
  const ids = (rol: string | null, vistas: string[]) =>
    novedadesPendientes(rol, new Set(vistas), hoy, lista).map((n) => n.id);

  it("sin haber marcado nada, ve las recientes de su rol y no las viejas", () => {
    expect(ids("integrante", [])).toEqual(["2026-09-18-a", "2026-09-16-c"]);
    expect(ids("supervisor_sede", [])).toEqual(["2026-09-18-a", "2026-09-17-b", "2026-09-16-c"]);
  });

  it("la que marcó como entendida deja de estar pendiente, y solo esa", () => {
    expect(ids("integrante", ["2026-09-18-a"])).toEqual(["2026-09-16-c"]);
  });

  it("una marca de una novedad que ya no está en la lista no estorba", () => {
    expect(ids("integrante", ["2026-01-01-que-ya-no-existe"])).toEqual(["2026-09-18-a", "2026-09-16-c"]);
  });

  it("si entendió todas, no queda nada pendiente — y «Lo mío» no dibuja nada", () => {
    expect(ids("admin", ["2026-09-18-a", "2026-09-17-b", "2026-09-16-c"])).toEqual([]);
  });

  it("sin saber qué entendió (null), decide solo la fecha: el modo degradado de Anuncios", () => {
    expect(esNovedadPendiente(lista[0], null, hoy)).toBe(true);
    expect(esNovedadPendiente(lista[3], null, hoy)).toBe(false);
  });

  it("un conjunto vacío NO es «no sé»: todo lo reciente está pendiente, y lo entendido no", () => {
    expect(esNovedadPendiente(lista[0], new Set(), hoy)).toBe(true);
    expect(esNovedadPendiente(lista[0], new Set(["2026-09-18-a"]), hoy)).toBe(false);
  });

  it("un rol sin cargar solo ve las de todos, también entre las pendientes", () => {
    expect(ids(null, [])).toEqual(["2026-09-18-a", "2026-09-16-c"]);
  });
});

describe("primerParrafo: lo que «Lo mío» muestra de cada novedad", () => {
  it("es lo que hay antes de la primera línea en blanco", () => {
    const n = nov({ id: "2026-09-19-x", fecha: "2026-09-19", queMejoro: "Uno.\n\nDos.\n\nTres." });
    expect(primerParrafo(n)).toBe("Uno.");
    expect(tieneMasQueElPrimerParrafo(n)).toBe(true);
  });

  it("si solo tiene un párrafo, no invita a «leerla completa»", () => {
    const n = nov({ id: "2026-09-19-x", fecha: "2026-09-19", queMejoro: "Solo uno." });
    expect(primerParrafo(n)).toBe("Solo uno.");
    expect(tieneMasQueElPrimerParrafo(n)).toBe(false);
  });
});
