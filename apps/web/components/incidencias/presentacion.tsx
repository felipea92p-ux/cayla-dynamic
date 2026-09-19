// Cómo se lee cada incidencia en pantalla: su ícono, su nombre, la regla que la
// disparó y qué se puede hacer con ella. Un solo lugar para las dos superficies
// que la explican —el panel «Cómo se detectan» y el drawer de un caso—, para
// que no digan la regla con palabras distintas. La detección vive en
// lib/admin/incidencias.ts; acá no se decide nada, solo se nombra.

import {
  Building2, CalendarX2, Clock, Coffee, DoorOpen, FileCheck2, Gauge, LogOut, MoonStar, Repeat,
  type LucideIcon,
} from "lucide-react";
import { MAXIMO_DIAS_SIN_DESCANSO, MAXIMO_LEGAL_SEMANAL, TZ_LIMA } from "@cayla-dynamic/shared";
import { cx } from "@/components/ui/cx";
import {
  estadoDe, UMBRAL_PATRON_TARDANZAS, VENTANA_EXCESO_DIAS, VENTANA_PATRON_DIAS,
  type Incidencia, type TipoAceptable, type TipoIncidencia,
} from "@/lib/admin/incidencias";

// ── Formato ────────────────────────────────────────────────────────────────

/** «vie, 04 set.» — días de calendario, sin corrimiento de huso. */
export function fechaCorta(f: string): string {
  const [y, m, d] = f.split("-").map(Number);
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, weekday: "short", day: "2-digit", month: "short" })
    .format(new Date(Date.UTC(y, m - 1, d, 12)));
}
/** «Viernes, 4 de setiembre de 2026». Solo la primera letra en mayúscula: la
 * clase `capitalize` las ponía en cada palabra («De Setiembre De»). */
export function fechaLarga(f: string): string {
  const [y, m, d] = f.split("-").map(Number);
  const texto = new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, weekday: "long", day: "numeric", month: "long", year: "numeric" })
    .format(new Date(Date.UTC(y, m - 1, d, 12)));
  return texto.charAt(0).toUpperCase() + texto.slice(1);
}
/** Hora de Lima en 24 h, «14:15». Tabular, para que las columnas alineen. */
export function horaLima(ts: string | null): string {
  if (!ts) return "—";
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, hour: "2-digit", minute: "2-digit", hour12: false })
    .format(new Date(ts));
}
export function fechaHoraLima(ts: string): string {
  return new Intl.DateTimeFormat("es-PE", { timeZone: TZ_LIMA, day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: false })
    .format(new Date(ts));
}

// ── Qué es cada tipo ───────────────────────────────────────────────────────

const ICONO: Record<TipoIncidencia, LucideIcon> = {
  auto_cierre: MoonStar,
  sin_salida: DoorOpen,
  sin_retorno_almuerzo: Coffee,
  salida_anticipada: LogOut,
  patron_tardanzas: Clock,
  jornada_excedida_viva: Gauge,
  jornada_excedida: Gauge,
  racha_preventiva: Repeat,
  racha_sin_descanso: Repeat,
  deficit_encargadas: Building2,
  falta_injustificada: CalendarX2,
  falta_justificada: FileCheck2,
};

/** Ícono + texto, nunca solo color. Rojo únicamente para lo alto que sigue sin decisión. */
export function IconoIncidencia({ incidencia, className }: { incidencia: Incidencia; className?: string }) {
  const Icono = ICONO[incidencia.tipo];
  const urgente = incidencia.severidad === "alta" && estadoDe(incidencia) !== "resuelta";
  return (
    <span
      aria-hidden
      className={cx(
        "grid size-7 shrink-0 place-items-center rounded-control",
        urgente ? "bg-rojo/10 text-rojo-profundo" : "bg-hueso text-taupe",
        className,
      )}
    >
      <Icono className="size-4" strokeWidth={1.75} />
    </span>
  );
}

/** Nombre de cada tipo en el filtro. */
export const NOMBRE_TIPO: Record<TipoIncidencia, string> = {
  auto_cierre: "Auto-cerrada",
  sin_salida: "Sin salida final",
  sin_retorno_almuerzo: "Sin retorno del almuerzo",
  salida_anticipada: "Salida anticipada",
  patron_tardanzas: "Patrón de tardanzas",
  jornada_excedida_viva: "Jornada excedida (esta semana)",
  jornada_excedida: "Jornada excedida (ya ocurrió)",
  racha_preventiva: "6 días seguidos (preventivo)",
  racha_sin_descanso: "Días seguidos sin descanso",
  deficit_encargadas: "Déficit de líderes",
  falta_injustificada: "Falta injustificada",
  falta_justificada: "Falta justificada",
};

