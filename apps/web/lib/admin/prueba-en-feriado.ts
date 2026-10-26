/**
 * QUIEN ESTÁ DE PRUEBA Y UN FERIADO TRABAJADO, EN LO QUE UNA PANTALLA NECESITA SABER.
 *
 * QUÉ PROMETE. Una sola respuesta a «¿a esta persona le conviene a la empresa
 * ponerle trabajo este feriado?» y los textos con que Turnos lo dice. Es una
 * recomendación, no un freno: quien decide mantener el trabajo lo confirma y
 * sigue como siempre.
 *
 * POR QUÉ EXISTE. Un feriado trabajado sin día libre a cambio se paga triple.
 * A quien lleva uno o dos días de prueba, y todavía puede no seguir, eso se
 * le paga igual (nadie lo discute) pero cuesta más que darle ese día de
 * descanso. Decisión de Felipe, 2026-10-24: que el sistema lo diga ANTES de
 * poner el turno, recomiende descanso, y deje trabajar si se confirma.
 *
 * QUÉ NO HACE.
 *   · No cambia un sol de lo que se paga: el pago sigue saliendo de las marcas.
 *   · No impide marcar. El terminal nunca se bloquea por esto: si la persona
 *     viene y marca, se le paga lo que trabajó.
 *   · No calcula montos ni dice «triple» como cifra: dice que se paga más y
 *     remite a la regla (Feriados). Un monto aquí envejecería en silencio.
 *   · No mira a practicantes ni a quien ya cumplió sus días de prueba: la
 *     situación la dice la base (`fn_pruebas_abiertas`, 0536).
 *
 * SI FALLA LA LECTURA DE LA PRUEBA. `dias` llega `null` y se avisa igual por el
 * vínculo: «no se pudo contar sus días» se lee como «tal vez sí está de prueba»,
 * que es la dirección en que un aviso blando no cuesta nada.
 */

export interface PruebaDelDia {
  /** `personas.tipo_vinculo`. Solo «prueba» entra. */
  tipoVinculo: string | null;
  /** La situación que dijo la base, o `null` si no se pudo leer. */
  situacion: string | null;
  /** Días de prueba trabajados hasta hoy, o `null` si no se pudo leer. */
  dias: number | null;
  /** Días del plazo (3). */
  plazo: number | null;
}

/** ¿Hay que recomendar descanso? Solo vínculo «prueba» y prueba aún en curso (o no leída). */
export function conviveDarDescanso(p: PruebaDelDia, esFeriado: boolean): boolean {
  if (!esFeriado) return false;
  if (p.tipoVinculo !== "prueba") return false;
  // Cumplida o vencida: ya hizo sus días, toca contrato; no es quien se quiere cuidar.
  if (p.situacion === "cumplida" || p.situacion === "vencida") return false;
  return true;
}

/** «lleva 1 de 3 días de prueba», o vacío si no se pudo contar. */
export function textoDiasDePrueba(p: Pick<PruebaDelDia, "dias" | "plazo">): string {
  if (p.dias === null || p.plazo === null) return "";
  return `lleva ${p.dias} de ${p.plazo} días de prueba`;
}

/** Título del aviso dentro del editor de turno. */
export function tituloDelAviso(nombreFeriado: string | null): string {
  return nombreFeriado ? `Es feriado (${nombreFeriado}) y está de prueba` : "Es feriado y está de prueba";
}

/** Cuerpo del aviso: qué pasa y qué se recomienda. Siempre dice que se le paga. */
export function cuerpoDelAviso(p: Pick<PruebaDelDia, "dias" | "plazo">): string {
  const dias = textoDiasDePrueba(p);
  return (
    `${dias ? `Esta persona ${dias}. ` : ""}`
    + "Si trabaja este feriado se le paga con la sobretasa de feriado, porque no se le da un día libre a cambio. "
    + "Lo recomendable es darle descanso ese día. Si aun así debe venir, confírmalo y sigue con su horario normal."
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
  plazo: number | null;
}

/** La línea de la lista de avisos de la semana: «Mariel · Fiestas Patrias · lleva 1 de 3 días de prueba». */
export function lineaDeSemana(p: PersonaEnFeriado, fechaCorta: string): string {
  const dias = textoDiasDePrueba(p);
  return `${p.nombre} — ${fechaCorta} · ${p.feriado}${dias ? ` · ${dias}` : ""}`;
}

/** Texto extra del botón «Copiar semana anterior» cuando la semana destino tiene feriado y hay gente de prueba. */
export function avisoDeCopiar(feriados: readonly string[], hayPrueba: boolean): string | null {
  if (!hayPrueba || feriados.length === 0) return null;
  const que = feriados.length === 1 ? `el feriado «${feriados[0]}»` : `los feriados ${feriados.map((f) => `«${f}»`).join(" y ")}`;
  return `Esta semana hay ${que} y hay gente de prueba en la sede: si la copia les deja turno ese día, te lo avisamos abajo para que decidas.`;
}
