"use client";

import { useSyncExternalStore } from "react";
import {
  alternarMovimiento,
  cambiarMovimiento,
  MOVIMIENTO_POR_DEFECTO,
  movimientoDelDocumento,
  suscribirMovimiento,
  textosDelBotonMovimiento,
} from "@/lib/vidrio-movimiento";

// El botón «Animaciones», el de Retail: en la cabecera, junto al del modo oscuro y con su mismo cuerpo. Es del aparato, como el tema.
// El panel arranca quieto; al pulsarlo, todo se anima, y al instante en todas las pestañas del aparato.
//
// Como el del tema, el ÍCONO lo decide el CSS (`.boton-movimiento` en estilos/vidrio/marco.css) a partir del atributo que el guion ya puso:
// sale bien desde la primera pintura. React solo lleva `aria-pressed`, y el servidor siempre pinta quieto.
export function BotonMovimiento() {
  const movimiento = useSyncExternalStore(suscribirMovimiento, () => movimientoDelDocumento() ?? MOVIMIENTO_POR_DEFECTO, () => MOVIMIENTO_POR_DEFECTO);
  const { etiqueta, titulo } = textosDelBotonMovimiento(movimiento);
  return (
    <button
      type="button"
      onClick={() => cambiarMovimiento(alternarMovimiento(movimientoDelDocumento() ?? MOVIMIENTO_POR_DEFECTO))}
      aria-label={etiqueta}
      // receta-propia: es el botón del destello de la cabecera de Retail, no un filtro; <Filtro> no tiene esa forma ni su ícono
      aria-pressed={movimiento === "vivo"}
      title={titulo}
      className="boton-movimiento inline-grid h-9 w-9 shrink-0 place-items-center rounded-lg text-tinta/65 transition-colors hover:bg-sand/60 hover:text-rojo"
    >
      {/* El destello: encendido, solo; quieto, cruzado por una raya. */}
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" aria-hidden className="h-[18px] w-[18px]">
        <path d="M9.94 15.5a2 2 0 00-1.44-1.44l-6.13-1.58a.5.5 0 010-.96L8.5 9.94A2 2 0 009.94 8.5l1.58-6.14a.5.5 0 01.96 0l1.58 6.14a2 2 0 001.44 1.44l6.14 1.58a.5.5 0 010 .96l-6.14 1.58a2 2 0 00-1.44 1.44l-1.58 6.14a.5.5 0 01-.96 0z" />
        <path className="movimiento-raya" d="M3 3l18 18" />
      </svg>
    </button>
  );
}
