// ============================================================================
// marcaje-faltante.ts — con qué arranca «Agregar un marcaje faltante»
// ============================================================================
// QUÉ PROMETE · proponer el marcaje que le falta al día y la hora a la que le
//               tocaba según su horario, para que el formulario de Correcciones
//               no arranque en «Entrada · 08:00» para todo el mundo.
// QUÉ ASUME   · que «qué marca toca» lo decide `determinarSiguienteAccion`
//               (packages/shared, la misma que usa el terminal) y que «qué le
//               tocaba ese día» lo decide `esperadoDelDia` (jornada-esperada.ts).
//               Aquí no se vuelve a escribir ninguna de las dos.
//
// POR QUÉ ASÍ · se pidió el 2026-10-13. La alternativa que se planteó primero
//   —arrancar en la hora en que se hace la corrección— se descartó: ese campo
//   dice cuándo entró o salió la persona, no cuándo se corrige (eso ya lo guarda
//   la auditoría), y casi toda corrección es de algo que ya pasó. Un clic sin
//   mirar habría registrado una entrada a las 4 de la tarde: tardanza falsa y
//   horas de menos. Con la hora del horario, ese mismo clic sin mirar deja a la
//   persona como puntual, que es el error barato (CLAUDE.md: «los falsos
//   positivos son el peor error»).
//
// Y una salvaguarda que no se ve: no se propone una marca que todavía no puede
// haber pasado. Si el día es hoy y su hora de salida aún no llega, la persona
// no «olvidó» marcar la salida: sigue trabajando. Proponérsela —y que alguien
// la aceptara sin mirar— le cerraría el día en el terminal a quien está en la
// tienda. `fn_agregar_marcaje` no rechaza horas futuras, así que esto no lo
// para nadie más.
//
// Es solo un valor de arranque: la persona del panel lo cambia con un clic, y
// lo que elija manda sobre la sugerencia.
// ============================================================================
import { determinarSiguienteAccion, type MarcajeDelDia, type TipoMarca } from "@cayla-dynamic/shared";
import type { Esperado } from "@/lib/admin/jornada-esperada";

/** Cuándo se está mirando, en hora de Lima: el día abierto, hoy y la hora actual ("HH:MM"). */
export interface Momento {
  fecha: string;
  hoy: string;
  ahora: string;
}

/** ¿Esa hora de ese día ya pasó? Un día anterior a hoy, entero; hoy, hasta `ahora`. */
function yaPaso(hhmm: string, { fecha, hoy, ahora }: Momento): boolean {
  return fecha < hoy || (fecha === hoy && hhmm <= ahora);
}

/**
 * A qué hora le tocaba ese tipo de marca según su horario de ese día, o `null`
 * si el horario no lo dice: sin horario, día de descanso, un tipo que el horario
 * no fija (refrigerio, trámites…) o una hora que todavía no llega.
 */
export function horaDelHorario(tipo: TipoMarca, esperado: Esperado | null, momento: Momento): string | null {
  const hora = tipo === "entrada" ? esperado?.entrada : tipo === "salida_final" ? esperado?.salida : null;
  return hora && yaPaso(hora, momento) ? hora : null;
}

/**
 * Qué marcaje le falta al día, o `null` si no hay uno que proponer.
 *
 * `marcas` son las del día SIN las anuladas (no cuentan para la jornada, y la
 * máquina del terminal tampoco las ve).
 *
 * - Sin entrada → «Entrada».
 * - Con una salida temporal abierta → su retorno (el único posible).
 * - Adentro, sin salida final → «Salida final», pero solo si el día ya terminó:
 *   un día anterior, u hoy con su hora de salida ya pasada.
 * - Día cerrado → nada: no falta ninguna marca, y adivinar cuál quiere agregar
 *   no le toca a esta función.
 */
export function tipoQueFalta(marcas: MarcajeDelDia[], esperado: Esperado | null, momento: Momento): TipoMarca | null {
  const siguiente = determinarSiguienteAccion(marcas);
  if (siguiente.modo === "unico") return siguiente.tipo;
  if (siguiente.modo === "cerrado") return null;
  const diaTerminado = momento.fecha < momento.hoy || horaDelHorario("salida_final", esperado, momento) !== null;
  return diaTerminado ? "salida_final" : null;
}
