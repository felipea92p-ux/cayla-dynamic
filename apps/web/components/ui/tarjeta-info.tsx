// El envoltorio "rounded-2xl border border-sand bg-papel p-5" aparece copiado
// a mano en al menos 8 pantallas (personas/[id], objetivos, feriados, sedes,
// equipo, horas, dashboard, incidencias) — con el mismo defecto que ya
// resolvieron Boton/Campo/Insignia: cada copia hereda el padding que le tocó
// (p-4 en horas, p-5 en el resto), sin que el contenido explique la
// diferencia. Acá vive una sola vez.

import type { ReactNode } from "react";
import { cx } from "./cx";

export function TarjetaInfo({
  titulo,
  accion,
  children,
  className,
}: {
  /** Texto del encabezado (font-serif text-lg, igual que el h2 que ya escribían a mano). Omitilo si la tarjeta no necesita título propio. */
  titulo?: ReactNode;
  /** Elemento a la derecha del título — típicamente un <Link> "Editar →" o similar. Se ignora si no hay `titulo`. */
  accion?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cx("rounded-superficie border border-sand bg-papel p-5", className)}>
      {titulo && (
        <div className="mb-2 flex items-baseline justify-between gap-2">
          <h2 className="font-serif text-lg">{titulo}</h2>
          {accion}
        </div>
      )}
      {children}
    </div>
  );
}
