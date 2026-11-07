// ============================================================================
// semana-por-persona.ts — «Semana» de Turnos: cómo le fue a cada día (2026-11-07)
// ============================================================================
// PROMETE: de las celdas de UN día que ya calcula la Integrada (celdaConNombres),
//          decir en una palabra cómo está ese día —sin gente, sin meta, alcanza o
//          falta, con su peor tramo—, en qué tramos no hay líder y el tono de cada
//          hora para la tira de color. Es la fila «En piso» de arriba de Semana.
// ASUME:   que las celdas son las de la Integrada para ese día: mismas filas, la
//          misma ancla, en orden y una detrás de otra.
// NO HACE: contar. El número de una hora es SIEMPRE el de celdaConNombres. Si
//          Semana contara por su cuenta, la misma hora podría decir «falta 1» en
//          una pestaña y «completo» en la otra, y nadie sabría a cuál creerle.
//
// Por qué un tipo con cuatro formas y no un puñado de booleanos: «falta» sin su
// peor tramo, o «alcanza» un día sin nadie, no se pueden escribir. La pantalla
// pinta lo que el tipo le deja pintar.
// ============================================================================
import { ventanaDeTurnos, type CeldaConNombres, type TurnoConNombre } from "./semana-con-nombres";

export type TonoDeHora = "fuera" | "sin_meta" | "falta" | "ok" | "sobra";

/** El estado de una hora contra su meta. Una hora sin meta no está «completa»: no tiene contra qué medirse. */
export function tonoDeHora(c: CeldaConNombres): TonoDeHora {
  if (c.fuera) return "fuera";
  if (c.meta <= 0) return "sin_meta";
  if (c.enPiso < c.meta) return "falta";
  return c.enPiso > c.meta ? "sobra" : "ok";
}

export interface Tramo {
  desde: number;
  hasta: number;
}

export type EstadoDelDia =
  | { tipo: "sin_gente" }
  | { tipo: "sin_meta" }
  | { tipo: "alcanza" }
  /** `peor` es el tramo donde más falta; empate → el más temprano. `otrosTramos`, cuántos tramos con falta hay además. */
  | { tipo: "falta"; peor: Tramo & { faltan: number }; otrosTramos: number };

export interface ResumenSemanalDelDia {
  estado: EstadoDelDia;
  sinLider: Tramo[];
  tonos: TonoDeHora[];
}

/**
 * Junta las horas seguidas que cumplen `cumple` en tramos, con el máximo de `cuanto`
 * en cada uno, y los recorta a la ventana del día: si la tienda cierra a las 18:15,
 * el tramo dice 18:15 y no el fin de la fila (18:30).
 */
function tramosDe(
  celdas: CeldaConNombres[],
  cumple: (c: CeldaConNombres) => boolean,
  cuanto: (c: CeldaConNombres) => number,
  ventana: Tramo,
): (Tramo & { max: number })[] {
  const out: (Tramo & { max: number })[] = [];
  let actual: (Tramo & { max: number }) | null = null;
  for (const c of celdas) {
    if (!cumple(c)) { actual = null; continue; }
    if (actual && Math.abs(actual.hasta - c.desde) < 1e-9) {
      actual.hasta = c.hasta;
      actual.max = Math.max(actual.max, cuanto(c));
    } else {
      actual = { desde: c.desde, hasta: c.hasta, max: cuanto(c) };
      out.push(actual);
    }
  }
  return out.map((t) => ({ desde: Math.max(t.desde, ventana.desde), hasta: Math.min(t.hasta, ventana.hasta), max: t.max }));
}

export function resumenSemanalDelDia(celdas: CeldaConNombres[], turnos: TurnoConNombre[]): ResumenSemanalDelDia {
  const tonos = celdas.map(tonoDeHora);
  const ventana = ventanaDeTurnos(turnos);
  if (ventana === null || tonos.every((t) => t === "fuera")) return { estado: { tipo: "sin_gente" }, sinLider: [], tonos };

  const sinLider = tramosDe(celdas, (c) => c.sinLider, () => 0, ventana).map(({ desde, hasta }) => ({ desde, hasta }));
  const faltas = tramosDe(celdas, (c) => tonoDeHora(c) === "falta", (c) => c.meta - c.enPiso, ventana);
  if (faltas.length > 0) {
    // Ordenado por cuánto falta y, a igualdad, por hora: el que se ve es siempre el mismo.
    const [peor] = [...faltas].sort((a, b) => b.max - a.max || a.desde - b.desde);
    return {
      estado: { tipo: "falta", peor: { desde: peor.desde, hasta: peor.hasta, faltan: peor.max }, otrosTramos: faltas.length - 1 },
      sinLider,
      tonos,
    };
  }
  if (tonos.every((t) => t === "fuera" || t === "sin_meta")) return { estado: { tipo: "sin_meta" }, sinLider, tonos };
  return { estado: { tipo: "alcanza" }, sinLider, tonos };
}
