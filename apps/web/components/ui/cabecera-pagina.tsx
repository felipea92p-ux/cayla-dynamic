// Cabecera de página compartida (2026-09-06). Antes cada una de las ~24
// pantallas de admin escribía su propio <h1 className="font-serif text-2xl">
// a mano, con márgenes inconsistentes (mb-1 en la mayoría, sin margen en
// otras, text-3xl suelto en Dashboard). Un solo tamaño fijo de acá en
// adelante.

import type { ReactNode } from "react";

export function CabeceraPagina({
  titulo,
  descripcion,
  accion,
}: {
  titulo: string;
  descripcion?: ReactNode;
  accion?: ReactNode;
}) {
  return (
    <div className="mb-8 flex items-start justify-between gap-4">
      <div>
        <h1 className="font-serif text-[1.75rem] font-medium leading-tight tracking-[-0.01em] text-tinta">
          {titulo}
        </h1>
        {descripcion && (
          <p className="mt-1 max-w-2xl text-sm text-taupe">{descripcion}</p>
        )}
      </div>
      {accion && <div className="shrink-0">{accion}</div>}
    </div>
  );
}
