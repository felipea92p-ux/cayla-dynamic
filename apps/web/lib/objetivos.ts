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
  indicaciones: string | null;
  cumplido: boolean;
  orden: number;
}

/**
 * Lectura de los objetivos de un mes. **No devuelve ningún monto: los objetivos
 * dejaron de pagar el 2026-08-06 (migración 0171).**
 *
 * Hasta entonces esta función se llamaba `nivelPlus` y traducía el porcentaje a
 * «Plus 21%» / «Plus 12.6%» / «Sin plus», que era el gemelo en el navegador de
 * lo que pagaba `fn_planilla_calcular`. Ese plus era remuneración tratada como
 * si no lo fuera —el Art. 19 del D.S. 001-97-TR no lo lista entre los conceptos
 * no computables— y contradecía la política salarial que el equipo firmó:
 * «CAYLA no aplica aumentos discrecionales».
 *
 * Lo que se conserva es la marca de bajo desempeño por debajo del 30%. Nunca
 * fue un pago: es un aviso para conversar, y la decisión es siempre de una
 * persona.
 */
export function lecturaObjetivos(cumplidos: number, total: number): {
  etiqueta: string;
  observacion: boolean;
} {
  if (total <= 0) return { etiqueta: "—", observacion: false };
  const pct = cumplidos / total;
  return {
    etiqueta: `${Math.round(pct * 100)}% cumplido`,
    observacion: pct < 0.3,
  };
}
