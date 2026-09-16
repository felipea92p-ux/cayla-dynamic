// Cabecera de página compartida (2026-09-06). Antes cada una de las ~24
// pantallas de admin escribía su propio <h1 className="font-serif text-2xl">
// a mano, con márgenes inconsistentes (mb-1 en la mayoría, sin margen en
// otras, text-3xl suelto en Dashboard). Un solo tamaño fijo de acá en
// adelante.
//
// `flex-wrap` (2026-09-14): con `accion`, en una pantalla angosta el título
// y el botón no cabían en una fila y el botón se cortaba fuera del viewport
// — se vio con "+ Generar documento" en Documentación, pero ya le pasaba
// también a "+ Registrar asignación" en Educación. Envolver a una segunda
// línea es estrictamente mejor que recortar la acción principal de la
// pantalla; en desktop nunca hay tan poco ancho como para que dispare.
//
// `descripcion` va en un `<div>`, no en un `<p>` (2026-09-16): Dashboard y
// Horas nunca adoptaron esta cabecera porque su descripción real es más de
// una línea (el punto "en vivo", el aviso de qué NO se refresca, filtros de
// rango) y un `<p>` no puede contener otros bloques sin que el navegador
// cierre la etiqueta antes de tiempo. Un `<div>` con `mt-1 text-sm text-taupe`
// se ve idéntico para el caso de una sola línea de texto (Tailwind ya pone
// todos los márgenes en cero) y además admite varias.
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
    <div className="mb-8 flex flex-wrap items-start justify-between gap-4">
      <div>
        <h1 className="font-serif text-[1.75rem] font-medium leading-tight tracking-[-0.01em] text-tinta">
          {titulo}
        </h1>
        {descripcion && (
          <div className="mt-1 max-w-2xl text-sm text-taupe">{descripcion}</div>
        )}
      </div>
      {accion && <div className="shrink-0">{accion}</div>}
    </div>
  );
}
