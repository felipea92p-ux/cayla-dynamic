// Los cinco dibujos de las tendencias del Dashboard (SVG y HTML propios, sin librería: igual que
// `grafico-horas` y `grafico-objetivos`). Cada uno recibe datos YA preparados por `lib/admin/tendencias.ts`
// —las reglas de privacidad viven allá— y solo dibuja.
//
// Reglas de dibujo (skill dataviz + ADR 0004):
//   · UNA tinta por gráfico. Los 13 colores de la marca no pasan el validador de paleta categórica (verde y
//     ámbar se confunden bajo daltonismo), así que ningún dato se distingue SOLO por color: el significado va
//     en una palabra («antes», «después», «parcial») y el color apoya.
//   · Nada se dibuja como cero si no se midió: «sin dato» es una celda vacía con su guion, no una barra baja.
//   · Responsive por viewBox: sin scroll horizontal de página en el celular.

import type { BarrasCasos, CeldaCalor, ColumnaCosto, LlegadaSede, PuntoSemana } from "@/lib/admin/tendencias";
import { soles } from "@/lib/admin/educacion-formato";
import { cx } from "@/components/ui/cx";

// ── Casos: barras horizontales ───────────────────────────────────────────────
export function BarrasCasos({ datos }: { datos: BarrasCasos }) {
  const max = Math.max(...datos.barras.map((b) => b.total), 1);
  return (
    <ul className="grid gap-2" aria-label="Reportes por sobre qué trata">
      {datos.barras.map((b) => (
        <li key={b.clave} className="grid grid-cols-[minmax(0,9rem)_1fr_auto] items-center gap-3 text-sm sm:grid-cols-[12rem_1fr_auto]">
          <span className="truncate text-tinta" title={b.etiqueta}>{b.etiqueta}</span>
          <span className="h-3 rounded-control bg-sand/60">
            <span className="block h-3 rounded-control bg-taupe" style={{ width: `${(b.total / max) * 100}%` }} />
          </span>
          <span className="w-6 text-right font-serif text-base tabular-nums text-tinta">{b.total}</span>
        </li>
      ))}
    </ul>
  );
}

