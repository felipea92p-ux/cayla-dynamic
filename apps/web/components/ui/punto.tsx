// El punto de color que acompaña a una etiqueta (decisiones 2 y 14 de
// docs/adr/0004-diseno-unificado.md). Un solo dibujo para <Cifra> y
// <RotuloEstado>: antes cada pantalla pintaba el suyo con `size-2`, `h-2 w-2` o
// `size-1.5` según el día. Los nombres de tono son los de <Insignia> y
// <BannerAviso>.
//
// Es decorativo (`aria-hidden`) a propósito: el significado lo dice la palabra de
// al lado. El color solo no comunica a quien no distingue verde de rojo.

import { cx } from "./cx";

export type TonoPunto = "alerta" | "advertencia" | "positivo" | "informativo";

const COLOR: Record<TonoPunto, string> = {
  alerta: "bg-rojo",
  advertencia: "bg-ambar",
  positivo: "bg-verde",
  informativo: "bg-pizarra",
};

export function Punto({ tono, className }: { tono: TonoPunto; className?: string }) {
  return <span aria-hidden className={cx("size-2 shrink-0 rounded-pildora", COLOR[tono], className)} />;
}
