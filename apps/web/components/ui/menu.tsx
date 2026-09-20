// Menú "..." compartido (2026-09-14). No existía ningún menú desplegable en
// el panel — todas las acciones vivían como botones sueltos en línea — y este
// es el primero, así que se escribe una sola vez para los dos sitios que lo
// necesitan a la vez (cabecera del perfil, fila de un documento) en vez de
// que cada uno arme su propio "fixed... onClick fuera" a mano.
//
// Mismo criterio que components/ui/modal.tsx: cierra con clic afuera y con
// Escape, y devuelve el foco al botón que lo abrió.
//
// ── POR QUÉ FLOTA FUERA DE SU CONTENEDOR (2026-09-15) ──
// Hasta hoy la caja era `absolute` dentro del propio botón. En Equipo el menú
// vive en una fila de <Tabla>, y ese envoltorio lleva `overflow-x-auto` (y
// `overflow-y-auto` con alturaMaxima): todo lo que sobresale se RECORTA. En la
// última fila, «Registrar salida» quedaba cortado o escondido detrás del borde
// de la tabla — justo la acción que menos debe pasar desapercibida.
//
// Subirle el z-index no lo arregla: un overflow recorta sin importar el
// z-index. La única salida es sacar la caja de ese contenedor, así que se
// dibuja en <body> con `position: fixed` y se ubica midiendo el botón. La
// posición se escribe directo en el estilo del nodo y no en un estado de
// React: cambia en cada scroll, y pasar por un render por píxel no aporta nada.
//
// z-50: por encima de Drawer y Modal (z-40), porque un menú puede abrirse
// dentro de ellos; por debajo de los avisos (toast, z-[60]).

"use client";

import Link from "next/link";
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { cx } from "./cx";

/** Distancia entre el botón y la caja. */
const SEPARACION = 4;
/** Distancia mínima a los bordes de la ventana. */
const MARGEN = 8;

