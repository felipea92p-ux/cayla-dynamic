// El primer input/select compartido del sistema (2026-09-06). Antes cada
// pantalla escribía "rounded-lg border px-3 py-2" a mano — más de 100 veces
// medidas en 16+ archivos, con divergencias reales (border vs border-sand,
// con o sin bg-crema, foco visible en 2-9 de ~40 archivos nada más). El foco
// no se declara acá: lo cubre la regla :focus-visible de globals.css para
// cualquier control de la app.

import type { InputHTMLAttributes, SelectHTMLAttributes, ReactNode } from "react";
import { cx } from "./cx";

type BaseProps = {
  etiqueta?: string;
  /** Mensaje de error, con borde rojo a juego. No valida por sí solo. */
  error?: string;
};

export function Campo({
  etiqueta,
  error,
  id,
  className,
  ...props
}: BaseProps & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="flex flex-col gap-1.5">
      {etiqueta && (
        <span className="text-xs font-medium uppercase tracking-[0.06em] text-taupe">{etiqueta}</span>
      )}
      <input
        id={id}
        className={cx(
          "rounded-control border border-sand bg-hueso px-3 py-2 text-sm text-tinta transition-colors duration-150 placeholder:text-taupe/60",
          error && "border-rojo",
          className,
        )}
        {...props}
      />
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

export function CampoSelect({
  etiqueta,
  error,
  id,
  className,
  children,
  ...props
}: BaseProps & SelectHTMLAttributes<HTMLSelectElement> & { children: ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      {etiqueta && (
        <span className="text-xs font-medium uppercase tracking-[0.06em] text-taupe">{etiqueta}</span>
      )}
      <select
        id={id}
        className={cx(
          "appearance-none rounded-control border border-sand bg-hueso bg-[right_0.6rem_center] bg-no-repeat px-3 py-2 pr-8 text-sm text-tinta transition-colors duration-150",
          "bg-[url('data:image/svg+xml;utf8,<svg%20xmlns=%22http://www.w3.org/2000/svg%22%20viewBox=%220%200%2020%2020%22><path%20d=%22M5.5%207.5l4.5%204.5%204.5-4.5%22%20stroke=%22%23805c4c%22%20stroke-width=%221.5%22%20fill=%22none%22/></svg>')]",
          error && "border-rojo",
          className,
        )}
        {...props}
      >
        {children}
      </select>
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}
