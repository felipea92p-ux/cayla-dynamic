// Qué personas se ven en la tabla «Por persona» de Costos, y en qué orden.
//
// QUÉ PROMETE
//   personasVisibles(filas, filtro): las que coinciden con lo buscado (cada palabra en el nombre, sin tildes ni mayúsculas) y con la
//   sede elegida, ordenadas por costo real, horas o periodos, de mayor a menor o al revés. Un empate se desempata por costo real (de
//   mayor a menor) y después por nombre: el orden no depende de cómo llegaron las filas, así que la página 2 no cambia de gente al
//   volver a cargar.
//
// QUÉ ASUME
//   Que cada fila es una persona del año (`por_persona` de fn_costos_planilla) y que `sede` es el código de la sede donde cobró. Si
//   cobró en dos sedes ese año, la base manda una sola (`max(sede_codigo)`), y el filtro la encuentra solo en esa.
//
// No toca la base, React ni el navegador: se prueba en tests/costos-por-persona.test.ts. Pidió el buscador, la sede, el orden y las
// páginas de 15 Felipe el 2026-11-10, con la tabla ya larga en un año con rotación.

import { sinTildes } from "@/lib/sin-tildes";

export type OrdenPersonas =
  | "costo_desc" | "costo_asc"
  | "horas_desc" | "horas_asc"
  | "periodos_desc" | "periodos_asc";

/** En el orden en que se ofrecen. El primero es el de siempre: quien más cuesta, arriba. */
export const ORDENES_PERSONAS: readonly { valor: OrdenPersonas; etiqueta: string }[] = [
  { valor: "costo_desc", etiqueta: "Mayor costo real" },
  { valor: "costo_asc", etiqueta: "Menor costo real" },
  { valor: "horas_desc", etiqueta: "Más horas" },
  { valor: "horas_asc", etiqueta: "Menos horas" },
  { valor: "periodos_desc", etiqueta: "Más periodos" },
  { valor: "periodos_asc", etiqueta: "Menos periodos" },
];

export const PERSONAS_POR_PAGINA = 15;

export interface FiltroPersonas {
  texto: string;
  /** Código de sede; vacío = todas. */
  sede: string;
  orden: OrdenPersonas;
}

export const FILTRO_PERSONAS_INICIAL: FiltroPersonas = { texto: "", sede: "", orden: "costo_desc" };

interface FilaPersona {
  nombre: string;
  sede: string;
  periodos: number;
  horas: number;
  costo: number;
}

const CAMPO: Record<OrdenPersonas, "costo" | "horas" | "periodos"> = {
  costo_desc: "costo", costo_asc: "costo",
  horas_desc: "horas", horas_asc: "horas",
  periodos_desc: "periodos", periodos_asc: "periodos",
};

export function personasVisibles<T extends FilaPersona>(filas: readonly T[], filtro: FiltroPersonas): T[] {
  // Palabra por palabra: «maria zegarra» encuentra a «María de los Ángeles … y Zegarra».
  const palabras = sinTildes(filtro.texto).split(/\s+/).filter(Boolean);
  const campo = CAMPO[filtro.orden];
  const signo = filtro.orden.endsWith("_asc") ? 1 : -1;
  return filas
    .filter((p) => (filtro.sede === "" || p.sede === filtro.sede)
      && palabras.every((w) => sinTildes(p.nombre).includes(w)))
    .sort((a, b) => signo * (a[campo] - b[campo]) || b.costo - a.costo || a.nombre.localeCompare(b.nombre, "es"));
}

/** ¿Hay algo distinto de lo de siempre? Decide si se ofrece «Limpiar filtros». */
export function hayFiltro(filtro: FiltroPersonas): boolean {
  return filtro.texto.trim() !== "" || filtro.sede !== "" || filtro.orden !== FILTRO_PERSONAS_INICIAL.orden;
}
