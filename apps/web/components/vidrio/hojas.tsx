"use client";

// Las tres hojas con vidrio: las de `modal.tsx`, `drawer.tsx` y `hoja-inferior.tsx` cuando el interruptor está encendido. Por fuera prometen lo mismo que
// las de siempre, con las mismas clases, porque la pantalla no se entera. Lo que cambia está en `lib/use-hoja-viva.ts` y `estilos/vidrio/movimiento.css`.
//
// DECIDÍ: cuelgan de <body>.
// DESCARTÉ: dejarlas donde las escribe cada pantalla, porque en el teléfono lo de atrás se aleja con un `transform`, y un `transform` en un ancestro vuelve
//   relativo a él todo lo `fixed`: la hoja se encogería junto con la pantalla. Lo mismo pasa con una hoja dentro de una tarjeta de vidrio.
// SE ROMPE SI: una hoja queda dentro de un <form> de su pantalla y confía en él para enviarse: un portal saca sus campos del formulario. Medido el 2026-11-05 en las 113
//   hojas: ninguna. O un <Menu> envuelve la hoja: su `contains(e.target)` tomaría el clic de adentro por un clic afuera y lo cerraría. Medido el mismo día: ninguno.

import { useEffect, useId, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";
import { useHojaViva } from "@/lib/use-hoja-viva";

function Asa() {
  return <div aria-hidden data-asa-hoja className="vidrio-asa" />;
}

type PropsModal = { onCerrar: () => void; titulo?: string; anchoClase: string; bloqueado: boolean; children: ReactNode };

function ModalAbierto({ onCerrar, titulo, anchoClase, bloqueado, children }: PropsModal) {
  const tituloId = useId();
  const pedirCierre = () => {
    if (!bloqueado) onCerrar();
  };
  const { velo, hoja, ponerHoja } = useHojaViva({ onCerrar, bloqueado });

  const disparador = useRef<HTMLElement | null>(null);
  useEffect(() => {
    disparador.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  }, []);
  useFocoAtrapado({ abierto: true, onCerrar: pedirCierre, caja: hoja, volverElFocoA: disparador, enfocarPrimero: false });
  // El foco en el propio diálogo, no en su primer botón: puede ser «Anular» o «Eliminar». Sin desplazar nada mientras la hoja entra.
  useEffect(() => {
    hoja.current?.focus({ preventScroll: true });
  }, [hoja]);

  return createPortal(
    <div ref={velo} data-hoja-vidrio className="fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4" onClick={pedirCierre}>
      <div
        ref={ponerHoja}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titulo ? tituloId : undefined}
        aria-label={titulo ? undefined : "Diálogo"}
        tabIndex={-1}
        className={`max-h-[90vh] w-full ${anchoClase} overflow-y-auto rounded-flotante border border-taupe/35 bg-papel p-6 outline-none`}
        onClick={(e) => e.stopPropagation()}
      >
        <Asa />
        {titulo && (
          <h2 id={tituloId} className="mb-4 font-serif text-lg font-medium text-tinta">
            {titulo}
          </h2>
        )}
        {children}
      </div>
    </div>,
    document.body,
  );
}

export function ModalVidrio({ abierto, ...resto }: PropsModal & { abierto: boolean }) {
  if (!abierto || typeof document === "undefined") return null;
  return <ModalAbierto {...resto} />;
}

type PropsDrawer = {
  onCerrar: () => void;
  titulo?: string;
  anchoClase: string;
  bloqueado: boolean;
  volverElFocoA: React.RefObject<HTMLElement | null>;
  children: ReactNode;
};

function DrawerAbierto({ onCerrar, titulo, anchoClase, bloqueado, volverElFocoA, children }: PropsDrawer) {
  const tituloId = useId();
  const pedirCierre = () => {
    if (!bloqueado) onCerrar();
  };
  const { velo, hoja, ponerHoja } = useHojaViva({ onCerrar, bloqueado });
  useFocoAtrapado({ abierto: true, onCerrar: pedirCierre, caja: hoja, volverElFocoA });

  return createPortal(
    <div ref={velo} data-hoja-vidrio className="fixed inset-0 z-40 bg-black/40" onClick={pedirCierre}>
      <div
        ref={ponerHoja}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titulo ? tituloId : undefined}
        aria-label={titulo ? undefined : "Panel"}
        tabIndex={-1}
        className={`absolute inset-y-0 right-0 flex w-full ${anchoClase} flex-col border-l border-taupe/35 bg-papel outline-none`}
        onClick={(e) => e.stopPropagation()}
      >
        <Asa />
        {titulo && (
          <div className="shrink-0 border-b border-sand px-6 py-4">
            <h2 id={tituloId} className="font-serif text-lg font-medium text-tinta">
              {titulo}
            </h2>
          </div>
        )}
        <div className="flex-1 overflow-y-auto p-6">{children}</div>
      </div>
    </div>,
    document.body,
  );
}

export function DrawerVidrio({ abierto, ...resto }: PropsDrawer & { abierto: boolean }) {
  if (!abierto || typeof document === "undefined") return null;
  return <DrawerAbierto {...resto} />;
}

type PropsHojaInferior = {
  onCerrar: () => void;
  titulo: string;
  accion?: ReactNode;
  volverElFocoA: React.RefObject<HTMLElement | null>;
  children: ReactNode;
};

function HojaInferiorAbierta({ onCerrar, titulo, accion, volverElFocoA, children }: PropsHojaInferior) {
  const tituloId = useId();
  const { velo, hoja, ponerHoja } = useHojaViva({ onCerrar });
  useFocoAtrapado({ abierto: true, onCerrar, caja: hoja, volverElFocoA });

  return createPortal(
    <div ref={velo} data-hoja-vidrio className="fixed inset-0 z-40 bg-black/40 sm:hidden" onClick={onCerrar}>
      <div
        ref={ponerHoja}
        role="dialog"
        aria-modal="true"
        aria-labelledby={tituloId}
        tabIndex={-1}
        className="absolute inset-x-0 bottom-0 flex max-h-[85vh] flex-col rounded-t-flotante border-t border-taupe/35 bg-papel outline-none"
        onClick={(e) => e.stopPropagation()}
      >
        <Asa />
        <div className="flex shrink-0 items-baseline justify-between gap-3 px-5 pt-4 pb-2">
          <h2 id={tituloId} className="font-serif text-xl font-medium text-tinta">
            {titulo}
          </h2>
          {accion}
        </div>
        <div className="flex-1 overflow-y-auto px-5 pt-2 pb-[max(1.25rem,env(safe-area-inset-bottom))]">{children}</div>
      </div>
    </div>,
    document.body,
  );
}

export function HojaInferiorVidrio({ abierto, ...resto }: PropsHojaInferior & { abierto: boolean }) {
  if (!abierto || typeof document === "undefined") return null;
  return <HojaInferiorAbierta {...resto} />;
}
