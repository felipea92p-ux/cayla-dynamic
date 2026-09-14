// ============================================================================
// duracion.ts — minutos, en el idioma en que la gente los piensa
// ============================================================================
// QUÉ PROMETE · convertir un número de minutos en "Xh YYm" (o "Xm" si es menos
//               de una hora), igual en cualquier pantalla que hable de una
//               tardanza o una salida anticipada.
// QUÉ ASUME   · que `min` ya es un entero de minutos, sin signo — el llamador
//               decide si el número es una tardanza, un anticipo o un exceso.
//
// Nació ya escrita dos veces (`admin/horas/page.tsx` y `mio/page.tsx`, ambas
// idénticas) antes de que el Dashboard estuviera a punto de escribirla una
// tercera vez para mostrar "anticip. 265m" en vez de "4h 25m". Iba a ser
// exactamente el problema que packages/shared existe para evitar: si alguien
// ajustaba el redondeo en una copia y no en las otras, "anticipo" habría
// dicho números distintos para la misma persona el mismo día según qué
// pantalla se mirara.
// ============================================================================

/** 265 → "4h 25m"; 45 → "45 min". */
export function formatoMinutos(min: number): string {
  if (min < 60) return `${min} min`;
  return `${Math.floor(min / 60)}h ${String(min % 60).padStart(2, "0")}m`;
}
