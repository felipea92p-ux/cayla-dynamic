// Menú "..." compartido (2026-09-14). No existía ningún menú desplegable en
// el panel — todas las acciones vivían como botones sueltos en línea — y este
// es el primero, así que se escribe una sola vez para los dos sitios que lo
// necesitan a la vez (cabecera del perfil, fila de un documento) en vez de
// que cada uno arme su propio "fixed... onClick fuera" a mano.
//
// Mínimo funcional, mismo criterio que components/ui/modal.tsx: cierra con
// clic afuera y con Escape, y devuelve el foco al botón que lo abrió. Un
// recorrido con flechas entre ítems queda pendiente — no bloquea lo esencial,
// que es que alguien con teclado pueda abrirlo, leerlo y cerrarlo sin
// perderse.

"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type ReactNode } from "react";
import { cx } from "./cx";

export function Menu({
  trigger,
  children,
  alinear = "derecha",
}: {
  /** Recibe si está abierto y la función que lo alterna — así el propio
   * disparador decide su apariencia (aria-expanded, ícono) sin que Menu
   * tenga que imponer un botón fijo. */
  trigger: (estado: { abierto: boolean; alternar: () => void }) => ReactNode;
  children: ReactNode;
  alinear?: "derecha" | "izquierda";
}) {
  const [abierto, setAbierto] = useState(false);
  const cajaRef = useRef<HTMLDivElement>(null);
  const disparadorRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!abierto) return;
    function alClicFuera(e: MouseEvent) {
      if (cajaRef.current?.contains(e.target as Node)) return;
      if (disparadorRef.current?.contains(e.target as Node)) return;
      setAbierto(false);
    }
    function alTeclear(e: KeyboardEvent) {
      if (e.key !== "Escape") return;
      setAbierto(false);
      // Sin esto, Escape cierra el menú pero deja el foco flotando en el
      // documento — quien navega con teclado pierde su lugar en la página.
      disparadorRef.current?.querySelector("button")?.focus();
    }
    document.addEventListener("mousedown", alClicFuera);
    document.addEventListener("keydown", alTeclear);
    return () => {
      document.removeEventListener("mousedown", alClicFuera);
      document.removeEventListener("keydown", alTeclear);
    };
  }, [abierto]);

  return (
    <div className="relative inline-block text-left">
      <div ref={disparadorRef}>{trigger({ abierto, alternar: () => setAbierto((a) => !a) })}</div>
      {abierto && (
        <div
          ref={cajaRef}
          role="menu"
          className={cx(
            "absolute top-full z-30 mt-1 min-w-48 overflow-hidden rounded-control border border-sand bg-papel py-1 shadow-lg",
            alinear === "derecha" ? "right-0" : "left-0",
          )}
          // `stopPropagation` y no solo cerrar: sin esto, elegir una opción
          // del menú también dispara el `onClick` de lo que lo contenga —en
          // Contratos, la fila entera abre el visor de detalle al mismo
          // tiempo que "Editar" o "Anular" hacían lo suyo. El menú ya se
          // trata a sí mismo como el destino final del clic (por eso cierra
          // acá); detenerlo es la otra mitad de esa misma idea.
          onClick={(e) => {
            e.stopPropagation();
            setAbierto(false);
          }}
        >
          {children}
        </div>
      )}
    </div>
  );
}

export function MenuItem({
  onClick,
  href,
  variante = "normal",
  children,
}: {
  onClick?: () => void;
  href?: string;
  /** "peligro" para lo destructivo o excepcional (cancelar, anular) — mismo
   * criterio de color que Boton variante="peligro". */
  variante?: "normal" | "peligro";
  children: ReactNode;
}) {
  const clase = cx(
    "block w-full px-3 py-2 text-left text-sm transition-colors duration-150 hover:bg-sand/50",
    variante === "peligro" ? "text-rojo" : "text-tinta",
  );
  if (href) {
    return (
      <Link href={href} role="menuitem" className={clase}>
        {children}
      </Link>
    );
  }
  return (
    <button type="button" role="menuitem" onClick={onClick} className={clase}>
      {children}
    </button>
  );
}
