// El envoltorio "overflow-x-auto rounded-2xl border border-sand bg-papel" y el
// encabezado "bg-sand/70 text-left text-taupe" aparecen, idénticos, en más de
// diez tablas de admin. <tr> y <td> se quedan afuera a propósito: ahí sí varía
// cada pantalla (colores condicionales, colSpan, celdas especiales).

import type { ReactNode } from "react";
import { cx } from "./cx";

export function Tabla({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cx("overflow-x-auto rounded-2xl border border-sand bg-papel", className)}>
      <table className="w-full text-sm">{children}</table>
    </div>
  );
}

export function TablaEncabezado({ children }: { children: ReactNode }) {
  return (
    <thead className="bg-sand/70 text-left text-taupe">
      <tr>{children}</tr>
    </thead>
  );
}

export function Th({ children, className }: { children: ReactNode; className?: string }) {
  return <th className={cx("px-4 py-2 font-normal", className)}>{children}</th>;
}
