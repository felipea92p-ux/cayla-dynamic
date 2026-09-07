"use client";

// El menú del panel por debajo de 768px: un cajón que entra desde la
// izquierda sobre un velo, no un bloque que empuja la página hacia abajo como
// hacía el menú anterior.
//
// El cambio no es estético. Felipe abre el panel desde el teléfono, y el menú
// viejo no atrapaba el foco, no cerraba con Escape y no devolvía el foco a la
// hamburguesa al cerrarse: con el teclado te ibas caminando por detrás del
// menú abierto sin ninguna forma de volver.

import { useEffect, useRef } from "react";
import { LogOut, X } from "lucide-react";
import { PanelNavegacion, type Contadores } from "@/components/nav/panel-navegacion";
import { Marca } from "@/components/marca";
import type { Grupo } from "@/app/(admin)/admin/nav-items";

const FOCUSABLES =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function CajonAdmin({
  abierto,
  onCerrar,
  grupos,
  pathname,
  contadores,
  nombre,
  onCerrarSesion,
  volverElFocoA,
}: {
  abierto: boolean;
  onCerrar: () => void;
  grupos: Grupo[];
  pathname: string;
  contadores: Contadores;
  nombre?: string;
  onCerrarSesion: () => void;
  /** La hamburguesa que lo abrió, para devolverle el foco al cerrar. */
  volverElFocoA: React.RefObject<HTMLButtonElement | null>;
}) {
  const caja = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!abierto) return;

    const disparador = volverElFocoA.current;
    // El primer enlace, no el contenedor: quien abre el menú con el teclado
    // espera estar YA sobre algo que pueda pulsar.
    const primero = caja.current?.querySelector<HTMLElement>(FOCUSABLES);
    primero?.focus();

    function alPresionar(e: KeyboardEvent) {
      if (e.key === "Escape") {
        e.preventDefault();
        onCerrar();
        return;
      }
      if (e.key !== "Tab" || !caja.current) return;

      // Atrapar el foco: sin esto, tabular desde el último enlace del menú
      // sigue hacia la página que está debajo del velo, que no se puede ver
      // ni tocar.
      const focusables = Array.from(caja.current.querySelectorAll<HTMLElement>(FOCUSABLES));
      if (focusables.length === 0) return;
      const inicio = focusables[0];
      const fin = focusables[focusables.length - 1];

      if (e.shiftKey && document.activeElement === inicio) {
        e.preventDefault();
        fin.focus();
      } else if (!e.shiftKey && document.activeElement === fin) {
        e.preventDefault();
        inicio.focus();
      }
    }

    document.addEventListener("keydown", alPresionar);
    return () => {
      document.removeEventListener("keydown", alPresionar);
      // Al cerrar, el foco vuelve de donde salió. Si no, se queda en el
      // <body> y la siguiente tabulación arranca desde el principio de todo.
      disparador?.focus();
    };
  }, [abierto, onCerrar, volverElFocoA]);

  if (!abierto) return null;

  return (
    <>
      {/* `bg-black/40` y no `bg-tinta/NN`: en modo oscuro tinta ACLARA, que es
          lo contrario de lo que un velo tiene que hacer. */}
      <div onClick={onCerrar} className="fixed inset-0 z-40 bg-black/40 md:hidden" aria-hidden />
      <div
        ref={caja}
        role="dialog"
        aria-modal="true"
        aria-label="Menú principal"
        className="fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col border-r border-sand bg-crema md:hidden print:hidden"
      >
        <div className="flex h-16 shrink-0 items-center justify-between border-b border-sand px-4">
          <Marca tono="tinta" isotipo="rojo" />
          <button
            onClick={onCerrar}
            aria-label="Cerrar menú"
            className="rounded-control p-2 text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-rojo active:scale-[0.97]"
          >
            <X size={20} strokeWidth={1.8} aria-hidden />
          </button>
        </div>

        <nav aria-label="Navegación principal" className="min-h-0 flex-1 overflow-y-auto px-2 py-2">
          <PanelNavegacion
            grupos={grupos}
            pathname={pathname}
            contadores={contadores}
            modo="cajon"
            onNavegar={onCerrar}
          />
        </nav>

        <div className="shrink-0 border-t border-sand p-3">
          {nombre ? (
            <p className="px-1 pb-2 text-xs text-taupe" title="Sesión activa">
              Sesión: {nombre}
            </p>
          ) : null}
          <button
            onClick={onCerrarSesion}
            className="flex w-full items-center gap-3 rounded-control border border-sand px-3 py-3 text-left text-sm text-taupe transition-colors duration-150 hover:border-rojo/30 hover:text-rojo active:scale-[0.97]"
          >
            <LogOut size={18} strokeWidth={1.8} aria-hidden /> Cerrar sesión
          </button>
        </div>
      </div>
    </>
  );
}
