// La lista de casos de Disciplina: tabla compacta en escritorio, tarjetas en
// el celular, con UN solo marcado.
//
// No es <Tabla> (components/ui/tabla.tsx) a propósito. Una <table> no se
// vuelve tarjeta sin duplicar la fila entera en otro marcado, y dos copias de
// la misma fila son dos lugares donde un botón de «Firmar» puede quedar
// habilitado en uno y no en el otro. Acá cada fila es una grilla que en el
// celular apila sus celdas con su rótulo delante, y desde `md` se alinea con
// el encabezado.
//
// `plantilla` lleva las clases `md:grid-cols-[…] lg:grid-cols-[…]` como texto
// LITERAL escrito en quien llama: Tailwind solo genera las clases que puede
// leer en el código. La columna `secundaria` se esconde en tablet (`md`) y
// vuelve en escritorio (`lg`), así que la plantilla de `md` tiene una columna
// menos por cada secundaria.

import type { ReactNode } from "react";
import { cx } from "@/components/ui/cx";

export interface Encabezado {
  texto: string;
  secundaria?: boolean;
  derecha?: boolean;
}

export function ListaCasos({
  etiqueta, plantilla, encabezados, children,
}: {
  /** Nombre accesible de la lista, p. ej. «Borradores». */
  etiqueta: string;
  plantilla: string;
  encabezados: Encabezado[];
  children: ReactNode;
}) {
  return (
    <div role="table" aria-label={etiqueta} className="overflow-hidden rounded-superficie border border-sand bg-papel">
      <div role="row" className={cx("hidden gap-4 bg-sand/70 px-4 py-2 text-xs text-taupe md:grid", plantilla)}>
        {encabezados.map((e, i) => (
          <div key={i} role="columnheader" className={cx(e.secundaria && "md:hidden lg:block", e.derecha && "text-right")}>
            {e.texto}
          </div>
        ))}
      </div>
      <div role="rowgroup" className="divide-y divide-sand">{children}</div>
    </div>
  );
}

export function FilaCaso({
  plantilla, id, resaltada = false, atenuada = false, children,
}: {
  plantilla: string;
  /** Ancla para los enlaces del Dashboard (`#tard-…`, `#falta-…`). */
  id?: string;
  resaltada?: boolean;
  /** Para lo que solo se sigue y no pide acción: se lee, pero no compite. */
  atenuada?: boolean;
  children: ReactNode;
}) {
  return (
    <div
      role="row"
      id={id}
      className={cx(
        "grid scroll-mt-24 gap-x-4 gap-y-1.5 px-4 py-3 text-sm transition-colors duration-300 md:items-center",
        plantilla,
        resaltada && "bg-rojo/10",
        atenuada && "text-taupe",
      )}
    >
      {children}
    </div>
  );
}

export function Celda({
  etiqueta, secundaria = false, acciones = false, children,
}: {
  /** El rótulo que se ve delante del valor en el celular, donde no hay encabezado. */
  etiqueta?: string;
  secundaria?: boolean;
  acciones?: boolean;
  children: ReactNode;
}) {
  return (
    <div
      role="cell"
      className={cx(
        "min-w-0",
        secundaria && "md:hidden lg:block",
        acciones && "flex flex-wrap items-center gap-2 pt-1 md:justify-end md:pt-0",
      )}
    >
      {etiqueta && <span className="mr-1.5 text-xs text-taupe md:hidden">{etiqueta}</span>}
      {children}
    </div>
  );
}
