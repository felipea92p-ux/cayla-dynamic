/**
 * El login «El vuelo vivo» (Felipe 2026-10-13, ADR-0136 act. 2026-10-13; maqueta: docs/maquetas/login-2026-10/, `?v=C4`).
 *
 * El colibrí aparece dibujándose en Trujillo y aleteando, salta a Arequipa y a Lima (flota un instante en cada una y la «cose»), da
 * la vuelta, cruza por detrás del lema tiñendo «transforma.» y sube a su lugar, donde se acomoda: dos aleteos que se apagan y el hilo
 * da un tirón. Aquí vive solo la geometría, la línea de tiempo y el texto (lógica pura, con su prueba); el componente
 * `components/login/PanelVuelo.tsx` mide la pantalla, mueve el ave y dibuja el hilo.
 *
 * Portado de CAYLA Retail (`apps/web/lib/login-vuelo.ts`, PR #1041): la geometría y la línea de tiempo son idénticas a propósito, para que
 * las dos aplicaciones se vean como una. Lo único que cambia es de dónde sale la hora: aquí, de `fecha-lima.ts`.
 */

import { TZ_LIMA, fechaLima, horaDecimalLima } from "@cayla-dynamic/shared";
import { toqueDeFecha } from "./easter-eggs";

export type Punto = { x: number; y: number };

/** Lo que el componente mide del panel: su tamaño, el centro de cada ojal (una sede) y dónde queda la cola del ave al llegar. */
export type MedidasDelVuelo = { ancho: number; alto: number; sedes: Punto[]; destino: Punto };

/** El colibrí de la marca (los mismos trazos del isotipo de Retail, en su lienzo de 223×150; el `.colibri` de aquí es la misma figura como imagen): el ala son los dos primeros. */
export const TRAZOS_DEL_AVE = [
  "M3,6 C45,14 95,28 118,50 C134,64 136,96 124,112 C110,130 80,138 47,146 L68,102",
  "M3,6 C10,40 40,70 70,80 C85,85 100,87 112,87",
  "M104,40 C102,22 118,6 140,5 C155,4 165,10 172,16 L220,12",
  "M172,16 C156,22 144,38 134,62",
] as const;

/** La cola del colibrí (punto 47,146 del lienzo de 223×150): ahí se ata el hilo. */
export const COLA_DEL_AVE = { x: 47 / 223, y: 146 / 150 };

// ---------------------------------------------------------------- el ala

/** El hombro: el ala gira desde aquí. */
const HOMBRO = { x: 116, y: 62 };
/** Los puntos del ala que se mueven y cuánto (1 = la punta, 0 = pegado al hombro). */
const PUNTOS_DEL_ALA = {
  punta: [3, 6, 1],
  c1: [45, 14, 0.7],
  c2: [95, 28, 0.3],
  d1: [10, 40, 0.85],
  d2: [40, 70, 0.5],
  d3: [70, 80, 0.2],
} as const;

/** La amplitud del aleteo en vuelo, en grados. */
export const ALETEO_MAXIMO = 34;

/**
 * Los dos trazos del ala para un momento del aleteo. `angulo` en grados (positivo = arriba); `largo` de 0 a 1 acorta el ala hacia el
 * hombro (el escorzo cuando sube). Con (0, 1) devuelve exactamente la pose del logo.
 */
export function alaDelAve(angulo: number, largo = 1): [string, string] {
  const r = (angulo * Math.PI) / 180;
  const p = {} as Record<keyof typeof PUNTOS_DEL_ALA, string>;
  for (const [nombre, [x, y, peso]] of Object.entries(PUNTOS_DEL_ALA) as [keyof typeof PUNTOS_DEL_ALA, readonly [number, number, number]][]) {
    const vx = x - HOMBRO.x;
    const vy = y - HOMBRO.y;
    const a = r * peso;
    const f = 1 - (1 - largo) * peso;
    const n = (v: number) => String(Math.round(v * 10) / 10);
    p[nombre] = `${n(HOMBRO.x + (vx * Math.cos(a) - vy * Math.sin(a)) * f)},${n(HOMBRO.y + (vx * Math.sin(a) + vy * Math.cos(a)) * f)}`;
  }
  return [
    `M${p.punta} C${p.c1} ${p.c2} 118,50 C134,64 136,96 124,112 C110,130 80,138 47,146 L68,102`,
    `M${p.punta} C${p.d1} ${p.d2} ${p.d3} C85,85 100,87 112,87`,
  ];
}

/** El aleteo de un instante: ángulo y escorzo según la fase (en radianes) y la amplitud que toca. */
export function aleteo(fase: number, amplitud: number): { angulo: number; largo: number } {
  const seno = Math.sin(fase);
  return { angulo: amplitud * seno, largo: 1 - 0.28 * Math.max(0, seno) * (amplitud / ALETEO_MAXIMO) };
}

