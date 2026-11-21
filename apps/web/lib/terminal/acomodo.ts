// ============================================================================
// acomodo.ts — cuántas columnas y de qué tamaño van los retratos del terminal
// ============================================================================
//
// QUÉ PROMETE
//   Que el equipo de una sede entre COMPLETO en la pantalla de la Mac mini sin
//   desplazarla, tenga 3 personas o más de 20, y con el retrato más grande que
//   quepa. Lo pidió Felipe el 2026-11-21: «en unas sedes son 3 o más de 20».
//   Si no entra a un tamaño que se lea, lo dice (`desliza`): la pantalla
//   entonces se desliza y lo avisa, en vez de encoger los nombres.
//
// QUÉ ASUME
//   Que quien llama mide el espacio libre de verdad (el alto que queda bajo la
//   cabecera, la leyenda y los avisos) y lo pasa en píxeles. Aquí no hay
//   navegador: por eso se puede probar sin levantar nada.
//
// DECIDÍ: probar cada cantidad de columnas y quedarme con la que deja el
//   retrato de mayor área, dentro de una proporción que todavía es una foto.
// DESCARTÉ:
//   · Una tabla fija «hasta 8 personas, 4 columnas; hasta 13, 7…». Sirve en un
//     monitor y falla en el siguiente: la misma sede no cabe igual a 1920×1080
//     que a 1366×768, y el aviso de marcas sin registrar le quita alto a todas.
//   · Solo CSS (`auto-fit`). Llena el ancho, pero no sabe del alto: con 24
//     personas la tercera fila se iba fuera de la pantalla sin avisar.
//
// SE ROMPE SI
//   La casilla cambia de anatomía (otro relleno, otra línea de texto) y no se
//   actualiza `altoDelTexto`: los retratos se calcularían para una casilla que
//   ya no mide eso y la última fila se cortaría. Las medidas de aquí son las
//   de `.tr-casilla` en estilos/vidrio/terminal-retratos.css: relleno de 8 px,
//   borde de 1 px, y el estado a 20 px el primer renglón y 18 cada uno más.
// ============================================================================

/** El relleno de la casilla alrededor del retrato, en px (`.tr-casilla`). */
export const RELLENO_CASILLA = 8;
/** Lo que la casilla suma al retrato y al texto: su relleno y su borde de 1 px, arriba y abajo (o a los lados). */
export const MARCO_CASILLA = 2 * RELLENO_CASILLA + 2;
/** Por debajo de este ancho un nombre de pila ya no se lee a un metro. */
export const ANCHO_MINIMO = 148;
/** Con tres personas el retrato no crece hasta llenar la pantalla. */
export const ANCHO_MAXIMO = 380;
export const FOTO_MAXIMA = 320;
/** Entre qué proporciones (alto ÷ ancho) el retrato sigue viéndose como una foto. */
const PROPORCION_MINIMA = 0.55;
const PROPORCION_MAXIMA = 1.25;
/**
 * El ancho interior desde el que el estado entra en un solo renglón. Medido en el navegador el 2026-11-21: el texto
 * más largo que puede llevar una casilla, «En almacén · vuelve 13:32», ocupa 164,6 px a 14 px; con su ícono (15), el
 * espacio (5) y los márgenes del renglón (4) son 188,6. Por debajo se le reserva un renglón más: una hora cortada
 * con «…» no sirve.
 */
export const ANCHO_DE_UNA_LINEA = 190;

export interface Acomodo {
  columnas: number;
  filas: number;
  /** Ancho de cada casilla, en px. */
  ancho: number;
  /** Alto del retrato, en px. */
  foto: number;
  /** Letra del nombre de pila, en px. */
  letraNombre: number;
  /** Alto que ocupa el texto bajo el retrato, en px. */
  texto: number;
  /**
   * Cuántos renglones tiene reservados el estado. Uno; uno más si alguien salió y volvió («salió 13:00 · volvió
   * 13:45»); y uno más si la casilla es tan angosta que esos textos no entran en un renglón.
   */
  renglones: number;
  /** Espacio entre casillas, en px. */
  separacion: number;
  /** No entran a un tamaño que se lea: la grilla se desliza y lo avisa. */
  desliza: boolean;
}

