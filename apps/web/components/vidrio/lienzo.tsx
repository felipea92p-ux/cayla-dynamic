"use client";

import { usePathname } from "next/navigation";

// El fondo del vidrio: el Lienzo de Retail, un solo degradado detrás de todo (estilos/vidrio/marco.css). No dibuja nada adentro: el
// degradado es el fondo de esta misma capa. Vive donde vive el marco: el ingreso y la nueva clave tienen su propio aspecto, y ese se
// revisa en su módulo.
export function Lienzo({ excepto = [] }: { excepto?: readonly string[] }) {
  const ruta = usePathname();
  if (excepto.includes(ruta)) return null;
  return <div aria-hidden className="vidrio-lienzo" />;
}
