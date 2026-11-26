// ============================================================================
// organigrama.ts — cómo se arma el dibujo del organigrama (0623)
// ============================================================================
// La base entrega equipos, personas y líneas (`fn_organigrama`); aquí se decide
// la forma: qué equipos van lado a lado, qué casilla ocupa cada persona y por
// dónde pasa cada línea. Son funciones puras, sin navegador ni Supabase.
//
// LAS TRES REGLAS DEL DIBUJO
//   · Los equipos de una misma «fila» van lado a lado.
//   · Junto a otros, un equipo es una columna de fichas (o dos, si su ancho es
//     2: Dirección). Solo en su fila, cada «nivel» es un renglón centrado.
//   · Hacia un equipo de más abajo va una sola línea; entre equipos de la misma
//     fila, una por persona (así los tres de un equipo se ven unidos por igual).
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

export interface Equipo {
  bloque: Bloque;
  /** Su gente, en el orden en que se lee: por nivel, columna y posición. */
  personas: Nodo[];
}

export interface Fila {
  fila: number;
  equipos: Equipo[];
  /**
   * Algún equipo empieza más abajo que otro: la fila comparte los renglones, así
   * quien encabeza queda a la altura del medio de su equipo sin medidas a mano.
   */
  comparteNiveles: boolean;
  primerNivel: number;
  ultimoNivel: number;
}

const porLugar = (a: Nodo, b: Nodo) =>
  a.nivel - b.nivel || (a.columna ?? 99) - (b.columna ?? 99) || a.orden - b.orden
  || a.apellidos.localeCompare(b.apellidos, "es") || a.nombres.localeCompare(b.nombres, "es")
  || a.persona_id.localeCompare(b.persona_id);

/** El dibujo en filas. Un equipo sin nadie no se dibuja. */
export function filasDelOrganigrama(bloques: readonly Bloque[], personas: readonly Nodo[]): Fila[] {
  const equipos = [...bloques]
    .sort((a, b) => a.fila - b.fila || a.orden - b.orden)
    .map((bloque) => ({ bloque, personas: personas.filter((p) => p.bloque === bloque.clave).sort(porLugar) }))
    .filter((e) => e.personas.length > 0);
  return [...new Set(equipos.map((e) => e.bloque.fila))].map((fila) => {
    const suyos = equipos.filter((e) => e.bloque.fila === fila);
    const niveles = suyos.flatMap((e) => e.personas.map((p) => p.nivel));
    const primerNivel = Math.min(...niveles);
    return {
      fila,
      equipos: suyos,
      comparteNiveles: suyos.length > 1 && suyos.some((e) => e.personas[0].nivel > primerNivel),
      primerNivel,
      ultimoNivel: Math.max(...niveles),
    };
  });
}

/** Cómo se acomoda la gente de un equipo: en columnas una junto a otra, o en renglones centrados. */
export type Forma = { tipo: "columnas"; grupos: Nodo[][] } | { tipo: "renglones"; grupos: Nodo[][] };

export function formaDelEquipo({ bloque, personas }: Equipo, soloEnSuFila: boolean): Forma {
  if (soloEnSuFila) {
    const niveles = [...new Set(personas.map((p) => p.nivel))];
    return { tipo: "renglones", grupos: niveles.map((n) => personas.filter((p) => p.nivel === n)) };
  }
  const columnas = bloque.ancho >= 2 ? bloque.columnas ?? 1 : 1;
  if (columnas < 2) return { tipo: "columnas", grupos: [personas] };
  // Quien no dice columna (o dice una que ya no existe) va en la primera.
  const en = (p: Nodo) => (p.columna !== null && p.columna <= columnas ? p.columna : 1);
  return {
    tipo: "columnas",
    grupos: Array.from({ length: columnas }, (_, i) => personas.filter((p) => en(p) === i + 1)).filter((g) => g.length > 0),
  };
}

/** Cuántas fichas por renglón: hasta cuatro en una fila; si son más, de tres en tres. */
export const fichasPorRenglon = (cuantas: number) => (cuantas > 4 ? 3 : cuantas);

/** «Arequipa · tienda» se lee como título y bajada. */
export function tituloDeEquipo(nombre: string): { titulo: string; bajada: string | null } {
  const [titulo, ...resto] = nombre.split(" · ");
  return { titulo, bajada: resto.length ? resto.join(" · ") : null };
}

/** Dónde quedó cada persona en el dibujo. */
export interface Lugar {
  fila: number;
  equipo: string;
  columna: number;
  /** Su puesto dentro de la columna, de arriba abajo. */
  puesto: number;
}

