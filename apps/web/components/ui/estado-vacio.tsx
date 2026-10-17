// Estado vacío (decisión 8 de docs/adr/0004-diseno-unificado.md): cuando no hay
// nada que mostrar, una caja centrada que dice qué falta y —si hay una— ofrece
// el siguiente paso. Hasta el 2026-10-13 unas pantallas ponían una línea gris
// suelta y otras una caja, y ninguna decía qué hacer ahora: quien llega a una
// lista vacía sin saber qué sigue pide ayuda, y eso es del diseño, no de ella.
//
// `accion` es opcional A PROPÓSITO: donde no hay un siguiente paso evidente se
// usa la caja sola. Inventar un botón para llenar el hueco sería peor que no
// tenerlo. Dentro de una tabla (`<td colSpan>`) NO se usa: ahí el vacío es una
// fila y la tabla ya es la caja.

import type { ReactNode } from "react";
import { cx } from "./cx";

export function EstadoVacio({
  children,
  accion,
  className,
}: {
  /** Qué falta, en una línea: «Todavía no hay marcajes de hoy.» */
  children: ReactNode;
  /** El siguiente paso, típicamente un <Boton variante="secundario">. */
  accion?: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cx(
        "flex flex-col items-center gap-3 rounded-superficie border border-sand bg-papel px-4 py-6 text-center text-sm text-taupe",
        className,
      )}
    >
      <p>{children}</p>
      {accion}
    </div>
  );
}
