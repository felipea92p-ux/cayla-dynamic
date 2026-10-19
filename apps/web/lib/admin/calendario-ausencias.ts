// ============================================================================
// calendario-ausencias.ts — qué casilla pinta cada día del mes (Ausencias › Calendario)
// ============================================================================
// QUÉ PROMETE   · para un mes y una lista de ausencias, dar una fila por persona con una casilla por día: de qué tipo
//                 de ausencia es (o ninguna) y si está pendiente de aprobar (se dibuja rayada).
// QUÉ ASUME     · fechas ISO `AAAA-MM-DD` ya en hora de Lima (las ausencias son días, no instantes). Que dos ausencias
//                 vigentes de la misma persona NO se solapan (la base lo impide con una restricción de exclusión), así
//                 que una casilla tiene a lo sumo una.
// QUÉ NO HACE   · no pinta las anuladas: siguen en la lista, con su motivo, pero un día anulado ya no es un día fuera.
//                 Tampoco decide nada de pagos ni de faltas: solo dibuja lo registrado.
// ============================================================================

export interface AusenciaDeCalendario {
  id: string;
  personaId: string;
  nombre: string;
  /** Código del tipo («vacaciones», «descanso_medico»…). */
  tipo: string;
  tipoNombre: string;
  inicio: string;
  fin: string;
  pendiente: boolean;
  anulada: boolean;
}

export interface CasillaDia {
  dia: number;
  /** La ausencia que cubre ese día, o null. */
  ausencia: AusenciaDeCalendario | null;
}

export interface FilaDeCalendario {
  personaId: string;
  nombre: string;
  casillas: CasillaDia[];
}

/** Cuántos días tiene el mes (mes de 1 a 12). */
export function diasDelMes(anio: number, mes: number): number {
  return new Date(Date.UTC(anio, mes, 0)).getUTCDate();
}

function iso(anio: number, mes: number, dia: number): string {
  return `${anio}-${String(mes).padStart(2, "0")}-${String(dia).padStart(2, "0")}`;
}

/** Día de la semana de una fecha del mes: 0 = domingo … 6 = sábado. */
export function diaDeLaSemana(anio: number, mes: number, dia: number): number {
  return new Date(Date.UTC(anio, mes - 1, dia)).getUTCDay();
}

export function cubreElDia(a: Pick<AusenciaDeCalendario, "inicio" | "fin">, fecha: string): boolean {
  return a.inicio <= fecha && fecha <= a.fin;
}

/** Una fila por persona que tenga al menos un día fuera en el mes, ordenadas por nombre. */
export function filasDelMes(ausencias: readonly AusenciaDeCalendario[], anio: number, mes: number): FilaDeCalendario[] {
  const n = diasDelMes(anio, mes);
  const primero = iso(anio, mes, 1);
  const ultimo = iso(anio, mes, n);
  const delMes = ausencias.filter((a) => !a.anulada && a.inicio <= ultimo && a.fin >= primero);

  const porPersona = new Map<string, AusenciaDeCalendario[]>();
  for (const a of delMes) {
    const lista = porPersona.get(a.personaId) ?? [];
    lista.push(a);
    porPersona.set(a.personaId, lista);
  }

  return [...porPersona.entries()]
    .map(([personaId, lista]) => ({
      personaId,
      nombre: lista[0].nombre,
      casillas: Array.from({ length: n }, (_, i) => {
        const fecha = iso(anio, mes, i + 1);
        return { dia: i + 1, ausencia: lista.find((a) => cubreElDia(a, fecha)) ?? null };
      }),
    }))
    .sort((x, y) => x.nombre.localeCompare(y.nombre, "es"));
}

/** El mes anterior o siguiente, con el cambio de año resuelto. */
export function mesVecino(anio: number, mes: number, delta: -1 | 1): { anio: number; mes: number } {
  const total = anio * 12 + (mes - 1) + delta;
  return { anio: Math.floor(total / 12), mes: (total % 12) + 1 };
}
