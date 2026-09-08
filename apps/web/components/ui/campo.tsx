// El primer input/select compartido del sistema (2026-09-06). Antes cada
// pantalla escribía "rounded-lg border px-3 py-2" a mano — más de 100 veces
// medidas en 16+ archivos, con divergencias reales (border vs border-sand,
// con o sin bg-crema, foco visible en 2-9 de ~40 archivos nada más). El foco
// no se declara acá: lo cubre la regla :focus-visible de globals.css para
// cualquier control de la app.
//
// Retocado 2026-09-07, antes de que el Día 2 empiece a adoptarlo en masa:
// - La etiqueta pasa de mayúsculas con tracking a caja normal, igual que las
//   83 que ya existen hoy (`<label className="… text-sm">`). Se comparó a
//   ojo «Contacto de emergencia — parentesco» en los tres tratamientos:
//   mayúsculas cortas leen palabra por palabra, caja normal lee de corrido.
//   Las mayúsculas quedan para encabezados de sección, que es donde vive
//   `.etiqueta` — un formulario no es un encabezado.
// - `text-sm` en el control pasa a `text-base sm:text-sm`: Safari de iOS
//   agranda la página al enfocar cualquier control con letra menor a 16px, y
//   no lo deshace sola. Medido: 232 controles del panel están hoy bajo ese
//   umbral. Arreglarlo acá cuesta una línea; después del Día 2 cuesta 232
//   sitios.

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
          "rounded-control border border-sand bg-hueso px-3 py-2 text-base text-tinta transition-colors duration-150 placeholder:text-taupe/60 sm:text-sm",
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
    <label className="flex flex-col gap-1">
      {etiqueta && <span className="text-sm text-taupe">{etiqueta}</span>}
      <div className="relative">
        <select
          id={id}
          className={cx(
            "w-full appearance-none rounded-control border border-sand bg-hueso px-3 py-2 pr-8 text-base text-tinta transition-colors duration-150 sm:text-sm",
            error && "border-rojo",
            className,
          )}
          {...props}
        >
          {children}
        </select>
        {/* Flecha propia en vez del truco de fondo: `mask` en vez de `background-image`
            para que tome el color de `bg-taupe` y siga el tema — un color cocido dentro
            del data-URI (como antes) no lo ve ningún grep de clases ni el token oscuro. */}
        <span
          aria-hidden
          className={cx(
            "pointer-events-none absolute top-1/2 right-[0.6rem] size-[10px] -translate-y-1/2 bg-taupe",
            "[mask-image:url('data:image/svg+xml;utf8,<svg%20xmlns=%22http://www.w3.org/2000/svg%22%20viewBox=%220%200%2020%2020%22><path%20d=%22M5.5%207.5l4.5%204.5%204.5-4.5%22%20stroke=%22black%22%20stroke-width=%221.5%22%20fill=%22none%22/></svg>')]",
            "[mask-repeat:no-repeat] [mask-size:contain] [-webkit-mask-repeat:no-repeat] [-webkit-mask-size:contain]",
            "[-webkit-mask-image:url('data:image/svg+xml;utf8,<svg%20xmlns=%22http://www.w3.org/2000/svg%22%20viewBox=%220%200%2020%2020%22><path%20d=%22M5.5%207.5l4.5%204.5%204.5-4.5%22%20stroke=%22black%22%20stroke-width=%221.5%22%20fill=%22none%22/></svg>')]",
          )}
        />
      </div>
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

// Sin este primitivo, las 17 casillas del panel se escriben sueltas y en tres
// formas distintas: 14 sin ninguna clase (salen en el azul del sistema
// operativo, ninguno de los once colores de la marca), "size-4" en horas, y
// "h-4 w-4 accent-tinta" en equipo — el único de los tres que sí usa el
// color de la marca. CampoCasilla generaliza ese último patrón. La etiqueta
// va EN FILA (no en columna, como Campo/CampoSelect): una casilla y su texto
// son una sola unidad de lectura, y ponerlos uno encima del otro es la
// disposición equivocada.
export function CampoCasilla({
  etiqueta,
  error,
  id,
  className,
  ...props
}: BaseProps & InputHTMLAttributes<HTMLInputElement>) {
  return (
    <label className="flex items-center gap-2">
      <input type="checkbox" id={id} className={cx("size-4 accent-tinta disabled:opacity-50", className)} {...props} />
      {etiqueta && <span className="text-sm text-tinta">{etiqueta}</span>}
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}
