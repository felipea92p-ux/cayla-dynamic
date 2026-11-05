"use client";

import { usePathname } from "next/navigation";

// El fondo del vidrio: tres nubes muy tenues detrás de todo (estilos/vidrio/marco.css). Vive donde vive el marco: el ingreso y la
// nueva clave tienen su propio aspecto, y ese se revisa en su módulo.
export function Aurora({ excepto = [] }: { excepto?: readonly string[] }) {
  const ruta = usePathname();
  if (excepto.includes(ruta)) return null;
  return (
    <div aria-hidden className="vidrio-aurora">
      <i />
      <i />
      <i />
    </div>
  );
}
