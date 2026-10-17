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
  sobretitulo,
  titulo,
  descripcion,
  accion,
}: {
  /**
   * La línea chica encima del título («Planilla», «Hoja de sede»). Mayúsculas con
   * espaciado (decisión 11 de docs/adr/0004-diseno-unificado.md, 2026-10-13):
   * es el detalle de identidad que ya aparece en el login. Opcional: la
   * mayoría de las pantallas no lleva. Acepta un nodo y no solo texto
   * (2026-10-17): el de un reporte lleva su código con cifras tabulares.
   */
  sobretitulo?: ReactNode;
  titulo: string;
  descripcion?: ReactNode;
  accion?: ReactNode;
}) {
  return (
    // `mb-5` en celular (2026-10-06): 32 px de aire bajo el título eran 32 px
    // menos de pantalla útil en un teléfono, en las 18 pantallas que la usan.
    <div className="mb-5 flex flex-wrap items-start justify-between gap-4 sm:mb-8">
      <div>
        {sobretitulo && <p className="etiqueta mb-1 text-taupe">{sobretitulo}</p>}
        <h1 className="font-serif text-[1.75rem] font-medium leading-tight tracking-[-0.01em] text-tinta">
          {titulo}
        </h1>
        {descripcion && (
          <div className="mt-1 max-w-2xl text-sm text-taupe">{descripcion}</div>
        )}
      </div>
      {/* `max-w-full` (2026-10-17): `shrink-0` solo evita que el botón se aplaste, pero también dejaba que
          cuatro botones juntos (Seguros) midieran lo que midieran y se salieran del teléfono, aunque su propio
          contenedor sea `flex-wrap`: no tenían un ancho contra el cual envolver. Con el tope, un grupo de botones
          envuelve a otra fila; una acción sola, que cabe, no cambia. */}
      {accion && <div className="max-w-full shrink-0">{accion}</div>}
    </div>
  );
}
