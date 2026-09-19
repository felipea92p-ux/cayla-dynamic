"use client";

import { useState } from "react";
import { pesoLegible } from "@/lib/reducir-imagen";
import type { TipoBoleta } from "@/lib/boletas";
import type { HojaFirmada } from "@/lib/boletas-archivos";

/**
 * LAS HOJAS DE UNA BOLETA, UNA DEBAJO DE OTRA.
 *
 * Lo comparten la pantalla de DO (para revisar antes de publicar y para abrir
 * cualquier versión del historial) y la de la persona (su boleta). Si cada una
 * dibujara las hojas por su cuenta, «cómo se ve una boleta» tendría dos
 * respuestas.
 *
 * FOTOS: se apilan, con «Hoja 2 de 3»; tocar una la amplía —una foto de un papel
 * en un celular no se lee sin acercarla— y volver a tocar la devuelve a su tamaño.
 * El contenedor de la foto hace scroll propio cuando está ampliada.
 * PDF: cada uno es una tarjeta con «Abrir PDF» en una pestaña nueva. No se
 * incrusta: el visor de PDF de un celular suele mostrar solo la primera página,
 * y una boleta que se ve a medias es peor que una que se abre aparte.
 *
 * El fondo de la foto es `bg-hueso` y no un color fijo: sigue el modo oscuro como
 * el resto de la pantalla. Los colores son los once tokens de `globals.css`.
 */
export function VisorDeHojas({ hojas, tipo }: { hojas: readonly HojaFirmada[]; tipo: TipoBoleta }) {
  const [ampliada, setAmpliada] = useState<number | null>(null);
  const total = hojas.length;

  return (
    <div className="space-y-3">
      {hojas.map((h, i) => (
        <div key={h.ruta}>
          {total > 1 && (
            <p className="mb-1 text-xs text-taupe">
              {tipo === "pdf" ? "Documento" : "Hoja"} {i + 1} de {total}
            </p>
          )}
          {tipo === "pdf" ? (
            <div className="flex items-center justify-between gap-3 rounded-xl border border-sand bg-hueso px-4 py-3">
              <div className="min-w-0">
                <p className="text-sm text-tinta">PDF · {pesoLegible(h.bytes)}</p>
              </div>
              <a
                href={h.url}
                target="_blank"
                rel="noopener noreferrer"
                className="shrink-0 rounded-lg border border-taupe px-3 py-1.5 text-sm text-tinta hover:bg-papel"
              >
                Abrir PDF
              </a>
            </div>
          ) : (
            <div className="max-h-[68vh] overflow-auto rounded-xl border border-sand bg-hueso">
              <button
                type="button"
                onClick={() => setAmpliada(ampliada === i ? null : i)}
                aria-label={ampliada === i ? "Ver la hoja completa" : "Ampliar la hoja"}
                className="block w-full"
              >
                {/* eslint-disable-next-line @next/next/no-img-element -- imagen de un bucket privado, no un asset local */}
                <img
                  src={h.url}
                  alt={total > 1 ? `Hoja ${i + 1} de ${total} de la boleta` : "Boleta"}
                  className={ampliada === i ? "block h-auto w-[190%] max-w-none cursor-zoom-out" : "block h-auto w-full cursor-zoom-in"}
                />
              </button>
            </div>
          )}
        </div>
      ))}
      {tipo === "imagen" && (
        <p className="text-xs text-taupe">
          {ampliada === null ? "Toca una foto para ampliarla." : "Toca la foto para verla completa."}
        </p>
      )}
    </div>
  );
}
