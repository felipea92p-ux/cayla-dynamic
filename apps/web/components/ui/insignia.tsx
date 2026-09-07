// El "pill" de estado (activa/inactiva, tardanza, en pausa...) se repite con
// pequeñas variaciones de color en más de veinte pantallas de admin. Acá
// viven los tonos que Dynamic ya usa — no se inventa uno nuevo por pantalla.

import type { ReactNode } from "react";
import { cx } from "./cx";

type Variante = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";

const TONOS: Record<Variante, string> = {
  neutral: "bg-sand text-tinta",
  alerta: "bg-rojo/10 text-rojo",
  advertencia: "bg-ambar/15 text-ambar",
  // "presente", "aprobado", "activa" — el estado más frecuente del panel no
  // tenía variante propia pese a que --color-verde existe justo para esto.
  positivo: "bg-verde/15 text-verde",
  // "programado", "en revisión", "borrador", "pendiente de firma" — hoy se
  // apilaban sin distinguirse sobre sand neutro.
  informativo: "bg-pizarra/15 text-pizarra",
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
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-pildora px-2 py-0.5 text-xs",
        atenuada ? "bg-sand text-taupe" : TONOS[variante],
        className,
      )}
    >
      {/* Punto de color además del texto: ayuda a quien no distingue bien
       * verde de ámbar por matiz (la forma más común de daltonismo). */}
      <span className="size-1.5 rounded-full bg-current" aria-hidden />
      {children}
    </span>
  );
}
