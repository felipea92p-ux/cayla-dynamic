/**
 * LOS GRUPOS DE LA PANTALLA DE EDUCACIÓN — «¿en qué punto está cada persona?»
 *
 * PROMETE: contestar, con una sola cuenta, a qué grupo pertenece cada estudio
 *   (por el estado de SU CONSTANCIA) y quién todavía no pidió nada.
 * ASUME: las filas de `fn_educacion_situacion` (una por estudio) y las personas
 *   activas de `fn_educacion_candidatos`. No lee la base.
 * NO HACE: no toca lo que se paga. Aprobar o rechazar una constancia es solo
 *   alerta (0450); lo que decide si un apoyo paga es `paga`, y viene aparte.
 *
 * ── POR QUÉ SE AGRUPA POR CONSTANCIA Y NO POR APOYO ────────────────────────
 * Un apoyo paga desde que tiene UNA constancia aprobada; las de los meses
 * siguientes no cambian el pago. Por eso en una misma pantalla conviven
 * «3 constancias vencidas» y «3 apoyos pagándose». Para una auditoría lo que
 * importa es la constancia de cada pago —es el respaldo de que el apoyo no es
 * remuneración—, así que el grupo sale de ahí y «¿paga?» va como columna.
 *
 * ── LA TRAMPA DE `al_dia` ──────────────────────────────────────────────────
 * `al_dia` quiere decir «el próximo pago todavía no llega», no «ya entregó y se
 * aprobó». Un estudio recién registrado, sin ninguna constancia, también es
 * `al_dia`. Por eso «Al día» exige además `aprobadas > 0`: sin eso la pestaña
 * le diría a un auditor que hay respaldo donde no hay ninguno.
 */

import { ESTADO_CONSTANCIA, type EstadoConstancia, type TonoEstado } from "@cayla-dynamic/shared";

export type GrupoEducacion = "al_dia" | "por_revisar" | "por_completar" | "en_falta" | "sin_solicitar";

export const GRUPOS_EDUCACION: { clave: GrupoEducacion; etiqueta: string; ayuda: string }[] = [
  { clave: "al_dia", etiqueta: "Al día", ayuda: "Tienen constancia aprobada y su próximo pago todavía no llega." },
  { clave: "por_revisar", etiqueta: "Por revisar", ayuda: "Enviaron una constancia y espera a Desarrollo Organizacional." },
  { clave: "por_completar", etiqueta: "Por completar", ayuda: "Falta enviar la constancia (todavía con plazo), o falta definir el calendario de pagos." },
  { clave: "en_falta", etiqueta: "Vencidas o rechazadas", ayuda: "El plazo pasó sin constancia, o la última se rechazó y falta la corregida." },
  { clave: "sin_solicitar", etiqueta: "Sin solicitar", ayuda: "Personas activas que no tienen ningún apoyo ni una solicitud por revisar." },
];

export interface EstudioParaGrupo {
  estado_constancia: string;
  aprobadas: number;
}

/** El grupo de un estudio. «sin_solicitar» no sale de acá: son personas, no estudios. */
export function grupoDeEstudio(s: EstudioParaGrupo): Exclude<GrupoEducacion, "sin_solicitar"> {
  switch (s.estado_constancia) {
    case "pendiente_revision":
      return "por_revisar";
    case "vencida":
    case "rechazada":
      return "en_falta";
    case "al_dia":
      return s.aprobadas > 0 ? "al_dia" : "por_completar";
    default:
      // por_vencer, falta_enviar, sin_calendario y cualquier estado nuevo: lo que
      // no se conoce se muestra como «por completar», nunca como «al día».
      return "por_completar";
  }
}

/**
 * Lo que dice la insignia de un estudio. Igual que el estado de la base salvo en
 * un caso: `al_dia` sin ninguna constancia aprobada NO se pinta «Al día», porque
 * no hay nada que esté al día —solo que el primer pago todavía no llega—. La
 * pestaña ya lo manda a «Por completar»; la insignia no puede contradecirla.
 */
export function estadoParaMostrar(s: EstudioParaGrupo): { etiqueta: string; tono: TonoEstado } {
  if (s.estado_constancia === "al_dia" && s.aprobadas === 0) {
    return { etiqueta: "Sin constancias aún", tono: "neutral" };
  }
  return ESTADO_CONSTANCIA[s.estado_constancia as EstadoConstancia] ?? { etiqueta: s.estado_constancia, tono: "neutral" };
}

export interface PersonaActiva {
  persona_id: string;
  persona: string;
  sede: string;
  rango: string;
  tope: number | null;
}

/**
 * Las personas activas que no tienen ningún estudio —de ningún tiempo: quien ya
 * terminó el suyo pidió, y no es «sin solicitar»— ni una solicitud por revisar.
 * Las ya liquidadas salen salvo que se pida verlas.
 */
export function personasSinSolicitar(
  activas: PersonaActiva[],
  estudios: { persona_id: string }[],
  solicitudesPendientes: { persona_id: string }[],
  liquidadas: Set<string>,
  incluirLiquidadas: boolean,
): PersonaActiva[] {
  const conAlgo = new Set<string>([
    ...estudios.map((e) => e.persona_id),
    ...solicitudesPendientes.map((s) => s.persona_id),
  ]);
  return activas.filter((p) => !conAlgo.has(p.persona_id) && (incluirLiquidadas || !liquidadas.has(p.persona_id)));
}

export interface NivelDeApoyo {
  rango: string;
  /** null = el rango no tiene techo cargado; la pantalla lo dice. */
  tope: number | null;
  personas: number;
}

/**
 * Los techos por rango, leídos de las personas activas —que ya traen el techo
 * de su rango desde la base— en vez de una lista escrita a mano (regla #3 de
 * CLAUDE.md). Solo salen los rangos que hoy tienen gente.
 */
export function nivelesDeApoyo(activas: PersonaActiva[]): NivelDeApoyo[] {
  const porRango = new Map<string, NivelDeApoyo>();
  for (const p of activas) {
    const n = porRango.get(p.rango) ?? { rango: p.rango, tope: p.tope, personas: 0 };
    n.personas += 1;
    porRango.set(p.rango, n);
  }
  return [...porRango.values()].sort(
    (a, b) => (a.tope ?? Number.MAX_SAFE_INTEGER) - (b.tope ?? Number.MAX_SAFE_INTEGER) || a.rango.localeCompare(b.rango),
  );
}
