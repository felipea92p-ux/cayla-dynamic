// ============================================================================
// organigrama.ts — cómo se arma el dibujo del organigrama (0623)
// ============================================================================
// La base entrega equipos, personas y líneas (`fn_organigrama`); aquí se decide
// la forma: qué equipos van lado a lado, qué casilla ocupa cada persona y por
// dónde pasa cada línea. Son funciones puras, sin navegador ni Supabase.
//
// LAS TRES REGLAS DEL DIBUJO
//   · Los equipos de una misma «fila» van lado a lado, con su ancho relativo.
//   · Dentro de un equipo, cada «nivel» es un renglón. Si el equipo tiene
//     columnas, cada persona cae en la suya (quien no la dice ocupa todo el
//     renglón); si no, el renglón se reparte solo.
//   · Si algún equipo de una fila empieza más abajo del nivel 1, toda la fila
//     comparte los renglones: así quien encabeza queda a la altura del medio
//     de su equipo sin escribir medidas a mano.
// ============================================================================

export type Etiqueta = "apoyo_lider" | "asesoria" | "externo";
export type Color = "verde" | "azul" | "ambar";
export type TipoLinea = "equipo" | "asesoria";

export const ETIQUETAS: Record<Etiqueta, string> = {
  apoyo_lider: "Apoyo a líder",
  asesoria: "Asesoría",
  externo: "Externo",
};

/** Los colores de tarjeta, con el nombre que se les dice. «ambar» es el naranja tostado de la marca. */
export const COLORES: Record<Color, string> = { verde: "Verde", azul: "Azul", ambar: "Naranja" };

export const TIPOS_DE_LINEA: Record<TipoLinea, string> = {
  equipo: "Equipo (línea llena)",
  asesoria: "Asesoría, sin mando (punteada)",
};

export interface Bloque {
  clave: string;
  nombre: string;
  fila: number;
  orden: number;
  ancho: number;
  columnas: number | null;
  discreto: boolean;
  orden_movil: number;
}

export interface Nodo {
  persona_id: string;
  nombres: string;
  apellidos: string;
  foto_url: string | null;
  bloque: string;
  nivel: number;
  columna: number | null;
  orden: number;
  funcion: string;
  etiqueta: Etiqueta | null;
  color: Color | null;
  discreto: boolean;
  /** Una especialidad en común con otras personas («Negocios internacionales», 0624). Puede faltar antes de pegar la migración. */
  distintivo?: string | null;
}

export interface Linea {
  desde: string;
  hasta: string;
  tipo: TipoLinea;
}

export interface Pendiente {
  persona_id: string;
  nombres: string;
  apellidos: string;
  cargo: string | null;
  sede: string | null;
}

export interface Organigrama {
  publicado: boolean;
  puede_editar: boolean;
  bloques: Bloque[];
  personas: Nodo[];
  lineas: Linea[];
  sin_ubicar: Pendiente[];
}

/** La respuesta de `fn_organigrama` llega sin tipo: lo que no venga se toma como vacío. */
export function leerOrganigrama(json: unknown): Organigrama {
  const o = (json && typeof json === "object" ? json : {}) as Partial<Organigrama>;
  const lista = <T,>(x: unknown): T[] => (Array.isArray(x) ? (x as T[]) : []);
  return {
    publicado: o.publicado === true,
    puede_editar: o.puede_editar === true,
    bloques: lista<Bloque>(o.bloques),
    personas: lista<Nodo>(o.personas),
    lineas: lista<Linea>(o.lineas),
    sin_ubicar: lista<Pendiente>(o.sin_ubicar),
  };
}

export interface Celda {
  nodo: Nodo;
  /** Columna de la cuadrícula en la que cae (desde 1). */
  columna: number;
  /** Cuántas columnas ocupa. */
  ocupa: number;
}

export interface Nivel {
  nivel: number;
  columnas: number;
  celdas: Celda[];
}

export interface Equipo {
  bloque: Bloque;
  niveles: Nivel[];
}

export interface Fila {
  fila: number;
  equipos: Equipo[];
  /** Los renglones se comparten entre equipos (alguno empieza más abajo del primero). */
  comparteNiveles: boolean;
  /** El nivel más bajo que usa la fila: cuántos renglones compartidos hacen falta. */
  ultimoNivel: number;
}

const porLugar = (a: Nodo, b: Nodo) =>
  a.orden - b.orden || a.apellidos.localeCompare(b.apellidos, "es") || a.nombres.localeCompare(b.nombres, "es")
  || a.persona_id.localeCompare(b.persona_id);

function nivelesDe(bloque: Bloque, nodos: readonly Nodo[]): Nivel[] {
  const numeros = [...new Set(nodos.map((n) => n.nivel))].sort((a, b) => a - b);
  return numeros.map((nivel) => {
    const enNivel = nodos.filter((n) => n.nivel === nivel)
      .sort((a, b) => (a.columna ?? 99) - (b.columna ?? 99) || porLugar(a, b));
    if (bloque.columnas) {
      const columnas = bloque.columnas;
      return {
        nivel,
        columnas,
        celdas: enNivel.map((nodo) => {
          const cabe = nodo.columna !== null && nodo.columna <= columnas;
          return { nodo, columna: cabe ? (nodo.columna as number) : 1, ocupa: cabe ? 1 : columnas };
        }),
      };
    }
    const columnas = enNivel.length;
    return { nivel, columnas, celdas: enNivel.map((nodo, i) => ({ nodo, columna: i + 1, ocupa: 1 })) };
  });
}

