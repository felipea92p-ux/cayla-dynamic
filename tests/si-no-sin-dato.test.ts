// ============================================================================
// si-no-sin-dato.test.ts — El «NO» que el padrón afirmaba sin que nadie lo dijera
// ============================================================================
// El padrón es el archivo que sale de CAYLA hacia el contador y de ahí al
// T-Registro de SUNAT. Imprimía dos columnas con un ternario:
//
//     "Asignacion familiar": f?.hijos_menores ? "SI" : "NO"
//     Discapacidad:          f?.discapacidad  ? "SI" : "NO"
//
// Y ahí caben TRES estados, no dos: `true`, `false`, y el `null` de una ficha
// que nadie ha llenado todavía (o una persona sin ficha, que da `undefined`).
// Los dos últimos salían iguales. O sea que el documento le AFIRMABA a un
// tercero que la persona no tiene hijos menores cuando la verdad es que no se
// había preguntado nunca.
//
// Lo que cuesta: la asignación familiar son S/113 al mes y es un derecho, no
// una liberalidad. Un «NO» falso escrito por la propia empresa, en el papel que
// entrega al contador.
//
// MEDIDO EN PRODUCCIÓN el 2026-08-10, y por eso esto es una red y no una
// urgencia: de las 21 personas activas en planilla, las 21 tienen el dato
// declarado y coincide con lo que se les paga. Cero desacuerdos. Lo que estas
// pruebas impiden es que la primera persona que entre SIN ficha salga en el
// padrón con un «NO» que nadie escribió.
//
// LA TRAMPA QUE CUIDAN. El arreglo evidente es dejar la celda vacía, y sería
// peor: ese mismo archivo ya decidió lo contrario para las etiquetas de
// catálogo, con este argumento —«un dato raro en el CSV se ve y se pregunta;
// una celda en blanco se lee como *no tiene*»—. Lo desconocido se dice con
// todas sus letras. Por eso hay una prueba que exige que NUNCA devuelva "".
// ============================================================================

import { describe, expect, it } from "vitest";
import { siNoSinDato } from "@cayla-dynamic/shared";

describe("los tres estados siguen siendo tres", () => {
  it("declarado que sí", () => {
    expect(siNoSinDato(true)).toBe("SI");
  });

  it("declarado que no", () => {
    expect(siNoSinDato(false)).toBe("NO");
  });

  it("la ficha existe pero el campo está sin llenar", () => {
    expect(siNoSinDato(null)).toBe("SIN DATO");
  });

  it("la persona no tiene ficha todavía", () => {
    // `fichas.get(id)` devuelve undefined, y `f?.hijos_menores` con él.
    expect(siNoSinDato(undefined)).toBe("SIN DATO");
  });
});

describe("lo que no puede volver a pasar", () => {
  it("un dato que no se sabe NO se imprime como «NO»", () => {
    // Éste es el defecto original, tal cual. Si alguien vuelve al ternario,
    // esta prueba es la que se pone roja.
    expect(siNoSinDato(null)).not.toBe("NO");
    expect(siNoSinDato(undefined)).not.toBe("NO");
  });

  it("un dato que no se sabe tampoco se imprime en blanco", () => {
    // El arreglo aparentemente elegante, que sería volver al mismo error por
    // otra puerta: en este archivo una celda vacía se lee como «no tiene».
    expect(siNoSinDato(null)).not.toBe("");
    expect(siNoSinDato(undefined)).not.toBe("");
  });

  it("los tres estados dan tres textos distintos entre sí", () => {
    const salidas = [siNoSinDato(true), siNoSinDato(false), siNoSinDato(null)];
    expect(new Set(salidas).size).toBe(3);
  });
});
