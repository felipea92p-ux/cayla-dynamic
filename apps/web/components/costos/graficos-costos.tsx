"use client";

// Los gráficos del costado de «Costos del equipo» (2026-10-20): lo que las tablas dicen en filas, dicho en barras, para llenar
// el ancho de la pantalla con algo que se entiende de un vistazo. Cada gráfico lleva SUS cifras escritas al lado de la barra:
// el gráfico dice «cuánto más o menos», el número dice «cuánto». Sin librerías: barras de HTML con los colores del sistema.
//
// Solo dibujan lo que reciben; no calculan costos. De dónde sale cada cifra está en el comentario de la pantalla.

import { cx } from "@/components/ui/cx";
import { formatSoles } from "@/lib/rangos";

/** «S/ 33.4 mil», «S/ 1.2 M»: para el rótulo de una barra, donde «S/ 33,404.56» no cabe. Menos de mil se escribe tal cual. */
export function abreviarSoles(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1_000_000) return `S/ ${(n / 1_000_000).toFixed(1)} M`;
  if (abs >= 1_000) return `S/ ${(n / 1_000).toFixed(1)} mil`;
  return `S/ ${Math.round(n)}`;
}

export interface BarraPeriodo { etiqueta: string; neto: number; provisiones: number; costo: number }

/** Una columna por periodo, la más antigua a la izquierda: abajo lo que se transfirió, arriba las provisiones. */
export function GraficoPorPeriodo({ periodos }: { periodos: BarraPeriodo[] }) {
  const max = Math.max(...periodos.map((p) => p.neto + p.provisiones), 1);
  return (
    <div>
      <div className="flex h-44 items-end gap-3" role="img" aria-label="Costo real por periodo, con lo transferido y las provisiones">
        {periodos.map((p) => {
          const total = p.neto + p.provisiones;
          return (
            <div key={p.etiqueta} className="flex h-full min-w-0 flex-1 flex-col justify-end" title={`${p.etiqueta}: se transfirió ${formatSoles(p.neto)} + provisiones ${formatSoles(p.provisiones)} = ${formatSoles(p.costo)}`}>
              <span className="mb-1 text-center text-[11px] tabular-nums text-taupe">{abreviarSoles(p.costo)}</span>
              <div className="flex w-full flex-col-reverse overflow-hidden rounded-t" style={{ height: `${(total / max) * 82}%` }}>
                <div className="bg-[color-mix(in_oklab,var(--color-tinta)_80%,var(--color-papel))]" style={{ height: `${total > 0 ? (p.neto / total) * 100 : 0}%` }} />
                <div className="bg-ambar" style={{ height: `${total > 0 ? (p.provisiones / total) * 100 : 0}%` }} />
              </div>
            </div>
          );
        })}
      </div>
      <div className="flex gap-3 border-t border-sand pt-1.5">
        {periodos.map((p) => <span key={p.etiqueta} className="min-w-0 flex-1 truncate text-center text-xs text-taupe">{p.etiqueta}</span>)}
      </div>
      <p className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-xs text-taupe">
        <span><i className="mr-1 inline-block size-2.5 rounded-sm bg-[color-mix(in_oklab,var(--color-tinta)_80%,var(--color-papel))] align-middle" aria-hidden />Se transfirió</span>
        <span><i className="mr-1 inline-block size-2.5 rounded-sm bg-ambar align-middle" aria-hidden />Provisiones</span>
      </p>
    </div>
  );
}

export interface ItemBarra { etiqueta: string; valor: number; texto: string; detalle?: string }

/** Barras horizontales ordenadas de mayor a menor, cada una con su número escrito. */
export function BarrasHorizontales({ items, tono = "tinta" }: { items: ItemBarra[]; tono?: "tinta" | "verde" }) {
  const max = Math.max(...items.map((i) => i.valor), 1);
  return (
    <ul className="space-y-3">
      {items.map((i) => (
        <li key={i.etiqueta}>
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="min-w-0 truncate text-tinta">{i.etiqueta}</span>
            <span className="shrink-0 font-medium tabular-nums">{i.texto}</span>
          </div>
          <div className="mt-1 h-2 overflow-hidden rounded-full bg-hueso" aria-hidden>
            <i className={cx("block h-full rounded-full", tono === "verde" ? "bg-verde/70" : "bg-[color-mix(in_oklab,var(--color-tinta)_80%,var(--color-papel))]")} style={{ width: `${Math.max(2, (i.valor / max) * 100)}%` }} />
          </div>
          {i.detalle && <p className="mt-0.5 text-xs text-taupe">{i.detalle}</p>}
        </li>
      ))}
    </ul>
  );
}
