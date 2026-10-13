"use client";

import { useState } from "react";
import Link from "next/link";
import { Boton } from "@/components/ui/boton";
import { RotuloEstado } from "@/components/ui/rotulo";

// «Requiere atención»: lo que hay que mirar hoy, en un solo lugar. Dos formas
// del MISMO contenido, según el ancho:
//   · lateral — columna a la derecha, se puede ocultar del todo (como el equipo
//     en Correcciones). Ocultarlo no calla nada: el contador de críticas sigue
//     en el encabezado de la pantalla.
//   · banner — arriba, colapsable, para tablet y celular, donde una columna
//     lateral le quita el ancho a todo.
//
// Lo «crítico» NO se redefine aquí: es el `tono` que ya traía cada aviso del
// Dashboard (sin marcajes, casos de Disciplina). La cobertura insuficiente sigue
// siendo ámbar («aviso»), como hoy.

export interface ItemAtencionVista {
  key: string;
  sede: string;
  texto: string;
  tono: "critico" | "advertencia";
  /** A dónde lleva la acción del aviso. */
  href?: string;
  /** El nombre de la acción: «Ver turnos», no un «Ver →» que no dice a dónde va. */
  accion?: string;
}

const BOTON_ACCION =
  "rounded-control border border-sand bg-papel px-3 py-1 text-xs font-medium text-tinta transition-colors hover:border-taupe";

function Aviso({ it }: { it: ItemAtencionVista }) {
  return (
    <li className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1.5 border-t border-sand/60 py-2.5 text-sm first:border-t-0">
      <span className="flex items-baseline gap-2">
        <span aria-hidden className={`size-2 shrink-0 translate-y-[-1px] rounded-full ${it.tono === "critico" ? "bg-rojo" : "bg-ambar"}`} />
        <span><strong className="font-semibold">{it.sede}:</strong> <span className="text-tinta">{it.texto}</span></span>
      </span>
      {it.href && <Link href={it.href} className={BOTON_ACCION}>{it.accion ?? "Ver"}</Link>}
    </li>
  );
}

function Grupos({ items }: { items: ItemAtencionVista[] }) {
  const criticos = items.filter((i) => i.tono === "critico");
  const avisos = items.filter((i) => i.tono !== "critico");
  return (
    <>
      {criticos.length > 0 && (
        <div className="mt-2">
          <RotuloEstado tono="alerta">Críticas</RotuloEstado>
          <ul>{criticos.map((it) => <Aviso key={it.key} it={it} />)}</ul>
        </div>
      )}
      {avisos.length > 0 && (
        <div className="mt-3">
          <RotuloEstado tono="advertencia">Avisos</RotuloEstado>
          <ul>{avisos.map((it) => <Aviso key={it.key} it={it} />)}</ul>
        </div>
      )}
    </>
  );
}

const ContadorCriticas = ({ n }: { n: number }) =>
  n > 0 ? <span className="ml-2 rounded-full bg-rojo px-2 py-0.5 align-middle text-xs font-semibold text-crema">{n}</span> : null;

export function PanelAtencionLateral({ items, alOcultar }: { items: ItemAtencionVista[]; alOcultar: () => void }) {
  const criticas = items.filter((i) => i.tono === "critico").length;
  return (
    <div className="rounded-2xl border border-sand bg-papel p-5">
      <div className="flex items-start justify-between gap-2">
        <h2 className="font-serif text-xl font-medium">Requiere atención<ContadorCriticas n={criticas} /></h2>
        <Boton variante="enlace" tamano="sm" onClick={alOcultar} title="Ocultar el panel y darle todo el ancho al contenido">
          Ocultar ⟩
        </Boton>
      </div>
      {items.length === 0 ? <p className="mt-2 text-sm text-taupe">Nada pendiente ahora mismo.</p> : <Grupos items={items} />}
    </div>
  );
}

export function PanelAtencionBanner({ items }: { items: ItemAtencionVista[] }) {
  // En celular nace PLEGADO: queda una línea con el rojo y el conteo, y el
  // detalle se abre con un toque. En tablet y escritorio nace abierto, como
  // siempre. Se decide al montar y no con CSS porque `abierto` también manda el
  // texto del botón y el aria-expanded. Es seguro leer `window` aquí: este
  // banner solo se monta cuando el Dashboard ya cargó, nunca en el servidor.
  const [abierto, setAbierto] = useState(() => typeof window === "undefined" || !window.matchMedia("(max-width: 639px)").matches);
  const criticas = items.filter((i) => i.tono === "critico").length;
  if (items.length === 0) return null;
  const titulo = criticas > 0
    ? `${criticas} ${criticas === 1 ? "cosa requiere" : "cosas requieren"} atención`
    : `${items.length} ${items.length === 1 ? "aviso" : "avisos"}`;
  return (
    <div className={`rounded-2xl border bg-papel px-3 py-2.5 sm:p-4 ${criticas > 0 ? "border-rojo/40" : "border-sand"}`} role={criticas > 0 ? "alert" : undefined}>
      {/* Celular: toda la fila es el botón. Un «Ver» de 12 px en la esquina es
          un blanco que se falla con el pulgar. */}
      <button
        type="button"
        onClick={() => setAbierto((a) => !a)}
        aria-expanded={abierto}
        className="flex w-full items-center gap-2 text-left sm:hidden"
      >
        <span aria-hidden className={`size-2 shrink-0 rounded-full ${criticas > 0 ? "bg-rojo" : "bg-ambar"}`} />
        <span className={`flex-1 text-sm font-medium ${criticas > 0 ? "text-rojo-profundo" : "text-tinta"}`}>{titulo}</span>
        <span aria-hidden className="text-taupe">{abierto ? "▴" : "▾"}</span>
      </button>
      <div className="hidden flex-wrap items-center justify-between gap-2 sm:flex">
        <h2 className={`font-serif text-lg font-medium ${criticas > 0 ? "text-rojo-profundo" : "text-tinta"}`}>
          {criticas > 0 ? `${titulo} inmediata` : titulo}
        </h2>
        <Boton variante="enlace" tamano="sm" onClick={() => setAbierto((a) => !a)} aria-expanded={abierto}>
          {abierto ? "Ocultar" : "Ver"}
        </Boton>
      </div>
      {abierto && <Grupos items={items} />}
    </div>
  );
}
