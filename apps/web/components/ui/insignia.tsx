// El "pill" de estado (activa/inactiva, tardanza, en pausa...) se repite con
// pequeñas variaciones de color en más de veinte pantallas de admin. Acá
// viven los tonos que Dynamic ya usa — no se inventa uno nuevo por pantalla.
//
// Retocado 2026-09-07, antes del Día 2:
// - `alerta` cambia el texto a rojo-profundo (el fondo bg-rojo/10 no se
//   toca: --color-rojo es el acento sagrado y lo comparte el terminal).
//   Medido tal como se pinta de verdad —texto sobre el 10% de opacidad
//   compuesto sobre crema y papel—: con text-rojo daba 3.82-4.49:1 según
//   tema y fondo, los cuatro bajo el 4.5:1 de WCAG AA para texto normal, y
//   es el patrón con que 76 sitios del panel muestran un error. Con
//   text-rojo-profundo da 5.30-7.03:1. Las otras cuatro variantes ya pasan
//   4.5:1 con los tokens retonados el mismo día (ver globals.css).
// - Nueva variante `contador`: nav.tsx escribe seis veces a mano
//   "rounded-full bg-rojo ... text-crema" para los contadores del menú, en
//   dos tamaños — un pill de ESTADO (fondo tenue + punto) no sirve para eso.
//   `punto` pasa a opcional porque un número ya es su propia señal.
import type { ReactNode } from "react";
import { cx } from "./cx";

type Variante = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo" | "contador";
type Tamano = "sm" | "md";

const TONOS: Record<Variante, string> = {
  neutral: "bg-sand text-tinta",
  alerta: "bg-rojo/10 text-rojo-profundo",
  advertencia: "bg-ambar/15 text-ambar",
  // "presente", "aprobado", "activa" — el estado más frecuente del panel no
  // tenía variante propia pese a que --color-verde existe justo para esto.
  positivo: "bg-verde/15 text-verde",
  // "programado", "en revisión", "borrador", "pendiente de firma" — hoy se
  // apilaban sin distinguirse sobre sand neutro.
  informativo: "bg-pizarra/15 text-pizarra",
  // Relleno sólido, no un estado — el contador del menú (nav.tsx).
  contador: "bg-rojo font-medium text-crema",
};

const TAMANOS_CONTADOR: Record<Tamano, string> = {
  sm: "px-1.5 text-[10px] leading-4",
  md: "px-2 text-xs leading-5",
};

export function Insignia({
  children,
  variante = "neutral",
  atenuada = false,
  punto,
  tamano = "md",
  className,
}: {
  children: ReactNode;
  variante?: Variante;
  /** Para estados neutros que no ameritan llamar la atención (ej. "inactiva"): mismo fondo, texto apagado. */
  atenuada?: boolean;
  /** El punto de color además del texto. Por defecto va en las variantes de estado y no en "contador" (un número ya es su propia señal). */
  punto?: boolean;
  /** Solo aplica a variante="contador": los dos tamaños que ya usa nav.tsx. */
  tamano?: Tamano;
  className?: string;
}) {
  const esContador = variante === "contador";
  const mostrarPunto = punto ?? !esContador;
  return (
    <span
      className={cx(
        "inline-flex items-center whitespace-nowrap rounded-pildora",
        esContador ? cx("justify-center", TAMANOS_CONTADOR[tamano]) : "gap-1.5 px-2 py-0.5 text-xs",
        atenuada ? "bg-sand text-taupe" : TONOS[variante],
        className,
      )}
    >
      {/* Punto de color además del texto: ayuda a quien no distingue bien
       * verde de ámbar por matiz (la forma más común de daltonismo). */}
      {mostrarPunto && <span className="size-1.5 rounded-full bg-current" aria-hidden />}
      {children}
    </span>
  );
}
