"use client";

// Las páginas de una lista larga: «← Anterior · 1–5 de 23 · Siguiente →».
//
// QUÉ PROMETE
//   <Paginas>: la fila de abajo, sin estado. No se dibuja si todo cabe en una página: un «1–3 de 3» con dos botones apagados es ruido.
//   <ListaPaginada>: la lista entera con su página guardada. Corta con lib/paginar.ts, le pasa a `children` solo lo de esta página y, si al
//   cambiar de página el principio de la lista quedó arriba, fuera de la vista, la sube hasta ahí: en el teléfono se toca «Siguiente» al pie
//   de la lista, y sin esto la persona quedaría mirando el pie y tendría que subir a buscar el primero de los cinco nuevos.
//
// QUÉ ASUME
//   Que la lista llega en el orden en que se lee (lo más nuevo primero, casi siempre). Que quien la usa dentro de algo que cambia de rango
//   le pone `key` con ese rango, para volver a la página 1; si no, lib/paginar.ts la acerca a la última que exista y nunca queda vacía.
//
// La forma es la que ya tenían «Cambios a tu registro» y «Mis llamados» en Lo mío, escrita dos veces a mano; aquí se escribe una sola.
// Nació el 2026-11-09, cuando Felipe pidió listas de 5 en el teléfono: «Día por día», «Cambios a tu horario» y «Tus últimos periodos».

import { useRef, useState, type ReactNode } from "react";
import { Boton } from "./boton";
import { cx } from "./cx";
import { paginar, type Pagina } from "@/lib/paginar";
import { prefiereQuieto } from "@/lib/vidrio-movimiento";

/** Lo que Felipe pidió para las listas de Lo mío que en el teléfono quedaban muy largas (2026-11-09). */
export const CINCO_POR_PAGINA = 5;

export function Paginas({
  pag,
  etiqueta,
  alCambiar,
  className,
}: {
  pag: Pick<Pagina<unknown>, "pagina" | "paginas" | "desde" | "hasta" | "total">;
  /** Para el lector de pantalla: «Páginas de tus días». */
  etiqueta: string;
  alCambiar: (pagina: number) => void;
  className?: string;
}) {
  if (pag.paginas <= 1) return null;
  return (
    <nav aria-label={etiqueta} className={cx("flex items-center justify-between gap-2 border-t border-sand pt-3", className)}>
      <Boton variante="secundario" tamano="sm" disabled={pag.pagina === 0} onClick={() => alCambiar(pag.pagina - 1)}>
        ← Anterior
      </Boton>
      <span aria-live="polite" className="whitespace-nowrap text-xs text-taupe tabular-nums">
        {pag.desde}–{pag.hasta} de {pag.total}
      </span>
      <Boton variante="secundario" tamano="sm" disabled={pag.pagina >= pag.paginas - 1} onClick={() => alCambiar(pag.pagina + 1)}>
        Siguiente →
      </Boton>
    </nav>
  );
}

export function ListaPaginada<T>({
  items,
  porPagina = CINCO_POR_PAGINA,
  etiqueta,
  children,
}: {
  items: readonly T[];
  porPagina?: number;
  etiqueta: string;
  /** Dibuja solo lo de esta página. */
  children: (enEstaPagina: T[]) => ReactNode;
}) {
  const [n, setN] = useState(0);
  const ancla = useRef<HTMLDivElement>(null);
  const pag = paginar(items, n, porPagina);

  function cambiar(siguiente: number) {
    setN(siguiente);
    const el = ancla.current;
    if (!el) return;
    // `scroll-mt-24` deja lugar a la cabecera fija del teléfono; si el principio ya se ve, no se mueve nada.
    const margen = parseFloat(getComputedStyle(el).scrollMarginTop) || 0;
    if (el.getBoundingClientRect().top < margen) el.scrollIntoView({ block: "start", behavior: prefiereQuieto() ? "auto" : "smooth" });
  }

  return (
    <div ref={ancla} className="scroll-mt-24">
      {children(pag.items)}
      <Paginas pag={pag} etiqueta={etiqueta} alCambiar={cambiar} className="mt-4" />
    </div>
  );
}
