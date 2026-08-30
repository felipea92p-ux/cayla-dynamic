// El "pill" de estado (activa/inactiva, tardanza, en pausa...) se repite con
// pequeñas variaciones de color en más de veinte pantallas de admin. Acá
// viven los tonos que Dynamic ya usa — no se inventa uno nuevo por pantalla.

import type { ReactNode } from "react";
import { cx } from "./cx";

type Variante = "neutral" | "alerta" | "advertencia";

const TONOS: Record<Variante, string> = {
  neutral: "bg-sand text-tinta",
  alerta: "bg-rojo/10 text-rojo",
  advertencia: "bg-ambar/15 text-ambar",
};

export function Insignia({
  children,
  variante = "neutral",
  atenuada = false,
  className,
}: {
  children: ReactNode;
  variante?: Variante;
  /** Para estados neutros que no ameritan llamar la atención (ej. "inactiva"): mismo fondo, texto apagado. */
  atenuada?: boolean;
  className?: string;
}) {
  return (
    <span
      className={cx(
        "whitespace-nowrap rounded-full px-2 py-0.5 text-xs",
        atenuada ? "bg-sand text-taupe" : TONOS[variante],
        className,
      )}
    >
      {children}
    </span>
  );
}
