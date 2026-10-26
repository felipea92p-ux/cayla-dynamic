"use client";

// EL BUSCADOR DE PERSONA (2026-10-20): elegir a alguien sin recorrer una lista de 30 nombres.
//
// Nació en el formulario «Registrar ausencia», donde era un desplegable con todos en fila. Quien
// registra casi siempre sabe de qué sede es o cómo empieza el nombre, así que el control deja
// contestar eso primero: la sede en fichas (reduce la lista de un vistazo) y un campo donde se
// escribe y la lista se va acortando. Se maneja con teclado (↑ ↓ Enter, Esc) como un buscador.
//
// La lista FLOTA fuera del formulario: se dibuja en <body> con `position: fixed`, justo bajo el
// campo, igual que el menú «•••» (ver menu.tsx). Estos formularios viven en un <Modal> con
// `overflow-y-auto`: una caja `absolute` dentro de él se recorta o lo estira, y una lista en línea
// empuja todo lo de abajo cada vez que se abre. Flotando, el formulario no se mueve. Solo se
// muestra cuando se está usando (enfocado, con sede elegida o con texto).
//
// No decide nada de negocio: recibe las opciones ya filtradas por quien lo usa (activas, sin
// cuentas de servicio…) y devuelve el id elegido. Las sedes salen de las propias opciones.

import { useId, useLayoutEffect, useMemo, useRef, useState, type KeyboardEvent } from "react";
import { createPortal } from "react-dom";
import { Search } from "lucide-react";
import { Boton } from "./boton";
import { Filtro } from "./filtro";
import { cx } from "./cx";
import { sinTildes } from "@/lib/admin/sin-tildes";

export interface OpcionBuscador {
  id: string;
  /** Como se lee y se busca: «Gaby Integrante». */
  nombre: string;
  sede?: string | null;
  /** Una línea chica bajo el nombre («Tienda AQP · Vendedora»). */
  detalle?: string;
}

/** El nombre con lo que se escribió en negrita, para ver por qué coincide. Si quitar las tildes cambia el largo, no se resalta. */
function Resaltado({ texto, q }: { texto: string; q: string }) {
  const plano = sinTildes(texto);
  const i = q ? plano.indexOf(q) : -1;
  if (i < 0 || plano.length !== texto.length) return <>{texto}</>;
  return (
    <>
      {texto.slice(0, i)}
      <b className="font-semibold">{texto.slice(i, i + q.length)}</b>
      {texto.slice(i + q.length)}
    </>
  );
}

