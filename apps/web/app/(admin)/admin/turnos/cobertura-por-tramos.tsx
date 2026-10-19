"use client";

// «MAÑANA Y TARDE» (2026-10-19, variante E de la maqueta de Turnos): la cobertura de un día dicha como la meta se pone —en dos
// tramos y con un número— y no dibujada. «Mañana 2 de 3 · falta 1», «Tarde completo», con quién está en cada tramo. Tocar a una
// persona abre su turno, igual que antes la barra.
//
// Solo dibuja: los números salen de `lib/admin/cobertura-tramos.ts` (con prueba) y quién cuenta como operativa o líder, de
// `cobertura-equipo.ts`. El color nunca va solo: cada estado lleva su palabra y su símbolo.

import type { ReactNode } from "react";
import { Insignia } from "@/components/ui/insignia";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { cx } from "@/components/ui/cx";
import type { EstadoTramo } from "@/lib/admin/cobertura-tramos";

export interface PersonaDelDia {
  id: string;
  nombre: string;
  /** «08:45–18:00», o lo que quede decir de su día («descanso», «sin turno»). */
  detalle: string;
  /** Una etiqueta pequeña (el área, cuando no es operativa). */
  aparte?: string;
}

type VarianteInsignia = "positivo" | "alerta" | "advertencia" | "neutral";
const INSIGNIA: Record<EstadoTramo, { texto: (faltan: number, sobran: number) => string; variante: VarianteInsignia; simbolo: string }> = {
  sin_meta: { texto: () => "sin meta", variante: "neutral", simbolo: "·" },
  falta: { texto: (f) => (f === 1 ? "falta 1" : `faltan ${f}`), variante: "alerta", simbolo: "▲" },
  con_huecos: { texto: () => "con huecos", variante: "advertencia", simbolo: "▲" },
  sobra: { texto: (_, s) => (s === 1 ? "sobra 1" : `sobran ${s}`), variante: "advertencia", simbolo: "●" },
  completo: { texto: () => "completo", variante: "positivo", simbolo: "✓" },
};
const TONO_SEGMENTO: Record<EstadoTramo, string> = {
  sin_meta: "bg-taupe/50 border-taupe",
  falta: "bg-rojo/55 border-rojo",
  con_huecos: "bg-ambar/55 border-ambar",
  sobra: "bg-ambar/55 border-ambar",
  completo: "bg-verde/55 border-verde",
};

/** El medidor: un cuadrito por persona; con meta, los vacíos son las que faltan. */
export function Medidor({ n, meta, estado }: { n: number; meta: number; estado: EstadoTramo }) {
  const total = Math.max(meta, n, 1);
  return (
    <span className="inline-flex gap-1" aria-hidden>
      {Array.from({ length: total }, (_, i) => (
        <i key={i} className={cx("h-2.5 w-5 rounded-[3px] border", i < n ? TONO_SEGMENTO[estado] : "border-sand bg-hueso")} />
      ))}
    </span>
  );
}

export function InsigniaTramo({ estado, faltan, sobran }: { estado: EstadoTramo; faltan: number; sobran: number }) {
  const i = INSIGNIA[estado];
  return <Insignia variante={i.variante}>{i.simbolo} {i.texto(faltan, sobran)}</Insignia>;
}

function Chip({ p, onAbrir }: { p: PersonaDelDia; onAbrir?: (id: string) => void }) {
  return (
    <button
      type="button"
      onClick={onAbrir ? () => onAbrir(p.id) : undefined}
      disabled={!onAbrir}
      className="inline-flex items-baseline gap-1.5 rounded-pildora border border-sand bg-crema px-3 py-1 text-sm transition-colors duration-150 enabled:hover:border-taupe disabled:cursor-default"
    >
      <span>{p.nombre}</span>
      <small className="tabular-nums text-taupe">{p.detalle}</small>
      {p.aparte && <small className="text-ambar">· {p.aparte}</small>}
    </button>
  );
}

export function TarjetaTramo({
  titulo,
  subtitulo,
  n,
  meta,
  estado,
  faltan,
  sobran,
  gente,
  metaEditable,
  onAbrir,
}: {
  titulo: string;
  subtitulo: string;
  n: number;
  meta: number;
  estado: EstadoTramo;
  faltan: number;
  sobran: number;
  gente: PersonaDelDia[];
  /** El campo de la meta (solo para quien puede cambiarla); si no hay, se escribe «de N». */
  metaEditable?: ReactNode;
  onAbrir?: (id: string) => void;
}) {
  return (
    <TarjetaInfo className="min-w-0">
      <div className="flex items-start justify-between gap-2">
        <h3 className="font-serif text-lg">
          {titulo} <span className="font-sans text-sm text-taupe">{subtitulo}</span>
        </h3>
        <InsigniaTramo estado={estado} faltan={faltan} sobran={sobran} />
      </div>
      <div className="mt-2 flex items-center gap-2.5">
        <Medidor n={n} meta={meta} estado={estado} />
        <strong className="tabular-nums">{n}</strong>
        <span className="flex items-center gap-1.5 text-sm text-taupe">
          {metaEditable ?? (meta > 0 ? `de ${meta}` : "sin meta")}
        </span>
      </div>
      <div className="mt-3 flex flex-wrap gap-1.5">
        {gente.length > 0 ? gente.map((p) => <Chip key={p.id} p={p} onAbrir={onAbrir} />) : <span className="text-sm text-taupe">nadie</span>}
      </div>
    </TarjetaInfo>
  );
}

export function TarjetaGrupo({ titulo, nota, gente, onAbrir, vacio }: { titulo: ReactNode; nota?: ReactNode; gente: PersonaDelDia[]; onAbrir?: (id: string) => void; vacio?: string }) {
  if (gente.length === 0 && !vacio) return null;
  return (
    <TarjetaInfo className="min-w-0">
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="font-serif text-lg">{titulo}</h3>
        {nota && <span className="text-xs text-taupe">{nota}</span>}
      </div>
      <div className="flex flex-wrap gap-1.5">
        {gente.length > 0 ? gente.map((p) => <Chip key={p.id} p={p} onAbrir={onAbrir} />) : <span className="text-sm text-taupe">{vacio}</span>}
      </div>
    </TarjetaInfo>
  );
}
