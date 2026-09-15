"use client";

// «Requiere atención» — lo que hay que resolver o mirar antes de pagar.
//
// Decisión del 2026-09-15: solo reglas que YA existen. Los dos frenos de la
// base (días sin confirmar, liquidación sin descontar), los datos que ya viajan
// en cada fila (sin salario, sin horario, sin régimen, 4ta, cese), y lo que ya
// se sabe de los periodos. Los chequeos que hoy solo están en los scripts SQL
// de cierre (feriados faltantes, ausencias sin firma de DO…) NO entran: traerlos
// exige una función nueva en la base, y un panel que promete revisarlo todo sin
// hacerlo es peor que uno que dice exactamente lo que mira.
//
// Cubre TODO el periodo, no la pestaña: el sentido del panel es que nada se
// quede fuera de la vista. Cada persona dice su grupo cuando no es la pestaña
// en la que se está.

import { useState, type ReactNode } from "react";
import Link from "next/link";
import { TIPO_VINCULO_LABEL, type TipoVinculo } from "@cayla-dynamic/shared";
import { Insignia } from "@/components/ui/insignia";
import type { CodigoHallazgo, HallazgoAgrupado, Severidad } from "@/lib/admin/planilla/revision";

const TITULO: Record<CodigoHallazgo, string> = {
  dias_sin_confirmar: "Días con la salida puesta por el sistema, sin confirmar",
  liquidacion_sin_descuento: "Ya cobraron su liquidación y falta descontarla",
  sin_salario: "Horas sin salario asignado",
  feriado_sin_salario: "Feriados sin salario ese día",
  sin_horario: "Sin horario asignado",
  no_marco: "No marcaron ningún día",
  sin_regimen_pension: "Sin régimen de pensión",
  retencion_4ta_sin_configurar: "Retención de 4ta sin configurar",
  desglose_no_cuadra: "Desglose que no suma el total",
  ceso_en_periodo: "Cesaron o están inactivas",
};

const SEVERIDAD: Record<Severidad, { etiqueta: string; variante: "alerta" | "advertencia" | "neutral" }> = {
  bloquea: { etiqueta: "Frena el pago", variante: "alerta" },
  revisar: { etiqueta: "Revisar", variante: "advertencia" },
  informa: { etiqueta: "Para saber", variante: "neutral" },
};

function Item({ h, grupoActivo, onAbrirPersona }: {
  h: HallazgoAgrupado;
  grupoActivo: TipoVinculo;
  onAbrirPersona: (personaId: string, grupo: TipoVinculo) => void;
}) {
  const [abierto, setAbierto] = useState(h.severidad === "bloquea");
  const s = SEVERIDAD[h.severidad];
  return (
    <li className="border-t border-sand py-2.5 first:border-t-0">
      <button
        type="button"
        onClick={() => setAbierto((v) => !v)}
        aria-expanded={abierto}
        className="flex w-full flex-wrap items-center gap-x-3 gap-y-1 text-left text-sm"
      >
        <Insignia variante={s.variante} tamano="sm">{s.etiqueta}</Insignia>
        <span className="font-medium text-tinta">{TITULO[h.codigo]}</span>
        <span className="text-taupe">
          · {h.personas.length} {h.personas.length === 1 ? "persona" : "personas"} {abierto ? "▾" : "▸"}
        </span>
      </button>
      {abierto && (
        <ul className="mt-2 space-y-1 pl-1 text-sm">
          {h.personas.map((p) => (
            // Llave por persona+grupo: quien cambió de tipo_vinculo a mitad de
            // periodo puede aparecer aquí dos veces (una fila por grupo), y
            // `persona_id` a secas chocaría — silenciando la segunda fila.
            <li key={`${p.persona_id}:${p.grupo}`} className="flex flex-wrap items-baseline gap-x-2">
              <button
                type="button"
                onClick={() => onAbrirPersona(p.persona_id, p.grupo)}
                className="font-medium text-tinta underline decoration-taupe/30 underline-offset-2 hover:decoration-tinta"
              >
                {p.nombre}
              </button>
              {p.grupo !== grupoActivo && <span className="text-xs text-taupe">({TIPO_VINCULO_LABEL[p.grupo]})</span>}
              <span className="text-taupe">{p.texto}</span>
            </li>
          ))}
          {h.resolverEn && (
            <li>
              <Link href={h.resolverEn.href} className="text-xs text-taupe underline underline-offset-2 hover:text-tinta">
                Se resuelve en {h.resolverEn.etiqueta} →
              </Link>
            </li>
          )}
        </ul>
      )}
    </li>
  );
}

export function RequiereAtencion({ hallazgos, grupoActivo, onAbrirPersona, extra }: {
  hallazgos: HallazgoAgrupado[];
  grupoActivo: TipoVinculo;
  onAbrirPersona: (personaId: string, grupo: TipoVinculo) => void;
  /** Avisos del periodo que no son de una persona (grati/CTS pendiente…). */
  extra?: ReactNode;
}) {
  const frenan = hallazgos.filter((h) => h.severidad === "bloquea").length;
  const revisar = hallazgos.filter((h) => h.severidad === "revisar").length;

  if (hallazgos.length === 0 && !extra) {
    return (
      <div className="rounded-superficie border border-verde/30 bg-verde/[0.06] px-5 py-3 text-sm text-verde">
        Nada frena el pago ni pide revisión en los datos de este periodo.
      </div>
    );
  }

  return (
    <section
      aria-labelledby="requiere-atencion"
      className={`rounded-superficie border bg-papel p-5 ${frenan > 0 ? "border-rojo/30" : "border-ambar/40"}`}
    >
      <div className="mb-2 flex flex-wrap items-baseline justify-between gap-2">
        <h2 id="requiere-atencion" className="font-serif text-lg">Requiere atención</h2>
        <p className="text-xs text-taupe">
          {[
            frenan > 0 && `${frenan} ${frenan === 1 ? "tema frena" : "temas frenan"} el pago`,
            revisar > 0 && `${revisar} ${revisar === 1 ? "tema" : "temas"} por revisar`,
          ]
            .filter(Boolean).join(" · ") || "Solo avisos"}
        </p>
      </div>
      {extra}
      {hallazgos.length > 0 && (
        <ul>
          {hallazgos.map((h) => (
            <Item key={h.codigo} h={h} grupoActivo={grupoActivo} onAbrirPersona={onAbrirPersona} />
          ))}
        </ul>
      )}
      <p className="mt-2 text-xs text-taupe">
        Mira los datos del periodo que ya trae el sistema. Los chequeos de cierre que viven en SQL (feriados faltantes,
        ausencias sin firma de DO) todavía no están aquí.
      </p>
    </section>
  );
}
