"use client";

// ============================================================================
// TablaSemana — Turnos · Semana: una fila por persona y una columna por día (2026-11-07)
// ============================================================================
// El dibujo de la maqueta que Felipe eligió para las líderes de equipo
// (docs/turnos-semana-prototipo-2026-11-07.html, opción 2): la semana de cada
// persona en una fila, como un rol de turnos, y arriba cómo le fue a cada día.
// Tocar el encabezado de un día lo abre debajo (lo que antes era la vista Día);
// tocar una casilla abre el editor de turno de siempre.
//
// Solo dibuja. Qué le toca a cada persona cada día lo resuelve jornada-esperada.ts,
// las horas y la jornada borrador-semana.ts, y el estado de cada día
// semana-por-persona.ts con la misma cuenta de la Integrada.
// ============================================================================

import { ChevronDown } from "lucide-react";
import { Fila, Tabla, TablaEncabezado } from "@/components/ui/tabla";
import { Insignia } from "@/components/ui/insignia";
import { cx } from "@/components/ui/cx";
import { textoCumple, type Cumple } from "@/lib/admin/borrador-semana";
import type { ResumenSemanalDelDia, TonoDeHora } from "@/lib/admin/semana-por-persona";

export type CasillaSemana =
  | { tipo: "turno"; entrada: string; salida: string | null; almacen: string | null }
  | { tipo: "descanso" }
  | { tipo: "sin_turno" };

export interface FilaSemana {
  id: string;
  nombre: string;
  lider: boolean;
  /** Por qué no suma a la meta («preselección», el área). Si viene, la fila va al grupo de abajo. */
  aparte?: string;
  /** Una por día, en el orden de `dias`. */
  casillas: CasillaSemana[];
  horas: Cumple;
}

export interface DiaDeLaTabla {
  iso: string;
  abr: string;
  num: string;
  hoy: boolean;
}

const coma = (n: number) => (Math.round(n * 10) / 10).toLocaleString("es-PE");
const fmtH = (h: number) => {
  const H = Math.floor(h + 1e-9);
  return `${String(H).padStart(2, "0")}:${String(Math.round((h - H) * 60)).padStart(2, "0")}`;
};

// La tira de cada día: un trazo por hora con el color de su estado. El estado también va en palabras debajo:
// el color nunca va solo.
const TIRA: Record<TonoDeHora, string> = {
  falta: "bg-rojo",
  ok: "bg-verde/60",
  sobra: "bg-ambar/55",
  sin_meta: "bg-sand",
  fuera: "border border-dashed border-sand",
};

function EstadoDelDia({ dia }: { dia: ResumenSemanalDelDia }) {
  const e = dia.estado;
  return (
    <div className="flex flex-col items-start gap-1">
      {e.tipo === "falta" && (
        <span className="flex flex-wrap items-center gap-x-1.5">
          <Insignia variante="alerta" tamano="sm">Falta {e.peor.faltan}</Insignia>
          <span className="text-[11px] tabular-nums text-taupe">{fmtH(e.peor.desde)}–{fmtH(e.peor.hasta)}</span>
        </span>
      )}
      {e.tipo === "falta" && e.otrosTramos > 0 && (
        <span className="text-[11px] text-taupe">y {e.otrosTramos} tramo{e.otrosTramos > 1 ? "s" : ""} más con falta</span>
      )}
      {e.tipo === "alcanza" && <Insignia variante="positivo" tamano="sm">Alcanza</Insignia>}
      {e.tipo === "sin_meta" && <Insignia tamano="sm">Sin meta</Insignia>}
      {e.tipo === "sin_gente" && <span className="text-[11px] text-taupe">Nadie trabaja</span>}
      {dia.sinLider.map((t) => (
        <span key={t.desde} className="flex flex-wrap items-center gap-x-1.5">
          <Insignia variante="alerta" tamano="sm">Sin líder</Insignia>
          <span className="text-[11px] tabular-nums text-taupe">{fmtH(t.desde)}–{fmtH(t.hasta)}</span>
        </span>
      ))}
    </div>
  );
}

