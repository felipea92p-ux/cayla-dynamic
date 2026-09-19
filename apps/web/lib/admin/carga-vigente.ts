/**
 * Cuál de varias cargas simultáneas es la que vale.
 *
 * QUÉ PROMETE. Que solo la ÚLTIMA carga que se pidió pueda escribir en la
 * pantalla. Una carga anterior que llega después se descarta.
 *
 * POR QUÉ EXISTE. Al pasar de «Últimos 30 días» a «Esta semana» salen dos cargas
 * en vuelo. Si la de 30 días es la más lenta, termina la última y pisa a la
 * buena: la pantalla dice «Esta semana» con casos de 30 días, y «Marcar como
 * revisadas» actúa sobre casos que quien mira cree fuera del periodo elegido.
 *
 * SE ROMPE SI una pantalla escribe estado ANTES de preguntar `vigente(id)`
 * (después de cada `await`, no solo del último).
 */
export function crearCargaVigente() {
  let ultima = 0;
  return {
    /** Se llama al empezar a cargar; devuelve el número de esa carga. */
    empezar: () => ++ultima,
    /** ¿Sigue siendo la carga más reciente? */
    vigente: (id: number) => id === ultima,
  };
}
