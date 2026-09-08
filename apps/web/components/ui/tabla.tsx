// El envoltorio "overflow-x-auto rounded-2xl border border-sand bg-papel" y el
// encabezado "bg-sand/70 text-left text-taupe" aparecen, idénticos, en más de
// diez tablas de admin. <tr> y <td> se quedan afuera a propósito: ahí sí varía
// cada pantalla (colores condicionales, colSpan, celdas especiales).

import type { CSSProperties, ReactNode } from "react";
import { cx } from "./cx";

export function Tabla({
  children,
  className,
  alturaMaxima,
}: {
  children: ReactNode;
  className?: string;
  /**
   * Alto máximo del envoltorio (ej. "70vh", "480px"), para tablas largas.
   * Sin este prop el div nunca desborda verticalmente — nunca hace scroll
   * propio — así que el encabezado sticky de TablaEncabezado no tiene contra
   * qué pegarse y no hace nada. Pásalo cuando la tabla necesite cabecera fija
   * de verdad (ver TablaEncabezado más abajo).
   */
  alturaMaxima?: string;
}) {
  const style: CSSProperties | undefined = alturaMaxima ? { maxHeight: alturaMaxima } : undefined;
  return (
    <div
      className={cx(
        "overflow-x-auto rounded-superficie border border-sand bg-papel",
        alturaMaxima && "overflow-y-auto",
        className,
      )}
      style={style}
    >
      <table className="w-full text-sm">{children}</table>
    </div>
  );
}

// El sticky solo cobra efecto cuando el <Tabla> que envuelve recibe
// `alturaMaxima`: es ese div acotado el que hace scroll vertical, y el
// sticky se ancla a él (position: sticky se pega al contenedor con scroll
// más cercano, no a la ventana). Sin `alturaMaxima` el div nunca desborda,
// nunca hace scroll, y "sticky" no tiene ningún efecto visible — quien use
// TablaEncabezado en una tabla larga y quiera la cabecera fija tiene que
// pasarle `alturaMaxima` a su <Tabla>.
export function TablaEncabezado({ children }: { children: ReactNode }) {
  return (
    <thead className="sticky top-0 z-10 bg-sand/70 text-left text-taupe">
      <tr>{children}</tr>
    </thead>
  );
}

export function Th({ children, className }: { children?: ReactNode; className?: string }) {
  return <th className={cx("px-4 py-2 font-normal", className)}>{children}</th>;
}

// Fila con zebra sobre --color-hueso (la superficie "hundida" agregada el
// 2026-09-06) — no reemplaza los <tr> ya escritos a mano en cada pantalla,
// da un patrón listo para adoptar pantalla por pantalla.
export function Fila({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <tr
      className={cx(
        "border-t border-sand transition-colors duration-150 even:bg-hueso/50 hover:bg-crema/60",
        className,
      )}
    >
      {children}
    </tr>
  );
}
