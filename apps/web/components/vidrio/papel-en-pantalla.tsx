// La parte de una pantalla que ES el papel, cuando toda la pantalla lleva la clase `hoja`. Las dos de constancias (de una norma y de la política) la llevan en el <main> para que salgan bien
// al imprimir, y ahí adentro también viven el menú, «Imprimir» y «Volver»: en pantalla, eso no es parte del documento y no va encima de la hoja. Apagado no agrega nada.

import type { ReactNode } from "react";
import { interruptoresVidrio } from "@/lib/vidrio";

export function PapelEnPantalla({ children }: { children: ReactNode }) {
  if (!interruptoresVidrio().panel) return <>{children}</>;
  return <div className="vidrio-papel">{children}</div>;
}