/** El dibujo en filas. Un equipo sin nadie no se dibuja. */
export function filasDelOrganigrama(bloques: readonly Bloque[], personas: readonly Nodo[]): Fila[] {
  const equipos = [...bloques]
    .sort((a, b) => a.fila - b.fila || a.orden - b.orden)
    .map((bloque) => ({ bloque, niveles: nivelesDe(bloque, personas.filter((p) => p.bloque === bloque.clave)) }))
    .filter((e) => e.niveles.length > 0);
  const numeros = [...new Set(equipos.map((e) => e.bloque.fila))];
  return numeros.map((fila) => {
    const suyos = equipos.filter((e) => e.bloque.fila === fila);
    return {
      fila,
      equipos: suyos,
      comparteNiveles: suyos.length > 1 && suyos.some((e) => e.niveles[0].nivel > 1),
      ultimoNivel: Math.max(...suyos.map((e) => e.niveles[e.niveles.length - 1].nivel)),
    };
  });
}

// ── Las líneas ──────────────────────────────────────────────────────────────

/** Una tarjeta ya medida: izquierda, derecha, arriba y abajo. */
export interface Caja {
  izq: number;
  der: number;
  arr: number;
  aba: number;
}

/** Cuánto antes de la tarjeta de llegada dobla una línea con codo. */
const CODO = 14;

const cruce = (a1: number, a2: number, b1: number, b2: number) => ({ ini: Math.max(a1, b1), fin: Math.min(a2, b2) });
const medio = (a: number, b: number) => Math.round((a + b) / 2);

/**
 * El trazo SVG entre dos tarjetas:
 *   · a la misma altura → recta horizontal de borde a borde;
 *   · una encima de otra → recta vertical;
 *   · en diagonal → sale de costado y dobla justo antes de `hasta` (así varias
 *     que llegan a la misma persona comparten el tronco).
 */
export function trazarLinea(desde: Caja, hasta: Caja): string {
  const v = cruce(desde.arr, desde.aba, hasta.arr, hasta.aba);
  const h = cruce(desde.izq, desde.der, hasta.izq, hasta.der);
  const aLaDerecha = hasta.izq >= desde.der;
  if (h.fin > h.ini) {
    const x = medio(h.ini, h.fin);
    const [alta, baja] = desde.arr <= hasta.arr ? [desde, hasta] : [hasta, desde];
    return `M${x} ${Math.round(alta.aba)}V${Math.round(baja.arr)}`;
  }
  const xSale = Math.round(aLaDerecha ? desde.der : desde.izq);
  const xLlega = Math.round(aLaDerecha ? hasta.izq : hasta.der);
  const menorAlto = Math.min(desde.aba - desde.arr, hasta.aba - hasta.arr);
  if (v.fin - v.ini >= menorAlto * 0.6) {
    return `M${xSale} ${medio(v.ini, v.fin)}H${xLlega}`;
  }
  const xCodo = aLaDerecha ? xLlega - CODO : xLlega + CODO;
  return `M${xSale} ${medio(desde.arr, desde.aba)}H${xCodo}V${medio(hasta.arr, hasta.aba)}H${xLlega}`;
}

/** Cuánto dentro de la tarjeta de llegada baja una línea que viene de otra fila: lejos del título, que va centrado. */
const ENTRADA = 24;
/** Separación entre los carriles de un canal, para que las líneas de dos personas no se confundan. */
const CARRIL = 12;

/** Una fila por la que pasa una línea: dónde empieza (ahí está su canal) y los pasillos libres entre sus equipos. */
export interface PasoDeFila {
  arriba: number;
  pasillos: number[];
}

/**
 * El trazo de una línea que une dos filas sin pasar por encima de ninguna
 * tarjeta: baja hasta el canal que hay sobre la fila siguiente, avanza por él,
 * atraviesa las filas intermedias por el pasillo más cercano al equipo de
 * llegada y entra en la tarjeta desde arriba.
 *
 * `filas` va desde la que sigue a la de salida hasta la de llegada.
 */
export function trazarEntreFilas(desde: Caja, hasta: Caja, { filas, obstaculos, centroDestino, carril }: {
  filas: readonly PasoDeFila[];
  /** Todas las tarjetas: si hay una justo debajo de quien sale, la línea sale de costado. */
  obstaculos: readonly Caja[];
  /** El centro del equipo al que llega. */
  centroDestino: number;
  carril: number;
}): string {
  const canal = (i: number) => Math.round(filas[i].arriba + 6 + carril * CARRIL);
  const centro = medio(desde.izq, desde.der);
  const tapado = obstaculos.some((o) => o.izq < centro && o.der > centro && o.arr >= desde.aba && o.arr < canal(0));
  let trazo = tapado
    ? `M${Math.round(desde.izq)} ${medio(desde.arr, desde.aba)}H${Math.round(desde.izq) - 5}V${canal(0)}`
    : `M${centro} ${Math.round(desde.aba)}V${canal(0)}`;
  const entra = Math.round(medio(hasta.izq, hasta.der) <= centroDestino + 1 ? hasta.izq + ENTRADA : hasta.der - ENTRADA);
  for (let i = 1; i < filas.length; i++) {
    const [pasillo] = [...filas[i - 1].pasillos].sort((a, b) => Math.abs(a - centroDestino) - Math.abs(b - centroDestino));
    trazo += `H${Math.round(pasillo ?? entra)}V${canal(i)}`;
  }
  return `${trazo}H${entra}V${Math.round(hasta.arr)}`;
}