export function BuscadorPersona({
  opciones,
  value,
  onChange,
  etiqueta = "Persona",
  disabled,
  error,
  placeholder = "Escribe un nombre…",
}: {
  opciones: OpcionBuscador[];
  value: string;
  onChange: (id: string) => void;
  etiqueta?: string;
  disabled?: boolean;
  /** Mensaje de error, con borde rojo a juego. No valida por sí solo. */
  error?: string;
  /** Lo que dice el campo vacío; con `disabled` sirve para decir por qué («Elige primero el seguro»). */
  placeholder?: string;
}) {
  const idLista = useId();
  const [busca, setBusca] = useState("");
  const [sede, setSede] = useState("");
  const [enfocado, setEnfocado] = useState(false);
  const [cambiando, setCambiando] = useState(false);
  const [activa, setActiva] = useState(0);
  const entrada = useRef<HTMLInputElement>(null);
  const campo = useRef<HTMLLabelElement>(null);
  const [pos, setPos] = useState<{ left: number; top: number; ancho: number; alto: number } | null>(null);

  // Las sedes salen de las personas que hay, no de una lista escrita a mano.
  const sedes = useMemo(
    () => [...new Set(opciones.map((o) => o.sede).filter((x): x is string => Boolean(x)))].sort(),
    [opciones],
  );

  const q = sinTildes(busca.trim());
  const visibles = useMemo(
    () => opciones.filter((o) => (sede === "" || o.sede === sede) && (q === "" || sinTildes(o.nombre).includes(q))),
    [opciones, sede, q],
  );
  const indice = Math.min(activa, Math.max(visibles.length - 1, 0));

  function elegir(id: string) {
    onChange(id);
    setCambiando(false);
    setEnfocado(false);
    setBusca("");
    setSede("");
    setActiva(0);
  }

  const elegida = opciones.find((o) => o.id === value);
  const listaAbierta = (enfocado || sede !== "" || busca !== "") && !(elegida && !cambiando);

  // Ubica la lista bajo el campo (o encima, si abajo no cabe). Se recalcula con el scroll de cualquier
  // contenedor y al cambiar el tamaño: el modal puede estar desplazándose mientras se escribe.
  useLayoutEffect(() => {
    if (!listaAbierta) return;
    const medir = () => {
      const r = campo.current?.getBoundingClientRect();
      if (!r) return;
      const abajo = window.innerHeight - r.bottom - 12;
      const arriba = r.top - 12;
      const quiereAlto = 232;
      const hacia = abajo >= Math.min(quiereAlto, 160) || abajo >= arriba ? "abajo" : "arriba";
      const alto = Math.max(120, Math.min(quiereAlto, hacia === "abajo" ? abajo : arriba));
      setPos({ left: r.left, ancho: r.width, alto, top: hacia === "abajo" ? r.bottom + 4 : r.top - 4 - alto });
    };
    medir();
    window.addEventListener("resize", medir);
    window.addEventListener("scroll", medir, true);
    return () => {
      window.removeEventListener("resize", medir);
      window.removeEventListener("scroll", medir, true);
    };
  }, [listaAbierta, visibles.length]);

  if (elegida && !cambiando) {
    return (
      <div className="space-y-1">
        <span className="text-sm text-taupe">{etiqueta}</span>
        <div className="flex items-center justify-between gap-3 rounded-control border border-sand bg-hueso px-3 py-2">
          <span className="min-w-0">
            <span className="block truncate text-sm font-medium text-tinta">{elegida.nombre}</span>
            {(elegida.sede || elegida.detalle) && (
              <span className="block truncate text-xs text-taupe">{[elegida.sede, elegida.detalle].filter(Boolean).join(" · ")}</span>
            )}
          </span>
          {!disabled && (
            <Boton variante="enlace" className="shrink-0 text-xs text-taupe" onClick={() => { setCambiando(true); setEnfocado(true); }}>
              Cambiar
            </Boton>
          )}
        </div>
      </div>
    );
  }

  function teclas(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setEnfocado(true);
      setActiva(Math.min(indice + 1, visibles.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActiva(Math.max(indice - 1, 0));
    } else if (e.key === "Enter" && listaAbierta && visibles[indice]) {
      // Enter dentro de un formulario no debe enviarlo: aquí elige.
      e.preventDefault();
      elegir(visibles[indice].id);
    } else if (e.key === "Escape" && listaAbierta) {
      // Cierra la lista, no el modal que la contiene.
      e.stopPropagation();
      setEnfocado(false);
      setBusca("");
      setSede("");
    }
  }

  return (
    <div
      className="space-y-2"
      onFocus={() => setEnfocado(true)}
      onBlur={(e) => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setEnfocado(false); }}
    >
      <span className="text-sm text-taupe">{etiqueta}</span>
      {sedes.length > 1 && (
        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Filtrar por sede">
          <Filtro tamano="sm" activo={sede === ""} disabled={disabled} onClick={() => { setSede(""); setActiva(0); entrada.current?.focus(); }}>Todas</Filtro>
          {sedes.map((s) => (
            <Filtro key={s} tamano="sm" activo={sede === s} disabled={disabled} onClick={() => { setSede(sede === s ? "" : s); setActiva(0); entrada.current?.focus(); }}>
              {s}
            </Filtro>
          ))}
        </div>
      )}
      <label ref={campo} className="relative block">
        <span className="sr-only">Buscar por nombre</span>
        <Search size={14} strokeWidth={1.8} className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-taupe" aria-hidden />
        <input
          ref={entrada}
          role="combobox"
          aria-expanded={listaAbierta}
          aria-controls={idLista}
          aria-activedescendant={listaAbierta && visibles[indice] ? `${idLista}-${visibles[indice].id}` : undefined}
          aria-autocomplete="list"
          type="text"
          autoComplete="off"
          placeholder={placeholder}
          value={busca}
          disabled={disabled}
          autoFocus={cambiando}
          onChange={(e) => { setBusca(e.target.value); setActiva(0); }}
          onKeyDown={teclas}
          className={cx("w-full rounded-control border border-sand bg-hueso py-2 pl-8 pr-3 text-base text-tinta placeholder:text-taupe/60 focus-visible:outline-offset-0 disabled:opacity-60 sm:text-sm", error && "border-rojo")}
        />
      </label>
      {error && <span className="block text-xs text-rojo">{error}</span>}
      {listaAbierta && pos &&
        createPortal(
          <div
            // z-50: por encima del Modal (z-40) que contiene al campo, igual que <Menu>.
            style={{ position: "fixed", left: pos.left, top: pos.top, width: pos.ancho, maxHeight: pos.alto }}
            className="z-50 flex flex-col overflow-hidden rounded-control border border-sand bg-papel shadow-lg"
            // La lista no le quita el foco al campo (ni al arrastrar su barra): si no, se cerraría antes de elegir.
            onMouseDown={(e) => e.preventDefault()}
          >
            {visibles.length === 0 ? (
              <p className="px-3 py-2.5 text-sm text-taupe">Nadie coincide{sede ? ` en ${sede}` : ""}.</p>
            ) : (
              <ul id={idLista} role="listbox" aria-label="Personas" className="min-h-0 flex-1 overflow-y-auto p-1">
                {visibles.map((o, i) => (
                  <li key={o.id} id={`${idLista}-${o.id}`} role="option" aria-selected={i === indice}>
                    <button
                      type="button"
                      tabIndex={-1}
                      onClick={() => elegir(o.id)}
                      onMouseMove={() => setActiva(i)}
                      className={cx(
                        "flex w-full items-baseline justify-between gap-3 rounded-control px-2.5 py-1.5 text-left text-sm transition-colors duration-100",
                        i === indice ? "bg-hueso" : "",
                      )}
                    >
                      <span className="truncate text-tinta"><Resaltado texto={o.nombre} q={q} /></span>
                      <span className="shrink-0 text-xs text-taupe">{[o.sede, o.detalle].filter(Boolean).join(" · ")}</span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <p className="shrink-0 border-t border-sand px-3 py-1 text-xs text-taupe">{visibles.length} de {opciones.length}</p>
          </div>,
          document.body,
        )}
    </div>
  );
}
