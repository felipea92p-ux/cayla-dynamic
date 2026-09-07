// El primer input/select compartido del sistema (2026-09-06). Antes cada
// pantalla escribía "rounded-lg border px-3 py-2" a mano — más de 100 veces
// medidas en 16+ archivos, con divergencias reales (border vs border-sand,
// con o sin bg-crema, foco visible en 2-9 de ~40 archivos nada más). El foco
// no se declara acá: lo cubre la regla :focus-visible de globals.css para
// cualquier control de la app.
//
// La etiqueta del campo es texto-sm en caja normal, NO la clase .etiqueta de
// globals.css (mayúsculas + tracking 0.16em). Se midió contra las 83 etiquetas
// de formulario que ya existían en el panel — todas en caja normal, gap-1 — y
// las mayúsculas alargaban y afeaban etiquetas largas tipo "Contacto de
// emergencia — parentesco" (se leen letra por letra, no por silueta). .etiqueta
// se queda para encabezados de sección, que es donde ya vivía.

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
    <label className="flex flex-col gap-1">
      {etiqueta && <span className="text-sm text-taupe">{etiqueta}</span>}
      <input
        id={id}
        className={cx(
          // text-base en el teléfono: por debajo de 16px Safari de iOS hace zoom
          // al enfocar el campo y no lo deshace al salir. sm: vuelve a 14px en
          // escritorio, donde el zoom automático no aplica.
          "rounded-control border border-sand bg-hueso px-3 py-2 text-base sm:text-sm text-tinta transition-colors duration-150 placeholder:text-taupe/60",
          error && "border-rojo",
          className,
        )}
        {...props}
      />
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

// Las 17 casillas del panel se escribían sueltas y en tres formas distintas
// (sin clase, size-4, h-3.5 w-3.5 accent-tinta, h-4 w-4 accent-tinta): 14 de
// ellas sin accent salían en el azul por defecto del sistema operativo —que
// no es ninguno de los once colores de la marca— y en oscuro además con el
// recuadro claro, porque el proyecto no declaraba color-scheme (ya resuelto
// en globals.css). CampoCasilla fija una sola forma: label en fila (a
// diferencia de Campo/CampoSelect, que van en columna — una casilla se lee
// antes que su etiqueta, no debajo), accent-tinta + size-4.
export function CampoCasilla({
  etiqueta,
  error,
  id,
  className,
  ...props
}: BaseProps & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="flex items-center gap-2">
      <input
        id={id}
        type="checkbox"
        className={cx("size-4 accent-tinta", error && "outline outline-1 outline-rojo", className)}
        {...props}
      />
      {etiqueta && <span className="text-sm text-tinta">{etiqueta}</span>}
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
    <label className="flex flex-col gap-1">
      {etiqueta && <span className="text-sm text-taupe">{etiqueta}</span>}
      <div className="relative">
        <select
          id={id}
          className={cx(
            // text-base en el teléfono, mismo motivo que en Campo.
            "w-full appearance-none rounded-control border border-sand bg-hueso px-3 py-2 pr-8 text-base sm:text-sm text-tinta transition-colors duration-150",
            error && "border-rojo",
            className,
          )}
          {...props}
        >
          {children}
        </select>
        {/* Flecha propia en vez de un color quemado dentro del data-URI de fondo:
            currentColor + text-taupe sigue el token entre tema claro y oscuro,
            igual que el resto de la app. Un hex fijo ahí adentro no lo ve ningún
            grep de clases y se queda mal en oscuro sin que nadie lo note. */}
        <svg
          aria-hidden="true"
          viewBox="0 0 20 20"
          className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-taupe"
        >
          <path d="M5.5 7.5l4.5 4.5 4.5-4.5" stroke="currentColor" strokeWidth="1.5" fill="none" />
        </svg>
      </div>
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}
