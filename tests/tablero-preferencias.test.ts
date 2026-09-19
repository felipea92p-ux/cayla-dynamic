import { describe, it, expect } from "vitest";
import {
  PANELES, PREFERENCIAS_INICIALES, alternarAlertas, alternarColapsado, alternarKpiExtra, alternarOculto,
  moverPanel, normalizarPreferencias,
} from "@/lib/admin/tablero-preferencias";

describe("normalizarPreferencias — lo guardado nunca rompe la pantalla", () => {
  it("sin nada guardado (null, texto, número, lista) devuelve el diseño por defecto", () => {
    for (const crudo of [null, undefined, "hola", 42, [], true]) {
      expect(normalizarPreferencias(crudo)).toEqual(PREFERENCIAS_INICIALES);
    }
  });

  it("un panel desconocido se descarta y uno que falta se agrega al final", () => {
    const p = normalizarPreferencias({ orden: ["sedes", "panel_que_ya_no_existe", "resumen"] });
    expect(p.orden).toEqual(["sedes", "resumen", "memos", "contratos"]);
  });

  it("un panel repetido en el orden aparece una sola vez", () => {
    expect(normalizarPreferencias({ orden: ["memos", "memos", "sedes"] }).orden).toEqual(["memos", "sedes", "resumen", "contratos"]);
  });

  it("los contratos y los memos NO se pueden ocultar, ni siquiera si lo guardado dice que sí", () => {
    const p = normalizarPreferencias({ ocultos: { contratos: true, memos: true, sedes: true } });
    expect(p.ocultos).toEqual({ sedes: true });
  });

  it("solo cuenta como verdadero un `true` exacto: «true» como texto o 1 no", () => {
    const p = normalizarPreferencias({ colapsados: { sedes: "true", resumen: 1, memos: true }, alertasOcultas: "si" });
    expect(p.colapsados).toEqual({ memos: true });
    expect(p.alertasOcultas).toBe(false);
  });

  it("una clave de indicador desconocida se ignora", () => {
    expect(normalizarPreferencias({ kpisExtra: { pendientes: true, cierre_planilla: true } }).kpisExtra).toEqual({ pendientes: true });
  });

  it("siempre devuelve todos los paneles, sin importar la basura de entrada", () => {
    expect([...normalizarPreferencias({ orden: [1, null, {}, "x"] }).orden].sort()).toEqual([...PANELES].sort());
  });

  it("no comparte objetos con el valor inicial: modificar el resultado no lo contamina", () => {
    const p = normalizarPreferencias(null);
    p.orden.push("resumen");
    p.kpisExtra.personal = true;
    expect(PREFERENCIAS_INICIALES.orden).toHaveLength(PANELES.length);
    expect(PREFERENCIAS_INICIALES.kpisExtra).toEqual({});
  });
});

describe("las acciones del tablero", () => {
  it("moverPanel intercambia con el vecino y en el borde no hace nada", () => {
    const p = PREFERENCIAS_INICIALES;
    expect(moverPanel(p, "sedes", -1).orden).toEqual(["sedes", "resumen", "memos", "contratos"]);
    expect(moverPanel(p, "resumen", -1)).toBe(p);
    expect(moverPanel(p, "contratos", 1)).toBe(p);
  });

  it("alternarOculto oculta y vuelve a mostrar, salvo memos y contratos", () => {
    const oculto = alternarOculto(PREFERENCIAS_INICIALES, "sedes");
    expect(oculto.ocultos).toEqual({ sedes: true });
    expect(alternarOculto(oculto, "sedes").ocultos).toEqual({});
    expect(alternarOculto(PREFERENCIAS_INICIALES, "contratos")).toBe(PREFERENCIAS_INICIALES);
    expect(alternarOculto(PREFERENCIAS_INICIALES, "memos")).toBe(PREFERENCIAS_INICIALES);
  });

  it("colapsar sí vale para memos y contratos", () => {
    expect(alternarColapsado(PREFERENCIAS_INICIALES, "contratos").colapsados).toEqual({ contratos: true });
  });

  it("agregar y quitar un indicador extra", () => {
    const con = alternarKpiExtra(PREFERENCIAS_INICIALES, "personal");
    expect(con.kpisExtra).toEqual({ personal: true });
    expect(alternarKpiExtra(con, "personal").kpisExtra).toEqual({});
  });

  it("ocultar el panel de alertas y volver a mostrarlo", () => {
    const oculto = alternarAlertas(PREFERENCIAS_INICIALES);
    expect(oculto.alertasOcultas).toBe(true);
    expect(alternarAlertas(oculto).alertasOcultas).toBe(false);
  });

  it("las acciones no modifican el valor anterior", () => {
    const antes = structuredClone(PREFERENCIAS_INICIALES);
    alternarOculto(PREFERENCIAS_INICIALES, "sedes");
    moverPanel(PREFERENCIAS_INICIALES, "sedes", -1);
    alternarColapsado(PREFERENCIAS_INICIALES, "resumen");
    expect(PREFERENCIAS_INICIALES).toEqual(antes);
  });
});
