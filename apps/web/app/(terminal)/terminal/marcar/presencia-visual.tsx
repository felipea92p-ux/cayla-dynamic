"use client";

import { useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { Check, Clock, Footprints, LogOut, Moon, Utensils, type LucideIcon } from "lucide-react";
import { ESTADO_PRESENCIA_LABELS } from "@cayla-dynamic/shared";
import { ORDEN_PRESENCIA, type ClavePresencia } from "@/lib/terminal/presencia";

// Cómo se VE cada punto del día de una persona en el terminal. La lógica de
// «en qué punto está» no vive acá: sale de los marcajes (`estadoPresencia`, en
// packages/shared) y de `lib/terminal/presencia.ts`. Esto solo le pone cara.
//
// LA TARJETA ES CALMA, EL COLOR VIVE EN EL ÍCONO. Todas las tarjetas son iguales
// —papel, borde fino— y el estado se dice con el círculo de color de la esquina
// de la foto y una línea gris con la hora. Es el diseño más quieto que se probó:
// una grilla de doce tarjetas tintadas de seis colores se leía como ruido.
//
// EL CONTROL ES LA PÍLDORA DE ARRIBA, no el ícono de la foto. Tocar un estado ahí
// ilumina a todas las personas que lo comparten (el borde y un tono del color del
// estado) y atenúa al resto. Ilumina, no oculta: nadie pierde su nombre de la
// pantalla, que es lo que hacía peligroso al filtro anterior si alguien lo dejaba
// puesto. El ícono de la foto solo informa —su palabra sale al pasar el mouse— y
// tocarlo marca, como tocar cualquier parte de la tarjeta.
//
// Cada estado tiene su color, su ícono y su palabra, y NINGUNO va solo: el color
// se ve de lejos, el ícono se reconoce de cerca y la palabra aparece al pasar el
// mouse, en la píldora y para quien usa lector de pantalla. Por eso el daltonismo
// no deja a nadie sin saber qué significa un ícono.
//
// Los colores son los de globals.css —verde, ámbar, azul, ceniza—, nunca uno de
// Tailwind por defecto (CLAUDE.md). Las clases van completas y no armadas con
// plantillas: Tailwind solo genera lo que ve escrito literal.

export interface EstiloPresencia {
  Icono: LucideIcon;
  /** El círculo del ícono sobre la foto: el color del estado. */
  punto: string;
  /** El color del estado como texto: el ícono del segmento activo de la píldora. */
  texto: string;
  /**
   * La tarjeta cuando se ilumina: borde y tono del estado. `--anillo` es el color
   * del FONDO de la tarjeta, para que el borde del círculo del ícono parezca
   * recortado de la foto. Quienes no tienen color propio (sin entrada, libre)
   * se iluminan con borde oscuro y fondo papel: con fondo arena el círculo arena
   * de su ícono se confundiría con la tarjeta.
   */
  iluminada: string;
  /** Ya no hay nada que hacer ahí (terminó, o hoy no trabaja): foto y nombre se apagan. */
  apagada: boolean;
}

/** La tarjeta en reposo: la misma para todos los estados. */
export const REPOSO_PRESENCIA = "border-borde-control bg-papel [--anillo:var(--color-papel)]";

export const ESTILO_PRESENCIA: Record<ClavePresencia, EstiloPresencia> = {
  sin_entrada: {
    Icono: Clock,
    punto: "bg-sand text-taupe",
    texto: "text-taupe",
    iluminada: "border-tinta bg-papel [--anillo:var(--color-papel)]",
    apagada: false,
  },
  laborando: {
    Icono: Check,
    punto: "bg-verde text-crema",
    texto: "text-verde",
    iluminada: "border-verde bg-verde/10 [--anillo:color-mix(in_srgb,var(--color-verde)_10%,var(--color-papel))]",
    apagada: false,
  },
  refrigerio: {
    Icono: Utensils,
    punto: "bg-ambar text-crema",
    texto: "text-ambar",
    iluminada: "border-ambar bg-ambar/10 [--anillo:color-mix(in_srgb,var(--color-ambar)_10%,var(--color-papel))]",
    apagada: false,
  },
  pausa: {
    Icono: Footprints,
    punto: "bg-azul text-crema",
    texto: "text-azul",
    iluminada: "border-azul bg-azul/10 [--anillo:color-mix(in_srgb,var(--color-azul)_10%,var(--color-papel))]",
    apagada: false,
  },
  termino: {
    Icono: LogOut,
    punto: "bg-ceniza text-crema",
    texto: "text-ceniza",
    iluminada: "border-ceniza bg-ceniza/10 [--anillo:color-mix(in_srgb,var(--color-ceniza)_10%,var(--color-papel))]",
    apagada: true,
  },
  libre: {
    Icono: Moon,
    punto: "bg-sand text-taupe",
    texto: "text-taupe",
    iluminada: "border-tinta bg-papel [--anillo:var(--color-papel)]",
    apagada: true,
  },
};

/** La palabra de cada estado: la etiqueta flotante, la píldora y el lector de pantalla. */
export function etiquetaDePresencia(clave: ClavePresencia): string {
  return clave === "libre" ? "Libre hoy" : ESTADO_PRESENCIA_LABELS[clave];
}

/**
 * Lo que dice un ícono, al pasar el mouse por encima (o al llegar a él con el
 * teclado, si es un control). Solo con mouse: en una pantalla táctil un toque dispara el mismo
 * evento de «entrar» y la etiqueta se quedaría pegada después de tocar.
 *
 * Vive en un PORTAL, fuera de la tarjeta, a propósito: una tarjeta atenuada
 * lleva `opacity-30`, y todo lo que cuelga de ella —una etiqueta incluida— se
 * atenúa con ella. Justo la etiqueta del ícono de alguien que NO está
 * iluminado es la que más hace falta leer.
 */
export function ConEtiqueta({
  texto,
  className,
  children,
}: {
  texto: string;
  className?: string;
  children: ReactNode;
}) {
  const [punto, setPunto] = useState<{ x: number; y: number } | null>(null);
  const mostrar = (el: HTMLElement) => {
    const r = el.getBoundingClientRect();
    setPunto({ x: r.left + r.width / 2, y: r.bottom + 6 });
  };
  return (
    <span
      className={className}
      onPointerEnter={(e) => {
        if (e.pointerType === "mouse") mostrar(e.currentTarget);
      }}
      onPointerLeave={() => setPunto(null)}
      // Con el teclado sí, pero no al hacer clic: un clic con el mouse también da
      // foco, y la etiqueta se quedaría puesta hasta que se mueva el foco.
      onFocus={(e) => {
        if ((e.target as HTMLElement).matches(":focus-visible")) mostrar(e.currentTarget);
      }}
      onBlur={() => setPunto(null)}
    >
      {children}
      {punto &&
        createPortal(
          <span
            role="tooltip"
            className="pointer-events-none fixed z-50 -translate-x-1/2 whitespace-nowrap rounded-control bg-tinta px-2.5 py-1 text-sm text-crema"
            style={{ left: punto.x, top: punto.y }}
          >
            {texto}
          </span>,
          document.body,
        )}
    </span>
  );
}

const SEGMENTO = "flex min-h-11 cursor-pointer items-center gap-1.5 rounded-pildora text-sm transition-colors";

/**
 * Una sola píldora fina, en vez de seis botones sueltos, con cada estado que
 * existe y cuánta gente hay en él. Un estado en cero NO se dibuja: en una sede de
 * cuatro personas la leyenda de antes era casi puro cero. El segmento que está
 * iluminado muestra su nombre y se pinta de su color; los demás, solo ícono y
 * número —su palabra sale al pasar el mouse—.
 *
 * Tocar un segmento ilumina a quienes están en ese estado, y volver a tocarlo lo
 * apaga. Es el único control del filtro.
 */
export function PildoraDeEstados({
  conteos,
  total,
  resaltado,
  onResaltar,
}: {
  conteos: Record<ClavePresencia, number>;
  total: number;
  resaltado: ClavePresencia | null;
  onResaltar: (clave: ClavePresencia | null) => void;
}) {
  return (
    <div
      className="inline-flex flex-wrap items-center justify-center rounded-pildora border border-borde-control p-0.5"
      role="group"
      aria-label="Estados"
    >
      <button
        type="button"
        aria-pressed={resaltado === null}
        onClick={() => onResaltar(null)}
        className={`${SEGMENTO} px-4 ${resaltado === null ? "bg-sand font-medium text-tinta" : "text-taupe hover:text-tinta"}`}
      >
        Todos <span className="font-serif text-base leading-none">{total}</span>
      </button>
      {ORDEN_PRESENCIA.filter((c) => conteos[c] > 0).map((c) => {
        const e = ESTILO_PRESENCIA[c];
        const Icono = e.Icono;
        const activo = resaltado === c;
        const etiqueta = etiquetaDePresencia(c);
        return (
          <ConEtiqueta key={c} texto={etiqueta} className="inline-flex">
            <button
              type="button"
              aria-pressed={activo}
              aria-label={`${etiqueta}: ${conteos[c]}`}
              onClick={() => onResaltar(activo ? null : c)}
              className={`${SEGMENTO} px-3 ${activo ? "bg-sand text-tinta" : "text-taupe hover:text-tinta"}`}
            >
              <Icono size={16} strokeWidth={2.25} className={activo ? e.texto : undefined} aria-hidden />
              <span className="font-serif text-base leading-none">{conteos[c]}</span>
              {activo && <span className="font-medium">{etiqueta}</span>}
            </button>
          </ConEtiqueta>
        );
      })}
    </div>
  );
}
