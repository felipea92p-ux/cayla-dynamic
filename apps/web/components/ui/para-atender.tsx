// «Para atender»: lo que pide una decisión hoy, en UNA línea de pastillas que filtran al tocarlas.
// Nació en Educación (2026-10-17), donde reemplazó a cinco tarjetas grandes; se movió acá cuando
// Asistencia pidió lo mismo, para que las dos pantallas lean igual y no haya dos formas de
// «lo que falta resolver».
//
// Un cero no se dibuja: una pastilla con 0 es ruido que obliga a leerla para saber que no hay
// nada. Si no hay nada pendiente, la línea lo dice en tres palabras. El color no va solo: cada
// pastilla lleva su cuenta y su palabra («2 vencidas»).

import type { ReactNode } from "react";

const TONO = {
  pizarra: "border-pizarra/40 bg-pizarra/10 text-pizarra",
  rojo: "border-rojo/30 bg-rojo/10 text-rojo-profundo",
  ambar: "border-ambar/40 bg-ambar/15 text-ambar",
  neutro: "border-sand bg-papel text-tinta",
} as const;

export type TonoParaAtender = keyof typeof TONO;

export function ParaAtender({
  items,
  activa,
  alTocar,
  extra,
  titulo = "Para atender",
  compacta = false,
}: {
  items: { clave: string; texto: string; n: number; tono: TonoParaAtender }[];
  /** La pastilla que está filtrando ahora; se muestra aunque su cuenta haya bajado a cero. */
  activa: string | null;
  alTocar: (clave: string) => void;
  extra?: ReactNode;
  /** «Para atender» casi siempre; «Para decidir» donde lo pendiente son decisiones (Turnos), no trámites. */
  titulo?: string;
  /** Dentro de otra franja (Planilla): sin rótulo ni margen inferior; la franja ya dice de qué habla. */
  compacta?: boolean;
}) {
  const con = items.filter((x) => x.n > 0 || x.clave === activa);
  return (
    <div className={`${compacta ? "" : "mb-4 "}flex flex-wrap items-center gap-2`}>
      {!compacta && <span className="text-xs font-medium uppercase tracking-wide text-taupe">{titulo}</span>}
      {con.length === 0 && !extra ? <span className="text-sm text-verde">Nada pendiente</span> : con.map((x) => (
        <button key={x.clave} type="button" aria-pressed={activa === x.clave} onClick={() => alTocar(x.clave)}
          className={`rounded-full border px-3 py-1 text-xs font-medium tabular-nums transition-shadow duration-150 ${TONO[x.tono]} ${
            activa === x.clave ? "ring-2 ring-tinta" : ""}`}>
          {x.texto}
        </button>
      ))}
      {extra}
    </div>
  );
}
