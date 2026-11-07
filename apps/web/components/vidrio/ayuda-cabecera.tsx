"use client";

// El «?» junto al título de una pantalla y su globo de vidrio: el de Retail (components/ui/AyudaCabecera.tsx). La frase que explica la pantalla
// deja de verse siempre y vive aquí. Se abre al tocar, se cierra al tocar otra vez, al tocar afuera o con Escape, y no mueve la página. No
// oscurece nada: para leer una frase no hace falta tapar la pantalla.

import { useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

export function AyudaCabecera({ nombre, children }: { nombre?: string; children: ReactNode }) {
  const [abierto, setAbierto] = useState(false);
  const boton = useRef<HTMLButtonElement>(null);
  const globo = useRef<HTMLDivElement>(null);
  const pico = useRef<HTMLSpanElement>(null);
  const id = useId();

  // Directo en el estilo y antes de pintar: el primer cuadro ya sale en su lugar.
  useLayoutEffect(() => {
    if (!abierto) return;
    const colocar = () => {
      const b = boton.current;
      const g = globo.current;
      const p = pico.current;
      if (!b || !g || !p) return;
      const margen = 16;
      const anchoVentana = document.documentElement.clientWidth || window.innerWidth;
      const ancho = anchoVentana < 640 ? anchoVentana - 2 * margen : Math.min(380, anchoVentana - 2 * margen);
      g.style.width = `${ancho}px`;
      const r = b.getBoundingClientRect();
      const izquierda = Math.min(Math.max(margen, r.left - 8), anchoVentana - margen - ancho);
      g.style.left = `${izquierda}px`;
      const alto = g.offsetHeight;
      const cabeAbajo = r.bottom + 12 + alto + margen <= window.innerHeight;
      const arriba = !cabeAbajo && r.top - 12 - alto - margen >= 0;
      g.style.top = arriba ? `${r.top - 12 - alto}px` : `${r.bottom + 12}px`;
      const centro = r.left + r.width / 2;
      g.style.setProperty("--pico-x", `${Math.round(centro - izquierda)}px`);
      g.dataset.lado = arriba ? "arriba" : "abajo";
      p.dataset.lado = g.dataset.lado;
      p.style.left = `${Math.round(centro - 6)}px`;
      p.style.top = arriba ? `${r.top - 12 - 6}px` : `${r.bottom + 12 - 6}px`;
    };
    colocar();
    window.addEventListener("resize", colocar);
    window.addEventListener("scroll", colocar, true);
    return () => {
      window.removeEventListener("resize", colocar);
      window.removeEventListener("scroll", colocar, true);
    };
  }, [abierto]);

  useEffect(() => {
    if (!abierto) return;
    const alTocarAfuera = (e: MouseEvent) => {
      const t = e.target as Node;
      if (!boton.current?.contains(t) && !globo.current?.contains(t)) setAbierto(false);
    };
    const alEscape = (e: KeyboardEvent) => {
      if (e.key !== "Escape") return;
      setAbierto(false);
      boton.current?.focus();
    };
    document.addEventListener("mousedown", alTocarAfuera);
    document.addEventListener("keydown", alEscape);
    return () => {
      document.removeEventListener("mousedown", alTocarAfuera);
      document.removeEventListener("keydown", alEscape);
    };
  }, [abierto]);

  return (
    <>
      {/* Unión de palabra (U+2060): el «?» nunca baja solo a otra línea, se queda pegado a la última palabra del título. */}
      {"⁠"}
      <button
        ref={boton}
        type="button"
        className="ayuda-cab-q"
        aria-expanded={abierto}
        aria-controls={abierto ? id : undefined}
        aria-label={nombre ? `Qué es ${nombre}` : "Qué es esta pantalla"}
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          setAbierto((v) => !v);
        }}
      >
        <span aria-hidden>?</span>
      </button>
      {abierto
        ? createPortal(
            <>
              <span ref={pico} className="ayuda-cab-pico" aria-hidden />
              <div ref={globo} id={id} role="note" className="ayuda-cab-globo" onClick={(e) => e.stopPropagation()}>
                {nombre ? <p className="ayuda-cab-nombre">{nombre}</p> : null}
                <div className="ayuda-cab-texto">{children}</div>
              </div>
            </>,
            document.body,
          )
        : null}
    </>
  );
}