export type Trazo =
  /** Entre dos fichas vecinas de la misma columna. */
  | { clase: "vecinas"; tipo: TipoLinea; desde: string; hasta: string }
  /** Entre dos equipos de la misma fila: de `desde` sale una línea a cada una de `hasta`, con el tronco compartido. */
  | { clase: "al-lado"; tipo: TipoLinea; desde: string; hasta: string[] }
  /** De una persona a un equipo de más abajo. */
  | { clase: "a-equipo"; tipo: TipoLinea; desde: string; equipo: string };

/**
 * Las líneas guardadas (de persona a persona) convertidas en las que se dibujan.
 * Dentro de un equipo el panel ya dice quiénes van juntos: solo se traza la que
 * une a dos fichas vecinas en línea de equipo.
 */
export function agruparLineas(lineas: readonly Linea[], lugares: ReadonlyMap<string, Lugar>): Trazo[] {
  const entre = lineas.flatMap((l) => {
    const a = lugares.get(l.desde);
    const b = lugares.get(l.hasta);
    return a && b ? [{ l, a, b }] : [];
  });
  const salida = new Map<string, Trazo>();
  // Cuántas líneas de un tipo tiene cada persona hacia un equipo: en una misma fila, quien más tiene es de quien sale.
  const abanico = new Map<string, number>();
  const llave = (persona: string, equipo: string, tipo: TipoLinea) => `${persona}|${equipo}|${tipo}`;
  for (const { l, a, b } of entre) {
    for (const k of [llave(l.desde, b.equipo, l.tipo), llave(l.hasta, a.equipo, l.tipo)]) abanico.set(k, (abanico.get(k) ?? 0) + 1);
  }
  for (const { l, a, b } of entre) {
    if (a.equipo === b.equipo) {
      if (l.tipo === "equipo" && a.columna === b.columna && Math.abs(a.puesto - b.puesto) === 1) {
        salida.set(`${l.desde}|${l.hasta}`, { clase: "vecinas", tipo: l.tipo, desde: l.desde, hasta: l.hasta });
      }
      continue;
    }
    const sale = a.fila !== b.fila
      ? a.fila < b.fila
      : (abanico.get(llave(l.desde, b.equipo, l.tipo)) ?? 0) >= (abanico.get(llave(l.hasta, a.equipo, l.tipo)) ?? 0);
    const [desde, hasta, destino] = sale ? [l.desde, l.hasta, b] : [l.hasta, l.desde, a];
    const k = llave(desde, destino.equipo, l.tipo);
    if (a.fila !== b.fila) {
      salida.set(k, { clase: "a-equipo", tipo: l.tipo, desde, equipo: destino.equipo });
    } else {
      const previo = salida.get(k);
      salida.set(k, { clase: "al-lado", tipo: l.tipo, desde, hasta: [...(previo?.clase === "al-lado" ? previo.hasta : []), hasta] });
    }
  }
  return [...salida.values()];
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

/** A qué altura, bajo el comienzo de una fila, va su canal horizontal. */
const CANAL = 14;
/** Separación entre los carriles de un canal, cuando dos personas necesitan el mismo tramo. */
const CARRIL = 10;
/** Cuánto se aparta de la tarjeta una línea que tiene que salir de costado. */
const SALIDA = 14;

/** Una fila por la que pasa una línea: dónde empieza (ahí está su canal) y los pasillos libres entre sus equipos. */
export interface PasoDeFila {
  arriba: number;
  pasillos: number[];
}

/** La altura del canal de una fila para un carril. */
export function alturaDelCanal(fila: PasoDeFila, carril: number): number {
  return Math.round(fila.arriba + CANAL + carril * CARRIL);
}

/**
 * El trazo de una línea que une dos filas sin pasar por encima de ninguna
 * tarjeta: baja hasta el canal que hay sobre la fila siguiente, avanza por él,
 * atraviesa las filas intermedias por el pasillo más cercano a quien sale (así
 * cada árbol se queda de su lado y no cruza el de los demás) y entra por el
 * centro de la llegada, desde arriba.
 *
 * Si hay una tarjeta justo debajo de quien sale, la línea sale por su costado
 * izquierdo: así el árbol de quien está en la orilla corre por el margen.
 *
 * `filas` va desde la que sigue a la de salida hasta la de llegada.
 */
export function trazarEntreFilas(desde: Caja, hasta: Caja, { filas, obstaculos, carril }: {
  filas: readonly PasoDeFila[];
  /** Todas las tarjetas, para saber si debajo de quien sale hay una. */
  obstaculos: readonly Caja[];
  carril: number;
}): string {
  const canal = (i: number) => alturaDelCanal(filas[i], carril);
  const centro = medio(desde.izq, desde.der);
  const tapado = obstaculos.some((o) => o.izq < centro && o.der > centro && o.arr >= desde.aba && o.arr < canal(0));
  let trazo = tapado
    ? `M${Math.round(desde.izq)} ${medio(desde.arr, desde.aba)}H${Math.round(desde.izq) - SALIDA}V${canal(0)}`
    : `M${centro} ${Math.round(desde.aba)}V${canal(0)}`;
  const entra = medio(hasta.izq, hasta.der);
  for (let i = 1; i < filas.length; i++) {
    const [pasillo] = [...filas[i - 1].pasillos].sort((a, b) => Math.abs(a - centro) - Math.abs(b - centro));
    trazo += `H${Math.round(pasillo ?? entra)}V${canal(i)}`;
  }
  return `${trazo}H${entra}V${Math.round(hasta.arr)}`;
}

type Punto = [number, number];

/** Los vértices de un trazo hecho con M, H y V. */
export function vertices(d: string): Punto[] {
  const puntos: Punto[] = [];
  for (const [, orden, a, b] of d.matchAll(/([MHV])(-?\d+(?:\.\d+)?)(?: (-?\d+(?:\.\d+)?))?/g)) {
    const [x, y] = puntos[puntos.length - 1] ?? [0, 0];
    puntos.push(orden === "M" ? [Number(a), Number(b)] : orden === "H" ? [Number(a), y] : [x, Number(a)]);
  }
  return puntos;
}

/** De dónde a dónde ocupa un trazo la altura `y`: sirve para saber si dos líneas se estorban en el canal. */
export function tramoEn(d: string, y: number): { ini: number; fin: number } | null {
  const xs = vertices(d).filter((p) => p[1] === y).map((p) => p[0]);
  return xs.length ? { ini: Math.min(...xs), fin: Math.max(...xs) } : null;
}

/**
 * A cada quien, el carril más alto en el que su tramo no se pisa con el de otro.
 * Quienes no se estorban comparten altura. Entre dos que sí, va arriba quien
 * sale más a la derecha: su bajada no corta el renglón del otro.
 */
export function asignarCarriles(tramos: readonly { clave: string; ini: number; fin: number }[]): Map<string, number> {
  const ocupados: { ini: number; fin: number }[][] = [];
  const carriles = new Map<string, number>();
  for (const t of [...tramos].sort((a, b) => b.ini - a.ini || a.clave.localeCompare(b.clave))) {
    let c = ocupados.findIndex((o) => o.every((x) => t.fin + 8 < x.ini || t.ini > x.fin + 8));
    if (c < 0) { c = ocupados.length; ocupados.push([]); }
    ocupados[c].push(t);
    carriles.set(t.clave, c);
  }
  return carriles;
}

/** El mismo trazo con las esquinas redondeadas. */
export function redondear(d: string, radio = 9): string {
  // Los puntos repetidos o en la misma recta no son esquinas.
  const p = vertices(d).filter((q, i, v) => i === 0 || q[0] !== v[i - 1][0] || q[1] !== v[i - 1][1]);
  const esquinas = p.filter((q, i) => i === 0 || i === p.length - 1
    || !((p[i - 1][0] === q[0] && q[0] === p[i + 1][0]) || (p[i - 1][1] === q[1] && q[1] === p[i + 1][1])));
  if (esquinas.length < 2) return d;
  const hacia = (a: Punto, b: Punto, r: number): string => {
    const largo = Math.hypot(b[0] - a[0], b[1] - a[1]);
    return `${a[0] + ((b[0] - a[0]) * r) / largo} ${a[1] + ((b[1] - a[1]) * r) / largo}`;
  };
  let trazo = `M${esquinas[0][0]} ${esquinas[0][1]}`;
  for (let i = 1; i < esquinas.length - 1; i++) {
    const [a, q, b] = [esquinas[i - 1], esquinas[i], esquinas[i + 1]];
    const r = Math.min(radio, Math.hypot(q[0] - a[0], q[1] - a[1]) / 2, Math.hypot(b[0] - q[0], b[1] - q[1]) / 2);
    trazo += `L${hacia(q, a, r)}Q${q[0]} ${q[1]} ${hacia(q, b, r)}`;
  }
  const fin = esquinas[esquinas.length - 1];
  return `${trazo}L${fin[0]} ${fin[1]}`;
}
