"use client";

// Gráfico de barras de horas por día — marca CAYLA (SVG puro, sin librerías).
// Verde para días normales, rojo para días con incidencia; línea de meta punteada.

export interface DiaGrafico {
  fecha: string; // YYYY-MM-DD
  horas: number;
  problema?: boolean; // tardanza / auto-cierre / sin salida
}

function diaCorto(fecha: string): string {
  const [, m, d] = fecha.split("-");
  return `${Number(d)}/${Number(m)}`;
}

export function GraficoHoras({ dias, meta = 7.5 }: { dias: DiaGrafico[]; meta?: number }) {
  if (dias.length === 0) {
    return <p className="text-sm text-taupe">Sin datos en el periodo elegido.</p>;
  }

  const maxDato = Math.max(meta, ...dias.map((d) => d.horas));
  const maxY = Math.ceil(maxDato / 2) * 2 || 2; // redondea a par superior
  const H = 240;
  const PAD_TOP = 12;
  const PAD_BOTTOM = 46;
  const PAD_LEFT = 34;
  const anchoBarra = 26;
  const gap = 10;
  const W = PAD_LEFT + dias.length * (anchoBarra + gap) + 8;
  const alto = H - PAD_TOP - PAD_BOTTOM;
  const y = (h: number) => PAD_TOP + alto - (h / maxY) * alto;

  const ticks = Array.from({ length: maxY / 2 + 1 }, (_, i) => i * 2); // 0,2,4,…

  return (
    <div className="overflow-x-auto">
      <svg width={W} height={H} className="min-w-full" role="img" aria-label="Horas por día">
        {/* líneas guía + eje Y */}
        {ticks.map((t) => (
          <g key={t}>
            <line x1={PAD_LEFT} x2={W - 4} y1={y(t)} y2={y(t)} stroke="var(--color-sand)" strokeWidth={1} />
            <text x={PAD_LEFT - 6} y={y(t) + 3} textAnchor="end" fontSize={9} fill="var(--color-taupe)">
              {t}h
            </text>
          </g>
        ))}

        {/* línea de meta */}
        <line
          x1={PAD_LEFT}
          x2={W - 4}
          y1={y(meta)}
          y2={y(meta)}
          stroke="var(--color-rojo)"
          strokeWidth={1.5}
          strokeDasharray="4 3"
        />
        <text x={W - 6} y={y(meta) - 4} textAnchor="end" fontSize={9} fill="var(--color-rojo)">
          meta {meta}h
        </text>

        {/* barras */}
        {dias.map((d, i) => {
          const x = PAD_LEFT + i * (anchoBarra + gap);
          const altoBarra = Math.max(0, PAD_TOP + alto - y(d.horas));
          const color = d.problema ? "var(--color-rojo)" : "var(--color-verde)";
          return (
            <g key={d.fecha}>
              {d.horas > 0 && (
                <rect x={x} y={y(d.horas)} width={anchoBarra} height={altoBarra} rx={3} fill={color} />
              )}
              <text
                x={x + anchoBarra / 2}
                y={H - PAD_BOTTOM + 14}
                textAnchor="end"
                fontSize={9}
                fill="var(--color-taupe)"
                transform={`rotate(-45 ${x + anchoBarra / 2} ${H - PAD_BOTTOM + 14})`}
              >
                {diaCorto(d.fecha)}
              </text>
            </g>
          );
        })}
      </svg>
    </div>
  );
}