/** Qué tipos siguen el filtro Desde/Hasta. Los demás se miden sobre ventanas
 * fijas y se dice en pantalla, para que el periodo no prometa lo que no filtra. */
export const SIGUE_EL_PERIODO: ReadonlySet<TipoIncidencia> = new Set([
  "auto_cierre", "sin_salida", "sin_retorno_almuerzo", "salida_anticipada", "falta_injustificada", "falta_justificada",
]);

/** Por qué salió el aviso, en una o dos frases. */
export const REGLA: Record<TipoIncidencia, string> = {
  auto_cierre:
    "No marcó salida y el sistema cerró el día a su hora programada. Falta confirmar la hora real en Correcciones; al hacerlo, el aviso se va solo.",
  sin_salida:
    "Hay entrada y no hay salida, y el día ya pasó. Se va solo en cuanto se registra la salida en Correcciones.",
  sin_retorno_almuerzo:
    "Hay marca de salida al refrigerio y no de retorno. El sistema no sabe si volvió sin marcar o si trabajó de corrido: si volvió, registra las marcas en Correcciones; si trabajó de corrido, confírmalo.",
  salida_anticipada:
    "Salió más de 15 minutos antes de su hora de ese día (turno del día, si no el horario por día, si no el horario base). Dentro de los 15 minutos no se marca.",
  patron_tardanzas:
    `${UMBRAL_PATRON_TARDANZAS} o más tardanzas sin levantar en los últimos ${VENTANA_PATRON_DIAS} días corridos, solo para quien está en planilla. ` +
    "No es el conteo que arma un memo: el reglamento interno cuenta por mes calendario, y eso vive en Disciplina.",
  jornada_excedida_viva:
    `Más de ${MAXIMO_LEGAL_SEMANAL} h en una ventana de 7 días seguidos que termina esta semana (una practicante preprofesional: 30 h). ` +
    "Es el máximo legal, no un objetivo, y todavía se puede mover un turno. No se avisa al personal de dirección: la ley lo excluye de la jornada máxima.",
  jornada_excedida:
    `Pasó de ${MAXIMO_LEGAL_SEMANAL} h en 7 días seguidos hace más de una semana (se mira hasta ${VENTANA_EXCESO_DIAS} días atrás). ` +
    "Ya no se puede evitar: marcarla revisada deja constancia de quién la vio. El recargo del sobretiempo se paga aparte y no levanta el tope. " +
    "No se avisa al personal de dirección: la ley lo excluye de la jornada máxima.",
  racha_preventiva:
    `Lleva ${MAXIMO_DIAS_SIN_DESCANSO} días seguidos trabajando: el siguiente le toca descansar. El descanso se cuenta en ciclos de 7 días, no por semana de calendario. ` +
    "El aviso se va solo en cuanto descansa.",
  racha_sin_descanso:
    `Trabajó más de ${MAXIMO_DIAS_SIN_DESCANSO} días seguidos sin su descanso semanal. La infracción ya ocurrió: marcarla revisada deja constancia. ` +
    "Si la racha sigue creciendo, el aviso vuelve con el día nuevo.",
  deficit_encargadas:
    "Ese día la sede tiene menos líderes programados que su mínimo (se configura en Turnos). Mira esta semana y la siguiente, para avisar mientras todavía se puede reprogramar.",
  falta_injustificada:
    "Le tocaba trabajar según su turno u horario, no marcó, no era feriado y su contrato seguía vigente. " +
    "Justificarla la saca del conteo; sin justificar, puede entrar a un expediente en Disciplina.",
  falta_justificada:
    "Le tocaba trabajar y no marcó, pero una ausencia, vacaciones, suspensión o descanso sustitutorio cubre ese día. No cuenta como falta.",
};

/** El orden en que se explican en «Cómo se detectan»: de lo más frecuente a lo más raro. */
export const REGLAS_EN_ORDEN: readonly { titulo: string; tipos: TipoIncidencia[] }[] = [
  { titulo: "Salida anticipada", tipos: ["salida_anticipada"] },
  { titulo: "Sin salida, auto-cierre, sin retorno del almuerzo", tipos: ["sin_salida", "auto_cierre", "sin_retorno_almuerzo"] },
  { titulo: "Falta injustificada", tipos: ["falta_injustificada"] },
  { titulo: "Patrón de tardanzas", tipos: ["patron_tardanzas"] },
  { titulo: "Jornada excedida", tipos: ["jornada_excedida_viva", "jornada_excedida"] },
  { titulo: "Días sin descanso", tipos: ["racha_preventiva", "racha_sin_descanso"] },
  { titulo: "Déficit de líderes", tipos: ["deficit_encargadas"] },
];

