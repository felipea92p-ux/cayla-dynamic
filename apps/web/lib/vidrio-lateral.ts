// ============================================================================
// El menú lateral con vidrio: si se ve abierto (272 px) o plegado (84 px).
// ============================================================================
//
// QUÉ PROMETE
//   Un solo lugar dice si el menú está plegado: el atributo `data-lateral` de <html>. Lo pone el guion que corre antes de pintar
//   (lib/vidrio.ts) y lo mantienen estas funciones. La hoja de estilos lo lee directo, así que el primer pintado ya sale bien.
//
// QUÉ ASUME
//   La misma preferencia y la misma clave de `lib/use-nav-colapsado.ts`: quien pidió el menú angosto lo pidió una vez, con el vidrio
//   encendido o apagado. Sin elección, manda el ancho de la ventana: bajo 1280 px, plegado.
//
// DECIDÍ: el atributo en <html>, escrito antes de pintar.
// DESCARTÉ: el estado de React de `useNavColapsado`, porque ese recién sabe el ancho después de montar: una laptop de 1024 px vería
//   el menú abierto un instante y cerrarse. Con 37 filas y 272 px de ancho, ese salto se nota en cada recarga.
// SE ROMPE SI: alguien pone el plegado solo en React. La hoja de estilos y las filas dirían cosas distintas hasta la siguiente lectura.
// ============================================================================

export const CLAVE_LATERAL = "cayla-nav-colapsado";
export const ATRIBUTO_LATERAL = "data-lateral";
// En rem, como las utilidades `xl:` y `md:` de Tailwind: las dos cosas tienen que cambiar en el mismo ancho aunque alguien agrande la letra.
export const CONSULTA_ANCHA = "(min-width: 80rem)";
export const CONSULTA_CELULAR = "(max-width: 47.99rem)";

/** La regla entera. La repite, por fuerza, el guion de lib/vidrio.ts; la prueba exige que contesten igual. */
export function resolverPlegado(guardado: string | null, ventanaAncha: boolean): boolean {
  if (guardado === "rail") return true;
  if (guardado === "ancho") return false;
  return !ventanaAncha;
}

function leerGuardado(): string | null {
  try {
    return localStorage.getItem(CLAVE_LATERAL);
  } catch {
    return null; // Sin almacenamiento (modo privado) no hay preferencia: manda la ventana.
  }
}

const oyentes = new Set<() => void>();
const avisar = () => oyentes.forEach((o) => o());

function escribir(plegado: boolean): void {
  const raiz = document.documentElement;
  if (plegado) raiz.setAttribute(ATRIBUTO_LATERAL, "plegado");
  else raiz.removeAttribute(ATRIBUTO_LATERAL);
  avisar();
}

export const lateralPlegado = (): boolean => document.documentElement.getAttribute(ATRIBUTO_LATERAL) === "plegado";

/** Vuelve a leer la preferencia y la ventana. Lo usa quien entra al panel sin recargar (`VidrioEnRuta`) y el cambio de ancho. */
export function aplicarLateral(): void {
  escribir(resolverPlegado(leerGuardado(), window.matchMedia(CONSULTA_ANCHA).matches));
}

/** El botón redondo y la tecla «[». Lo que se elige a mano se recuerda y le gana a la ventana. */
export function alternarLateral(): void {
  const plegar = !lateralPlegado();
  try {
    localStorage.setItem(CLAVE_LATERAL, plegar ? "rail" : "ancho");
  } catch {
    // Cambia igual en esta pestaña; solo no se acuerda mañana.
  }
  escribir(plegar);
}

export function suscribirLateral(oyente: () => void): () => void {
  oyentes.add(oyente);
  const consulta = window.matchMedia(CONSULTA_ANCHA);
  consulta.addEventListener("change", aplicarLateral);
  return () => {
    oyentes.delete(oyente);
    consulta.removeEventListener("change", aplicarLateral);
  };
}
