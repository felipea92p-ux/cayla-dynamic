// El botón primario ("rounded-lg bg-tinta px-4 py-2 text-sm font-medium
// text-crema disabled:opacity-50") aparece copiado, casi idéntico, en más de
// cuarenta sitios de admin — 23 de ellos con esa cadena exacta. Cada copia es
// una oportunidad de que alguien ajuste el tono de rojo en una pantalla y se
// le olvide en las otras 22.

import type { ButtonHTMLAttributes } from "react";
import { cx } from "./cx";

type Variante = "primario" | "secundario" | "peligro" | "enlace";
type Tamano = "sm" | "md";

const CHROME: Record<Variante, string> = {
  primario: "rounded-lg bg-tinta text-crema hover:bg-rojo-profundo",
  secundario: "rounded-lg border hover:bg-sand/50",
  peligro: "rounded-lg border border-rojo/30 text-rojo hover:bg-rojo/10",
  enlace: "underline underline-offset-2 hover:text-taupe",
};

const TAMANOS: Record<Tamano, string> = {
  sm: "px-2 py-1 text-xs",
  md: "px-4 py-2 text-sm",
};

export function Boton({
  variante = "secundario",
  tamano = "md",
  className,
  ...props
}: { variante?: Variante; tamano?: Tamano } & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      className={cx(
        CHROME[variante],
        variante !== "enlace" && TAMANOS[tamano],
        "font-medium disabled:opacity-50",
        className,
      )}
      {...props}
    />
  );
}