// ── Qué se puede hacer ─────────────────────────────────────────────────────

/**
 * Lo que un visto bueno sobre un incumplimiento de la empresa NO dice. Un exceso
 * de 48 h o una racha sin descanso son de CAYLA, no de la persona; la compensación
 * se paga en la planilla (recargo del sobretiempo desde la 0185, sobretasa del
 * descanso semanal trabajado desde la 0280) y esta pantalla no la verifica. Sin
 * esa frase, «revisada» se lee como «resuelta».
 */
export const COMPENSACION_NO_COMPROBADA: Record<"racha_sin_descanso" | "jornada_excedida", string> = {
  racha_sin_descanso:
    "La sobretasa por trabajar el descanso semanal se paga en la planilla; esta constancia no comprueba que se haya pagado.",
  jornada_excedida:
    "El recargo del sobretiempo se paga en la planilla; esta constancia no comprueba que se haya pagado.",
};

/** El texto del visto bueno dice QUÉ se está afirmando (decisión de Felipe,
 * 2026-09-15). En el almuerzo esa afirmación decide cuántas horas se pagan. */
export const VISTO_BUENO: Record<TipoAceptable, { boton: string; ayuda: string }> = {
  salida_anticipada: {
    boton: "Dar por válida",
    ayuda:
      "Confirmas que salió antes con tu conocimiento. No cambia marcas ni horas: el día se paga tal como está calculado. " +
      "Si fue un error de marca, corrígela en vez de usar esto. Si después una corrección cambia los minutos, el aviso vuelve.",
  },
  sin_retorno_almuerzo: {
    boton: "Trabajó de corrido",
    ayuda:
      "Confirmas que no tomó refrigerio y siguió trabajando: el día se paga tal como está calculado. " +
      "Si sí almorzó, no uses esto: registra en Correcciones la hora en que salió y la hora en que volvió.",
  },
  racha_sin_descanso: {
    boton: "Marcar revisada",
    ayuda:
      "Dejas constancia de que viste esta racha. No la borra: queda quién la revisó y cuándo. " +
      "La racha ya pasó y no se puede deshacer — esto solo dice que no se te escapó. " +
      COMPENSACION_NO_COMPROBADA.racha_sin_descanso,
  },
  jornada_excedida: {
    boton: "Marcar revisada",
    ayuda:
      "Dejas constancia de que viste este exceso. No lo borra: queda quién lo revisó y cuándo. " +
      "Pasar de 48 h no se arregla pagando el recargo: es un tope. " +
      COMPENSACION_NO_COMPROBADA.jornada_excedida,
  },
};

export type Accion =
  | { etiqueta: string; tipo: "panel" }
  | { etiqueta: string; tipo: "enlace"; href: string };

/** Adónde se resuelve cada caso fuera de esta pantalla, o null si se resuelve acá. */
export function enlaceDe(i: Incidencia): { etiqueta: string; href: string } | null {
  if (!i.personaId) return { etiqueta: "Ver turnos", href: `/admin/turnos?fecha=${i.fecha}` };
  switch (i.tipo) {
    case "auto_cierre":
    case "sin_salida":
    case "sin_retorno_almuerzo":
    case "salida_anticipada":
      return { etiqueta: "Corregir marcas", href: `/admin/correcciones?persona=${i.personaId}&fecha=${i.fecha}` };
    case "jornada_excedida_viva":
    case "racha_preventiva":
      return { etiqueta: "Ver turnos", href: `/admin/turnos?fecha=${i.fecha}` };
    // Disciplina y Ausencias no leen parámetros de la URL: un «?persona=» ahí
    // prometería un salto que no existe.
    case "patron_tardanzas":
      return { etiqueta: "Ver en Disciplina", href: "/admin/disciplina" };
    default:
      return null;
  }
}

/** El botón de la fila. Si el caso se resuelve en otra pantalla, lleva ahí;
 * si se decide acá (visto bueno, justificar), abre el caso. */
export function accionDe(i: Incidencia): Accion {
  if (estadoDe(i) === "resuelta") return { etiqueta: "Ver", tipo: "panel" };
  if (i.tipo === "falta_injustificada") return { etiqueta: "Justificar", tipo: "panel" };
  if (i.aceptable) return { etiqueta: "Revisar", tipo: "panel" };
  const enlace = enlaceDe(i);
  if (enlace) return { ...enlace, etiqueta: enlace.etiqueta === "Corregir marcas" ? "Corregir" : enlace.etiqueta, tipo: "enlace" };
  return { etiqueta: "Ver", tipo: "panel" };
}
