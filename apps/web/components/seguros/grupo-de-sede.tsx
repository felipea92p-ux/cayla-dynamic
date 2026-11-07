"use client";

// Una SEDE en la pantalla de Seguros: un encabezado que se abre y se cierra, con lo que importa de ella a la vista aunque
// esté cerrada — cuántas personas son y cuántas piden algo. Adentro van las fichas de cada persona (también plegables).
//
// No decide nada: la situación de cada persona ya viene resuelta (`seguroPorPersona`); aquí solo se cuenta.

import { ChevronDown, ChevronRight } from "lucide-react";
import type { ReactNode } from "react";
import { Insignia } from "@/components/ui/insignia";
import { faltanPorRegistrar, pideAlgo, plural, type SeguroDePersona } from "@/lib/admin/seguros";

export function GrupoDeSede({
  sede, personas, abierto, onAlternar, children,
}: {
  sede: string;
  /** TODA la sede, aunque un filtro esconda a alguien: «Todo al día» nunca se dice de una parte. */
  personas: SeguroDePersona[];
  abierto: boolean;
  onAlternar: () => void;
  children: ReactNode;
}) {
  const sinPoliza = personas.filter((p) => p.situacion === "hueco").length;
  const suspendidas = personas.filter((p) => p.situacion === "suspendida").length;
  const piden = personas.filter(pideAlgo).length;
  const sinRegistrar = faltanPorRegistrar(personas);
  const Chevron = abierto ? ChevronDown : ChevronRight;
  return (
    <section className="rounded-superficie border border-sand bg-crema/40">
      <button
        type="button"
        aria-expanded={abierto}
        onClick={onAlternar}
        className="flex w-full items-center justify-between gap-3 px-4 py-3 text-left"
      >
        <span className="flex min-w-0 items-center gap-2">
          <Chevron size={16} strokeWidth={1.8} className="shrink-0 text-taupe" aria-hidden />
          <span className="font-serif text-lg text-tinta">{sede}</span>
          <span className="text-sm text-taupe">· {plural(personas.length, "persona", "personas")}</span>
        </span>
        <span className="flex shrink-0 flex-wrap items-center justify-end gap-1.5">
          {sinPoliza > 0 && <Insignia variante="alerta" tamano="sm">{plural(sinPoliza, "sin póliza", "sin póliza")}</Insignia>}
          {suspendidas > 0 && <Insignia variante="alerta" tamano="sm">{plural(suspendidas, "suspendida", "suspendidas")}</Insignia>}
          {piden > sinPoliza + suspendidas && <Insignia variante="advertencia" tamano="sm">{plural(piden - sinPoliza - suspendidas, "pide algo", "piden algo")}</Insignia>}
          {sinRegistrar.map((f) => <Insignia key={f.nombre} variante="neutral" tamano="sm">{f.n} sin {f.nombre}</Insignia>)}
          {piden === 0 && sinRegistrar.length === 0 && <Insignia variante="positivo" tamano="sm">Todo al día</Insignia>}
        </span>
      </button>
      {abierto && <div className="space-y-2 border-t border-sand p-3">{children}</div>}
    </section>
  );
}
