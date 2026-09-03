"use client";

// Gráfico de barras del historial mensual de objetivos — mismo estilo que
// grafico-horas.tsx (SVG puro, sin librerías, colores por variable CSS para
// que el modo oscuro los redefina solo).
//
// Un mes con total=0 (sin checklist ese mes) NO es un 0% cumplido: es "no hay
// dato", y se dibuja distinto —una marca gris al piso— para no acusar de bajo
// desempeño a un mes que simplemente no tuvo objetivos cargados.

import { MESES_CORTO, nivelColorObjetivos, type MesHistorial } from "@/lib/objetivos";

const COLOR_VAR: Record<"verde" | "ambar" | "rojo", string> = {
  verde: "var(--color-verde)",
  ambar: "var(--color-ambar)",
  rojo: "var(--color-rojo)",
};

function etiquetaMes(m: MesHistorial): string {
  return `${MESES_CORTO[m.mes - 1]} ${String(m.anio).slice(2)}`;
}

export function GraficoObjetivos({ historial }: { historial: MesHistorial[] }) {
  if (historial.length === 0) {
    return <p className="text-sm text-taupe">Sin historial para mostrar.</p>;
  }

  const H = 180;
  const PAD_TOP = 10;
  const PAD_BOTTOM = 30;
  const PAD_LEFT = 30;
  const anchoBarra = 20;
  const gap = 8;
  const W = PAD_LEFT + historial.length * (anchoBarra + gap) + 8;
  const alto = H - PAD_TOP - PAD_BOTTOM;
  const y = (pct: number) => PAD_TOP + alto - (pct / 100) * alto;

  const ticks = [0, 25, 50, 75, 100];

  return (
    <div className="overflow-x-auto">
      <svg width={W} height={H} className="min-w-full" role="img" aria-label="Historial mensual de objetivos cumplidos">
        {ticks.map((t) => (
          <g key={t}>
            <line x1={PAD_LEFT} x2={W - 4} y1={y(t)} y2={y(t)} stroke="var(--color-sand)" strokeWidth={1} />
            <text x={PAD_LEFT - 6} y={y(t) + 3} textAnchor="end" fontSize={9} fill="var(--color-taupe)">
              {t}%
            </text>
          </g>
        ))}

        {historial.map((m, i) => {
          const x = PAD_LEFT + i * (anchoBarra + gap);
          const sinDato = m.total <= 0;
          const pct = sinDato ? 0 : (m.cumplidos / m.total) * 100;
          const nivel = nivelColorObjetivos(m.cumplidos, m.total);
          const titulo = sinDato
            ? `${etiquetaMes(m)}: sin checklist ese mes`
            : `${etiquetaMes(m)}: ${m.cumplidos} de ${m.total} (${Math.round(pct)}%)`;
          return (
            <g key={`${m.anio}-${m.mes}`}>
              <title>{titulo}</title>
              {sinDato ? (
                <rect
                  x={x}
                  y={PAD_TOP + alto - 3}
                  width={anchoBarra}
                  height={3}
                  rx={1.5}
                  fill="var(--color-taupe)"
                  opacity={0.4}
                />
              ) : (
                <rect
                  x={x}
                  // Mínimo 3px: un 0% CON checklist (de verdad cumplió cero)
                  // sigue siendo un dato, y una barra de alto 0 se vería
                  // idéntica al hueco gris de "sin checklist" de arriba.
                  y={Math.min(y(pct), PAD_TOP + alto - 3)}
                  width={anchoBarra}
                  height={Math.max(3, PAD_TOP + alto - y(pct))}
                  rx={3}
                  fill={COLOR_VAR[nivel]}
                />
              )}
              <text
                x={x + anchoBarra / 2}
                y={H - PAD_BOTTOM + 14}
                textAnchor="middle"
                fontSize={9}
                fill="var(--color-taupe)"
              >
                {etiquetaMes(m)}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
