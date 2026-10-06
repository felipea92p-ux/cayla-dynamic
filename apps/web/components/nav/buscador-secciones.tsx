"use client";

// El buscador (⌘K) de una pantalla con menú de secciones —hoy, «Lo mío»—:
// salta a cualquiera de sus secciones escribiendo, sin recorrer el menú.
//
// POR QUÉ NO ES `BuscadorGlobal`
//   Se ve igual a propósito —mismo recuadro, mismas filas, mismas teclas—,
//   pero busca otra cosa: el del panel busca PANTALLAS y PERSONAS, y navega;
//   este busca secciones de la pantalla en la que ya estás, y las elige sin
//   salir de ella. Se decidió el 2026-10-06 que en «Lo mío» busque solo sus
//   secciones y que el del panel no se tocara, así que son dos componentes con
//   la misma cara y no uno con dos modos. Si un día se quiere que el ⌘K de
//   «Lo mío» encuentre también el panel, el camino es enseñarle a
//   `BuscadorGlobal` un tercer tipo de fila, no hacer crecer este.
//
// La regla de qué coincide vive en `lib/secciones-de-menu.ts`, con sus pruebas.

import { useEffect, useMemo, useState } from "react";
import { Search, X } from "lucide-react";
import { buscarSecciones, type GrupoDetalle, type ResultadoSeccion } from "@/lib/secciones-de-menu";

export function BuscadorSecciones<T extends string>({
  grupos,
  abierto,
  onCerrar,
  onElegir,
}: {
  grupos: readonly GrupoDetalle<T>[];
  abierto: boolean;
  onCerrar: () => void;
  onElegir: (valor: T) => void;
}) {
  const [consulta, setConsulta] = useState("");
  const [indice, setIndice] = useState(0);

  // Cada apertura arranca en blanco, como la del panel. Se ajusta durante el
  // render —el patrón que React documenta para esto— y no en un efecto.
  const [abiertoAntes, setAbiertoAntes] = useState(abierto);
  if (abierto !== abiertoAntes) {
    setAbiertoAntes(abierto);
    if (abierto) { setConsulta(""); setIndice(0); }
  }

  useEffect(() => {
    if (!abierto) return;
    function alPresionar(e: KeyboardEvent) {
      if (e.key === "Escape") onCerrar();
    }
    window.addEventListener("keydown", alPresionar);
    return () => window.removeEventListener("keydown", alPresionar);
  }, [abierto, onCerrar]);

  const resultados = useMemo(() => buscarSecciones(grupos, consulta), [grupos, consulta]);
  // La búsqueda puede acortar la lista después de que las flechas ya bajaron
  // más lejos; sin este tope, ⏎ apuntaría a una fila que ya no existe.
  const indiceValido = Math.min(indice, Math.max(resultados.length - 1, 0));

  function elegir(r: ResultadoSeccion<T>) {
    onElegir(r.seccion.valor);
    onCerrar();
  }

  if (!abierto) return null;

  const q = consulta.trim();

  return (
    <>
      <div onClick={onCerrar} className="fixed inset-0 z-40 bg-black/20" aria-hidden />
      {/* Sin sombra, como el del panel: globals.css prohíbe las sombras, y el
          borde `taupe/35` con `rounded-flotante` es lo que en esta casa dice
          «esto flota». */}
      <div role="dialog" aria-label="Buscar una sección"
        className="fixed left-1/2 top-24 z-50 w-[calc(100%-2rem)] max-w-lg -translate-x-1/2 overflow-hidden rounded-flotante border border-taupe/35 bg-papel">
        <div className="flex items-center gap-2.5 border-b border-sand px-4 py-3">
          <Search size={17} strokeWidth={1.8} className="shrink-0 text-taupe" aria-hidden />
          <input
            autoFocus
            value={consulta}
            onChange={(e) => { setConsulta(e.target.value); setIndice(0); }}
            onKeyDown={(e) => {
              if (e.key === "ArrowDown") { e.preventDefault(); setIndice((i) => Math.min(i + 1, resultados.length - 1)); }
              else if (e.key === "ArrowUp") { e.preventDefault(); setIndice((i) => Math.max(i - 1, 0)); }
              else if (e.key === "Enter" && resultados[indiceValido]) { e.preventDefault(); elegir(resultados[indiceValido]); }
            }}
            placeholder="Buscar una sección: sueldo, turno, memo…"
            aria-label="Buscar una sección"
            className="w-full bg-transparent text-sm text-tinta placeholder:text-taupe focus:outline-none"
          />
          <button onClick={onCerrar} aria-label="Cerrar buscador"
            className="shrink-0 rounded-md p-1 text-taupe transition hover:bg-sand/40 hover:text-tinta">
            <X size={16} strokeWidth={1.8} aria-hidden />
          </button>
        </div>

        <div className="max-h-[60vh] overflow-y-auto p-2">
          {resultados.length === 0 ? (
            <p className="px-3 py-6 text-center text-sm text-taupe">
              Nada con «{q}». Prueba con «pago», «turno» o «memo».
            </p>
          ) : (
            resultados.map((r, i) => {
              const seleccionada = i === indiceValido;
              const { Icon } = r.seccion;
              return (
                <button
                  key={r.seccion.valor}
                  onClick={() => elegir(r)}
                  onMouseEnter={() => setIndice(i)}
                  className={`flex w-full items-center gap-2.5 rounded-md px-3 py-2 text-left text-sm transition ${
                    seleccionada ? "bg-sand/50 text-rojo" : "text-tinta hover:bg-sand/30 hover:text-rojo"}`}
                >
                  <Icon size={16} strokeWidth={1.8} className="shrink-0" aria-hidden />
                  <span className="min-w-0 truncate">
                    {r.seccion.label}
                    {/* Por qué salió, cuando no fue por su nombre: sin esto,
                        «Boletas» al escribir «sueldo» parece un error. */}
                    {r.porAlias ? <span className="text-taupe"> · por «{r.porAlias}»</span> : null}
                  </span>
                  {r.grupo ? <span className="etiqueta ml-auto shrink-0 text-taupe">{r.grupo}</span> : null}
                </button>
              );
            })
          )}
        </div>
      </div>
    </>
  );
}
