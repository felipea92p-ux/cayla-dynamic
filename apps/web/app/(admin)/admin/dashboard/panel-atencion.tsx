"use client";

import { useState } from "react";
import Link from "next/link";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { ChevronDown, PanelRightClose } from "lucide-react";
import { BotonIcono } from "@/components/ui/boton-icono";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
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
    <TarjetaInfo
      titulo={<>Requiere atención<ContadorCriticas n={criticas} /></>}
      accion={<BotonIcono etiqueta="Ocultar el panel y darle todo el ancho al contenido" icono={<PanelRightClose aria-hidden />} onClick={alOcultar} />}
    >
      {items.length === 0 ? <p className="text-sm text-taupe">Nada pendiente ahora mismo.</p> : <Grupos items={items} />}
    </TarjetaInfo>
  );
}

export function PanelAtencionBanner({ items }: { items: ItemAtencionVista[] }) {
  // Nace PLEGADO en todos los anchos (2026-10-19, pedido de Felipe): queda una línea con el punto rojo y
  // el conteo, y el detalle se abre con un toque. Antes solo el celular nacía así y en escritorio el aviso
  // abierto empujaba el resumen fuera de la pantalla. Lo que se conserva: el rojo, el conteo y el
  // `role="alert"` siguen a la vista, así que plegado no es lo mismo que oculto.
  const [abierto, setAbierto] = useState(false);
  const criticas = items.filter((i) => i.tono === "critico").length;
  if (items.length === 0) return null;
  const titulo = criticas > 0
    ? `${criticas} ${criticas === 1 ? "cosa requiere" : "cosas requieren"} atención`
    : `${items.length} ${items.length === 1 ? "aviso" : "avisos"}`;
  // Una sola línea cuando está plegado (2026-10-19): el aviso es del tamaño de lo que dice. Es un
  // <BannerAviso enLinea> —la forma de aviso chica del ADR 0004— y no una caja propia con título serif,
  // y su «Ver / Ocultar» es un botón «sm» como los demás, no un enlace subrayado de 16 px.
  return (
    <BannerAviso enLinea variante={criticas > 0 ? "alerta" : "advertencia"} role={criticas > 0 ? "alert" : undefined}>
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
      <div className="hidden items-center justify-between gap-3 sm:flex">
        <span className="flex items-center gap-2">
          <span aria-hidden className={`size-2 shrink-0 rounded-full ${criticas > 0 ? "bg-rojo" : "bg-ambar"}`} />
          <span className={`font-medium ${criticas > 0 ? "text-rojo-profundo" : "text-tinta"}`}>
            {criticas > 0 ? `${titulo} inmediata` : titulo}
          </span>
        </span>
        <BotonIcono
          etiqueta={abierto ? "Ocultar el detalle" : "Ver el detalle"}
          icono={<ChevronDown aria-hidden className={abierto ? "rotate-180" : ""} />}
          onClick={() => setAbierto((a) => !a)}
          aria-expanded={abierto}
        />
      </div>
      {abierto && <Grupos items={items} />}
    </BannerAviso>
  );
}
