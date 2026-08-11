// ============================================================================
// lo-que-no-se-pudo.test.ts — Un cero no es la ausencia de un dato
// ============================================================================
// La Hoja de sede lanza nueve consultas en un Promise.all y hasta hoy tiraba el
// `error` de ocho. Cuando una fallaba no pasaba nada visible: la tabla se
// pintaba con lo que quedó —cero— y el botón de PDF seguía habilitado. Ese papel
// se firma y se lleva a la sede diciendo que el equipo entero trabajó 0 h.
//
// Un cero es una AFIRMACIÓN, no un hueco. Por eso el arreglo no es «pintar el
// error en la consola»: es que la hoja diga qué le falta y NO se deje imprimir.
//
// Lo que se prueba aquí es justamente la parte que no se ve mirando la pantalla
// funcionando bien.
// ============================================================================
import { describe, expect, it } from "vitest";
import { loQueNoSePudo, sePuedeEntregar } from "@/lib/admin/lo-que-no-se-pudo";

describe("loQueNoSePudo", () => {
  it("con todo bien no reporta nada", () => {
    expect(
      loQueNoSePudo([
        { error: null, que: "el equipo de la sede" },
        { error: undefined, que: "los días y las horas" },
      ]),
    ).toEqual([]);
  });

  it("nombra lo que falta, no la consulta que falló", () => {
    const faltan = loQueNoSePudo([
      { error: null, que: "el equipo de la sede" },
      { error: { message: 'permission denied for function fn_tardanzas_resumen' }, que: "las tardanzas" },
    ]);
    // Quien lee el aviso está a punto de firmar el papel, no de depurar: el
    // mensaje de Postgres se queda fuera a propósito.
    expect(faltan).toEqual(["las tardanzas"]);
    expect(faltan.join(" ")).not.toContain("fn_tardanzas_resumen");
  });

  it("los lista en el orden declarado, para que la frase se lea igual siempre", () => {
    expect(
      loQueNoSePudo([
        { error: new Error("x"), que: "el equipo de la sede" },
        { error: null, que: "las áreas" },
        { error: new Error("y"), que: "las faltas" },
      ]),
    ).toEqual(["el equipo de la sede", "las faltas"]);
  });

  it("un error 'vacío' de Postgres también cuenta", () => {
    // PostgREST devuelve objetos, no strings. `{}` es verdadero y tiene que
    // contar: la alternativa —mirar error.message— dejaría pasar el fallo sin
    // mensaje, que es justo el que peor se diagnostica.
    expect(loQueNoSePudo([{ error: {}, que: "los días y las horas" }])).toEqual([
      "los días y las horas",
    ]);
  });
});

describe("sePuedeEntregar", () => {
  it("sí, solo si cargó del todo y no falta nada", () => {
    expect(sePuedeEntregar(true, [])).toBe(true);
  });

  it("no, si alguna consulta se cayó — aunque la tabla se vea llena", () => {
    expect(sePuedeEntregar(true, ["las tardanzas"])).toBe(false);
  });

  it("no, a medio cargar: imprimir temprano da el mismo papel en ceros por otra vía", () => {
    expect(sePuedeEntregar(false, [])).toBe(false);
  });
});