function Horas({ c }: { c: Cumple }) {
  const detalle = c.pasa48 ? "pasa de 48 h"
    : c.estado === "cumple" ? "su jornada"
      : c.estado === "faltan" ? `faltan ${coma(-(c.diferencia ?? 0))} h`
        : c.estado === "sobra" ? `se pasa ${coma(c.diferencia ?? 0)} h`
          : "sin jornada";
  const tono = c.pasa48 ? "text-rojo-profundo" : c.estado === "cumple" ? "text-verde" : c.estado === "sin_jornada" ? "text-taupe" : "text-ambar";
  return (
    <span className="block text-right tabular-nums" title={textoCumple(c)}>
      <span className="font-medium">{coma(c.horas)} h</span>
      <span className={cx("block whitespace-nowrap text-[11px]", tono)}>{detalle}</span>
    </span>
  );
}

export function TablaSemana({
  dias,
  filas,
  resumen,
  abierto,
  alTocarDia,
  alTocarCasilla,
}: {
  dias: DiaDeLaTabla[];
  filas: FilaSemana[];
  /** Cómo le fue a cada día, en el orden de `dias`. */
  resumen: ResumenSemanalDelDia[];
  /** El día abierto debajo de la tabla, o null. */
  abierto: string | null;
  alTocarDia: (iso: string) => void;
  /** Sin esto (quien solo mira) las casillas no se tocan. */
  alTocarCasilla?: (personaId: string, iso: string) => void;
}) {
  const grupos: { titulo: string; nota?: string; filas: FilaSemana[] }[] = [
    { titulo: "Líderes de equipo", nota: "meta: 1 en piso todo el día", filas: filas.filter((f) => f.lider) },
    { titulo: "Equipo de piso", filas: filas.filter((f) => !f.lider && !f.aparte) },
    { titulo: "No suman a la meta", nota: "preselección u otra área", filas: filas.filter((f) => !f.lider && f.aparte) },
  ].filter((g) => g.filas.length > 0);

  // La columna del día abierto lleva un marco, y la de hoy un fondo apenas distinto.
  const col = (d: DiaDeLaTabla) => cx(
    d.hoy && "bg-pizarra/[0.06]",
    d.iso === abierto && "shadow-[inset_2px_0_0_var(--color-tinta),inset_-2px_0_0_var(--color-tinta)]",
  );
  const primera = "sticky left-0 z-[1] bg-papel";

  return (
    <Tabla className="text-sm">
      <TablaEncabezado>
        <th className={cx(primera, "w-28 min-w-[6.5rem] max-w-[7.5rem] px-3 py-2 text-left text-xs font-medium uppercase tracking-wide sm:w-44 sm:max-w-[11rem]")}>Persona</th>
        {dias.map((d) => (
          <th key={d.iso} className={cx("px-1 py-1.5 text-left font-normal", col(d))}>
            <button
              type="button"
              onClick={() => alTocarDia(d.iso)}
              aria-expanded={d.iso === abierto}
              aria-controls="turnos-dia-abierto"
              title={d.iso === abierto ? `Cerrar el ${d.abr} ${d.num}` : `Ver cómo va el ${d.abr} ${d.num}`}
              className="inline-flex items-center gap-1 whitespace-nowrap rounded-control px-2 py-1 text-xs font-semibold uppercase tracking-wide text-tinta transition-colors hover:bg-crema aria-expanded:bg-tinta aria-expanded:text-crema"
            >
              {d.abr} <span className="font-normal normal-case tracking-normal opacity-70">{d.num}</span>
              <ChevronDown aria-hidden className="h-3.5 w-3.5 opacity-70" />
            </button>
            {d.hoy && <Insignia tamano="sm" className="ml-1">hoy</Insignia>}
          </th>
        ))}
        <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide">Semana</th>
      </TablaEncabezado>
      <tbody>
        {/* Arriba, cómo le fue a cada día: el resumen antes del detalle. */}
        <tr className="align-top">
          <th scope="row" className={cx(primera, "px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-taupe")}>
            En piso
            <span className="block font-normal normal-case tracking-normal">el peor momento</span>
          </th>
          {dias.map((d, i) => (
            <td key={d.iso} className={cx("px-2 py-2", col(d))}>
              <div aria-hidden className="mb-1.5 flex h-1.5 gap-[2px]">
                {resumen[i].tonos.map((t, k) => <span key={k} className={cx("flex-1 rounded-[2px]", TIRA[t])} />)}
              </div>
              <EstadoDelDia dia={resumen[i]} />
            </td>
          ))}
          <td />
        </tr>
        {grupos.map((g) => [
          <tr key={`g-${g.titulo}`}>
            <th colSpan={dias.length + 2} scope="rowgroup" className="bg-hueso px-3 py-1 text-left text-[11px] font-medium uppercase tracking-wide text-taupe">
              {g.titulo}{g.nota && <span className="font-normal normal-case tracking-normal"> · {g.nota}</span>}
            </th>
          </tr>,
          ...g.filas.map((f) => (
            <Fila key={f.id}>
              {/* Con tope de ancho: sin él, un nombre largo («María de los Ángeles Concepción…») empuja la semana fuera
                  de la pantalla. Se corta con «…» y el nombre completo queda en el title. */}
              <th scope="row" title={f.nombre} className={cx(primera, "max-w-[7.5rem] px-3 py-1.5 text-left font-normal sm:max-w-[11rem]")}>
                <span className="flex min-w-0 items-center gap-1.5">
                  {f.lider && (
                    <span aria-label="Líder de equipo" title="Líder de equipo"
                      className="grid h-4 w-4 shrink-0 place-items-center rounded-full bg-tinta text-[9px] font-bold leading-none text-crema">L</span>
                  )}
                  <span className="truncate">{f.nombre}</span>
                  {f.aparte && <span className="hidden shrink-0 rounded-full border border-dashed border-taupe px-1.5 text-[10px] text-taupe sm:inline">{f.aparte}</span>}
                </span>
              </th>
              {f.casillas.map((c, i) => {
                const d = dias[i];
                const titulo = `${f.nombre}, ${d.abr} ${d.num}`;
                const contenido = c.tipo === "turno" ? (
                  <>
                    <span className="flex flex-col items-center tabular-nums sm:flex-row sm:gap-1">
                      <span>{c.entrada}</span><span aria-hidden className="hidden text-taupe sm:inline">–</span><span>{c.salida ?? "…"}</span>
                    </span>
                    {c.almacen && <span className="mt-0.5 block rounded-full bg-azul/10 px-1.5 text-[10px] font-medium text-azul">alm. {c.almacen}</span>}
                  </>
                ) : c.tipo === "descanso" ? "Descanso" : "—";
                return (
                  <td key={d.iso} className={cx("px-1 py-1 text-center", col(d))}>
                    <button
                      type="button"
                      disabled={!alTocarCasilla}
                      onClick={() => alTocarCasilla?.(f.id, d.iso)}
                      aria-label={`${titulo}: ${c.tipo === "turno" ? `${c.entrada} a ${c.salida ?? "sin salida"}${c.almacen ? `, almacén ${c.almacen}` : ""}` : c.tipo === "descanso" ? "descanso" : "sin turno"}`}
                      title={alTocarCasilla ? `Cambiar el turno: ${titulo}` : undefined}
                      className={cx(
                        "w-full rounded-control border border-transparent px-1 py-1.5 text-[13px] transition-colors enabled:hover:border-taupe enabled:hover:bg-crema disabled:cursor-default",
                        c.tipo === "descanso" && "text-xs text-ceniza [background:repeating-linear-gradient(135deg,transparent_0_6px,color-mix(in_srgb,var(--color-sand)_70%,transparent)_6px_7px)]",
                        c.tipo === "sin_turno" && "text-taupe",
                        c.tipo === "turno" && f.aparte && "border-dashed border-taupe/60 text-taupe",
                      )}
                    >
                      {contenido}
                    </button>
                  </td>
                );
              })}
              <td className="px-3 py-1.5"><Horas c={f.horas} /></td>
            </Fila>
          )),
        ])}
      </tbody>
    </Tabla>
  );
}
