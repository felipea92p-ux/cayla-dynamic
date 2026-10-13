// «Un número y su etiqueta» (decisión 1 y 2 de docs/adr/0004-diseno-unificado.md).
// Hasta el 2026-10-13 había seis formas de dibujarla —cifra suelta, franja con
// divisiones, caja con la etiqueta arriba, caja con el número arriba y dos
// casillas filtro— y ningún componente: cada pantalla escribió la suya. Se
// eligió la casilla con fondo hueso al activarse (la de Horarios y Equipo)
// porque la misma caja sirve para una cifra sola y para filtrar lo de abajo.
//
// El color NO va en el número (decisión 2): el número es siempre tinta. El
// significado se dice con un punto de color junto a la etiqueta y con la
// propia etiqueta («Sin horario»), porque el color solo no comunica a quien no
// distingue verde de rojo, y el rojo es el acento escaso del sistema. Los
// nombres de tono son los de <Insignia> y <BannerAviso>: un solo vocabulario.
//
// Tres formas de uso, según lo que le pases:
//   · nada            → una casilla informativa (<div>)
//   · `onClick`       → un filtro (<button aria-pressed>); `activa` la marca
//   · `href`          → un enlace a donde se resuelve (<Link>)
// Todo lo de adentro son <span>, para que sea válido dentro de un <button>.
//
// El número va pegado al fondo de la casilla (`mt-auto`) y la etiqueta arriba:
// en una fila de casillas de igual alto, una etiqueta de una línea y otra de
// tres dejarían los números a distinta altura. Medido en un celular de 390 px
// con las etiquetas reales del Dashboard («Equipo que marca asistencia»). Lo
// que se paga: una casilla con `detalle` sube su número lo que mide el detalle.

import Link from "next/link";
import type { ReactNode } from "react";
import { cx } from "./cx";

type Tono = "alerta" | "advertencia" | "positivo" | "informativo";

const PUNTO: Record<Tono, string> = {
  alerta: "bg-rojo",
  advertencia: "bg-ambar",
  positivo: "bg-verde",
  informativo: "bg-pizarra",
};

export function Cifra({
  etiqueta,
  valor,
  detalle,
  tono,
  activa = false,
  onClick,
  href,
  className,
}: {
  etiqueta: ReactNode;
  /** Ya formateado: la casilla no decide si lleva miles, decimales ni «—». */
  valor: ReactNode;
  /** Una línea chica bajo el número («2 no lo requieren»). */
  detalle?: ReactNode;
  /** Punto de color junto a la etiqueta. Sin tono, no hay punto. */
  tono?: Tono;
  /** Solo tiene efecto con `onClick`: la casilla es el filtro que está aplicado. */
  activa?: boolean;
  onClick?: () => void;
  href?: string;
  className?: string;
}) {
  const interactiva = Boolean(onClick || href);
  const caja = cx(
    "flex flex-col rounded-superficie border p-3 text-left transition-colors duration-150",
    activa ? "border-taupe bg-hueso" : "border-sand bg-papel",
    interactiva && !activa && "hover:bg-hueso",
    className,
  );
  const contenido = (
    <>
      <span className="flex items-center gap-1.5 text-xs text-taupe">
        {tono && <span aria-hidden className={cx("size-2 shrink-0 rounded-pildora", PUNTO[tono])} />}
        {etiqueta}
      </span>
      <span className="mt-auto block pt-1 font-serif text-2xl tabular-nums text-tinta">{valor}</span>
      {detalle && <span className="block text-xs text-taupe">{detalle}</span>}
    </>
  );

  if (href) return <Link href={href} className={caja}>{contenido}</Link>;
  if (onClick) {
    return (
      <button type="button" aria-pressed={activa} onClick={onClick} className={cx(caja, "w-full")}>
        {contenido}
      </button>
    );
  }
  return <div className={caja}>{contenido}</div>;
}
