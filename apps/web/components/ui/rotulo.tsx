// Dos rótulos que hasta el 2026-10-13 eran la misma clase `.etiqueta`
// (mayúsculas con espaciado, 46 usos en 26 archivos) haciendo trabajos
// distintos. Se separaron por función (decisiones 11 a 14 de
// docs/adr/0004-diseno-unificado.md):
//
//   · <Rotulo>       → el nombre de una sub-sección DENTRO de una tarjeta ya
//                      titulada: «Plazos del Reglamento», «Acciones», «Medidas».
//                      Sans 12 px, peso medio, taupe. Un nivel por debajo del
//                      título serif de la tarjeta.
//   · <RotuloEstado> → el nombre de un GRUPO cuyo color dice algo: «En pausa»,
//                      «Críticas», «Avisos». Mayúsculas con espaciado en taupe y
//                      un punto del color del estado: el texto no se pinta, igual
//                      que el número de <Cifra>.
//
// Lo que NO es de ninguno de los dos: el sobretítulo sobre el título de pantalla
// (va por `sobretitulo` de <CabeceraPagina>) ni la cabecera de una tarjeta (va
// por `titulo` de <TarjetaInfo>, serif 18 px). El terminal sigue con su propia
// `.etiqueta`: ningún cambio de estilo compartido puede tocarlo.

import type { ReactNode } from "react";
import { cx } from "./cx";
import { Punto, type TonoPunto } from "./punto";

type Elemento = "p" | "div" | "span" | "h3";

export function Rotulo({
  children,
  como: Etiqueta = "p",
  className,
}: {
  children: ReactNode;
  /** El elemento HTML: `h3` si abre una sección que un lector de pantalla debe poder saltar. */
  como?: Elemento;
  className?: string;
}) {
  return <Etiqueta className={cx("text-xs font-medium text-taupe", className)}>{children}</Etiqueta>;
}

export function RotuloEstado({
  tono,
  children,
  como: Etiqueta = "div",
  className,
}: {
  /** Sin tono, es solo el rótulo en mayúsculas, sin punto («Avisos» neutros). */
  tono?: TonoPunto;
  children: ReactNode;
  como?: Elemento;
  className?: string;
}) {
  return (
    <Etiqueta className={cx("etiqueta flex items-center gap-1.5 text-taupe", className)}>
      {tono && <Punto tono={tono} />}
      {children}
    </Etiqueta>
  );
}
