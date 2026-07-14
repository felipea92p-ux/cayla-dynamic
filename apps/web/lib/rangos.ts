// Bandas salariales de CAYLA (salario mensual full-time, base 45 h/sem).
// El salario es EDITABLE por persona; estos montos son solo el default sugerido
// que se prellena al elegir el rango. Debe coincidir con el CHECK de la
// migración 0019 (asignaciones_salario.rango).

export interface Rango {
  codigo: string;
  label: string;
  salarioSugerido: number;
  orden: number;
}

export const RANGOS: Rango[] = [
  { codigo: "colibri", label: "Colibrí", salarioSugerido: 1320, orden: 1 },
  { codigo: "cayla", label: "Cayla", salarioSugerido: 1450, orden: 2 },
  { codigo: "caylo", label: "Caylo", salarioSugerido: 1450, orden: 3 },
  { codigo: "support", label: "Support", salarioSugerido: 1650, orden: 4 },
  { codigo: "aurora", label: "Aurora", salarioSugerido: 1890, orden: 5 },
  { codigo: "oraculo", label: "Oráculo", salarioSugerido: 2250, orden: 6 },
  { codigo: "archicaylo", label: "ArchiCaylo", salarioSugerido: 3000, orden: 7 },
];

export const RANGO_LABEL: Record<string, string> = Object.fromEntries(
  RANGOS.map((r) => [r.codigo, r.label]),
);

export function salarioSugerido(codigo: string): number | undefined {
  return RANGOS.find((r) => r.codigo === codigo)?.salarioSugerido;
}

export function formatSoles(n: number): string {
  return new Intl.NumberFormat("es-PE", {
    style: "currency",
    currency: "PEN",
    minimumFractionDigits: 2,
  }).format(n);
}
