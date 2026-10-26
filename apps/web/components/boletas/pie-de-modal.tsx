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
 * Y por eso va `-bottom-6`, no `bottom-0` (2026-10-17). El navegador pega un
 * `sticky` contra el borde del modal MENOS su relleno: con `bottom-0` el pie se
 * quedaba siempre 24 px más arriba de lo que su `-mb-6` le pide, y esos 24 px
 * los tapaba del contenido. Se medía igual con el modal corto o desplazado
 * hasta el final: 8 px de la última línea —«Queda como borrador…», la casilla
 * «Confirmo que es la boleta de…»— quedaban debajo del pie, sin barra que los
 * alcanzara, y debajo de los botones sobraba una franja de 24 px. `-bottom-6`
 * devuelve ese relleno: el pie toca el borde y la última línea se ve entera.
 *
 * En celular los botones se apilan a lo ancho (el principal, arriba); desde
 * `sm` van en una fila a la derecha.
 */
export function PieDeModal({ children }: { children: ReactNode }) {
  return (
    <div className="sticky -bottom-6 -mx-6 -mb-6 mt-4 flex flex-col-reverse gap-2 border-t border-sand bg-papel px-6 py-3 sm:flex-row sm:justify-end">
      {children}
    </div>
  );
}
