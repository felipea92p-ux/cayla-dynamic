// La línea de datos de una fila: sede, área, antigüedad… los datos sueltos que van debajo de un nombre y que no forman
// frase. Caso 2 de la regla «Separar sin punto» que Felipe aprobó el 2026-11-27 (docs/adr/0007-sin-punto-medio.md).
//
// Hasta entonces se escribían en una tira con «·» entre ellos («AQP · Calidad & servicio · 1 a. 7 m.»). Así no se sabe
// qué es cada dato, y un lector de pantalla los lee pegados: NVDA calla el «·» sin pausa. Aquí cada dato es su pieza,
// con espacio entre ellas y sin ningún signo. Lleva un ícono chico que dice qué es (Felipe eligió «con ícono»), mudo
// para el lector, y un rótulo que solo oye el lector («Sede: AQP»), como la tira de metadatos de la BBC.
//
// Retail manda en el diseño: esta pieza nació en Dynamic para la muestra de Asistencia, y la que quede en Retail
// reemplaza a esta con la misma forma (docs/familia/).

import type { ComponentType } from "react";
import { cx } from "./cx";

export interface DatoDeLinea {
  /** El ícono de lucide que dice qué es el dato. */
  icono: ComponentType<{ className?: string; "aria-hidden"?: boolean; strokeWidth?: number }>;
  /** Qué es, para el lector de pantalla: «Sede», «Área», «En CAYLA desde hace». */
  rotulo: string;
  valor: string;
}

export function LineaDeDatos({
  datos,
  className,
}: {
  /** Los vacíos se omiten: una pieza sin valor no se dibuja. */
  datos: readonly (DatoDeLinea | null | false | undefined)[];
  className?: string;
}) {
  const visibles = datos.filter((d): d is DatoDeLinea => Boolean(d && d.valor));
  if (visibles.length === 0) return null;
  // `span` y no `ul`: la línea vive a veces dentro de un <button> (las tarjetas de Desempeño), donde una lista no es válida.
  return (
    <span className={cx("flex flex-wrap items-center gap-x-3.5 gap-y-0.5 text-xs text-taupe", className)}>
      {visibles.map((d) => (
        <span key={d.rotulo} className="inline-flex items-center gap-1 whitespace-nowrap">
          <d.icono className="size-3 shrink-0" aria-hidden strokeWidth={1.8} />
          <span className="sr-only">{d.rotulo}: </span>
          {d.valor}
        </span>
      ))}
    </span>
  );
}
