// Cortar una lista en páginas: la única regla de «qué va en la página n» del panel y de Lo mío.
//
// QUÉ PROMETE
//   paginar(items, n, tamano): la página n (base 0), con su «desde–hasta de total» listo para escribir. Una página fuera de rango se acerca a la
//   última que existe, así que si la lista se achica (cambió el rango, se leyó un documento) nunca queda una página vacía en pantalla.
//
// QUÉ ASUME
//   Que la lista ya llega en el orden en que se lee. Esto no ordena ni filtra: solo corta.
//
// Nació en lib/mio-disciplina.ts (los documentos de «Mis llamados», de a 10) y se mudó aquí el 2026-11-09, cuando Felipe pidió paginar de a 5
// tres listas más de Lo mío. Cuatro copias de la misma cuenta habrían sido cuatro maneras de equivocarse en el borde.

export interface Pagina<T> {
  items: T[];
  /** Base 0. */
  pagina: number;
  paginas: number;
  total: number;
  /** «1–5 de 23»: desde y hasta, base 1. Con la lista vacía, 0 y 0. */
  desde: number;
  hasta: number;
}

/** La página `n` (base 0) de una lista, de a `tamano`. Una página fuera de rango se acerca a la última. */
export function paginar<T>(items: readonly T[], n: number, tamano: number): Pagina<T> {
  const total = items.length;
  const paginas = Math.max(1, Math.ceil(total / tamano));
  const pagina = Math.min(Math.max(0, Math.floor(n)), paginas - 1);
  const inicio = pagina * tamano;
  return {
    items: items.slice(inicio, inicio + tamano), pagina, paginas, total,
    desde: total === 0 ? 0 : inicio + 1, hasta: Math.min(inicio + tamano, total),
  };
}
