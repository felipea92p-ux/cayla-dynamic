// Lo pagado FUERA de la planilla (el libro de desembolsos) que la boleta
// muestra debajo del total, sin sumarlo (0622, pedido de Felipe el 2026-11-25:
// «¿y dónde aparece la CTS que ya pagué, de cada uno?»).
//
// Vive aparte de `boleta-hoja.tsx` para poder probar los textos sin React
// (`tests/boleta-depositos.test.ts`): lo que dice un papel que la persona se
// lleva no se revisa a ojo.
//
// Los nombres son los LEGALES —«Gratificación», «CTS»— por la decisión del
// 2026-07-28 que la 0621 terminó de cumplir: un derecho de ley no se llama
// «bono» en un papel de CAYLA.

import { fechaCorta } from "@/lib/admin/planilla/formato";

/** Una fila de `fn_boleta_depositos` (0622). */
export interface DepositoBoleta {
  ventana: string;
  anio: number;
  monto: number;
  fecha_pago: string;
  origen: string;
}

/** El semestre o el beneficio que se pagó, con su nombre legal. */
export function nombreDeposito(d: Pick<DepositoBoleta, "ventana" | "anio">): string {
  switch (d.ventana) {
    case "grati_s1":
      return `Gratificación ene–jun ${d.anio}`;
    case "grati_s2":
      return `Gratificación jul–dic ${d.anio}`;
    // La CTS de mayo cubre noviembre del año ANTERIOR a abril; la del libro se
    // guarda con el año del depósito (0163), así que el semestre empieza en anio-1.
    case "cts_may":
      return `CTS nov ${d.anio - 1}–abr ${d.anio}`;
    case "cts_nov":
      return `CTS may–oct ${d.anio}`;
    case "vacaciones":
      return "Vacaciones";
    case "subvencion_semestral":
      return "Media subvención";
    case "descanso_practicante":
      return "Descanso de 15 días";
    default:
      return d.ventana;
  }
}

/** Dónde fue la plata y cuándo. La CTS no se paga en mano: va a la cuenta CTS. */
export function detalleDeposito(d: Pick<DepositoBoleta, "ventana" | "fecha_pago">): string {
  const cuando = fechaCorta(d.fecha_pago);
  return d.ventana.startsWith("cts_")
    ? `depositada en tu cuenta CTS el ${cuando}`
    : `pagada el ${cuando}, aparte de este pago`;
}
