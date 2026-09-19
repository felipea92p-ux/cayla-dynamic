import type { ReactNode } from "react";

/**
 * Para los botones de un modal de boletas en un celular: 40 px de alto como
 * mínimo (un dedo no acierta a 28 px), y en computadora vuelven a su tamaño de
 * siempre. Se agrega como `className` a un `<Boton>`.
 */
export const TACTIL = "min-h-10 md:min-h-0";

/**
 * La fila de botones al pie de un modal de boletas.
 *
 * Queda PEGADA al borde de abajo mientras el contenido se desplaza: un editor
 * con muchas hojas mide más que la pantalla de un celular, y el botón de
 * guardar no puede quedar tres pantallas más abajo. Los márgenes negativos
 * cancelan el relleno del modal (`p-6`) para que el fondo cubra todo el ancho
 * y no se transparente el texto que pasa por detrás.
 *
 * En celular los botones se apilan a lo ancho (el principal, arriba); desde
 * `sm` van en una fila a la derecha.
 */
export function PieDeModal({ children }: { children: ReactNode }) {
  return (
    <div className="sticky bottom-0 -mx-6 -mb-6 mt-4 flex flex-col-reverse gap-2 border-t border-sand bg-papel px-6 py-3 sm:flex-row sm:justify-end">
      {children}
    </div>
  );
}
