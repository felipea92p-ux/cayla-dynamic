// El "pill" de estado (activa/inactiva, tardanza, en pausa...) se repite con
// pequeñas variaciones de color en más de veinte pantallas de admin. Acá
// viven los tonos que Dynamic ya usa — no se inventa uno nuevo por pantalla.

import type { ReactNode } from "react";
import { cx } from "./cx";

type Variante = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo" | "contador";
type Tamano = "sm" | "md";

const TONOS: Record<Variante, string> = {
  neutral: "bg-sand text-tinta",
  // Antes era "bg-rojo/10 text-rojo": medido con la fórmula de contraste
  // relativo WCAG tal como el navegador pinta la mezcla (10% de rojo sobre
  // crema/papel/hueso), ese par no llega a 4.5:1 en ningún tema — mínimo
  // 3.71:1 sobre hueso en claro, 3.82:1 sobre papel en oscuro. Con
  // text-rojo-profundo sobre el mismo fondo sube a un mínimo de 5.30:1 en los
  // cuatro contextos habituales (crema/papel × claro/oscuro). --color-rojo no
  // se toca: es el acento sagrado y lo comparte el terminal.
  alerta: "bg-rojo/10 text-rojo-profundo",
  advertencia: "bg-ambar/15 text-ambar",
  // "presente", "aprobado", "activa" — el estado más frecuente del panel no
  // tenía variante propia pese a que --color-verde existe justo para esto.
  // Opacidad de fondo bajada de 15% a 10%: medida, al 15% el par caía a
  // 4.43:1 en oscuro sobre papel, por debajo del mínimo AA. Al 10% el peor
  // caso (oscuro/papel) da 4.85:1.
  positivo: "bg-verde/10 text-verde",
  // "programado", "en revisión", "borrador", "pendiente de firma" — hoy se
  // apilaban sin distinguirse sobre sand neutro. Opacidad de fondo bajada de
  // 15% a 8%: medida, al 15% caía a 4.21:1 en claro sobre crema — el fondo
  // dominante del panel. Al 8% el peor caso (claro/crema) da 4.63:1.
  informativo: "bg-pizarra/8 text-pizarra",
  // Insignia de contador (badges numéricos del menú, hoy escritos a mano):
  // relleno sólido, no una mezcla translúcida — un número tiene que leerse de
  // inmediato, no convivir de fondo como un estado. Nunca lleva punto (ver
  // `punto` más abajo): no es un estado, es una cuenta.
  contador: "bg-rojo text-crema font-medium",
};

const TAMANOS: Record<Tamano, string> = {
  // El de siempre, sin cambios.
  md: "px-2 py-0.5 text-xs",
  // El contador chico del menú, junto a un ícono.
  sm: "px-1.5 text-[10px] leading-4",
};

export function Insignia({
  children,
  variante = "neutral",
  tamano = "md",
  atenuada = false,
  punto,
  className,
}: {
  children: ReactNode;
  variante?: Variante;
  /** "sm" es el tamaño chico del contador de menú; el resto de Insignia usa "md" (por defecto). */
  tamano?: Tamano;
  /** Para estados neutros que no ameritan llamar la atención (ej. "inactiva"): mismo fondo, texto apagado. */
  atenuada?: boolean;
  /**
   * Punto de color junto al texto. Por defecto va encendido en las variantes
   * de estado y apagado en "contador" (un número no es un estado). Se puede
   * forzar en cualquier caso — por ejemplo una etiqueta puramente descriptiva
   * ("se paga") que no debe leerse como un semáforo de estado.
   */
  punto?: boolean;
  className?: string;
}) {
  const conPunto = punto ?? variante !== "contador";
  return (
    <span
      className={cx(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-pildora",
        TAMANOS[tamano],
        atenuada ? "bg-sand text-taupe" : TONOS[variante],
        className,
      )}
    >
      {conPunto && (
        // Punto de color además del texto: ayuda a quien no distingue bien
        // verde de ámbar por matiz (la forma más común de daltonismo).
        <span className="size-1.5 rounded-full bg-current" aria-hidden />
      )}
      {children}
    </span>
  );
}
