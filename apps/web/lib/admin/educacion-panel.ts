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
import { esPagoUnicoAprobadoSinFecha, esPagoUnicoSustentado } from "@cayla-dynamic/shared";

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
      // Un pago único tiene UNA fecha, no un calendario. Mensual, por ciclo, otra y sin decir siguen con
      // la frase de siempre: su NULL es ambiguo («nadie dijo cuándo» o «ya no hay más pagos») y eso sigue
      // siendo una decisión abierta (0549).
      if (s.frecuencia_pago === "unico") {
        // Con constancia aprobada, el estado es el de la base de ANTES de la 0549 (main se publica sola y la
        // migración se pega a mano): ahí el consejo «escribe la fecha» EMPEORA el estudio, porque guardar una
        // fecha lo pasa a «falta enviar» y pide constancia de un pago ya sustentado. Se dice lo cierto y no se
        // aconseja nada que dañe. Sin aprobada, «falta la fecha» es cierto antes y después de pegarla.
        if (esPagoUnicoAprobadoSinFecha(s.estado_constancia, s.frecuencia_pago, s.aprobadas)) {
          return "Este pago único ya tiene su constancia aprobada. No hace falta una fecha; si el estudio ya terminó, puedes cerrar la asignación.";
        }
        return "Falta la fecha del pago, así que el sistema todavía no le pide constancia ni cuenta plazos. "
          + "Escribe la «Fecha del pago» y guárdala. Si ya no va a pagar, cierra la asignación.";
      }
      return "No se sabe cuándo toca su próximo pago a la institución, así que el sistema todavía no le pide constancia ni cuenta plazos. "
        + "Elige «Paga a su institución» y el «Próximo pago» y guarda el calendario. Si ya no va a pagar más, cierra la asignación."
        // Frecuencia en blanco + constancia aprobada: puede ser un pago único que nadie marcó como tal. Es la
        // pregunta de DO («si es pago único, ¿para qué me pide calendario?»): en un pago único la fecha es
        // opcional. Mensual, por ciclo y otra no llevan esta frase.
        + (!s.frecuencia_pago && s.aprobadas > 0
          ? " Ya tiene una constancia aprobada. Si fue un pago único, elige «Pago único» y guarda: la fecha es opcional."
          : "");
    case "al_dia":
      // Lo que la base contestó, no una cuenta nueva: ver `esPagoUnicoSustentado`.
      if (esPagoUnicoSustentado(s)) {
        return "Pago único registrado: no hay más pagos que sustentar. Si el estudio ya terminó, puedes cerrar la asignación.";
      }
      if (s.frecuencia_pago === "unico" && s.proxima_fecha_pago) {
        return `Está al día. Su pago único es el ${fechaCorta(s.proxima_fecha_pago)}.`;
      }
      return s.proxima_fecha_pago ? `Está al día. Su próximo pago es el ${fechaCorta(s.proxima_fecha_pago)}.` : "Está al día.";
    default:
      // por_vencer, vencida y falta_enviar: la base ya dijo de qué pago y hasta cuándo.
      return s.fecha_pago_constancia
        ? `Falta la constancia del pago del ${fechaCorta(s.fecha_pago_constancia)}${s.plazo ? `, plazo ${fechaCorta(s.plazo)}` : ""}.`
        : "Está pendiente la constancia de su próximo pago.";
  }
}

/**
 * LO QUE MUESTRA EL BLOQUE «Paga a su institución» DEL CAJÓN, según lo que DO tiene elegido en el
 * formulario (`frecuencia`, `proxima`: aún sin guardar) y lo que la base devolvió (`s`).
 *
 * PROMETE: que el botón nunca pida guardar «una fecha» cuando lo único que cambió es la frecuencia, y
 * que un pago único ya sustentado no muestre un campo de fecha vacío que parezca pedir algo.
 * ASUME: `esPagoUnicoSustentado` solo da true con la base de la 0549; sin ella, el campo se ve como siempre.
 * NO HACE: no decide el estado ni afirma qué hará el SQL al guardar una fecha.
 */
export function formularioDeCalendario(
  s: Pick<Situacion, "estado_constancia" | "frecuencia_pago" | "proxima_fecha_pago" | "fecha_pago_constancia">,
  frecuencia: string,
  proxima: string,
): {
  esUnico: boolean;
  /** Un pago único ya sustentado no pide fecha: se esconde el campo y se deja la frase. */
  ocultaFecha: boolean;
  /** Qué decir en lugar del campo; null si el campo se ve. */
  nota: string | null;
  rotuloBoton: string;
  /** Nada cambió respecto a lo guardado. */
  sinCambios: boolean;
} {
  const esUnico = frecuencia === "unico";
  // Se esconde solo si DO sigue en «Pago único»: si cambia la frecuencia a «Otra» o «Mensual» (hubo un
  // segundo pago) el campo vuelve, con la fecha que ya estaba guardada.
  const ocultaFecha = esUnico && esPagoUnicoSustentado(s);
  const cambioFrecuencia = frecuencia !== (s.frecuencia_pago ?? "");
  const cambioFecha = proxima !== (s.proxima_fecha_pago ?? "");
  const rotuloBoton = !esUnico
    ? "Guardar calendario"
    // Solo cambió la frecuencia: guardar eso no es «guardar una fecha», y la fecha de un pago único es opcional.
    : cambioFrecuencia && !cambioFecha ? "Guardar" : "Guardar fecha del pago";
  return {
    esUnico,
    ocultaFecha,
    nota: ocultaFecha
      ? "Pago único registrado: no hace falta una fecha. Si hubo un segundo pago, cambia la frecuencia a «Otra» o «Mensual»."
      : null,
    rotuloBoton,
    sinCambios: !cambioFrecuencia && !cambioFecha,
  };
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
