"use client";

// Gráfico de barras de horas por día — marca CAYLA (SVG puro, sin librerías).
// Verde para días normales, rojo para días con incidencia; línea de meta punteada.
//
// EL ALMUERZO (2026-10-20): la barra sigue midiendo HORAS TRABAJADAS y sigue siendo UNA sola pieza —mismo color, misma silueta—.
// El momento en que salió a almorzar se ve como una franja de rayitas claras DENTRO de la barra, a la altura de lo que había
// trabajado hasta entonces; con el cursor encima dice la hora de salida, la de vuelta y cuánto fue. No parte la barra en dos:
// partirla en dos colores se leía como dos días distintos.

export interface DiaGrafico {
  fecha: string; // YYYY-MM-DD
  horas: number;
  problema?: boolean; // tardanza / auto-cierre / sin salida
  /** Cuándo salió a almorzar, si hay marcas. `antesHoras` = horas trabajadas hasta salir. */
  almuerzo?: { antesHoras: number; texto: string; largo: boolean };
}

function diaCorto(fecha: string): string {
  const [, m, d] = fecha.split("-");
  return `${Number(d)}/${Number(m)}`;
}

export function GraficoHoras({ dias, meta = 7.5 }: { dias: DiaGrafico[]; meta?: number }) {
  if (dias.length === 0) {
    return <p className="text-sm text-taupe">Sin datos en el periodo elegido.</p>;
  }

  // Sin meta (<= 0) no se dibuja la línea. Pasa cuando la persona no tiene
  // horario cargado: una meta inventada sería peor que ninguna, porque se lee
  // como si el sistema supiera cuánto le tocaba.
  const hayMeta = meta > 0;
  const maxDato = Math.max(hayMeta ? meta : 0, ...dias.map((d) => d.horas));
  const maxY = Math.ceil(maxDato / 2) * 2 || 2; // redondea a par superior
  const H = 190; // 240 antes de la 0428 — compactado junto con el resto del perfil
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
        <defs>
          {/* Rayitas claras sobre la barra: se ven sobre verde y sobre rojo sin cambiar el color de la barra. */}
          <pattern id="rayas-almuerzo" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <rect width="3" height="6" fill="var(--color-crema)" opacity={0.7} />
          </pattern>
        </defs>
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
        {hayMeta && (
          <>
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
              meta {Number(meta.toFixed(2))}h
            </text>
          </>
        )}

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
              {d.horas > 0 && d.almuerzo && d.almuerzo.antesHoras > 0 && d.almuerzo.antesHoras < d.horas && (
                <g>
                  <rect x={x} y={y(d.almuerzo.antesHoras) - 3} width={anchoBarra} height={6} fill="url(#rayas-almuerzo)" />
                  {/* El área sensible es más alta que la franja, para poder apuntarle con el cursor. */}
                  <rect x={x} y={y(d.almuerzo.antesHoras) - 7} width={anchoBarra} height={14} fill="transparent">
                    <title>{d.almuerzo.texto}</title>
                  </rect>
                </g>
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
