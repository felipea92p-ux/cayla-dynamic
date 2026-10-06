import type { LucideIcon } from "lucide-react";

// ============================================================================
// Las secciones de una pantalla larga, en grupos, y cómo se buscan.
// ============================================================================
//
// QUÉ PROMETE
//   Los tipos con que se describe el menú de secciones (`MenuDetalle`) y la
//   única regla de búsqueda de su ⌘K: qué secciones coinciden con lo escrito.
//
// QUÉ ASUME
//   Que una sección no es una ruta sino un estado dentro de UNA pantalla —hoy,
//   «Lo mío»—. Por eso esto no es `admin/nav-items.ts`: allá cada renglón es un
//   `href` y la búsqueda navega; acá cada renglón es un `valor` y la búsqueda lo
//   elige sin salir de la pantalla.
//
// POR QUÉ VIVE APARTE DEL COMPONENTE
//   Es data y una función pura, sin React ni navegador. Así se prueba con
//   vitest en entorno node (`tests/mio-secciones.test.ts`), que es el único
//   que este repo tiene.
// ============================================================================

export type SeccionDetalle<T extends string> = {
  valor: T;
  label: string;
  Icon: LucideIcon;
  /**
   * Cuántas cosas nuevas esperan en esta sección (ej.: boletas publicadas y aún
   * sin abrir). Opcional: sin él, o en 0, el renglón no dibuja nada, así que las
   * secciones que no lo usan quedan exactamente como estaban.
   */
  contador?: number;
  /**
   * Las palabras con que alguien busca esta sección sin saber cómo se llama:
   * quien quiere ver su sueldo escribe «sueldo», no «Boletas». Solo las usa el
   * buscador (⌘K); en el menú no se ven.
   */
  alias?: readonly string[];
};

export type GrupoDetalle<T extends string> = {
  /** Sin etiqueta, el grupo va arriba y sin título: es el primero del menú. */
  label?: string;
  secciones: readonly SeccionDetalle<T>[];
};

// Sin tildes ni mayúsculas: buscar «educacion» tiene que encontrar «Educación».
// Las mismas dos líneas que el buscador del panel; no se comparte un helper por
// esto solo, igual que allá.
function sinTildes(t: string): string {
  return t.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
}

export type ResultadoSeccion<T extends string> = {
  seccion: SeccionDetalle<T>;
  /** El título del grupo donde vive, para mostrarlo al lado. */
  grupo?: string;
  /** Si apareció por un alias y no por su nombre, cuál: se le muestra a quien
   *  busca para que entienda por qué salió «Boletas» al escribir «sueldo». */
  porAlias?: string;
};

/**
 * Las secciones que coinciden con lo escrito, en el orden del menú. Sin nada
 * escrito, todas: abrir el buscador sirve también para hojear.
 *
 * Primero se mira el nombre y después los alias, y no al revés: si «Educación»
 * coincide por su nombre, decir «por estudios» al lado sería ruido.
 */
export function buscarSecciones<T extends string>(
  grupos: readonly GrupoDetalle<T>[],
  consulta: string,
): ResultadoSeccion<T>[] {
  const q = sinTildes(consulta.trim());
  const resultados: ResultadoSeccion<T>[] = [];
  for (const g of grupos) {
    for (const s of g.secciones) {
      if (!q || sinTildes(s.label).includes(q)) {
        resultados.push({ seccion: s, grupo: g.label });
        continue;
      }
      const alias = s.alias?.find((a) => sinTildes(a).includes(q));
      if (alias) resultados.push({ seccion: s, grupo: g.label, porAlias: alias });
    }
  }
  return resultados;
}
