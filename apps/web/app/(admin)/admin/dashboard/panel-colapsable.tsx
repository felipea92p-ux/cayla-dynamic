"use client";

import type { ReactNode } from "react";
import { Boton } from "@/components/ui/boton";

// Un panel del Dashboard: siempre se puede colapsar; en modo «Personalizar»
// además se sube, se baja y se oculta. La regla de qué paneles NO se pueden
// ocultar vive en lib/admin/tablero-preferencias.ts, no aquí: este componente
// solo recibe `puedeOcultar` y no decide nada.
//
// El orden se aplica con `order` de CSS sobre un contenedor flex en columna, a
// propósito: así el contenido de cada panel —que usa el estado de toda la
// pantalla— se queda escrito donde está y reordenar no lo mueve de sitio.

interface Props {
  id: string;
  titulo: string;
  /** «en vivo · cada 30 s» — cada bloque dice cada cuánto se actualiza. */
  frescura?: string;
  orden: number;
  colapsado: boolean;
  alAlternar: () => void;
  personalizando: boolean;
  oculto: boolean;
  puedeOcultar: boolean;
  puedeSubir: boolean;
  puedeBajar: boolean;
  alSubir: () => void;
  alBajar: () => void;
  alOcultar: () => void;
  children: ReactNode;
}

export function PanelColapsable({
  id, titulo, frescura, orden, colapsado, alAlternar, personalizando, oculto, puedeOcultar,
  puedeSubir, puedeBajar, alSubir, alBajar, alOcultar, children,
}: Props) {
  // Un panel oculto solo se ve en «Personalizar», y ahí sin contenido: es para
  // poder volver a mostrarlo, no para leerlo.
  const sinContenido = colapsado || oculto;
  return (
    <section style={{ order: orden }} aria-labelledby={`panel-${id}-titulo`} className={oculto ? "mb-6 opacity-60" : undefined}>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <div className="flex flex-wrap items-baseline gap-x-3">
          <button
            type="button"
            onClick={alAlternar}
            aria-expanded={!sinContenido}
            aria-controls={`panel-${id}`}
            className="flex items-center gap-2 rounded-control py-1 text-left"
          >
            <span aria-hidden className="w-3 text-sm text-taupe">{sinContenido ? "▸" : "▾"}</span>
            <h2 id={`panel-${id}-titulo`} className="font-serif text-xl font-medium">{titulo}</h2>
          </button>
          {frescura && <span className="text-xs text-taupe">{frescura}</span>}
        </div>
        {personalizando && (
          <div className="flex gap-1.5">
            <Boton variante="sutil" tamano="sm" disabled={!puedeSubir} onClick={alSubir} aria-label={`Subir ${titulo}`}>↑</Boton>
            <Boton variante="sutil" tamano="sm" disabled={!puedeBajar} onClick={alBajar} aria-label={`Bajar ${titulo}`}>↓</Boton>
            {puedeOcultar ? (
              <Boton variante="sutil" tamano="sm" onClick={alOcultar}>{oculto ? "Mostrar" : "Ocultar"}</Boton>
            ) : (
              <span className="self-center text-xs text-taupe" title="Tiene consecuencias legales si se pasa por alto: solo se puede colapsar.">Solo colapsa</span>
            )}
          </div>
        )}
      </div>
      <div id={`panel-${id}`} hidden={sinContenido}>{children}</div>
    </section>
  );
}
