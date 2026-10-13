/**
 * Los easter eggs de Dynamic: la lógica de CUÁNDO se activa cada uno.
 *
 * El catálogo completo —qué hace cada uno, cómo se activa y dónde— está en
 * `docs/easter-eggs.md`; este archivo es solo la parte que se puede probar sin
 * un navegador (`tests/easter-eggs.test.ts`). Lo que se dibuja vive junto a
 * cada pantalla.
 *
 * LAS REGLAS QUE LOS HACEN «NADA INVASIVOS» (se deciden aquí, una vez):
 *   · Pasivos: ninguno se ve si nadie lo busca. No hay pista en pantalla.
 *   · Jamás en el terminal de marcaje. Es el único sitio donde lo que se toca
 *     decide a quién se le paga qué día; una tecla suelta no puede activar nada.
 *   · Nunca escriben en la base ni mandan nada a ninguna parte.
 *   · Nunca mientras alguien escribe en un campo: no se puede perder un dato
 *     por buscar un huevo.
 */

import { sinTildes } from "./sin-tildes";

// ---------------------------------------------------------------- código Konami

/** ↑ ↑ ↓ ↓ ← → ← → B A. Las letras se comparan sin mayúsculas. */
export const CODIGO_KONAMI = [
  "ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown",
  "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight",
  "b", "a",
] as const;

// Cuántas teclas conserva cada prefijo del código si se falla justo ahí
// (la «tabla de fallos» de Knuth-Morris-Pratt). Se calcula una vez; sin ella,
// un error en medio obligaría a empezar de cero aunque lo último pulsado ya
// fuera el comienzo de un intento válido — ↑↑↑↓↓… debe seguir valiendo.
const SI_FALLA: number[] = (() => {
  const t: number[] = [0];
  for (let i = 1, k = 0; i < CODIGO_KONAMI.length; i++) {
    while (k > 0 && CODIGO_KONAMI[i] !== CODIGO_KONAMI[k]) k = t[k - 1];
    if (CODIGO_KONAMI[i] === CODIGO_KONAMI[k]) k++;
    t[i] = k;
  }
  return t;
})();

/**
 * Cuántas teclas de la secuencia lleva alguien, después de pulsar `tecla`.
 * Llega a `CODIGO_KONAMI.length` cuando completó el código; quien llama lo
 * vuelve a poner en 0 al activar. Un error no borra todo: se conserva lo que
 * todavía pueda ser el comienzo de un intento (↑↑↑↓↓… sigue siendo válido).
 */
export function avanzarKonami(progreso: number, tecla: string): number {
  const t = tecla.length === 1 ? tecla.toLowerCase() : tecla;
  let k = progreso;
  while (k > 0 && t !== CODIGO_KONAMI[k]) k = SI_FALLA[k - 1];
  return t === CODIGO_KONAMI[k] ? k + 1 : 0;
}

// ---------------------------------------------------------------- el buscador

/** La palabra que abre el juego en el buscador (⌘K). Sin tildes ni mayúsculas: «Colibrí», «colibri» y «COLIBRÍ» valen. */
export function esPalabraDelColibri(consulta: string): boolean {
  return sinTildes(consulta.trim()) === "colibri";
}

// ---------------------------------------------------------------- clics seguidos

export const CLICS_PARA_EL_HUEVO = 5;
/** Los cinco clics tienen que caber en este tiempo; si no, es alguien tocando el logo con calma. */
export const VENTANA_DE_CLICS_MS = 2000;

/**
 * Anota un clic y dice si ya hubo `CLICS_PARA_EL_HUEVO` dentro de la ventana.
 * Es pura: recibe las marcas de tiempo y devuelve las nuevas, así se prueba
 * sin reloj. Al dispararse arranca de cero.
 */
export function registrarClic(
  marcas: readonly number[],
  ahora: number,
): { marcas: number[]; dispara: boolean } {
  const vigentes = [...marcas.filter((m) => ahora - m <= VENTANA_DE_CLICS_MS), ahora];
  if (vigentes.length >= CLICS_PARA_EL_HUEVO) return { marcas: [], dispara: true };
  return { marcas: vigentes, dispara: false };
}

// ---------------------------------------------------------------- fechas

/**
 * Un toque de fecha en la línea de saludo del login («Buenos días · …»).
 * `fecha` es un día de Lima, «AAAA-MM-DD» (`fechaLima`/`hoyLima`), nunca la
 * hora del aparato.
 *
 * ESTO NO ES EL CALENDARIO DE FERIADOS. Los feriados de verdad —los que
 * mueven un pago— viven en la tabla `feriados` y se gestionan desde su
 * pantalla; el login ni siquiera puede leerla antes de entrar. Esto es un
 * adorno de saludo, y si algún día un feriado se mueve no cambia ni un sol de
 * nadie: por eso es una lista de dos y no una consulta. Quien quiera sumar una
 * fecha la agrega acá y en `docs/easter-eggs.md`.
 */
const TOQUES: ReadonlyArray<{ mes: number; dias: readonly number[]; texto: string }> = [
  { mes: 7, dias: [28, 29], texto: "Felices Fiestas Patrias" },
  { mes: 12, dias: [24, 25], texto: "Feliz Navidad" },
];

export function toqueDeFecha(fecha: string): string | null {
  const m = /^\d{4}-(\d{2})-(\d{2})$/.exec(fecha);
  if (!m) return null;
  const mes = Number(m[1]);
  const dia = Number(m[2]);
  return TOQUES.find((t) => t.mes === mes && t.dias.includes(dia))?.texto ?? null;
}