function itemsDe(caja: HTMLElement | null): HTMLElement[] {
  return caja ? Array.from(caja.querySelectorAll<HTMLElement>('[role="menuitem"]')) : [];
}

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

  const ubicar = useCallback(() => {
    const disparador = disparadorRef.current;
    const caja = cajaRef.current;
    if (!disparador || !caja) return;
    const r = disparador.getBoundingClientRect();
    // Si el scroll sacó el botón de la vista, un menú flotando solo en medio
    // de la pantalla ya no se entiende de quién es: se cierra.
    if (r.bottom < 0 || r.top > window.innerHeight) {
      setAbierto(false);
      return;
    }
    const alto = caja.offsetHeight;
    const ancho = caja.offsetWidth;
    // Abre hacia abajo; hacia arriba solo si abajo no cabe y arriba sí — en la
    // última fila de una tabla larga, abajo es el borde de la ventana.
    const cabeAbajo = r.bottom + SEPARACION + alto + MARGEN <= window.innerHeight;
    const cabeArriba = r.top - SEPARACION - alto >= MARGEN;
    const top = !cabeAbajo && cabeArriba ? r.top - SEPARACION - alto : r.bottom + SEPARACION;
    const izquierdaIdeal = alinear === "derecha" ? r.right - ancho : r.left;
    const left = Math.min(Math.max(izquierdaIdeal, MARGEN), window.innerWidth - ancho - MARGEN);
    caja.style.top = `${top}px`;
    caja.style.left = `${left}px`;
    caja.style.visibility = "visible";
  }, [alinear]);

  // Antes de pintar: la caja nace invisible en (0,0) y se ubica en el mismo
  // cuadro, así nunca se ve saltar desde la esquina. Y el foco entra al primer
  // ítem: la caja vive al final de <body>, así que Tab desde el botón ya no
  // llega a ella por orden del documento.
  useLayoutEffect(() => {
    if (!abierto) return;
    ubicar();
    itemsDe(cajaRef.current)[0]?.focus();
  }, [abierto, ubicar]);

  useEffect(() => {
    if (!abierto) return;
    function devolverFoco() {
      disparadorRef.current?.querySelector("button")?.focus();
    }
    function alClicFuera(e: MouseEvent) {
      if (cajaRef.current?.contains(e.target as Node)) return;
      if (disparadorRef.current?.contains(e.target as Node)) return;
      setAbierto(false);
    }
    function alTeclear(e: KeyboardEvent) {
      if (e.key === "Escape") {
        setAbierto(false);
        // Sin esto, Escape cierra el menú pero deja el foco flotando en el
        // documento — quien navega con teclado pierde su lugar en la página.
        devolverFoco();
        return;
      }
      if (e.key === "Tab") {
        // Tab sale del menú y sigue desde el botón que lo abrió, que es donde
        // estaba antes de abrirlo. Sin preventDefault: el navegador avanza
        // desde ahí al siguiente elemento, como si el menú no hubiera existido.
        setAbierto(false);
        devolverFoco();
        return;
      }
      const items = itemsDe(cajaRef.current);
      if (items.length === 0) return;
      const actual = items.indexOf(document.activeElement as HTMLElement);
      let siguiente: number | null = null;
      if (e.key === "ArrowDown") siguiente = (actual + 1) % items.length;
      else if (e.key === "ArrowUp") siguiente = (actual - 1 + items.length) % items.length;
      else if (e.key === "Home") siguiente = 0;
      else if (e.key === "End") siguiente = items.length - 1;
      if (siguiente === null) return;
      e.preventDefault();
      items[siguiente].focus();
    }
    document.addEventListener("mousedown", alClicFuera);
    document.addEventListener("keydown", alTeclear);
    // `true` = fase de captura: el scroll de un contenedor (la propia tabla de
    // Equipo) no burbujea hasta window, y sin captura el menú se quedaría
    // quieto mientras la fila se va.
    window.addEventListener("scroll", ubicar, true);
    window.addEventListener("resize", ubicar);
    return () => {
      document.removeEventListener("mousedown", alClicFuera);
      document.removeEventListener("keydown", alTeclear);
      window.removeEventListener("scroll", ubicar, true);
      window.removeEventListener("resize", ubicar);
    };
  }, [abierto, ubicar]);

  return (
    <div className="relative inline-block text-left">
      <div ref={disparadorRef}>{trigger({ abierto, alternar: () => setAbierto((a) => !a) })}</div>
      {abierto && typeof document !== "undefined" &&
        createPortal(
          <div
            ref={cajaRef}
            role="menu"
            className={cx(
              "invisible fixed left-0 top-0 z-50 min-w-48 overflow-hidden rounded-control border border-sand bg-papel py-1 text-left shadow-lg",
            )}
            // `stopPropagation` y no solo cerrar: sin esto, elegir una opción
            // del menú también dispara el `onClick` de lo que lo contenga —en
            // Contratos, la fila entera abre el visor de detalle al mismo
            // tiempo que "Editar" o "Anular" hacían lo suyo. Sigue haciendo
            // falta con el portal: React propaga los eventos por el árbol de
            // COMPONENTES, no por el del DOM, así que el clic igual llegaría
            // a la fila aunque la caja ya no esté dentro de ella.
            onClick={(e) => {
              e.stopPropagation();
              setAbierto(false);
            }}
          >
            {children}
          </div>,
          document.body,
        )}
    </div>
  );
}

export function MenuItem({
  onClick,
  href,
  variante = "normal",
  disabled = false,
  children,
}: {
  onClick?: () => void;
  href?: string;
  /** "peligro" para lo destructivo o excepcional (cancelar, anular) — mismo
   * criterio de color que Boton variante="peligro". */
  variante?: "normal" | "peligro";
  /** Solo para ítems con `onClick`. Se marca con `aria-disabled` y NO con el
   * atributo `disabled`: un botón deshabilitado no recibe foco, y la navegación
   * con flechas del menú recorre los ítems llamando a `.focus()`, así que se
   * quedaría trabada justo en él. Con `aria-disabled` el ítem sigue en el
   * recorrido, un lector de pantalla lo anuncia como no disponible, y el clic
   * no hace nada. */
  disabled?: boolean;
  children: ReactNode;
}) {
  // focus:bg-sand/50 además del hover: con flechas el foco recorre los ítems,
  // y sin fondo quien usa teclado no ve en cuál está. El hover se apaga en un
  // ítem no disponible; el foco no, por esa misma razón.
  const clase = cx(
    "block w-full px-3 py-2 text-left text-sm transition-colors duration-150 focus:bg-sand/50 focus:outline-none",
    disabled ? "cursor-not-allowed opacity-50" : "hover:bg-sand/50",
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
    <button
      type="button"
      role="menuitem"
      aria-disabled={disabled || undefined}
      onClick={disabled ? undefined : onClick}
      className={clase}
    >
      {children}
    </button>
  );
}
