// El primer input/select compartido del sistema (2026-09-06). Antes cada
// pantalla escribía "rounded-lg border px-3 py-2" a mano — más de 100 veces
// medidas en 16+ archivos, con divergencias reales (border vs border-sand,
// con o sin bg-crema, foco visible en 2-9 de ~40 archivos nada más). El foco
// lo cubre la regla :focus-visible de globals.css para cualquier control de la
// app, con UNA excepción puesta acá (2026-10-13): `outline-offset-0`. El anillo
// de 2 px separado 2 px del control se leía bien en un botón, pero en un campo
// —y sobre todo en un select abierto en modo oscuro— dejaba tres marcos
// seguidos (anillo, hueco, borde) alrededor de un fondo casi negro. Pegado al
// borde es un solo marco.
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

// Dos tamaños, con el mismo vocabulario que <Boton> y <Filtro> (2026-10-19): «md» es el de siempre;
// «sm» es para una barra de filtros que se mira todo el día junto a filtros «sm» (el buscador y los
// desplegables del Dashboard), donde el campo a 36 px y 14 px de letra pesaba más que lo que filtra.
// En celular el control sigue en 16 px sea cual sea el tamaño: Safari de iOS hace zoom por debajo.
const TAMANO_CAMPO = {
  md: "py-2 sm:text-sm",
  sm: "py-1.5 sm:text-xs",
} as const;

type BaseProps = {
  tamano?: keyof typeof TAMANO_CAMPO;
  etiqueta?: string;
  /** Mensaje de error, con borde rojo a juego. No valida por sí solo. */
  error?: string;
};

export function Campo({
  tamano = "md",
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
          "rounded-control border border-sand bg-hueso px-3 text-base text-tinta transition-colors duration-150 placeholder:text-taupe/60 focus-visible:outline-offset-0",
          TAMANO_CAMPO[tamano],
          error && "border-rojo",
          className,
        )}
        {...props}
      />
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

// Las 17 casillas del panel se escribían sueltas y en cuatro formas distintas
// (sin clase, size-4, h-3.5 w-3.5 accent-tinta, h-4 w-4 accent-tinta): 14 de
// ellas sin accent salían en el azul por defecto del sistema operativo —que
// no es ninguno de los once colores de la marca— y en oscuro además con el
// recuadro claro, porque el proyecto no declaraba color-scheme (ya resuelto
// en globals.css). CampoCasilla generaliza el único de los tres patrones con
// color que sí usaba el de la marca ("size-4" en horas, "h-4 w-4
// accent-tinta" en equipo): label en fila (a diferencia de Campo/CampoSelect,
// que van en columna — una casilla se lee antes que su etiqueta, no debajo),
// accent-tinta + size-4, con outline-rojo cuando trae error y opacidad
// reducida cuando está disabled.
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
        className={cx(
          "size-4 accent-tinta disabled:opacity-50",
          error && "outline outline-1 outline-rojo",
          className,
        )}
        {...props}
      />
      {etiqueta && <span className="text-sm text-tinta">{etiqueta}</span>}
      {error && <span className="text-xs text-rojo">{error}</span>}
    </label>
  );
}

export function CampoSelect({
  tamano = "md",
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
            "w-full appearance-none rounded-control border border-sand bg-hueso px-3 pr-8 text-base text-tinta transition-colors duration-150 focus-visible:outline-offset-0",
            TAMANO_CAMPO[tamano],
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
