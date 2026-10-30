// ============================================================================
// pruebas.ts — cómo se dice «en qué día de prueba va alguien» (0536, 0539)
// ============================================================================
// QUÉ PROMETE · una sola respuesta a «¿en qué situación está esta prueba?» y a
//               «¿cómo se rotula?» para el panel y para el terminal de marcaje.
// QUÉ ASUME   · que la base ya contó los días (`fn_pruebas_abiertas`,
//               `terminal_roster`): aquí solo se dicen. Los días son de jornada
//               CERRADA, no de calendario.
// QUÉ NO HACE · no calcula pagos ni decide quién puede cerrar una prueba.
//
// POR QUÉ VIVE EN `packages/shared` Y NO EN `apps/web/lib/admin`. Dos superficies
// distintas —el panel y el kiosco— rotulan lo mismo, y la regla de la casa
// para eso es una sola copia: es lo que ya hicieron `permisos.ts` y `vinculo.ts`.
// El kiosco no importa nada de `lib/admin`.
// ============================================================================

export type SituacionPrueba = "en_curso" | "cumplida" | "vencida";

export type VariantePrueba = "informativo" | "advertencia" | "alerta";

/**
 * La situación de una prueba. Se confía en la que dijo la base; solo si llega
 * algo que no se conoce se vuelve a derivar de los días — nunca se inventa una
 * ausencia ni una pasada de plazo.
 */
export function situacionDePrueba(f: { situacion?: string | null; dias_trabajados: number; dias_plazo: number }): SituacionPrueba {
  if (f.situacion === "en_curso" || f.situacion === "cumplida" || f.situacion === "vencida") return f.situacion;
  if (f.dias_trabajados > f.dias_plazo) return "vencida";
  if (f.dias_trabajados === f.dias_plazo) return "cumplida";
  return "en_curso";
}

/**
 * La etiqueta corta que acompaña a quien está en preselección en todo el sistema:
 * «Preselección · 2 de 3». Pasado el plazo dice cuántos días lleva; el color sube de
 * informativo (en curso) a advertencia (toca decidir) y a alerta (se pasó el plazo).
 */
export function etiquetaDePrueba(
  f: { situacion?: string | null; dias_trabajados: number; dias_plazo: number },
): { texto: string; variante: VariantePrueba } {
  const s = situacionDePrueba(f);
  if (s === "en_curso") return { texto: `Preselección · ${f.dias_trabajados} de ${f.dias_plazo}`, variante: "informativo" };
  if (s === "cumplida") return { texto: `Preselección · ${f.dias_plazo} de ${f.dias_plazo}`, variante: "advertencia" };
  return { texto: `Preselección · ${f.dias_trabajados} días`, variante: "alerta" };
}
