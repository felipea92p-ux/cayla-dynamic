// Una sección de la pantalla Costos: su título y su tabla. Vivía dentro de admin/costos/page.tsx; se mudó aquí el 2026-11-10 para que
// «Por persona», que ahora trae buscador, filtro y páginas, use el mismo título y la misma tabla que las otras cinco sin copiarlos.
//
// No se llama "Tabla" para no chocar con el primitivo compartido (@/components/ui/tabla): esto solo le agrega el título de sección, y
// por dentro usa ese mismo <Tabla>, con la superficie elevada (bg-papel, rounded-superficie) del resto del panel.

import type { ReactNode } from "react";
import { Tabla } from "@/components/ui/tabla";
import { interruptoresVidrio } from "@/lib/vidrio";

export function TituloSeccion({ children }: { children: ReactNode }) {
  return <h2 className="mb-2 font-serif text-lg">{children}</h2>;
}

/** El <Tabla> de Costos: con el vidrio, ancho de sobra para sus siete u ocho columnas. */
export function TablaCostos({ children }: { children: ReactNode }) {
  return <Tabla className={interruptoresVidrio().panel ? "vidrio-tabla-ancha" : undefined}>{children}</Tabla>;
}

export function SeccionTabla({ titulo, children }: { titulo: string; children: ReactNode }) {
  return (
    <section className="mb-6">
      <TituloSeccion>{titulo}</TituloSeccion>
      <TablaCostos>{children}</TablaCostos>
    </section>
  );
}
