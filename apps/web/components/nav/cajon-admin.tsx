"use client";

// El menú del panel por debajo de 768px: un cajón que entra desde la
// izquierda sobre un velo, no un bloque que empuja la página hacia abajo como
// hacía el menú anterior.
//
// El cambio no es estético. Felipe abre el panel desde el teléfono, y el menú
// viejo no atrapaba el foco, no cerraba con Escape y no devolvía el foco a la
// hamburguesa al cerrarse: con el teclado te ibas caminando por detrás del
// menú abierto sin ninguna forma de volver.

import { useRef } from "react";
import { LogOut, X } from "lucide-react";
import { PanelNavegacion, type Contadores } from "@/components/nav/panel-navegacion";
import { Marca } from "@/components/marca";
import { cx } from "@/components/ui/cx";
import { useFocoAtrapado } from "@/lib/use-foco-atrapado";
import { useSalidaAnimada } from "@/lib/use-salida-animada";
import type { Grupo } from "@/app/(admin)/admin/nav-items";

// Lo que tarda el cajón en irse. Tiene que coincidir con `.cajon-sale` de
// globals.css: es lo que el hook espera antes de desmontarlo.
const SALIDA_DEL_CAJON_MS = 200;

export function CajonAdmin({
  abierto,
  onCerrar,
  grupos,
  pathname,
  contadores,
  nombre,
  onCerrarSesion,
  volverElFocoA,
  cerrados,
  onAlternarGrupo,
}: {
  abierto: boolean;
  onCerrar: () => void;
  grupos: Grupo[];
  pathname: string;
  contadores: Contadores;
  nombre?: string;
  onCerrarSesion: () => void;
  cerrados: ReadonlySet<string>;
  onAlternarGrupo: (etiqueta: string) => void;
  /** La hamburguesa que lo abrió, para devolverle el foco al cerrar. */
  volverElFocoA: React.RefObject<HTMLButtonElement | null>;
}) {
  const caja = useRef<HTMLDivElement>(null);

  useFocoAtrapado({ abierto, onCerrar, caja, volverElFocoA });

  // Entra y sale deslizando (`.cajon-entra`/`.cajon-sale` en globals.css), igual
  // que el cajón de «Lo mío» desde el 2026-09-11: son la misma pieza en dos
  // superficies y no pueden moverse distinto. El hook lo mantiene montado los
  // 200 ms que tarda en irse; mientras tanto queda `inert`.
  const { montado, saliendo } = useSalidaAnimada(abierto, SALIDA_DEL_CAJON_MS);

  if (!montado) return null;

  return (
    <>
      {/* `bg-black/40` y no `bg-tinta/NN`: en modo oscuro tinta ACLARA, que es
          lo contrario de lo que un velo tiene que hacer. */}
      <div
        onClick={onCerrar}
        className={cx("fixed inset-0 z-40 bg-black/40 md:hidden", saliendo ? "velo-sale" : "velo-entra")}
        aria-hidden
      />
      <div
        ref={caja}
        role="dialog"
        aria-modal="true"
        aria-label="Menú principal"
        inert={saliendo || undefined}
        className={cx(
          "fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col border-r border-sand bg-crema md:hidden print:hidden",
          saliendo ? "cajon-sale" : "cajon-entra",
        )}
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
            cerrados={cerrados}
            onAlternarGrupo={onAlternarGrupo}
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
