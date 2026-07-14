// Checklist de objetivos SMART (0032) — tipos y reglas compartidas entre
// /admin/objetivos (gestión) y /admin/perfil (vista de solo lectura).

export const MESES = [
  "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
  "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
];

export interface ObjetivoItem {
  id: string;
  persona_id: string;
  descripcion: string;
  cumplido: boolean;
  orden: number;
}

/**
 * Nivel de plus según las reglas de la planilla (fn_planilla_calcular):
 * 100% → 21% del salario · ≥60% → 12.6% · <60% → sin plus.
 * <30% además genera observación por bajo desempeño (nunca automática).
 */
export function nivelPlus(cumplidos: number, total: number): {
  etiqueta: string;
  observacion: boolean;
} {
  if (total <= 0) return { etiqueta: "—", observacion: false };
  const pct = cumplidos / total;
  return {
    etiqueta: pct >= 1 ? "Plus 21%" : pct >= 0.6 ? "Plus 12.6%" : "Sin plus",
    observacion: pct < 0.3,
  };
}