/** La letra del nombre de pila crece con la casilla, entre 19 y 27 px. */
export function letraDelNombre(ancho: number): number {
  return Math.max(19, Math.min(27, Math.round(ancho * 0.115)));
}

/**
 * Lo que mide el texto bajo el retrato: nombre de pila, apellidos y la línea del
 * estado. Cada renglón de más del estado suma 18 px, y se reserva en TODAS las
 * casillas para que las filas no bailen.
 */
export function altoDelTexto(ancho: number, renglones: number): number {
  return 10 + Math.ceil(letraDelNombre(ancho) * 1.15) + 20 + 6 + 20 + 18 * (Math.max(1, renglones) - 1) + 4;
}

/** El alto de una casilla completa. */
export function altoDeCasilla(a: Pick<Acomodo, "foto" | "texto">): number {
  return a.foto + MARCO_CASILLA + a.texto;
}

/** Los renglones del estado: uno, más el de quien salió y volvió, más el que pide una casilla angosta. */
function renglonesPara(interior: number, segundaLinea: boolean): number {
  return 1 + (segundaLinea ? 1 : 0) + (interior < ANCHO_DE_UNA_LINEA ? 1 : 0);
}

function separacionPara(personas: number, ancho: number): number {
  if (personas <= 3) return 28;
  if (ancho >= 1600) return 16;
  return ancho >= 1100 ? 12 : 9;
}

export function acomodarRetratos(
  personas: number,
  ancho: number,
  alto: number,
  opciones: { segundaLinea?: boolean } = {},
): Acomodo {
  const segundaLinea = opciones.segundaLinea ?? false;
  const n = Math.max(1, Math.floor(personas));
  const separacion = separacionPara(n, ancho);
  let mejor: Acomodo | null = null;
  let mejorArea = 0;

  for (let columnas = 1; columnas <= n; columnas++) {
    const libre = Math.floor((ancho - separacion * (columnas - 1)) / columnas);
    if (libre < ANCHO_MINIMO) break; // con más columnas solo se angosta
    const anchoCasilla = Math.min(ANCHO_MAXIMO, libre);
    const filas = Math.ceil(n / columnas);
    const interior = anchoCasilla - MARCO_CASILLA;
    const renglones = renglonesPara(interior, segundaLinea);
    const texto = altoDelTexto(anchoCasilla, renglones);
    const altoFila = Math.floor((alto - separacion * (filas - 1)) / filas);
    const foto = Math.min(altoFila - MARCO_CASILLA - texto, Math.floor(interior * PROPORCION_MAXIMA), FOTO_MAXIMA);
    if (foto < interior * PROPORCION_MINIMA) continue; // quedaría una franja, no un retrato
    const area = interior * foto;
    if (!mejor || area > mejorArea) {
      mejor = { columnas, filas, ancho: anchoCasilla, foto, letraNombre: letraDelNombre(anchoCasilla), texto, renglones, separacion, desliza: false };
      mejorArea = area;
    }
  }

  if (mejor) return mejor;

  // No entran sin encoger los nombres: tantas columnas como quepan al ancho mínimo, y se desliza.
  const columnas = Math.max(1, Math.min(n, Math.floor((ancho + separacion) / (ANCHO_MINIMO + separacion))));
  const anchoCasilla = Math.max(1, Math.min(ANCHO_MAXIMO, Math.floor((ancho - separacion * (columnas - 1)) / columnas)));
  const renglones = renglonesPara(anchoCasilla - MARCO_CASILLA, segundaLinea);
  return {
    columnas,
    filas: Math.ceil(n / columnas),
    ancho: anchoCasilla,
    foto: Math.max(1, Math.round((anchoCasilla - MARCO_CASILLA) * 0.8)),
    letraNombre: letraDelNombre(anchoCasilla),
    texto: altoDelTexto(anchoCasilla, renglones),
    renglones,
    separacion,
    desliza: true,
  };
}
