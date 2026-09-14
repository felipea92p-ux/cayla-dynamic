// Checklist de objetivos SMART (0032) — tipos y reglas compartidas entre
// /admin/objetivos (gestión) y /admin/perfil (vista de solo lectura).

export const MESES = [
  "Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio",
  "Julio", "Agosto", "Septiembre", "Octubre", "Noviembre", "Diciembre",
];

export const MESES_CORTO = [
  "Ene", "Feb", "Mar", "Abr", "May", "Jun",
  "Jul", "Ago", "Sep", "Oct", "Nov", "Dic",
];

export interface ObjetivoItem {
  id: string;
  persona_id: string;
  descripcion: string;
  indicaciones: string | null;
  cumplido: boolean;
  orden: number;
  /** Autoría (0449) — quién lo creó y quién lo tocó por última vez (crear
   * cuenta como la primera edición, así que al nacer los dos coinciden). */
  creado_por: string | null;
  creado_at: string;
  actualizado_por: string | null;
  actualizado_at: string;
}

/** Un solo lugar para el texto del estado + la variante de <Insignia> que le
 * corresponde, para no repetir la escalera verde/ámbar/rojo/neutral en cada
 * pantalla que dibuja el estado de una persona (bandeja de equipo, tarjeta
 * individual, ficha). */
export function estadoObjetivos(
  cumplidos: number,
  total: number,
): { texto: string; variante: "positivo" | "advertencia" | "alerta" | "neutral" } {
  if (total <= 0) return { texto: "Sin objetivos", variante: "neutral" };
  const nivel = nivelColorObjetivos(cumplidos, total);
  if (nivel === "verde") return { texto: "Cumplido", variante: "positivo" };
  if (nivel === "ambar") return { texto: "Parcial", variante: "advertencia" };
  return { texto: "Observación", variante: "alerta" };
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

/**
 * Un solo lugar para los cortes 30/60 % que ya usaba la barra de progreso.
 * Se separó al agregar el gráfico de historial (0349) para no repetir los
 * mismos dos números en dos sitios — la lección de `rol === "admin"` y
 * `"America/Lima"`, aplicada a un umbral en vez de a un permiso o una fecha.
 */
export type NivelObjetivos = "verde" | "ambar" | "rojo";

export function nivelColorObjetivos(cumplidos: number, total: number): NivelObjetivos {
  if (total <= 0) return "rojo";
  const pct = (cumplidos / total) * 100;
  if (pct >= 60) return "verde";
  if (pct >= 30) return "ambar";
  return "rojo";
}

/** Una fila del historial mensual que devuelve fn_objetivos_historial. */
export interface MesHistorial {
  anio: number;
  mes: number;
  cumplidos: number;
  total: number;
}
