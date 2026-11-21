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
//   de `.tr-casilla` en estilos/vidrio/terminal-retratos.css.
// ============================================================================

/** El relleno de la casilla alrededor del retrato, en px (`.tr-casilla`). */
export const RELLENO_CASILLA = 8;
/** Por debajo de este ancho un nombre de pila ya no se lee a un metro. */
export const ANCHO_MINIMO = 148;
/** Con tres personas el retrato no crece hasta llenar la pantalla. */
export const ANCHO_MAXIMO = 380;
export const FOTO_MAXIMA = 320;
/** Entre qué proporciones (alto ÷ ancho) el retrato sigue viéndose como una foto. */
const PROPORCION_MINIMA = 0.6;
const PROPORCION_MAXIMA = 1.25;

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
 * estado. `segundaLinea` reserva un renglón más para «salió 13:00 · volvió 13:45»,
 * y se reserva en TODAS las casillas para que las filas no bailen.
 */
export function altoDelTexto(ancho: number, segundaLinea: boolean): number {
  return 10 + Math.ceil(letraDelNombre(ancho) * 1.15) + 20 + 6 + 20 + (segundaLinea ? 18 : 0) + 4;
}

/** El alto de una casilla completa. */
export function altoDeCasilla(a: Pick<Acomodo, "foto" | "texto">): number {
  return a.foto + 2 * RELLENO_CASILLA + a.texto;
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
  let mejor: (Acomodo & { area: number }) | null = null;

  for (let columnas = 1; columnas <= n; columnas++) {
    const libre = Math.floor((ancho - separacion * (columnas - 1)) / columnas);
    if (libre < ANCHO_MINIMO) break; // con más columnas solo se angosta
    const anchoCasilla = Math.min(ANCHO_MAXIMO, libre);
    const filas = Math.ceil(n / columnas);
    const interior = anchoCasilla - 2 * RELLENO_CASILLA;
    const texto = altoDelTexto(anchoCasilla, segundaLinea);
    const altoFila = Math.floor((alto - separacion * (filas - 1)) / filas);
    const foto = Math.min(altoFila - 2 * RELLENO_CASILLA - texto, Math.floor(interior * PROPORCION_MAXIMA), FOTO_MAXIMA);
    if (foto < interior * PROPORCION_MINIMA) continue; // quedaría una franja, no un retrato
    const area = interior * foto;
    if (!mejor || area > mejor.area) {
      mejor = { columnas, filas, ancho: anchoCasilla, foto, letraNombre: letraDelNombre(anchoCasilla), texto, separacion, desliza: false, area };
    }
  }

  if (mejor) {
    const { area: _area, ...acomodo } = mejor;
    return acomodo;
  }

  // No entran sin encoger los nombres: tantas columnas como quepan al ancho mínimo, y se desliza.
  const columnas = Math.max(1, Math.min(n, Math.floor((ancho + separacion) / (ANCHO_MINIMO + separacion))));
  const anchoCasilla = Math.max(1, Math.min(ANCHO_MAXIMO, Math.floor((ancho - separacion * (columnas - 1)) / columnas)));
  return {
    columnas,
    filas: Math.ceil(n / columnas),
    ancho: anchoCasilla,
    foto: Math.max(1, Math.round((anchoCasilla - 2 * RELLENO_CASILLA) * 0.8)),
    letraNombre: letraDelNombre(anchoCasilla),
    texto: altoDelTexto(anchoCasilla, segundaLinea),
    separacion,
    desliza: true,
  };
}
