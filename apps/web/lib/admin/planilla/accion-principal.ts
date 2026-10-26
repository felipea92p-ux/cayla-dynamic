// ============================================================================
// accion-principal.ts — qué botón grande le toca a Planilla según cómo va el mes
// ============================================================================
// QUÉ PROMETE   · decir UNA acción principal para la franja de arriba de Planilla:
//                   1. si algo FRENA el pago → «Resolver lo que frena (N)»: lo que bloquea se atiende antes que cualquier otra
//                      cosa, y el botón lo dice en el momento de actuar, no dentro de un ⓘ;
//                   2. si nada frena y algún grupo con gente sigue sin pagarse → «Revisar cierre de «Grupo»»;
//                   3. si todos los grupos con gente ya están pagados → «Boletas del periodo» (la boleta oficial llega
//                      DESPUÉS del pago).
//                 Hasta el 2026-10-19 el botón negro decía siempre «Boletas del periodo», aunque la pantalla de Boletas avisara
//                 que el periodo todavía no estaba pagado.
// QUÉ ASUME     · `personasFrenan` ya cuenta PERSONAS distintas (no avisos), como el resto de la pantalla; y `grupos` es el
//                 estado de pago por grupo de la base (cada grupo se paga por su cuenta, 0323).
// QUÉ NO HACE   · no cierra ni paga nada: solo elige qué botón se dibuja. El cierre sigue pidiendo su revisión y su
//                 confirmación, grupo por grupo, y ningún cálculo cambia.
// ============================================================================
import type { TipoVinculo } from "@cayla-dynamic/shared";
import type { GrupoPago } from "./tipos";

export type AccionPrincipal =
  | { tipo: "resolver"; frenan: number }
  | { tipo: "cerrar"; grupo: TipoVinculo }
  | { tipo: "boletas" };

export function accionPrincipalDelPeriodo(p: {
  personasFrenan: number;
  /** null = todavía no se sabe (cargando): no se ofrece ninguna acción en vez de adivinar una. */
  grupos: GrupoPago[] | null;
  /** La pestaña que se está mirando: si su grupo es el que falta, el botón cierra ESE. */
  grupoDeLaPestana: TipoVinculo;
}): AccionPrincipal | null {
  if (p.grupos === null) return null;
  if (p.personasFrenan > 0) return { tipo: "resolver", frenan: p.personasFrenan };
  const pendientes = p.grupos.filter((g) => g.personas > 0 && g.estado !== "pagado");
  if (pendientes.length > 0) {
    const deLaPestana = pendientes.find((g) => g.grupo === p.grupoDeLaPestana);
    return { tipo: "cerrar", grupo: (deLaPestana ?? pendientes[0]).grupo };
  }
  return { tipo: "boletas" };
}
