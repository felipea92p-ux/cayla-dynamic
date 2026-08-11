// ============================================================================
// asignacion-familiar.test.ts — Cuando el que paga y el que declara no coinciden
// ============================================================================
// Los S/113 de asignación familiar se deciden en un campo y se declaran en otro:
//
//   personas.con_hijos            → pantalla de EQUIPO. Es el que PAGA:
//                                   fn_planilla_calcular lo lee.
//   datos_personales.hijos_menores → pantalla de DATOS PERSONALES. Es el que
//                                   sale en el PADRÓN del contador.
//
// Nada los mantiene de acuerdo: ninguna migración menciona los dos, ninguna
// pantalla escribe los dos. Que hoy coincidan en las 21 personas de planilla
// —medido en producción el 2026-08-10— es mérito de quien los llenó a mano.
//
// POR QUÉ ESTAS PRUEBAS Y NO UNA COMPROBACIÓN EN LA PANTALLA. Porque un aviso
// FALSO contra una persona real cuesta más que no avisar — es la regla del
// repo—, y los dos casos que lo producirían son silenciosos:
//
//   · que un fallo de red se lea como «no tiene hijos» y ponga un ⚠ a todo el
//     equipo. La pantalla de Equipo degrada a `false` cuando su RPC falla;
//     copiar eso aquí habría hecho exactamente eso.
//   · que «la ficha está en blanco» se lea como «declaró que no», que es el
//     mismo error que el padrón ya cometía imprimiendo «NO».
// ============================================================================

import { describe, expect, it } from "vitest";
import { desacuerdoAsignacionFamiliar } from "@cayla-dynamic/shared";

describe("los desacuerdos que hay que decir", () => {
  it("se le paga y la ficha declara que NO tiene hijos", () => {
    // La empresa abona S/113 y en el padrón declara lo contrario.
    expect(desacuerdoAsignacionFamiliar(true, false)).toBe("paga_y_declara_que_no");
  });

  it("la ficha declara que sí y no se le paga — es plata que se le debe", () => {
    expect(desacuerdoAsignacionFamiliar(false, true)).toBe("declara_y_no_cobra");
  });

  it("se le paga y la ficha no dice nada", () => {
    // El padrón saldrá con «SIN DATO» para alguien a quien sí se le paga.
    expect(desacuerdoAsignacionFamiliar(true, null)).toBe("paga_y_la_ficha_calla");
    expect(desacuerdoAsignacionFamiliar(true, undefined)).toBe("paga_y_la_ficha_calla");
  });
});

describe("los silencios que hay que respetar", () => {
  it("las dos mitades de acuerdo no dicen nada", () => {
    expect(desacuerdoAsignacionFamiliar(true, true)).toBe("ninguno");
    expect(desacuerdoAsignacionFamiliar(false, false)).toBe("ninguno");
  });

  it("no se le paga y la ficha está en blanco: eso NO es un desacuerdo", () => {
    // Es el caso de la mayor parte del equipo. Avisar aquí pondría un ⚠ en casi
    // todas las fichas y enseñaría a ignorar los avisos — que es cómo muere un
    // aviso útil.
    expect(desacuerdoAsignacionFamiliar(false, null)).toBe("ninguno");
    expect(desacuerdoAsignacionFamiliar(false, undefined)).toBe("ninguno");
  });
});

describe("un fallo de carga NO es un «no tiene hijos»", () => {
  // `undefined` en el primer parámetro significa que la RPC no cargó. La
  // pantalla de Equipo degrada a `false` para todos en ese caso; si esta pieza
  // hiciera lo mismo, un corte de red pintaría un aviso falso contra cada
  // persona del equipo a la vez.
  for (const declara of [true, false, null, undefined] as const) {
    it(`no concluye nada con la ficha en ${String(declara)}`, () => {
      expect(desacuerdoAsignacionFamiliar(undefined, declara)).toBe("ninguno");
    });
  }
});

describe("la tabla completa, para que nada quede sin decidir", () => {
  it("las doce combinaciones dan lo esperado", () => {
    const esperado: Array<[boolean | undefined, boolean | null | undefined, string]> = [
      [true, true, "ninguno"],
      [true, false, "paga_y_declara_que_no"],
      [true, null, "paga_y_la_ficha_calla"],
      [true, undefined, "paga_y_la_ficha_calla"],
      [false, true, "declara_y_no_cobra"],
      [false, false, "ninguno"],
      [false, null, "ninguno"],
      [false, undefined, "ninguno"],
      [undefined, true, "ninguno"],
      [undefined, false, "ninguno"],
      [undefined, null, "ninguno"],
      [undefined, undefined, "ninguno"],
    ];
    for (const [paga, declara, salida] of esperado) {
      expect(desacuerdoAsignacionFamiliar(paga, declara)).toBe(salida);
    }
  });
});
