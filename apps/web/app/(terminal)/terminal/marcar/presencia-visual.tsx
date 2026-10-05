"use client";

import { Check, Clock, Footprints, LogOut, Moon, Users, Utensils, type LucideIcon } from "lucide-react";
import { ESTADO_PRESENCIA_LABELS } from "@cayla-dynamic/shared";
import type { ClavePresencia } from "@/lib/terminal/presencia";

// Cómo se VE cada punto del día de una persona en el terminal. La lógica de
// «en qué punto está» no vive acá: sale de los marcajes (`estadoPresencia`, en
// packages/shared) y de `lib/terminal/presencia.ts`. Esto solo le pone cara.
//
// Cada estado tiene su color, su ícono y su palabra, y NINGUNO va solo: el color
// se ve de lejos, el ícono se reconoce de cerca y la palabra (en la leyenda y
// para quien usa lector de pantalla) quita toda duda. Por eso el daltonismo no
// deja a nadie sin saber qué significa una casilla.
//
// Los colores son los de globals.css —verde, ámbar, azul, ceniza—, nunca uno de
// Tailwind por defecto (CLAUDE.md). Las clases van completas y no armadas con
// plantillas: Tailwind solo genera lo que ve escrito literal.

/** Lo que se puede filtrar. «Libre hoy» no: no es un lugar en el que alguien esté. */
export type ClaveFiltro = Exclude<ClavePresencia, "libre">;

export interface EstiloPresencia {
  Icono: LucideIcon;
  /** La casilla: tono de fondo y borde. `--bgt` es el fondo, para recortar el círculo del ícono. */
  tile: string;
  /** El círculo del ícono sobre la foto. */
  punto: string;
  /** El texto de la línea del estado. */
  texto: string;
  /** Ya no hay nada que hacer ahí (terminó, o hoy no trabaja): foto y nombre se apagan. */
  apagada: boolean;
}

export const ESTILO_PRESENCIA: Record<ClavePresencia, EstiloPresencia> = {
  sin_entrada: {
    Icono: Clock,
    // Borde punteado: un lugar todavía vacío. El borde es el de los controles
    // (contraste ≥3:1 sobre crema): esta casilla sigue siendo un botón.
    tile: "border-dashed border-borde-control bg-papel [--bgt:var(--color-papel)]",
    punto: "bg-sand text-taupe",
    texto: "text-taupe",
    apagada: false,
  },
  laborando: {
    Icono: Check,
    tile: "border-verde/55 bg-[var(--bgt)] [--bgt:color-mix(in_srgb,var(--color-verde)_11%,var(--color-papel))]",
    punto: "bg-verde text-crema",
    texto: "text-verde",
    apagada: false,
  },
  refrigerio: {
    Icono: Utensils,
    tile: "border-ambar/55 bg-[var(--bgt)] [--bgt:color-mix(in_srgb,var(--color-ambar)_11%,var(--color-papel))]",
    punto: "bg-ambar text-crema",
    texto: "text-ambar",
    apagada: false,
  },
  pausa: {
    Icono: Footprints,
    tile: "border-azul/55 bg-[var(--bgt)] [--bgt:color-mix(in_srgb,var(--color-azul)_11%,var(--color-papel))]",
    punto: "bg-azul text-crema",
    texto: "text-azul",
    apagada: false,
  },
  termino: {
    Icono: LogOut,
    tile: "border-ceniza/40 bg-[var(--bgt)] [--bgt:color-mix(in_srgb,var(--color-ceniza)_7%,var(--color-papel))]",
    punto: "bg-ceniza text-crema",
    texto: "text-ceniza",
    apagada: true,
  },
  libre: {
    Icono: Moon,
    tile: "border-dashed border-sand bg-transparent [--bgt:var(--color-crema)]",
    punto: "bg-sand text-taupe",
    texto: "text-taupe",
    apagada: true,
  },
};

/** La palabra de cada casilla, para quien usa lector de pantalla («Laborando»…). */
export function etiquetaDePresencia(clave: ClavePresencia): string {
  return clave === "libre" ? "Libre hoy" : ESTADO_PRESENCIA_LABELS[clave];
}

