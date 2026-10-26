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
//   · `onClick` + `controla` → abre un detalle debajo (acordeón): en vez de
//                       aria-pressed lleva aria-expanded y aria-controls, que es
//                       lo que un lector de pantalla espera de «mostrar más».
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
import { Punto, type TonoPunto } from "./punto";


export function Cifra({
  tamano = "md",
  etiqueta,
  valor,
  detalle,
  tono,
  activa = false,
  onClick,
  controla,
  href,
  className,
}: {
  /**
   * «md» es la casilla de siempre (etiqueta arriba, número abajo). «sm» (2026-10-19, a pedido de Felipe
   * para el resumen del Dashboard): una fila —la etiqueta a la izquierda, el número a la derecha— y
   * menos margen, de ~92 px de alto a ~48. El número sigue siendo serif y tinta (decisiones 1 y 2): lo
   * que se achica es el aire, no la cifra.
   */
  tamano?: "sm" | "md";
  etiqueta: ReactNode;
  /** Ya formateado: la casilla no decide si lleva miles, decimales ni «—». */
  valor: ReactNode;
  /** Una línea chica bajo el número («2 no lo requieren»). */
  detalle?: ReactNode;
  /** Punto de color junto a la etiqueta. Sin tono, no hay punto. */
  tono?: TonoPunto;
  /** Solo tiene efecto con `onClick`: la casilla es el filtro que está aplicado. */
  activa?: boolean;
  onClick?: () => void;
  /** El id de la región que esta casilla abre. Con él, `activa` significa «abierta». */
  controla?: string;
  href?: string;
  className?: string;
}) {
  const interactiva = Boolean(onClick || href);
  const compacta = tamano === "sm";
  const caja = cx(
    "flex rounded-superficie border text-left transition-colors duration-150",
    compacta ? "items-center justify-between gap-3 px-3 py-2" : "flex-col p-3",
    activa ? "border-taupe bg-hueso" : "border-sand bg-papel",
    interactiva && !activa && "hover:bg-hueso",
    className,
  );
  const contenido = compacta ? (
    <>
      <span className="min-w-0">
        <span className="flex items-center gap-1.5 text-xs leading-snug text-taupe">
          {tono && <Punto tono={tono} />}
          {etiqueta}
        </span>
        {detalle && <span className="block text-xs leading-snug text-taupe">{detalle}</span>}
      </span>
      <span className="shrink-0 font-serif text-xl tabular-nums text-tinta">{valor}</span>
    </>
  ) : (
    <>
      <span className="flex items-center gap-1.5 text-xs text-taupe">
        {tono && <Punto tono={tono} />}
        {etiqueta}
      </span>
      <span className="mt-auto block pt-1 font-serif text-2xl tabular-nums text-tinta">{valor}</span>
      {detalle && <span className="block text-xs text-taupe">{detalle}</span>}
    </>
  );

  if (href) return <Link href={href} className={caja}>{contenido}</Link>;
  if (onClick) {
    return (
      <button
        type="button"
        {...(controla ? { "aria-expanded": activa, "aria-controls": controla } : { "aria-pressed": activa })}
        onClick={onClick}
        className={cx(caja, "w-full")}
      >
        {contenido}
      </button>
    );
  }
  return <div className={caja}>{contenido}</div>;
}
