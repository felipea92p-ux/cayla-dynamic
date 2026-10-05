import {
  MOTIVO_PAUSA_LABELS,
  estadoPresencia,
  horaDecimalLima,
  horaLima,
  type ClaveEstadoPresencia,
  type MarcajeDelDia,
} from "@cayla-dynamic/shared";

/**
 * Lo que la casilla de cada persona dice en el terminal, ya listo para pintar.
 *
 * `estadoPresencia` (packages/shared) sabe en qué punto del día está alguien a
 * partir de sus marcajes. Esto le suma lo único que NO se sabe por las marcas:
 * el horario de hoy, para no tratar igual a quien «aún no llega» que a quien
 * hoy simplemente no trabaja.
 *
 * Es una función pura —recibe la hora— para poder probarla sin reloj.
 */

/** El horario de hoy de una persona, tal como lo carga `sugerencias.ts`. */
export interface HorarioDeHoy {
  /** "14:00" — la hora a la que le toca entrar hoy, o null si no se sabe. */
  entradaEsperada: string | null;
  /**
   * Hoy NO le toca trabajar, y eso es una respuesta (descanso en su horario o
   * en un turno puntual) y no un «no sé». Sin horario asignado es `false`: no se
   * afirma que alguien está de descanso porque falte un dato.
   */
  libreHoy: boolean;
}

export type ClavePresencia = ClaveEstadoPresencia | "libre";

export interface PresenciaCasilla {
  clave: ClavePresencia;
  /** La línea que va bajo el nombre. Se entiende sola, sin el nombre del estado. */
  detalle: string;
  /**
   * Una segunda línea, más discreta, solo cuando hace falta. Hoy: «salió 13:00 ·
   * volvió 13:45» de quien salió y regresó, para que la hora de su entrada de la
   * mañana no se pierda ni se confunda con la del regreso, y para que el regreso
   * se entienda: dice de cuándo a cuándo estuvo fuera.
   */
  detalle2?: string;
}

/** "14:00" → 14. Una sola receta; antes vivía privada en `sugerencias.ts`. */
export function horaDecimalDeHHMM(hhmm: string): number {
  const [h, m] = hhmm.slice(0, 5).split(":").map(Number);
  return h + (m || 0) / 60;
}

/** 25 → «25 min» · 75 → «1 h 15 min» · 120 → «2 h». */
function duracionCorta(minutos: number): string {
  if (minutos < 60) return `${minutos} min`;
  const h = Math.floor(minutos / 60);
  const m = minutos % 60;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

export function presenciaDeLaCasilla(
  marcas: MarcajeDelDia[],
  horario: Partial<HorarioDeHoy> | undefined,
  ahora: Date,
): PresenciaCasilla {
  const p = estadoPresencia(marcas);

  switch (p.estado) {
    case "sin_entrada": {
      if (horario?.libreHoy) return { clave: "libre", detalle: "día de descanso" };

      // «Entra 14:00» solo mientras todavía es futuro. Pasada esa hora NO se
      // dice «debía entrar»: esta pantalla la ve todo el equipo, Dynamic avisa
      // y nunca sanciona, y el peor error del sistema es acusar de más. Quien
      // llega tarde se ve igual que quien aún no llega — y el reporte de
      // tardanzas es el sitio donde eso se mide, no la pantalla de marcar.
      const entra = horario?.entradaEsperada;
      if (entra && horaDecimalDeHHMM(entra) > horaDecimalLima(ahora)) {
        return { clave: "sin_entrada", detalle: `entra ${entra.slice(0, 5)}` };
      }
      return { clave: "sin_entrada", detalle: "aún sin entrada" };
    }

    case "laborando":
      // La hora que se muestra es la de la ENTRADA del día, nunca la del regreso:
      // «desde 13:45» se leería como una llegada tardía (ver `estadoPresencia`).
      return {
        clave: "laborando",
        detalle: `entró ${horaLima(p.entrada)}`,
        ...(p.regreso
          ? {
              detalle2: p.regreso.salio
                ? `salió ${horaLima(p.regreso.salio)} · volvió ${horaLima(p.regreso.volvio)}`
                : `volvió ${horaLima(p.regreso.volvio)}`,
            }
          : {}),
      };

    case "refrigerio": {
      // Si el reloj de esta Mac va unos segundos atrás de la marca, el
      // resultado es negativo: se dice «recién salió», nunca un número raro.
      const minutos = Math.floor((ahora.getTime() - new Date(p.desde).getTime()) / 60_000);
      return {
        clave: "refrigerio",
        detalle: minutos >= 1 ? `salió hace ${duracionCorta(minutos)}` : "recién salió",
      };
    }

    case "pausa":
      return { clave: "pausa", detalle: `${MOTIVO_PAUSA_LABELS[p.motivo] ?? "Salida"} · ${horaLima(p.desde)}` };

    case "termino":
      return { clave: "termino", detalle: `salió a las ${horaLima(p.a)}` };
  }
}
