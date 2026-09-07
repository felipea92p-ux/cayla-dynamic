// El envoltorio "overflow-x-auto rounded-2xl border border-sand bg-papel" y el
// encabezado "bg-sand/70 text-left text-taupe" aparecen, idénticos, en más de
// diez tablas de admin. <tr> y <td> se quedan afuera a propósito: ahí sí varía
// cada pantalla (colores condicionales, colSpan, celdas especiales).

import type { ReactNode } from "react";
import { cx } from "./cx";

export function Tabla({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cx("overflow-x-auto rounded-superficie border border-sand bg-papel", className)}>
      <table className="w-full text-sm">{children}</table>
    </div>
  );
}

export function TablaEncabezado({ children }: { children: ReactNode }) {
  return (
    <thead className="sticky top-0 z-10 bg-sand/85 text-left text-taupe">
      <tr>{children}</tr>
    </thead>
  );
}

export function Th({ children, className }: { children: ReactNode; className?: string }) {
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
