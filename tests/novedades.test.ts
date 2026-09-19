// ============================================================================
// novedades.test.ts — La lista de novedades del sistema, comprobada
// ============================================================================
// La lista la escribe una persona a mano, en cada pull request, durante años.
// Lo que no se comprueba aquí se descubre cuando el equipo ya lo leyó: por eso
// las reglas de «qué NO va» (montos, nombres de rol prohibidos, fechas del
// futuro) están como pruebas y no solo como comentario.
// ============================================================================
import { describe, it, expect } from "vitest";
import { hoyLima } from "@cayla-dynamic/shared";
import {
  DIAS_COMO_NUEVA, NOVEDADES, esNovedadNueva, fechaDeNovedad, novedadesPara,
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
