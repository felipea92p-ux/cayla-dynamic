// accion-principal-planilla.test.ts — el botón grande de Planilla según cómo va el mes
import { describe, expect, it } from "vitest";
import { accionPrincipalDelPeriodo } from "../apps/web/lib/admin/planilla/accion-principal";
import type { GrupoPago } from "../apps/web/lib/admin/planilla/tipos";

const g = (grupo: GrupoPago["grupo"], estado: GrupoPago["estado"], personas = 5): GrupoPago => ({ grupo, estado, pagado_at: null, pagado_por_nombre: null, personas });

describe("accionPrincipalDelPeriodo", () => {
  it("mientras no se sabe el estado de los grupos no ofrece ninguna acción", () => {
    expect(accionPrincipalDelPeriodo({ personasFrenan: 0, grupos: null, grupoDeLaPestana: "planilla" })).toBeNull();
  });

  it("algo frena el pago: lo primero es resolverlo, aunque ya haya un grupo pagado", () => {
    const r = accionPrincipalDelPeriodo({ personasFrenan: 2, grupos: [g("planilla", "pagado"), g("prueba", "abierto")], grupoDeLaPestana: "planilla" });
    expect(r).toEqual({ tipo: "resolver", frenan: 2 });
  });

  it("nada frena y falta un grupo: cierra el de la pestaña si es el que falta", () => {
    const r = accionPrincipalDelPeriodo({ personasFrenan: 0, grupos: [g("planilla", "abierto"), g("prueba", "abierto")], grupoDeLaPestana: "prueba" });
    expect(r).toEqual({ tipo: "cerrar", grupo: "prueba" });
  });

  it("si la pestaña ya está pagada, ofrece cerrar el que sigue pendiente", () => {
    const r = accionPrincipalDelPeriodo({ personasFrenan: 0, grupos: [g("planilla", "pagado"), g("prueba", "abierto")], grupoDeLaPestana: "planilla" });
    expect(r).toEqual({ tipo: "cerrar", grupo: "prueba" });
  });

  it("un grupo SIN gente no cuenta como pendiente", () => {
    const r = accionPrincipalDelPeriodo({ personasFrenan: 0, grupos: [g("planilla", "pagado"), g("prueba", "abierto", 0)], grupoDeLaPestana: "planilla" });
    expect(r).toEqual({ tipo: "boletas" });
  });

  it("todos los grupos con gente pagados: boletas", () => {
    expect(accionPrincipalDelPeriodo({ personasFrenan: 0, grupos: [g("planilla", "pagado"), g("prueba", "pagado")], grupoDeLaPestana: "planilla" })).toEqual({ tipo: "boletas" });
  });
});
