// El ciclo de 7 días del sobretiempo (art. 9/10, D.S. 007-2002-TR): cuán cerca
// está alguien HOY del tope de 48 h de su ciclo en curso — para avisar ANTES
// de que se cruce, no solo contar el exceso ya pagado.
//
// ESTO ES UNA COPIA DE LECTURA, NO LA REGLA. La regla vive en
// `fn_planilla_calcular_nucleo` (supabase/migrations/0339, CTEs
// ot_dias → ot_islas → ot_ciclos, líneas ~478-503) y es la única que decide
// cuánto se paga. Este módulo porta ESE mismo algoritmo a TypeScript para una
// alerta operativa (Turnos), exactamente por lo que ya explica el
// encabezado de jornada-esperada.ts: sin esto, dos sitios responden la misma
// pregunta con reglas que un día divergen sin que nadie lo note.
//
// EL ALGORITMO, EN UNA LÍNEA: una racha de días consecutivos con horas > 0 es
// una "isla"; dentro de cada isla, bloques de 7 días SIN SOLAPE son los
// "ciclos". El tope de 48 h es POR CICLO, no por semana calendario ni por
// racha completa — por eso doce días seguidos de 8 h son dos ciclos (56 h y
// 40 h) y no uno de 96 h. Ver el comentario "CAMBIO 0185" en la 0339 para el
// sustento legal completo.
//
// SE ROMPE SI: alguien cambia la regla en 0339 y no acá. Antes de tocar este
// archivo, releer esas líneas — no basta con "parece que funciona igual".

export interface DiaTrabajado {
  /** ISO yyyy-mm-dd. */
  fecha: string;
  horas: number;
}

export interface CicloVigente {
  /** Horas acumuladas en el ciclo de 7 días que sigue abierto. */
  horas: number;
  /** Cuántos días de ese ciclo ya tienen horas registradas (1-7). */
  dia: number;
  desde: string;
  hasta: string;
}

function diffDias(a: string, b: string): number {
  const [ay, am, ad] = a.split("-").map(Number);
  const [by, bm, bd] = b.split("-").map(Number);
  return Math.round((Date.UTC(ay, am - 1, ad) - Date.UTC(by, bm - 1, bd)) / 86_400_000);
}

/**
 * El ciclo de 7 días vigente a la fecha `hoy`, o `null` si no hay una racha
 * abierta (el último día con horas quedó a 2 o más días de `hoy`: la racha ya
 * se cortó, y lo que haya quedado pendiente de pagar es cosa de la planilla,
 * no de esta alerta). `dias` no necesita venir ordenado ni completo — un
 * hueco entre dos fechas corta la racha, igual que en el SQL.
 */
export function cicloVigente(dias: DiaTrabajado[], hoy: string): CicloVigente | null {
  const positivos = [...dias].filter((d) => d.horas > 0).sort((a, b) => (a.fecha < b.fecha ? -1 : a.fecha > b.fecha ? 1 : 0));
  if (positivos.length === 0) return null;

  // Islas: una racha nueva empieza cuando el día no es consecutivo al anterior.
  const islas: DiaTrabajado[][] = [];
  for (const d of positivos) {
    const anterior = islas.at(-1)?.at(-1);
    if (anterior && diffDias(d.fecha, anterior.fecha) === 1) islas.at(-1)!.push(d);
    else islas.push([d]);
  }

  const islaActual = islas.at(-1)!;
  const ultimoDia = islaActual.at(-1)!;
  if (diffDias(hoy, ultimoDia.fecha) > 1) return null; // la racha ya se cortó

  // Bloques de 7 dentro de la isla — el último bloque es el vigente.
  const bloqueIdx = Math.floor((islaActual.length - 1) / 7);
  const bloque = islaActual.slice(bloqueIdx * 7, bloqueIdx * 7 + 7);
  return {
    horas: bloque.reduce((s, d) => s + d.horas, 0),
    dia: bloque.length,
    desde: bloque[0].fecha,
    hasta: bloque.at(-1)!.fecha,
  };
}
