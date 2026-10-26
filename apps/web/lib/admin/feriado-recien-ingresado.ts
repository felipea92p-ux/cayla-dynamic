/**
 * QUIEN INGRESÓ HACE POCO Y UN FERIADO TRABAJADO, EN LO QUE UNA PANTALLA NECESITA SABER.
 *
 * QUÉ PROMETE. Una sola respuesta a «¿a esta persona le conviene a la empresa
 * ponerle trabajo este feriado?» y los textos con que Turnos lo dice. Es una
 * recomendación, no un freno: quien decide mantener el trabajo lo confirma y
 * sigue como siempre.
 *
 * POR QUÉ EXISTE. Un feriado trabajado sin día libre a cambio se paga con
 * sobretasa del 100 %. A quien acaba de ingresar, y todavía puede no seguir,
 * eso se le paga igual (nadie lo discute) pero cuesta más que darle ese día de
 * descanso. Decisión de Felipe, 2026-10-24: que el sistema lo diga ANTES de
 * poner el turno, recomiende descanso, y deje trabajar si se confirma.
 *
 * QUÉ CAMBIÓ EL 2026-10-26. Antes el aviso era solo para el vínculo «prueba»
 * (tres días trabajados, sin contrato). Ese vínculo se retira: quien trabaja se
 * registra desde el primer día y «de prueba» es una condición del contrato, no
 * un vínculo. El criterio ahora es la ANTIGÜEDAD: menos de N días CALENDARIO
 * desde el ingreso, medidos A LA FECHA DEL FERIADO (decisión de Felipe, mismo
 * día). Calendario y no «días trabajados» porque al armar el horario de la
 * semana que viene los días trabajados todavía no existen.
 *
 * El umbral (15) es política de CAYLA, no ley: vive en Parámetros
 * (`feriado_aviso_antiguedad_dias`, 0553) y aquí llega como argumento.
 *
 * QUÉ NO HACE.
 *   · No cambia un sol de lo que se paga: el pago sigue saliendo de las marcas.
 *   · No impide marcar. El terminal nunca se bloquea por esto: si la persona
 *     viene y marca, se le paga lo que trabajó.
 *   · No calcula montos ni dice «triple» como cifra: dice que se paga más y
 *     remite a la regla (Feriados). Un monto aquí envejecería en silencio.
 *   · No le quita a nadie el pago del feriado: darle descanso NO es no pagarle.
 *     El feriado no laborable se paga siempre (art. 8, D. Leg. 713), en
 *     proporción a lo trabajado en el mes (docs/planilla-anexo-tecnico.md).
 *   · No mira a practicantes ni a quien no está en planilla.
 *
 * SI FALLA LA LECTURA. Sin fecha de ingreso legible no se avisa: un aviso blando
 * que no sale no cuesta nada, y uno equivocado se aprende a ignorar.
 */

import { diasEntreFechas, esIngresoReciente, DIAS_AVISO_FERIADO_DEFECTO } from "@cayla-dynamic/shared";

export { DIAS_AVISO_FERIADO_DEFECTO };

export interface IngresoDelDia {
  /** `personas.tipo_vinculo`. Solo planilla entra (y «prueba», que se retira, mientras quede alguien). */
  tipoVinculo: string | null;
  /** `personas.fecha_ingreso`, `AAAA-MM-DD`, o `null` si no se pudo leer. */
  fechaIngreso: string | null;
}

/** El vínculo «prueba» ya no se asigna, pero quien aún lo tenga sigue siendo una persona en planilla. */
function estaEnPlanilla(tipoVinculo: string | null): boolean {
  return tipoVinculo === "planilla" || tipoVinculo === "prueba";
}

/**
 * ¿Hay que recomendar descanso? Solo en feriado, solo en planilla, y solo si en
 * `fecha` lleva menos de `umbral` días calendario desde su ingreso.
 */
export function conviveDarDescanso(p: IngresoDelDia, fecha: string, esFeriado: boolean, umbral: number = DIAS_AVISO_FERIADO_DEFECTO): boolean {
  if (!esFeriado) return false;
  if (!estaEnPlanilla(p.tipoVinculo)) return false;
  return esIngresoReciente(p.fechaIngreso, fecha, umbral);
}

/** Días calendario desde el ingreso hasta `fecha`, o `null` si no se pueden contar. */
export function diasDesdeIngreso(fechaIngreso: string | null, fecha: string): number | null {
  if (!fechaIngreso) return null;
  return diasEntreFechas(fechaIngreso, fecha);
}

/** «ingresó hace 6 días», «ingresa ese mismo día», o vacío si no se pudo contar. */
export function textoAntiguedad(dias: number | null): string {
  if (dias === null || dias < 0) return "";
  if (dias === 0) return "ingresa ese mismo día";
  return `ingresó hace ${dias} ${dias === 1 ? "día" : "días"}`;
}

/** Título del aviso dentro del editor de turno. */
export function tituloDelAviso(nombreFeriado: string | null): string {
  return nombreFeriado ? `Es feriado (${nombreFeriado}) y ingresó hace poco` : "Es feriado y ingresó hace poco";
}

/** Cuerpo del aviso: qué pasa y qué se recomienda. Siempre dice que el feriado se paga igual. */
export function cuerpoDelAviso(p: { dias: number | null }): string {
  const antig = textoAntiguedad(p.dias);
  return (
    `${antig ? `Esta persona ${antig}. ` : ""}`
    + "Si trabaja este feriado sin un día libre a cambio, se le paga con la sobretasa de feriado. "
    + "Lo recomendable es darle descanso ese día: no es dejar de pagarle, el feriado se le paga igual. "
    + "Si aun así debe venir, puedes compensarlo con otro día libre y registrarlo en Feriados (descanso sustitutorio), "
    + "o confirmarlo y sigue con su horario normal."
  );
}

/** El texto de la casilla que desbloquea los botones de guardar. */
export const TEXTO_CONFIRMAR_TRABAJO_EN_FERIADO =
  "Estoy de acuerdo: trabajará este feriado y se le pagará como corresponde";

export interface PersonaEnFeriado {
  personaId: string;
  nombre: string;
  fecha: string;
  feriado: string;
  dias: number | null;
}

/** La línea de la lista de avisos de la semana: «Mariel · Todos los Santos · ingresó hace 6 días». */
export function lineaDeSemana(p: PersonaEnFeriado, fechaCorta: string): string {
  const antig = textoAntiguedad(p.dias);
  return `${p.nombre} — ${fechaCorta} · ${p.feriado}${antig ? ` · ${antig}` : ""}`;
}

/** Texto extra del botón «Copiar semana anterior» cuando la semana destino tiene feriado y hay gente recién ingresada. */
export function avisoDeCopiar(feriados: readonly string[], hayRecienIngresados: boolean): string | null {
  if (!hayRecienIngresados || feriados.length === 0) return null;
  const que = feriados.length === 1 ? `el feriado «${feriados[0]}»` : `los feriados ${feriados.map((f) => `«${f}»`).join(" y ")}`;
  return `Esta semana hay ${que} y hay gente que ingresó hace poco en la sede: si la copia les deja turno ese día, te lo avisamos abajo para que decidas.`;
}
