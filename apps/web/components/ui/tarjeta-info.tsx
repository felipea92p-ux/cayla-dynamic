// El envoltorio "rounded-2xl border border-sand bg-papel p-5" aparece copiado
// a mano en al menos 8 pantallas (personas/[id], objetivos, feriados, sedes,
// equipo, horas, dashboard, incidencias) — con el mismo defecto que ya
// resolvieron Boton/Campo/Insignia: cada copia hereda el padding que le tocó
// (p-4 en horas, p-5 en el resto), sin que el contenido explique la
// diferencia. Acá vive una sola vez.
//
// `como` y el resto de atributos (2026-10-17, migración de «Lo mío»): una
// tarjeta también es a veces un <section> con su id, un <li> de una lista o un
// <aside>, y obligar a que fuera siempre un <div> era la razón por la que esas
// se quedaban escritas a mano con la receta pegada. El elemento correcto se
// pide con `como`; lo demás (id, aria-live, data-tour…) pasa tal cual. Quien no
// los usa no nota nada.

import type { HTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

type Elemento = "div" | "section" | "li" | "article" | "aside" | "header";

export function TarjetaInfo({
  como: Etiqueta = "div",
  titulo,
  accion,
  children,
  className,
  ...resto
}: {
  /** El elemento HTML de la tarjeta. `section` si es una región con título, `li` si es un renglón de una lista. */
  como?: Elemento;
  /** Texto del encabezado (font-serif text-lg, igual que el h2 que ya escribían a mano). Omitilo si la tarjeta no necesita título propio. */
  titulo?: ReactNode;
  /** Elemento a la derecha del título — típicamente un <Link> "Editar →" o similar. Se ignora si no hay `titulo`. */
  accion?: ReactNode;
  children: ReactNode;
  className?: string;
} & Omit<HTMLAttributes<HTMLElement>, "title" | "className" | "children">) {
  return (
    // p-4 en celular y p-5 desde 640 px (decisión 3 de docs/adr/0004-diseno-unificado.md,
    // 2026-10-13): en el teléfono cada tarjeta regala 8 px de ancho útil, y en
    // escritorio respira igual que siempre.
    <Etiqueta className={cx("rounded-superficie border border-sand bg-papel p-4 sm:p-5", className)} {...resto}>
      {titulo && (
        <div className="mb-2 flex items-baseline justify-between gap-2">
          <h2 className="font-serif text-lg">{titulo}</h2>
          {accion}
        </div>
      )}
      {children}
    </Etiqueta>
  );
}
