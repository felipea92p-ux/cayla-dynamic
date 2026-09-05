import { describe, expect, it } from "vitest";
import { REGIMEN_PENSION_LABELS, REGIMENES_PENSION, nombreRegimenPension } from "@cayla-dynamic/shared";

// ============================================================================
// El esquema de comisión, en las tres superficies que lo dicen
// ============================================================================
// La 0114 modeló un solo esquema de comisión —la comisión sobre flujo— y anotó
// en su cabecera que el otro, la MIXTA, quedaba pendiente. Quedó pendiente hasta
// que el contador comparó las boletas contra AFPnet el 2026-08-31: a quien está
// en mixta se le venía reteniendo cada mes una comisión que su AFP no le cobra.
//
// La tasa la arregla la 0328 en la base. Lo que estas pruebas cuidan es lo otro
// que hizo falta para que el error entrara y se quedara: que las tres cosas que
// el panel MUESTRA sobre el régimen —el desplegable, su etiqueta y la línea de
// la boleta— sigan de acuerdo con la base. Un código cargado en `tasas_pension`
// que el desplegable no ofrece es un régimen que nadie puede elegir; una
// etiqueta que no dice el esquema es cómo se eligió mal la primera vez.

describe("el desplegable ofrece los dos esquemas de comisión", () => {
  it("cada AFP aparece en flujo y en mixta", () => {
    for (const afp of ["profuturo", "prima", "integra", "habitat"]) {
      expect(REGIMENES_PENSION).toContain(afp);
      expect(REGIMENES_PENSION).toContain(`${afp}_mixta`);
    }
  });

  // Si un código quedara sin etiqueta, el desplegable pintaría `undefined` — que
  // es peor que no ofrecerlo, porque se puede elegir igual.
  it("y todos tienen etiqueta", () => {
    for (const r of REGIMENES_PENSION) {
      expect(REGIMEN_PENSION_LABELS[r]).toBeTruthy();
    }
  });

  // La etiqueta es la única cara visible del esquema de comisión al llenar la
  // ficha. «AFP Integra (12.92 %)» a secas fue lo que hizo que la comisión sobre
  // flujo se eligiera sin que nadie supiera que estaba eligiendo entre dos.
  it("y la etiqueta dice de qué esquema se trata, no solo la AFP", () => {
    for (const afp of ["profuturo", "prima", "integra", "habitat"]) {
      expect(REGIMEN_PENSION_LABELS[afp as never]).toContain("sobre flujo");
      expect(REGIMEN_PENSION_LABELS[`${afp}_mixta` as never]).toContain("mixta");
    }
  });

  // Las cuatro mixtas retienen lo mismo porque en mixta la AFP no cobra nada del
  // sueldo: solo quedan el aporte de 10 % y la prima de 1.37 %, iguales en las
  // cuatro. Si alguna dijera otro número, o se movió la prima y falta actualizar
  // las cuatro, o alguien volvió a sumarle una comisión que no se retiene.
  it("y las cuatro mixtas retienen 11.37 %", () => {
    for (const afp of ["profuturo", "prima", "integra", "habitat"]) {
      expect(REGIMEN_PENSION_LABELS[`${afp}_mixta` as never]).toContain("11.37 %");
    }
  });
});

describe("nombreRegimenPension — el nombre que se imprime en la boleta", () => {
  // El defecto que la función vino a impedir: la boleta armaba el nombre con
  // charAt(0).toUpperCase(), que con `integra_mixta` imprime «AFP Integra_mixta»
  // en el documento que la persona firma.
  it("nombra el esquema sin dejar el guion bajo a la vista", () => {
    expect(nombreRegimenPension("integra_mixta")).toBe("AFP Integra — comisión mixta");
    expect(nombreRegimenPension("profuturo_mixta")).toBe("AFP Profuturo — comisión mixta");
  });

  it("y en flujo dice solo la AFP, porque la tasa ya va aparte en esa línea", () => {
    expect(nombreRegimenPension("integra")).toBe("AFP Integra");
    expect(nombreRegimenPension("habitat")).toBe("AFP Habitat");
  });

  it("la ONP no es una AFP y no se le antepone el prefijo", () => {
    expect(nombreRegimenPension("onp")).toBe("ONP");
  });

  // Sin régimen la boleta pone «Pensión» con su propio respaldo. Devolver null y
  // no un texto es lo que le deja esa decisión a quien pinta: en otra pantalla el
  // texto correcto para lo mismo es «todavía no se sabe».
  it("y sin régimen devuelve null, no un nombre inventado", () => {
    expect(nombreRegimenPension(null)).toBeNull();
    expect(nombreRegimenPension(undefined)).toBeNull();
    expect(nombreRegimenPension("  ")).toBeNull();
  });

  // La misma promesa que hace `fn_cambiar_regimen_pension` al validar contra
  // `tasas_pension` y no contra una lista escrita a mano (0277): una AFP nueva
  // se puede cargar en la tabla y usar antes de que el código la nombre.
  it("y un régimen que el código todavía no conoce sale legible igual", () => {
    expect(nombreRegimenPension("nuevaafp")).toBe("AFP Nuevaafp");
    expect(nombreRegimenPension("nuevaafp_mixta")).toBe("AFP Nuevaafp — comisión mixta");
  });

  // Todos los códigos del desplegable tienen que pasar por la boleta sin dejar
  // un guion bajo asomando: es la comprobación que habría cazado el defecto
  // original en el momento de agregarlos.
  it("y ningún código del desplegable imprime un guion bajo", () => {
    for (const r of REGIMENES_PENSION) {
      expect(nombreRegimenPension(r)).not.toContain("_");
    }
  });
});
