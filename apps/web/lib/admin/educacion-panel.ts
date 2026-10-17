/**
 * LO QUE DICE EL PANEL DE UN ESTUDIO — la frase de arriba y el mes de cada constancia.
 *
 * PROMETE: contestar, sin tocar la base ni el navegador, tres preguntas que DO se hace al
 *   abrir un estudio: ¿qué toca hacer ahora?, ¿cuál es la última constancia aprobada y a
 *   qué mes de la cuadrícula pertenece?, y ¿hay algo que merezca una segunda mirada?
 * ASUME: el estado ya lo contestó la base (`fn_educacion_situacion`, `s.estado_constancia`)
 *   y las constancias vienen de `fn_educacion_entregas`. Acá solo se ponen en palabras.
 * NO HACE: no calcula si una constancia falta, vence o está al día —ese cálculo vive en la
 *   base y tener dos es cómo empiezan a discrepar—, no acusa un mes sin constancia y no
 *   toca lo que se paga.
 *
 * Nació de un caso real (2026-10-17): una constancia aprobada con fecha de pago de junio de
 * 2024 no mostraba su check en la cuadrícula —que abre en los últimos seis meses— y el panel
 * solo decía «Sin calendario de pagos» y «No hay constancias por revisar»: nada que explicara
 * que el check existía, pero en una columna que nadie estaba mirando.
 *
 * SE ROMPE SI: alguien agrega aquí un caso que decide el estado por su cuenta (por ejemplo,
 * «si pasaron 30 días es que falta»). Las frases dicen lo que la base ya dijo.
 */

import type { Entrega, Situacion } from "./educacion-tipos";
import {
  MESES_INICIALES, mesDe, mesLargo, mesesDeLaEntrega, mesesEntre, etiquetaMes, type CoberturaMes,
} from "./educacion-meses";
import { fechaCorta } from "@/lib/educacion";

/** La constancia aprobada más reciente por fecha de pago; el empate lo deshace el envío y, al final, el id. */
export function ultimaAprobada(entregas: readonly Entrega[]): Entrega | null {
  const aprobadas = entregas.filter((e) => e.estado === "aprobada");
  if (aprobadas.length === 0) return null;
  return [...aprobadas].sort(
    (a, b) => b.fecha_pago.localeCompare(a.fecha_pago) || b.enviada_at.localeCompare(a.enviada_at) || b.id.localeCompare(a.id),
  )[0];
}

/**
 * Los meses de la cuadrícula en que cuenta una constancia, en palabras: «jun 2024», o
 * «jul – dic 2026» si es un pago adelantado. Es la misma respuesta que usa la cuadrícula
 * (`mesesDeLaEntrega`), para que el panel y la casilla nunca digan meses distintos.
 */
export function mesesQueCuenta(e: Entrega, coberturas?: ReadonlyMap<string, readonly CoberturaMes[]>): string {
  const meses = [...mesesDeLaEntrega(e, coberturas)].sort();
  const primero = meses[0], ultimo = meses[meses.length - 1];
  if (primero === ultimo) return mesLargo(primero);
  const a = etiquetaMes(primero), b = etiquetaMes(ultimo);
  return a.anio === b.anio ? `${a.corto} – ${b.corto} ${b.anio}` : `${mesLargo(primero)} – ${mesLargo(ultimo)}`;
}

/** «este mes», «el mes pasado», «hace 28 meses». `mes` y `hoy` son del mismo calendario de Lima. */
export function haceCuanto(mes: string, hoy: string): string {
  const n = mesesEntre(mes, mesDe(hoy));
  if (n === 0) return "este mes";
  if (n === 1) return "el mes pasado";
  if (n < 0) return "de un mes que todavía no llega";
  return `hace ${n} meses`;
}

export interface ResumenDelPanel {
  /** Qué toca hacer ahora, o cómo está, en una frase. */
  frase: string;
  /** La última constancia aprobada y a qué mes pertenece; null si todavía no se leyeron o no hay. */
  ultima: string | null;
  /** Algo que merece una segunda mirada; null si no hay nada. */
  ojo: string | null;
}

function fraseDelEstado(s: Situacion): string {
  switch (s.estado_constancia) {
    case "pendiente_revision":
      return "Hay una constancia esperando revisión: más abajo puedes aprobarla o rechazarla.";
    case "rechazada":
      return "Se rechazó la última; se espera que la integrante envíe la corregida.";
    case "sin_calendario":
      return "No se sabe cuándo toca su próximo pago a la institución, así que el sistema todavía no le pide constancia ni cuenta plazos. "
        + "Elige «Paga a su institución» y el «Próximo pago» y guarda el calendario. Si ya no va a pagar más, cierra la asignación.";
    case "al_dia":
      return s.proxima_fecha_pago ? `Está al día. Su próximo pago es el ${fechaCorta(s.proxima_fecha_pago)}.` : "Está al día.";
    default:
      // por_vencer, vencida y falta_enviar: la base ya dijo de qué pago y hasta cuándo.
      return s.fecha_pago_constancia
        ? `Falta la constancia del pago del ${fechaCorta(s.fecha_pago_constancia)}${s.plazo ? `, plazo ${fechaCorta(s.plazo)}` : ""}.`
        : "Está pendiente la constancia de su próximo pago.";
  }
}

/**
 * El resumen del panel. `entregas` es null mientras llegan: sin ellas no se dice nada de «la
 * última», y la frase del estado —que no las necesita— sale igual.
 */
export function resumenDelPanel(
  s: Situacion,
  entregas: readonly Entrega[] | null,
  hoy: string,
  coberturas?: ReadonlyMap<string, readonly CoberturaMes[]>,
): ResumenDelPanel {
  const frase = fraseDelEstado(s);
  if (entregas === null) return { frase, ultima: null, ojo: null };

  const ultima = ultimaAprobada(entregas);
  if (!ultima) {
    return { frase, ultima: s.aprobadas === 0 ? "Todavía no tiene ninguna constancia aprobada." : null, ojo: null };
  }

  const cuenta = mesesQueCuenta(ultima, coberturas);
  const meses = [...mesesDeLaEntrega(ultima, coberturas)].sort();
  const ultimoMes = meses[meses.length - 1];
  const hace = haceCuanto(ultimoMes, hoy);
  const texto = `Última constancia aprobada: pago del ${fechaCorta(ultima.fecha_pago)}, cuenta para ${cuenta} (${hace}).`;

  // La cuadrícula abre en los últimos `MESES_INICIALES` meses: una constancia más vieja existe, pero su check
  // queda en una columna que nadie está mirando. Solo se señala cuando el estudio sigue en marcha.
  const lejos = mesesEntre(ultimoMes, mesDe(hoy)) >= MESES_INICIALES;
  const enMarcha = s.vigencia === "vigente" || s.vigencia === "por_terminar";
  const ojo = lejos && enMarcha
    ? `Esa constancia es de ${cuenta}, así que su check no sale entre los últimos ${MESES_INICIALES} meses de la cuadrícula. `
      + "Si esa no es la fecha real del pago, se corrige rechazando la aprobación en «Aprobadas del ciclo» y cargándola de nuevo con la fecha correcta."
    : null;

  return { frase, ultima: texto, ojo };
}
