// ─────────────────────────────────────────────────────────────────────────────
// Faltas de conducta: lo que la pantalla necesita saber antes de llamar a la base.
//
// Módulo puro (sin React ni Supabase), para poder probarlo sin levantar nada.
// La verdad vive en la base —`faltas_catalogo` y `fn_expediente_crear_conducta`
// (0510)—; esto solo evita ofrecer lo que la base va a rechazar, y dice POR QUÉ
// no se puede guardar todavía en vez de dejar un botón gris sin explicación.
// ─────────────────────────────────────────────────────────────────────────────

import { esRolEncargada, esRolIntegrante, puedeTramitarDisciplina } from "@cayla-dynamic/shared";

export type Gravedad = "leve" | "significativa";
export type NivelConducta = "verbal" | "amonestacion";

/** Una falta del RIT, con el nombre corto con que se elige (0514). */
export interface FaltaCatalogo {
  rit_version: number;
  numeral: string;
  literal: string;
  gravedad: Gravedad;
  texto: string;
  se_registra_a_mano: boolean;
  /** Nombre corto para elegirla. El papel nunca lo usa: cita `texto`. */
  rotulo: string | null;
}

/** Clave estable de una falta dentro de su versión: «53.1.d». */
export const claveFalta = (f: Pick<FaltaCatalogo, "numeral" | "literal">) => `${f.numeral}.${f.literal}`;

/** Cómo se cita en un papel: «literal d) del numeral 53.1». El RIT 55.3 pide numeral y literal. */
export const citaDeFalta = (f: Pick<FaltaCatalogo, "numeral" | "literal">) => `literal ${f.literal}) del numeral ${f.numeral}`;

/**
 * Las faltas que se pueden elegir hoy: las de la versión vigente del RIT (la
 * mayor, como en la base) y que se registran a mano, separadas por gravedad.
 * El 53.2 a), b) y c) no aparecen: el a) lo suma el sistema y los otros dos
 * los miden los motores de tardanzas e inasistencias.
 */
export function faltasElegibles(catalogo: FaltaCatalogo[]): { leves: FaltaCatalogo[]; significativas: FaltaCatalogo[] } {
  const vigente = Math.max(0, ...catalogo.map((f) => Number(f.rit_version)));
  const elegibles = catalogo
    .filter((f) => Number(f.rit_version) === vigente && f.se_registra_a_mano)
    .sort((a, b) => claveFalta(a).localeCompare(claveFalta(b)));
  return {
    leves: elegibles.filter((f) => f.gravedad === "leve"),
    significativas: elegibles.filter((f) => f.gravedad === "significativa"),
  };
}

/** Lo mínimo que la pantalla sabe de quien está conectada. */
export interface QuienRegistra { id: string; rol: string | null; sedeBaseId: string | null; enPlanilla: boolean }
/** Lo mínimo que la pantalla sabe de a quién se le registraría. */
export interface Candidata { id: string; rol: string | null; sede_base_id: string | null; estado: string; en_planilla: boolean }

/**
 * ¿Se le ofrece registrar una falta a `yo` sobre `p`? Espeja la base (0510):
 * solo a quien el régimen disciplinario alcanza —activa y con contrato de
 * trabajo, RIT 2.5 y 2.6—, nunca a sí misma, y la líder solo a integrantes de
 * su sede (a otra líder la amonesta DO).
 */
export function puedeRegistrarleConducta(yo: QuienRegistra, p: Candidata): boolean {
  if (!puedeTramitarDisciplina(yo.rol, yo.enPlanilla)) return false;
  if (p.estado !== "activo" || !p.en_planilla || p.id === yo.id) return false;
  if (esRolEncargada(yo.rol)) return esRolIntegrante(p.rol) && p.sede_base_id === yo.sedeBaseId;
  return true;
}

/**
 * El nivel que viene marcado al abrir el formulario. Decidido el 2026-10-06
 * mirando el prototipo (`docs/conducta-prototipo-2026-10-06.html`, decisión 3,
 * opción B): lo que sugiere el sistema, que es lo máximo que una líder puede
 * firmar —la amonestación—. Lo que corresponde según el RIT se muestra al lado,
 * siempre, para que quede a la vista que la llamada verbal también cabe (52.10).
 */
export const NIVEL_SUGERIDO_CONDUCTA: NivelConducta = "amonestacion";

/** El relato más corto que la base acepta (`chk_conducta_completa`, 0510). */
export const RELATO_MINIMO = 20;

/**
 * Las cuatro preguntas que guían el relato. Lo que escribe la líder es lo que
 * la persona lee y lo que se discute si lo cuestiona: un hecho («le dijo X
 * delante de dos clientas») se sostiene; una opinión («fue grosera») no, y la
 * duda favorece a la colaboradora (RIT 52.8).
 */
export const PREGUNTAS_RELATO = [
  "¿Qué hizo o dijo, con sus palabras si las recuerdas?",
  "¿Dónde pasó?",
  "¿Quién más estaba?",
  "¿Lo viste tú, o cómo te enteraste?",
] as const;

export interface BorradorConducta {
  personaId: string | null;
  falta: Pick<FaltaCatalogo, "numeral" | "literal"> | null;
  fechaHecho: string;
  conocidoEl: string;
  relato: string;
  nivel: NivelConducta | null;
}

/**
 * Qué falta para poder guardar, dicho para quien lo lee — o null si ya se
 * puede. Las mismas condiciones que la base, en el orden en que se llena el
 * formulario: así la frase siempre señala el siguiente paso, no uno de abajo.
 * Las fechas son `YYYY-MM-DD`, que se comparan bien como texto.
 */
export function queFaltaParaRegistrar(b: BorradorConducta, hoy: string): string | null {
  if (!b.personaId) return "Elige a quién.";
  if (!b.falta) return "Elige qué falta fue.";
  if (!b.fechaHecho) return "Indica cuándo pasó.";
  if (b.fechaHecho > hoy) return "La fecha del hecho no puede ser futura.";
  if (!b.conocidoEl) return "Indica cuándo te enteraste.";
  if (b.conocidoEl > hoy) return "La fecha en que te enteraste no puede ser futura.";
  if (b.conocidoEl < b.fechaHecho) return "No pudiste enterarte antes de que pasara: revisa las dos fechas.";
  const faltan = RELATO_MINIMO - b.relato.trim().length;
  if (faltan > 0) return "Cuenta qué pasó, con al menos una frase completa.";
  if (!b.nivel) return "Elige qué vas a hacer.";
  return null;
}

/** Lo que devuelve `fn_conducta_antecedentes` (0510). */
export interface AntecedentesConducta {
  gravedad: Gravedad;
  texto: string;
  antecedente_vigente: { id: string; correlativo: string | null; nivel: string; entregado_at: string } | null;
  amonestaciones_leves_vigentes: number;
  significativa_por_acumulacion: boolean;
  que_corresponde: string;
}