// ---------------------------------------------------------------- el recorrido

/**
 * El recorrido, como un `d` de SVG en las medidas del panel. Va en línea recta por las sedes (de la primera a la última y un
 * poco más), sube en una vuelta, cruza el panel en diagonal por detrás del lema y entra al destino desde abajo a la izquierda.
 * Las proporciones salen de la maqueta (un panel de 756×900); el principio y el final son siempre los puntos medidos.
 */
export function trazoDelVuelo({ ancho: W, alto: H, sedes, destino: P }: MedidasDelVuelo): string {
  const primera = sedes[0];
  const ultima = sedes[sedes.length - 1];
  const y = primera.y;
  const fin = ultima.x + W * 0.17;
  const n = (v: number) => Math.round(v * 10) / 10;
  return [
    `M${n(primera.x)},${n(y)}`,
    `L${n(fin)},${n(y)}`,
    `C${n(ultima.x + W * 0.28)},${n(y)} ${n(ultima.x + W * 0.27)},${n(y - H * 0.09)} ${n(fin)},${n(y - H * 0.13)}`,
    `C${n(W * 0.5)},${n(y - H * 0.23)} ${n(W * 0.2)},${n(H * 0.62)} ${n(W * 0.22)},${n(H * 0.48)}`,
    `C${n(W * 0.24)},${n(H * 0.36)} ${n(P.x - W * 0.12)},${n(P.y + H * 0.07)} ${n(P.x)},${n(P.y)}`,
  ].join(" ");
}

// ---------------------------------------------------------------- la línea de tiempo

/** Cada momento del vuelo, en milisegundos desde que empieza. */
export const LINEA_DE_TIEMPO = {
  aparece: [0, 380],
  haciaSegunda: [380, 760],
  flotaSegunda: [760, 960],
  haciaTercera: [960, 1340],
  flotaTercera: [1340, 1540],
  granVuelo: [1540, 3340],
  llega: [3340, 3840],
  tiron: [3600, 4300],
} as const satisfies Record<string, readonly [number, number]>;

/** Lo que dura todo, en milisegundos. El formulario se puede llenar desde el primer instante. */
export const DURACION_DEL_VUELO = LINEA_DE_TIEMPO.tiron[1];

const acotar = (v: number, min = 0, max = 1) => Math.min(max, Math.max(min, v));
const avance = (ms: number, [desde, hasta]: readonly [number, number]) => acotar((ms - desde) / (hasta - desde));

/** Arranca y llega suave, sin pasarse ni rebotar (ADR-0136). */
export function ritmoDelVuelo(u: number): number {
  const v = acotar(u);
  return v < 0.5 ? 4 * v * v * v : 1 - Math.pow(-2 * v + 2, 3) / 2;
}
/** El salto de sede en sede: sale rápido y frena, sin pasarse. */
export const ritmoDelSalto = (u: number) => 1 - Math.pow(1 - acotar(u), 3);

/** Dónde va el ave en el hilo (`largo` en px: el recorrido completo; `segunda` y `tercera`: lo que mide hasta esas sedes). */
export type DistanciasDelHilo = { largo: number; segunda: number; tercera: number };

export type EstadoDelVuelo = {
  /** Cuánto hilo lleva recorrido, en px. */
  recorrido: number;
  escala: number;
  /** 1 mientras flota (se mece un poco), 0 cuando vuela. */
  flota: number;
  /** La inclinación hacia adelante de un salto, en grados (en el gran vuelo manda la curva). */
  inclinacionDelSalto: number;
  /** Aleteos por segundo y su amplitud en grados. */
  frecuencia: number;
  amplitud: number;
  /** De 0 a 1: cuánto del ave ya se dibujó al aparecer. */
  dibujado: number;
  /** Cuántas sedes ya cosió (0 a 3). */
  cosidas: number;
  enGranVuelo: boolean;
  /** De 0 a 1: el tirón final del hilo. */
  tiron: number;
  terminado: boolean;
};

