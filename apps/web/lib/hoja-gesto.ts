// Las reglas del dedo sobre una hoja del teléfono, sin React ni pantalla: cuándo un arrastre es de la hoja y no del contenido, cuánto se mueve, con
// qué velocidad se soltó y a dónde va al soltar. Vienen de Retail (lib/hoja-gesto.ts, ADR-0479) con sus mismos números; quien mueve la hoja es
// `use-hoja-arrastre.ts`, y las pruebas están en tests/hoja-gesto.test.ts.
//
// Las posiciones son píxeles hacia abajo desde la hoja abierta: 0 es abierta del todo y el alto de la hoja es cerrada.

/** Lo que el dedo tiene que recorrer antes de que se decida de quién es el gesto. */
export const MOVIMIENTO_MINIMO = 6;

/** Soltada más allá de este tramo, la hoja se va: un tercio. Cerrar es fácil, no accidental. */
export const FRACCION_PARA_PASAR = 1 / 3;

/** Un tirón decide aunque el dedo haya recorrido poco: 0,5 px/ms son 500 px por segundo. */
const VELOCIDAD_TIRON = 0.5;

/** La velocidad se mide en los últimos 100 ms: si el dedo se detuvo antes de soltar, no hay tirón. */
const VENTANA_VELOCIDAD = 100;

/** Lo más que cede la hoja cuando se tira más allá de su tope, o cuando no se puede cerrar porque está guardando. */
export const TOPE_GOMA = 44;

export type Muestra = { t: number; y: number };

/**
 * De quién es el gesto, o `null` si todavía no se sabe. La hoja solo lo toma cuando el dedo BAJA y todo lo que corre bajo él está arriba del todo; de
 * lado (una tabla que corre) o hacia arriba, el gesto es del contenido.
 */
export function decidirGesto(dx: number, dy: number, contenidoArriba: boolean): "hoja" | "contenido" | null {
  if (Math.abs(dx) < MOVIMIENTO_MINIMO && Math.abs(dy) < MOVIMIENTO_MINIMO) return null;
  if (Math.abs(dx) > Math.abs(dy)) return "contenido";
  return dy > 0 && contenidoArriba ? "hoja" : "contenido";
}

/** Cuánto cede algo que se tira `d` px más allá de su tope: crece cada vez menos y nunca pasa de `tope`. Sin rebote. */
export function goma(d: number, tope: number = TOPE_GOMA): number {
  if (d <= 0) return 0;
  return (1 - 1 / (d / (tope * 3.6) + 1)) * tope;
}

/** Dónde dibujar la hoja mientras el dedo la lleva. Más arriba de abierta, resiste. Con `resiste` (está guardando), también hacia abajo: se ve que la oyó, pero no se va. */
export function posicionAlArrastrar(dy: number, resiste = false): number {
  if (dy < 0) return -goma(-dy);
  return resiste ? goma(dy) : dy;
}

/** Velocidad del dedo al soltar, en px por ms (positiva hacia abajo). */
export function velocidad(muestras: readonly Muestra[]): number {
  if (muestras.length < 2) return 0;
  const ultima = muestras[muestras.length - 1];
  const primera = muestras.find((m) => ultima.t - m.t <= VENTANA_VELOCIDAD) ?? muestras[0];
  const dt = ultima.t - primera.t;
  if (dt <= 0) return 0;
  return (ultima.y - primera.y) / Math.max(16, dt);
}

/** ¿Se va la hoja al soltarla? Un tirón decide; si no, pasa quien recorrió más de un tercio de su alto. */
export function seVaAlSoltar(y: number, alto: number, vy: number): boolean {
  if (vy > VELOCIDAD_TIRON) return true;
  if (vy < -VELOCIDAD_TIRON) return false;
  return y > alto * FRACCION_PARA_PASAR;
}

/** Cuánto tarda en llegar al soltarla: lo que le queda dividido por la velocidad que traía el dedo, entre 180 y 420 ms. */
export function duracionHacia(distancia: number, vy: number): number {
  const ms = Math.abs(distancia) / Math.max(Math.abs(vy), 1);
  return Math.round(Math.min(420, Math.max(180, ms)));
}

/** Cuánto de la hoja se fue (0 abierta, 1 cerrada): el velo se aclara y lo de atrás vuelve en esa misma proporción. */
export function progresoDeCierre(y: number, alto: number): number {
  if (alto <= 0) return 0;
  return Math.min(1, Math.max(0, y / alto));
}

/** Lo de atrás con una hoja abierta: la pantalla se aleja a 0,92, baja 12 px y su cabecera se redondea, como una tarjeta que quedó debajo. */
export const FONDO_ALEJADO = { escala: 0.92, bajada: 12, radio: 18 } as const;

export function fondoSegun(progreso: number): { escala: number; bajada: number; radio: number } {
  const p = Math.min(1, Math.max(0, progreso));
  return {
    escala: FONDO_ALEJADO.escala + (1 - FONDO_ALEJADO.escala) * p,
    bajada: FONDO_ALEJADO.bajada * (1 - p),
    radio: FONDO_ALEJADO.radio * (1 - p),
  };
}

/** Lo de atrás con el menú abierto: el menú entra de costado, así que la pantalla se corre 34 px hacia la derecha y se aleja a 0,94. */
export const FONDO_DE_LADO = { escala: 0.94, corrida: 34, radio: 22 } as const;

export function fondoDeLadoSegun(progreso: number): { escala: number; corrida: number; radio: number } {
  const p = Math.min(1, Math.max(0, progreso));
  return {
    escala: FONDO_DE_LADO.escala + (1 - FONDO_DE_LADO.escala) * p,
    corrida: FONDO_DE_LADO.corrida * (1 - p),
    radio: FONDO_DE_LADO.radio * (1 - p),
  };
}
