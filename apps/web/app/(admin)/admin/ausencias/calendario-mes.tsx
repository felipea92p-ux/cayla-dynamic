"use client";

// EL CALENDARIO DEL MES (2026-10-19): las ausencias son fechas, así que además de la lista se pueden ver como un renglón
// por persona y una casilla por día. Sirve para lo que la lista esconde: quién falta el jueves, dónde se cruzan dos
// personas del mismo equipo y qué sigue pendiente de aprobar (rayado). Tocar una barra lleva a la lista, ya filtrada a
// esa persona, donde están las acciones (aprobar, adjuntar, anular).
//
// Solo dibuja: qué casilla va pintada sale de `lib/admin/calendario-ausencias.ts`, con su prueba.

import { ChevronLeft, ChevronRight } from "lucide-react";
import { BotonIcono } from "@/components/ui/boton-icono";
import { EstadoVacio } from "@/components/ui/estado-vacio";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { cx } from "@/components/ui/cx";
import {
  diaDeLaSemana, diasDelMes, filasDelMes, type AusenciaDeCalendario,
} from "@/lib/admin/calendario-ausencias";

const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];

/** El color de cada tipo. Los que no tienen el suyo comparten el taupe: la leyenda dice «otros». */
const COLOR: Record<string, { token: string; leyenda: string }> = {
  descanso_medico: { token: "var(--color-pizarra)", leyenda: "descanso médico" },
  vacaciones: { token: "var(--color-verde)", leyenda: "vacaciones" },
  licencia_con_goce: { token: "var(--color-azul)", leyenda: "licencia con goce" },
};
const OTROS = { token: "var(--color-taupe)", leyenda: "permisos y otros" };
const colorDe = (tipo: string) => COLOR[tipo] ?? OTROS;

function estiloCasilla(tipo: string, pendiente: boolean): React.CSSProperties {
  const c = colorDe(tipo).token;
  return pendiente
    ? {
        background: `repeating-linear-gradient(135deg, color-mix(in srgb, ${c} 55%, var(--color-papel)) 0 3px, var(--color-papel) 3px 6px)`,
        outline: `1px dashed ${c}`,
        outlineOffset: "-1px",
      }
    : { background: `color-mix(in srgb, ${c} 55%, var(--color-papel))` };
}

export function CalendarioMes({
  ausencias,
  anio,
  mes,
  hoy,
  onMes,
  onElegir,
}: {
  ausencias: readonly AusenciaDeCalendario[];
  anio: number;
  mes: number;
  /** Hoy, ISO en hora de Lima: se marca su columna. */
  hoy: string;
  onMes: (delta: -1 | 1) => void;
  onElegir: (nombre: string) => void;
}) {
  const n = diasDelMes(anio, mes);
  const filas = filasDelMes(ausencias, anio, mes);
  const hoyDia = hoy.startsWith(`${anio}-${String(mes).padStart(2, "0")}-`) ? Number(hoy.slice(8, 10)) : null;
  const columnas = `9.5rem repeat(${n}, minmax(1.1rem, 1fr))`;
  const tiposVistos = new Set(filas.flatMap((f) => f.casillas.map((c) => c.ausencia?.tipo)).filter((t): t is string => Boolean(t)));
  const hayPendientes = filas.some((f) => f.casillas.some((c) => c.ausencia?.pendiente));

  return (
    <TarjetaInfo className="overflow-hidden">
      <div className="mb-3 flex items-center justify-between gap-2">
        <h2 className="font-serif text-lg capitalize">{MESES[mes - 1]} {anio}</h2>
        <div className="flex items-center gap-1">
          <BotonIcono etiqueta="Mes anterior" icono={<ChevronLeft aria-hidden />} onClick={() => onMes(-1)} />
          <BotonIcono etiqueta="Mes siguiente" icono={<ChevronRight aria-hidden />} onClick={() => onMes(1)} />
        </div>
      </div>

      {filas.length === 0 ? (
        <EstadoVacio>Nadie tiene ausencias en {MESES[mes - 1]} con estos filtros.</EstadoVacio>
      ) : (
        <div className="overflow-x-auto">
          <div className="grid min-w-[44rem] gap-px text-[11px]" style={{ gridTemplateColumns: columnas }} role="table" aria-label={`Ausencias de ${MESES[mes - 1]} ${anio}`}>
            <div role="row" className="contents">
              <div />
              {Array.from({ length: n }, (_, i) => {
                const dia = i + 1;
                const finDeSemana = [0, 6].includes(diaDeLaSemana(anio, mes, dia));
                return (
                  <div
                    key={dia}
                    role="columnheader"
                    className={cx(
                      "py-0.5 text-center tabular-nums",
                      finDeSemana ? "text-rojo-profundo" : "text-taupe",
                      dia === hoyDia && "border-b-2 border-rojo font-bold text-tinta",
                    )}
                  >
                    {dia}
                  </div>
                );
              })}
            </div>
            {filas.map((f) => (
              <div key={f.personaId} role="row" className="contents">
                <div role="rowheader" className="flex items-center truncate py-1 pr-2 text-xs text-tinta">{f.nombre}</div>
                {f.casillas.map((c) =>
                  c.ausencia ? (
                    <button
                      key={c.dia}
                      type="button"
                      role="cell"
                      onClick={() => onElegir(f.nombre)}
                      title={`${c.ausencia.tipoNombre}${c.ausencia.pendiente ? " · pendiente de aprobar" : ""} · ${c.ausencia.inicio.split("-").reverse().join("/")} → ${c.ausencia.fin.split("-").reverse().join("/")}`}
                      aria-label={`${f.nombre}, día ${c.dia}: ${c.ausencia.tipoNombre}${c.ausencia.pendiente ? ", pendiente de aprobar" : ""}`}
                      className="h-6 transition-opacity duration-150 hover:opacity-70"
                      style={estiloCasilla(c.ausencia.tipo, c.ausencia.pendiente)}
                    />
                  ) : (
                    <div key={c.dia} role="cell" className="h-6 bg-sand/40" />
                  ),
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="mt-3 flex flex-wrap items-center gap-1.5 text-xs text-taupe">
        {/* La leyenda lleva el cuadro del color: sin él, el nombre del tipo no dice cuál barra es cuál. */}
        {[...new Map([...tiposVistos].map((t) => [colorDe(t).leyenda, colorDe(t).token])).entries()].map(([leyenda, token]) => (
          <span key={leyenda} className="inline-flex items-center gap-1.5 text-tinta">
            <i aria-hidden className="size-2.5 rounded-[3px]" style={{ background: `color-mix(in srgb, ${token} 55%, var(--color-papel))` }} />
            {leyenda}
          </span>
        ))}
        {hayPendientes && <span>· rayado = pendiente de aprobar</span>}
        <span>· las anuladas no se dibujan (están en la lista) · toca una barra para ver a esa persona en la lista</span>
      </div>
    </TarjetaInfo>
  );
}