const LEYENDA: Array<{ clave: ClaveFiltro; Icono: LucideIcon; punto: string; activo: string }> = [
  { clave: "laborando", Icono: Check, punto: "bg-verde text-crema", activo: "border-verde bg-verde/15" },
  { clave: "refrigerio", Icono: Utensils, punto: "bg-ambar text-crema", activo: "border-ambar bg-ambar/15" },
  { clave: "pausa", Icono: Footprints, punto: "bg-azul text-crema", activo: "border-azul bg-azul/15" },
  { clave: "termino", Icono: LogOut, punto: "bg-ceniza text-crema", activo: "border-ceniza bg-ceniza/15" },
  { clave: "sin_entrada", Icono: Clock, punto: "bg-sand text-taupe", activo: "border-taupe bg-sand" },
];

/**
 * Alto que suma la línea «Mostrando N de M» al filtrar: 44 px de línea más 16 de
 * separación. Quien tiene la grilla le resta esto a su alto mínimo para que el
 * alto TOTAL de la pantalla no cambie al filtrar —y con él, el reloj no salte—.
 */
export const ALTO_LINEA_FILTRO = 60;

/**
 * La leyenda es a la vez el filtro: cada estado se cuenta y, al tocarlo, la
 * grilla muestra solo a esas personas. Un solo vocabulario —los mismos íconos y
 * colores de cada casilla— para no tener que aprender dos.
 *
 * El filtro oculta, no atenúa, y por eso NO debe quedarse puesto: quien lo deja
 * así les quita a las demás su nombre para marcar. Lo quita solo quien tiene el
 * estado (`page.tsx`): a los pocos segundos, y al tocar cualquier nombre.
 */
export function LeyendaPresencia({
  conteos,
  total,
  filtro,
  onFiltro,
}: {
  conteos: Record<ClaveFiltro, number>;
  total: number;
  filtro: ClaveFiltro | null;
  onFiltro: (f: ClaveFiltro | null) => void;
}) {
  return (
    <div className="flex flex-col items-center gap-4">
      <div className="flex flex-wrap justify-center gap-2" role="group" aria-label="Filtrar por estado">
        <BotonLeyenda
          etiqueta="Todos"
          cuenta={total}
          Icono={Users}
          punto="bg-tinta text-crema"
          activo="border-tinta bg-sand"
          presionado={filtro === null}
          onClick={() => onFiltro(null)}
        />
        {LEYENDA.map((l) => (
          <BotonLeyenda
            key={l.clave}
            etiqueta={ESTADO_PRESENCIA_LABELS[l.clave]}
            cuenta={conteos[l.clave]}
            Icono={l.Icono}
            punto={l.punto}
            activo={l.activo}
            presionado={filtro === l.clave}
            // Tocar el que ya está puesto lo quita, como cualquier filtro.
            onClick={() => onFiltro(filtro === l.clave ? null : l.clave)}
          />
        ))}
      </div>

      {/* Solo existe mientras hay un filtro puesto. Va DEBAJO de la leyenda: la
          leyenda no se mueve al filtrar. */}
      {filtro && (
        <div className="flex min-h-11 items-center gap-3 text-base" role="status">
          <p>
            Mostrando <span className="font-medium">{conteos[filtro]}</span> de {total} ·{" "}
            <span className="font-medium">{ESTADO_PRESENCIA_LABELS[filtro]}</span>
          </p>
          <button
            type="button"
            onClick={() => onFiltro(null)}
            className="cursor-pointer rounded-control border border-borde-control px-4 py-1.5 font-medium transition-colors hover:bg-sand"
          >
            Ver todos
          </button>
        </div>
      )}
    </div>
  );
}

function BotonLeyenda({
  etiqueta,
  cuenta,
  Icono,
  punto,
  activo,
  presionado,
  onClick,
}: {
  etiqueta: string;
  cuenta: number;
  Icono: LucideIcon;
  punto: string;
  activo: string;
  presionado: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-pressed={presionado}
      onClick={onClick}
      className={`flex min-w-28 cursor-pointer flex-col items-center gap-1.5 rounded-superficie border px-3 py-2 transition-colors ${
        presionado ? activo : "border-transparent hover:bg-sand/50"
      }`}
    >
      <span className="flex items-center gap-2">
        <span className={`flex h-9 w-9 items-center justify-center rounded-pildora ${punto}`}>
          <Icono size={19} aria-hidden />
        </span>
        <span className="font-serif text-2xl leading-none">{cuenta}</span>
      </span>
      <span className="text-sm font-medium">{etiqueta}</span>
    </button>
  );
}
