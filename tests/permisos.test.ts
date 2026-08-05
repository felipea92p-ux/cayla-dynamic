// ============================================================================
// permisos.test.ts — Quién ve qué, comprobado
// ============================================================================
// Estas reglas vivían escritas a mano en 35 sitios, así que no había forma de
// probarlas: había que abrir veinte pantallas con veinte sesiones distintas.
// Ahora que viven en un solo archivo, la regla que importa —una encargada de
// sede NO ve sueldos— se comprueba en un segundo y en cada push.
// ============================================================================
import { describe, it, expect } from "vitest";
import {
  puedeVerPlanilla, puedeVerIdentidad, puedeGestionarCatalogos,
  puedeOperarEquipo, puedeVerTodasLasSedes, ROLES_CON_PANEL, ROLES_DO,
} from "@cayla-dynamic/shared";

describe("la encargada de sede opera a su equipo, pero no ve la plata", () => {
  it("no ve planilla, ni provisiones, ni costos", () => {
    expect(puedeVerPlanilla("supervisor_sede")).toBe(false);
  });
  it("no ve DNI ni cuenta bancaria", () => {
    expect(puedeVerIdentidad("supervisor_sede")).toBe(false);
  });
  it("no crea sedes, áreas ni feriados — eso cambia el pago de las cuatro sedes", () => {
    expect(puedeGestionarCatalogos("supervisor_sede")).toBe(false);
  });
  it("sí corrige marcajes, horarios y turnos de su gente", () => {
    expect(puedeOperarEquipo("supervisor_sede")).toBe(true);
  });
  it("pero solo de SU sede: el alcance es otra pregunta y responde que no", () => {
    expect(puedeVerTodasLasSedes("supervisor_sede")).toBe(false);
  });
});

describe("quien solo marca no entra al panel", () => {
  for (const permiso of [puedeVerPlanilla, puedeVerIdentidad, puedeGestionarCatalogos, puedeOperarEquipo, puedeVerTodasLasSedes]) {
    it(`integrante: ${permiso.name} = false`, () => {
      expect(permiso("integrante")).toBe(false);
    });
  }
});

describe("DO ve todo", () => {
  for (const rol of ["admin", "lider_do"]) {
    it(`${rol} pasa las cinco puertas`, () => {
      expect(puedeVerPlanilla(rol)).toBe(true);
      expect(puedeVerIdentidad(rol)).toBe(true);
      expect(puedeGestionarCatalogos(rol)).toBe(true);
      expect(puedeOperarEquipo(rol)).toBe(true);
      expect(puedeVerTodasLasSedes(rol)).toBe(true);
    });
  }
});

describe("null no pasa como autorizado", () => {
  // La misma regla que en Postgres (`is not true`, guards de la 0078): mientras
  // la sesión carga, el rol es null. Un `null` que pasara mostraría un sueldo
  // durante el parpadeo inicial de la pantalla.
  for (const raro of [null, undefined, "", "rrhh", "ADMIN", "Admin", "gerente"]) {
    it(`rol ${JSON.stringify(raro)} → no puede`, () => {
      expect(puedeVerPlanilla(raro)).toBe(false);
      expect(puedeOperarEquipo(raro)).toBe(false);
    });
  }
});

describe("las listas para filtrar en la base coinciden con las funciones", () => {
  // Si alguien agrega un rol a una lista y se olvida de la función (o al revés),
  // la pantalla y la consulta discreparían en silencio. Esto lo impide.
  it("ROLES_DO son exactamente los que ven planilla", () => {
    expect([...ROLES_DO].sort()).toEqual(["admin", "lider_do"]);
    for (const r of ROLES_DO) expect(puedeVerPlanilla(r)).toBe(true);
  });
  it("ROLES_CON_PANEL son exactamente los que operan al equipo", () => {
    expect([...ROLES_CON_PANEL].sort()).toEqual(["admin", "lider_do", "supervisor_sede"]);
    for (const r of ROLES_CON_PANEL) expect(puedeOperarEquipo(r)).toBe(true);
  });
});