/** El estado del vuelo en un instante. Es una función del tiempo: el componente solo la pinta. */
export function estadoDelVuelo(ms: number, { largo, segunda, tercera }: DistanciasDelHilo): EstadoDelVuelo {
  const T = LINEA_DE_TIEMPO;
  const base = {
    escala: 0.3,
    flota: 0,
    inclinacionDelSalto: 0,
    frecuencia: 9,
    amplitud: ALETEO_MAXIMO,
    dibujado: avance(ms, T.aparece),
    enGranVuelo: false,
    tiron: ms > T.tiron[0] ? ritmoDelVuelo(avance(ms, T.tiron)) : 0,
    terminado: ms >= DURACION_DEL_VUELO,
  };
  if (ms < T.haciaSegunda[0]) return { ...base, recorrido: 0, flota: 1, cosidas: 1 };
  if (ms < T.flotaSegunda[0]) {
    const u = avance(ms, T.haciaSegunda);
    return { ...base, recorrido: segunda * ritmoDelSalto(u), inclinacionDelSalto: 12 * Math.sin(Math.PI * u), cosidas: 1 };
  }
  if (ms < T.haciaTercera[0]) return { ...base, recorrido: segunda, flota: 1, cosidas: 2 };
  if (ms < T.flotaTercera[0]) {
    const u = avance(ms, T.haciaTercera);
    return {
      ...base,
      recorrido: segunda + (tercera - segunda) * ritmoDelSalto(u),
      inclinacionDelSalto: 12 * Math.sin(Math.PI * u),
      cosidas: 2,
    };
  }
  if (ms < T.granVuelo[0]) return { ...base, recorrido: tercera, flota: 1, cosidas: 3 };
  if (ms < T.llega[0]) {
    const u = ritmoDelVuelo(avance(ms, T.granVuelo));
    return { ...base, recorrido: tercera + (largo - tercera) * u, escala: 0.3 + 0.7 * u, frecuencia: 9 - 3 * u, enGranVuelo: true, cosidas: 3 };
  }
  // Llegó: flota y los aleteos se apagan hasta quedar en la pose del logo.
  const v = avance(ms, T.llega);
  return { ...base, recorrido: largo, escala: 1, flota: 1 - v, frecuencia: 4, amplitud: ALETEO_MAXIMO * (1 - v) * (1 - v), cosidas: 3 };
}

/**
 * Cómo mira el ave. `giro` va de -1 (a la izquierda) a 1 (a la derecha) e `inclinacion` en grados; los dos se acercan poco a poco a
 * su objetivo para que el ave se voltee y se ladee sin saltos. Solo en el gran vuelo sigue la curva (sin pasar de 22°); en los
 * saltos se inclina hacia adelante y en el resto queda derecha.
 */
export function poseDelAve(
  previa: { giro: number; inclinacion: number },
  rumbo: { dx: number; dy: number },
  estado: Pick<EstadoDelVuelo, "enGranVuelo" | "inclinacionDelSalto">,
  avanceDelGranVuelo: number,
): { giro: number; inclinacion: number } {
  let objetivoGiro = 1;
  let objetivo = estado.inclinacionDelSalto;
  if (estado.enGranVuelo) {
    objetivoGiro = rumbo.dx < -0.2 ? -1 : 1;
    const angulo = (Math.atan2(rumbo.dy, Math.abs(rumbo.dx) + 0.001) * 180) / Math.PI;
    objetivo = acotar(angulo, -22, 22) * (1 - avanceDelGranVuelo * avanceDelGranVuelo);
  }
  return {
    giro: previa.giro + (objetivoGiro - previa.giro) * (estado.enGranVuelo ? 0.14 : 0.2),
    inclinacion: previa.inclinacion + (objetivo - previa.inclinacion) * 0.15,
  };
}

/** El mecerse mientras flota, en px. */
export const meceo = (ms: number, flota: number) => flota * 2.6 * Math.sin((ms / 1000) * 2 * Math.PI * 3.2);

/**
 * Cuánto de «transforma.» ya está teñido de rojo (0 a 1, de derecha a izquierda, como cruza el ave). Solo avanza: el ave tiñe hasta
 * donde llega cuando pasa por la franja de la palabra; si al terminar el gran vuelo faltaba algo, se completa solo.
 */
export function tintaDeLaPalabra(
  previa: number,
  ave: Punto,
  palabra: { x: number; y: number; ancho: number; alto: number },
  pasoSegundos: number,
  granVueloTerminado: boolean,
): number {
  let tinta = previa;
  if (ave.y > palabra.y - 70 && ave.y < palabra.y + palabra.alto + 70) {
    tinta = Math.max(tinta, acotar((palabra.x + palabra.ancho - ave.x) / palabra.ancho));
  }
  if (granVueloTerminado) tinta = Math.min(1, tinta + pasoSegundos * 2.5);
  return tinta;
}

// ---------------------------------------------------------------- el saludo

/**
 * «Buenos días · martes 13 de octubre», con la hora de Perú (no la del aparato, que puede estar mal configurado).
 * Dos días al año lleva un toque al final —«… · Feliz Navidad»—: ver `toqueDeFecha` y `docs/easter-eggs.md`.
 */
export function saludoDelDia(ahora: Date): string {
  const hora = Math.floor(horaDecimalLima(ahora));
  const saludo = hora >= 5 && hora < 12 ? "Buenos días" : hora >= 12 && hora < 19 ? "Buenas tardes" : "Buenas noches";
  const fecha = new Intl.DateTimeFormat("es-PE", { weekday: "long", day: "numeric", month: "long", timeZone: TZ_LIMA }).format(ahora);
  const toque = toqueDeFecha(fechaLima(ahora));
  return `${saludo} · ${fecha.replace(",", "")}${toque ? ` · ${toque}` : ""}`;
}
