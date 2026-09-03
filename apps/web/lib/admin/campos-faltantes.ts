/**
 * Qué campos faltan, nombrados — no "faltan datos", sino cuáles.
 *
 * POR QUÉ EXISTE. El patrón de siempre era `if (!a || !b || !c) avisar("error",
 * "a, b y c son obligatorios")`: si de los tres solo faltaba uno, el aviso
 * seguía nombrando los tres, y quien lo leía no podía saber cuál le faltaba de
 * verdad con solo mirar la pantalla. `ausencias/page.tsx` ya lo resolvió una
 * vez a mano, armando un array y uniéndolo con `.join(" y ")`; esto generaliza
 * esa idea para no reinventarla en cada formulario nuevo.
 */
export function fraseFaltantes(campos: Array<readonly [etiqueta: string, falta: boolean]>): string | null {
  const faltan = campos.filter(([, falta]) => falta).map(([etiqueta]) => etiqueta);
  if (faltan.length === 0) return null;
  if (faltan.length === 1) return faltan[0];
  return `${faltan.slice(0, -1).join(", ")} y ${faltan[faltan.length - 1]}`;
}
