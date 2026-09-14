// El panel lateral (2026-09-14, rediseño de Horarios base). Hermano de Modal,
// no su reemplazo: Modal sigue siendo lo correcto para confirmaciones cortas
// y texto legal. Drawer es para un formulario con demasiado contenido para
// una ventana centrada — nació porque el de "Asignar/Cambiar horario" ya
// llevaba vigencia, copiar-de, historial, una grilla de hasta 7 filas, total
// semanal y motivo, y en un Modal esa pila competía por alto vertical.
//
// Reusa los dos hooks que ya resolvían exactamente este problema para el
// cajón del menú del panel y el de "Lo mío" (`useSalidaAnimada`,
// `useFocoAtrapado`) en vez de escribir una tercera versión de "animar la
// salida antes de desmontar" y "atrapar el foco" — la razón de ser de esos
// dos hooks fue justamente que la segunda copia ya era un riesgo.
//
// A diferencia de Modal, SÍ atrapa el foco completo (Tab no se escapa) y
// devuelve el foco a quien lo abrió al cerrarse — Modal todavía no lo hace
// (ver su propio comentario, "queda como mejora pendiente"); acá viene gratis
// por reusar `useFocoAtrapado`, no es un esfuerzo aparte.

"use client";

import { useId, useRef, type ReactNode } from "react";
import { useSalidaAnimada } from "@/lib/use-salida-animada";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";

// Tiene que calzar con la duración de `.cajon-derecha-sale` en globals.css —
// es la misma relación que ya exige el comentario de useSalidaAnimada.
const DURACION_SALIDA_MS = 200;

export function Drawer({
  abierto,
  onCerrar,
  titulo,
  bloqueado = false,
  volverElFocoA,
  children,
}: {
  abierto: boolean;
  onCerrar: () => void;
  titulo?: string;
  /** Mientras es true, ni el clic en el velo ni Escape cierran el drawer —
   * mismo contrato que Modal, para no perder una edición a medio guardar. */
  bloqueado?: boolean;
  /** A quién devolverle el foco al cerrar — normalmente el botón que abrió
   * el drawer. Ver useFocoAtrapado. */
  volverElFocoA: React.RefObject<HTMLElement | null>;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const tituloId = useId();
  const { montado, saliendo } = useSalidaAnimada(abierto, DURACION_SALIDA_MS);

  useFocoAtrapado({
    abierto,
    onCerrar: () => {
      if (!bloqueado) onCerrar();
    },
    caja: ref,
    volverElFocoA,
  });

  if (!montado) return null;

  return (
    <div
      className={`fixed inset-0 z-40 bg-black/40 ${saliendo ? "velo-sale" : "velo-entra"}`}
      onClick={() => {
        if (!bloqueado) onCerrar();
      }}
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titulo ? tituloId : undefined}
        aria-label={titulo ? undefined : "Panel"}
        tabIndex={-1}
        className={`absolute inset-y-0 right-0 flex w-full max-w-[460px] flex-col border-l border-taupe/35 bg-papel outline-none ${saliendo ? "cajon-derecha-sale" : "cajon-derecha-entra"}`}
        onClick={(e) => e.stopPropagation()}
      >
        {titulo && (
          <div className="shrink-0 border-b border-sand px-6 py-4">
            <h2 id={tituloId} className="font-serif text-lg font-medium text-tinta">
              {titulo}
            </h2>
          </div>
        )}
        <div className="flex-1 overflow-y-auto p-6">{children}</div>
      </div>
    </div>
  );
}