// ── Costo de planilla: columnas ─────────────────────────────────────────────
export function ColumnasCosto({ columnas }: { columnas: ColumnaCosto[] }) {
  const W = 640, H = 210, PL = 8, PR = 8, PT = 26, PB = 34;
  const max = Math.max(...columnas.map((c) => c.costo ?? 0), 1);
  const ancho = (W - PL - PR) / Math.max(columnas.length, 1);
  const barra = Math.min(ancho * 0.6, 56);
  const alto = H - PT - PB;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label="Costo de planilla por periodo">
      <defs>
        <pattern id="rayado-en-curso" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
          <line x1="0" y1="0" x2="0" y2="6" stroke="var(--color-taupe)" strokeWidth="2" />
        </pattern>
      </defs>
      <line x1={PL} x2={W - PR} y1={PT + alto} y2={PT + alto} stroke="var(--color-sand)" />
      {columnas.map((c, i) => {
        const cx0 = PL + ancho * i + ancho / 2;
        const h = c.costo !== null ? (c.costo / max) * alto : alto * 0.55;
        const y = PT + alto - h;
        return (
          <g key={c.clave}>
            <rect
              x={cx0 - barra / 2} y={y} width={barra} height={h} rx={3}
              fill={c.enCurso ? "url(#rayado-en-curso)" : "var(--color-taupe)"}
              stroke={c.enCurso ? "var(--color-taupe)" : "none"} strokeDasharray={c.enCurso ? "3 3" : undefined}
              opacity={c.enCurso ? 0.7 : 1}
            />
            <text x={cx0} y={y - 6} textAnchor="middle" fontSize={11} className="tabular-nums" fill="var(--color-tinta)">
              {c.costo !== null ? soles(Math.round(c.costo)).replace(/\.00$/, "") : "en curso"}
            </text>
            <text x={cx0} y={H - 16} textAnchor="middle" fontSize={11} fill="var(--color-taupe)">{c.etiqueta}</text>
            {(c.retroactivo || c.repagado) && (
              <text x={cx0} y={H - 3} textAnchor="middle" fontSize={9.5} fill="var(--color-taupe)">
                {c.retroactivo ? "retroactivo" : "repagado"}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

// ── Asistencia sobre lo esperado: línea ─────────────────────────────────────
export function LineaAsistencia({ puntos }: { puntos: PuntoSemana[] }) {
  const W = 640, H = 200, PL = 36, PR = 12, PT = 18, PB = 30;
  const conDato = puntos.filter((p) => p.pct !== null) as (PuntoSemana & { pct: number })[];
  if (conDato.length === 0) return null;
  const minV = Math.min(...conDato.map((p) => p.pct));
  // El eje NO empieza en 0 (una línea entre 92 y 98 % en un eje de 0 a 100 sería una raya plana) y por eso
  // se dice en voz alta: ver `piso`, que la pantalla escribe debajo del gráfico.
  const piso = Math.max(0, Math.floor((minV - 4) / 5) * 5);
  const alto = H - PT - PB;
  const x = (i: number) => PL + (puntos.length === 1 ? (W - PL - PR) / 2 : ((W - PL - PR) * i) / (puntos.length - 1));
  const y = (v: number) => PT + alto - ((v - piso) / (100 - piso)) * alto;
  const completos = puntos.map((p, i) => ({ p, i })).filter(({ p }) => p.pct !== null && !p.parcial);
  const trazo = completos.map(({ p, i }, k) => `${k === 0 ? "M" : "L"}${x(i)},${y(p.pct as number)}`).join(" ");
  const ticks = [piso, Math.round((piso + 100) / 2), 100];
  const cada = Math.max(1, Math.ceil(puntos.length / 8));
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label="Asistencia sobre lo esperado, por semana">
      {ticks.map((t) => (
        <g key={t}>
          <line x1={PL} x2={W - PR} y1={y(t)} y2={y(t)} stroke="var(--color-sand)" />
          <text x={PL - 6} y={y(t) + 3} textAnchor="end" fontSize={10} fill="var(--color-taupe)">{t}%</text>
        </g>
      ))}
      <path d={trazo} fill="none" stroke="var(--color-tinta)" strokeWidth={2} strokeLinejoin="round" />
      {puntos.map((p, i) => p.pct === null ? null : (
        <g key={p.semana}>
          <circle cx={x(i)} cy={y(p.pct)} r={p.parcial ? 4.5 : 3.5}
            fill={p.parcial ? "var(--color-papel)" : "var(--color-tinta)"} stroke="var(--color-tinta)" strokeWidth={p.parcial ? 1.8 : 0} />
          {(i === puntos.length - 1 || i === 0) && (
            <text x={x(i)} y={y(p.pct) - 9} textAnchor={i === 0 ? "start" : "end"} fontSize={11} fill="var(--color-tinta)" className="tabular-nums">
              {p.pct}%{p.parcial ? " (parcial)" : ""}
            </text>
          )}
        </g>
      ))}
      {puntos.map((p, i) => (i % cada === 0 ? (
        <text key={`e${p.semana}`} x={x(i)} y={H - 10} textAnchor="middle" fontSize={10} fill="var(--color-taupe)">
          {Number(p.semana.slice(8))}/{Number(p.semana.slice(5, 7))}
        </text>
      ) : null))}
    </svg>
  );
}
export function pisoDeLinea(puntos: PuntoSemana[]): number | null {
  const v = puntos.filter((p) => p.pct !== null).map((p) => p.pct as number);
  if (v.length === 0) return null;
  return Math.max(0, Math.floor((Math.min(...v) - 4) / 5) * 5);
}

// ── Hora de llegada frente al horario, por sede ─────────────────────────────
export function LlegadaPorSede({ sedes, nombreDe }: { sedes: LlegadaSede[]; nombreDe: (codigo: string) => string }) {
  const LIM = 20; // minutos a cada lado
  const pos = (m: number) => ((Math.max(-LIM, Math.min(LIM, m)) + LIM) / (2 * LIM)) * 100;
  const dicho = (m: number) => {
    const r = Math.round(Math.abs(m));
    return r === 0 ? "a la hora" : `${r} min ${m < 0 ? "antes" : "después"}`;
  };
  return (
    <div className="grid gap-3">
      {sedes.map((s) => (
        <div key={s.sede} className="grid grid-cols-[6.5rem_1fr_7.5rem] items-center gap-3 text-sm sm:grid-cols-[12rem_1fr_9rem]">
          <span className="truncate text-tinta" title={nombreDe(s.sede)}>{nombreDe(s.sede)}</span>
          {s.mediana === null || s.p25 === null || s.p75 === null ? (
            <>
              <span className="text-xs text-taupe">Pocas llegadas medidas ({s.n})</span>
              <span />
            </>
          ) : (
            <>
              <span className="relative h-5" aria-hidden>
                <span className="absolute inset-x-0 top-1/2 h-px bg-sand" />
                <span className="absolute inset-y-0 w-px bg-taupe" style={{ left: "50%" }} />
                <span className="absolute top-1/2 h-2.5 -translate-y-1/2 rounded-control bg-taupe/30" style={{ left: `${pos(s.p25)}%`, width: `${Math.max(pos(s.p75) - pos(s.p25), 1.5)}%` }} />
                <span className="absolute top-1/2 size-3 -translate-x-1/2 -translate-y-1/2 rounded-full bg-tinta" style={{ left: `${pos(s.mediana)}%` }} />
              </span>
              <span className="text-xs text-taupe"><strong className="font-medium text-tinta">{dicho(s.mediana)}</strong> · {s.n} llegadas</span>
            </>
          )}
        </div>
      ))}
      <div className="grid grid-cols-[6.5rem_1fr_7.5rem] gap-3 text-[11px] text-taupe sm:grid-cols-[12rem_1fr_9rem]" aria-hidden>
        <span />
        <span className="flex justify-between"><span>{LIM} min antes</span><span>a la hora</span><span>{LIM} min después</span></span>
        <span />
      </div>
    </div>
  );
}

// ── Cuándo se llega tarde: sede × día de la semana ──────────────────────────
const DIAS_CAL = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"];
export function CalorTardanza({ filas, nombreDe }: { filas: { sede: string; celdas: CeldaCalor[] }[]; nombreDe: (codigo: string) => string }) {
  const max = Math.max(1, ...filas.flatMap((f) => f.celdas.map((c) => c.pctTarde ?? 0)));
  return (
    <div className="overflow-hidden rounded-superficie border border-sand">
      <table className="w-full table-fixed text-center text-sm">
        <thead>
          <tr className="bg-sand/50 text-xs text-taupe">
            <th className="w-[22%] px-2 py-1.5 text-left font-normal">Sede</th>
            {DIAS_CAL.map((d) => <th key={d} className="px-1 py-1.5 font-normal">{d}</th>)}
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => (
            <tr key={f.sede} className="border-t border-sand">
              <th className="truncate px-2 py-1.5 text-left font-normal text-tinta" title={nombreDe(f.sede)}>{nombreDe(f.sede)}</th>
              {f.celdas.map((c) => (
                <td key={c.dia} className="p-0.5">
                  <span
                    className={cx("flex h-8 items-center justify-center rounded-control tabular-nums", c.pctTarde !== null ? "text-tinta" : "text-taupe")}
                    style={c.pctTarde !== null ? { backgroundColor: `color-mix(in srgb, var(--color-taupe) ${Math.round(10 + (c.pctTarde / max) * 55)}%, transparent)` } : undefined}
                    title={c.sinTrabajo ? "Nadie de la sede llegó este día en el periodo" : c.pctTarde === null ? `Solo ${c.llegadas} llegadas: pocas para decir algo` : `${c.pctTarde}% llegó ${5} min o más después`}
                  >
                    {c.sinTrabajo ? "–" : c.pctTarde === null ? "·" : `${c.pctTarde}%`}
                  </span>
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
