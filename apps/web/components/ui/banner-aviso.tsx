// El banner "rounded-2xl border border-{color}/N bg-{color}/N p-N" (título +
// texto, a veces + lista) está copiado a mano en al menos 7 pantallas (mio,
// incidencias, dashboard, reporte-sede, datos-personales, correcciones), cada
// una con su propio padding y su propia opacidad de borde/fondo — mismo
// defecto que ya resolvió <Insignia> para la pastilla chica, pero nadie lo
// había resuelto para el banner grande. Mismos nombres de variante que
// Insignia (neutral/alerta/advertencia/positivo/informativo), para pensar el
// color de un aviso siempre de la misma manera en toda la app.

import type { ReactNode } from "react";
import { cx } from "./cx";

type Variante = "neutral" | "alerta" | "advertencia" | "positivo" | "informativo";

// Border al 30-40% y fondo muy tenue (6-7%) — medido contra las instancias que
// ya usaban el mayor contenido (título + lista), que es el caso más exigente.
const TONOS: Record<Variante, string> = {
  neutral: "border-sand bg-sand/20",
  alerta: "border-rojo/30 bg-rojo/[0.06]",
  advertencia: "border-ambar/40 bg-ambar/[0.07]",
  positivo: "border-verde/30 bg-verde/[0.06]",
  informativo: "border-pizarra/30 bg-pizarra/[0.06]",
};

const TEXTO_TITULO: Record<Variante, string> = {
  neutral: "text-tinta",
  alerta: "text-rojo-profundo",
  advertencia: "text-ambar",
  positivo: "text-verde",
  informativo: "text-pizarra",
};

export function BannerAviso({
  titulo,
  variante = "advertencia",
  children,
  className,
}: {
  /** Texto del encabezado (font-serif text-lg). Omitilo para un aviso de una sola línea sin título propio. */
  titulo?: ReactNode;
  variante?: Variante;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cx("rounded-superficie border p-5 text-sm", TONOS[variante], className)}>
      {titulo && <h2 className={cx("mb-1 font-serif text-lg", TEXTO_TITULO[variante])}>{titulo}</h2>}
      {children}
    </div>
  );
}
