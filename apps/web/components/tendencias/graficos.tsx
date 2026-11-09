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
//   · Con el vidrio, en el teléfono se dibuja a su tamaño (`useAngosto`): encoger un dibujo de 640 a 300 px dejaba la letra en 5 px. Y las columnas son las de Retail
//     (finanzas/GraficoSemanas): en tinta, con el extremo del dato redondeado y ancladas a la línea base.

import { useId, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import {
  etiquetaCierre, MESES_CORTOS, resumenAsistencia, resumenCosto,
  type BarrasCasos, type CeldaCalor, type ColumnaCosto, type DiasPerdidos, type LlegadaSede, type PuntoSemana,
} from "@/lib/admin/tendencias";
import { faltaSeguido, horaMasCorta, type HoraDePiso } from "@/lib/admin/piso-venta";
import { MESES_LARGO } from "@/lib/admin/planilla/formato";
import { soles } from "@/lib/admin/educacion-formato";
import { cx } from "@/components/ui/cx";
import { BannerAviso } from "@/components/ui/banner-aviso";
import { useEsCelular } from "@/lib/use-vidrio-lateral";
import { interruptoresVidrio } from "@/lib/vidrio";

// ── Piezas comunes de los dibujos que se hacen a su medida ──────────────────
// «Días perdidos» y «Gente en piso» (2026-11-09) no se estiran con un viewBox: miden su contenedor y dibujan en
// píxeles. Un viewBox de 640 en una tarjeta de 1 800 px dejaba la letra de 10 px en casi 30.

/** El ancho real del contenedor, que cambia con la ventana. 0 hasta que se monta. */
function useAncho<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [ancho, setAncho] = useState(0);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const medir = () => setAncho(Math.floor(el.clientWidth));
    medir();
    const obs = new ResizeObserver(medir);
    obs.observe(el);
    return () => obs.disconnect();
  }, []);
  return [ref, ancho] as const;
}

/** Una columna con el extremo del dato redondeado y anclada a la línea base (las de Retail). */
function columna(x: number, y: number, w: number, h: number): string {
  const r = Math.min(4, w / 2, h);
  return `M${x},${y + h} V${y + r} q0,-${r} ${r},-${r} h${w - 2 * r} q${r},0 ${r},${r} V${y + h} Z`;
}

/** 6 → «6»; 6.4 → «6.4». */
const numero = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(1));

/** La cifra que encabeza un gráfico y su línea de contexto. */
function Encabeza({ valor, detalle }: { valor: ReactNode; detalle: ReactNode }) {
  return (
    <p className="mb-3 flex flex-wrap items-baseline gap-x-3 gap-y-1">
      {/* receta-propia: es la cifra que encabeza un gráfico dentro de su tarjeta; <Cifra> es una casilla con borde y aquí quedaría una caja dentro de otra */}
      <span className="font-serif text-3xl leading-none text-tinta">{valor}</span>
      <span className="text-sm text-taupe">{detalle}</span>
    </p>
  );
}

const T = { fontSize: 11, fill: "var(--color-taupe)" } as const;
const TT = { fontSize: 11, fill: "var(--color-tinta)", fontWeight: 500 } as const;

// ── La fila compacta del vidrio: Asistencia y Costo, uno al lado del otro ────
// Con 13 semanas que se mueven entre 97 y 100 % y cuatro o cinco periodos pagados, un dibujo a todo el ancho no
// decía más: solo se veía más grande. Cada uno empieza por la cifra que importa y debajo va un dibujo chico.

/** «2026-10-19» → «19/10», para los bordes del eje. */
const diaBarraMes = (iso: string) => `${Number(iso.slice(8))}/${Number(iso.slice(5, 7))}`;

export function AsistenciaCompacta({ puntos }: { puntos: PuntoSemana[] }) {
  const [ref, W] = useAncho<HTMLDivElement>();
  const r = resumenAsistencia(puntos);
  const conDato = puntos.filter((p) => p.pct !== null);
  // El mismo piso que el dibujo grande: el eje no empieza en 0, y se escribe en el eje mismo.
  const piso = pisoDeLinea(puntos) ?? 0;
  const H = 96, PL = 34, PR = 10, PT = 10, PB = 20;
  const n = puntos.length;
  const x = (i: number) => PL + (n === 1 ? (W - PL - PR) / 2 : ((W - PL - PR) * i) / (n - 1));
  const y = (v: number) => PT + (H - PT - PB) * (1 - (v - piso) / (100 - piso));
  const trazo = puntos
    .map((p, i) => ({ p, i }))
    .filter(({ p }) => p.pct !== null && !p.parcial)
    .map(({ p, i }, k) => `${k ? "L" : "M"}${x(i)},${y(p.pct as number)}`)
    .join(" ");
  const carril = n > 1 ? (W - PL - PR) / (n - 1) : W - PL - PR;
  // La más baja se nombra solo si hay con qué compararla y no es la misma que encabeza.
  const minima = r.minima && r.semanas > 1 && r.minima.semana !== r.ultima?.semana ? r.minima : null;
  const iMin = minima ? puntos.findIndex((p) => p.semana === minima.semana) : -1;

  return (
    <div>
      {r.ultima && (
        <Encabeza
          valor={`${r.ultima.pct}%`}
          detalle={<>semana del {etiquetaCierre(r.ultima.semana)} · promedio <strong className="font-medium text-tinta">{r.promedio}%</strong>{minima ? <> · la más baja <strong className="font-medium text-tinta">{minima.pct}%</strong> ({etiquetaCierre(minima.semana)})</> : null}</>}
        />
      )}
      <div ref={ref} className="w-full">
        {W > 0 && conDato.length > 0 && (
          <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Asistencia sobre lo esperado, por semana" className="block overflow-visible">
            {[piso, 100].map((t) => (
              <g key={t}>
                <line x1={PL} x2={W - PR} y1={y(t)} y2={y(t)} stroke="var(--color-sand)" />
                <text x={PL - 6} y={y(t) + 4} textAnchor="end" {...T}>{t}%</text>
              </g>
            ))}
            <path d={trazo} fill="none" stroke="var(--color-tinta)" strokeWidth={2} strokeLinejoin="round" />
            {puntos.map((p, i) => {
              if (p.pct === null) return null;
              const destacado = p.semana === r.ultima?.semana || i === iMin || p.parcial;
              return (
                <g key={p.semana}>
                  <title>{`Semana del ${etiquetaCierre(p.semana)}${p.parcial ? " (en curso)" : ""}: ${p.pct}% · ${p.trabajados} de ${p.trabajados + p.faltas} días con marca`}</title>
                  <rect x={x(i) - carril / 2} y={0} width={carril} height={H} fill="transparent" />
                  <circle cx={x(i)} cy={y(p.pct)} r={destacado ? 4 : 2.2}
                    fill={p.parcial ? "var(--color-papel)" : "var(--color-tinta)"} stroke="var(--color-tinta)" strokeWidth={p.parcial ? 1.6 : 0} />
                </g>
              );
            })}
            {minima && <text x={x(iMin)} y={y(minima.pct) + 16} textAnchor="middle" className="tabular-nums" {...T}>{minima.pct}%</text>}
            <text x={PL} y={H - 4} {...T}>{diaBarraMes(puntos[0].semana)}</text>
            <text x={W - PR} y={H - 4} textAnchor="end" {...T}>{diaBarraMes(puntos[n - 1].semana)}{puntos[n - 1].parcial ? " · en curso" : ""}</text>
          </svg>
        )}
      </div>
    </div>
  );
}

export function CostoCompacto({ columnas }: { columnas: ColumnaCosto[] }) {
  const [ref, W] = useAncho<HTMLDivElement>();
  const rayado = useId().replace(/:/g, "");
  const r = resumenCosto(columnas);
  const monto = (n: number) => soles(Math.round(n)).replace(/\.00$/, "");
  const H = 128, PT = 20, PB = 20, alto = H - PT - PB;
  const max = Math.max(1, ...columnas.map((c) => c.costo ?? 0));
  const carril = W / Math.max(columnas.length, 1);
  const ancho = Math.min(carril * 0.56, 44);
  // Las marcas de un periodo van en una línea aparte, no debajo de cada columna: con doce no caben, y una
  // palabra repetida en cada columna deja de decir algo.
  const repagados = columnas.filter((c) => c.repagado).map((c) => c.etiqueta);
  const retroactivos = columnas.filter((c) => c.retroactivo).map((c) => c.etiqueta);
  const signo = (n: number) => (n >= 0 ? "+" : "−");

  return (
    <div>
      {r.ultima && (
        <Encabeza
          valor={monto(r.ultima.costo)}
          detalle={<>cerró el {r.ultima.etiqueta}{r.diferencia !== null ? <> · <strong className="font-medium text-tinta">{signo(r.diferencia)}{monto(Math.abs(r.diferencia))}</strong>{r.variacionPct !== null ? ` (${signo(r.variacionPct)}${Math.abs(r.variacionPct)} %)` : ""} frente al anterior</> : null}{r.ultima.personas !== null ? ` · ${r.ultima.personas} personas` : ""}</>}
        />
      )}
      <div ref={ref} className="w-full">
        {W > 0 && (
          <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Costo de planilla de cada periodo" className="block overflow-visible">
            <defs>
              <pattern id={rayado} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                <line x1="0" y1="0" x2="0" y2="6" stroke="var(--color-taupe)" strokeWidth="1.6" />
              </pattern>
            </defs>
            <line x1={0} x2={W} y1={PT + alto} y2={PT + alto} stroke="var(--color-sand)" />
            {columnas.map((c, i) => {
              const cx0 = carril * i + carril / 2;
              const h = c.costo !== null ? (c.costo / max) * alto : alto * 0.5;
              const y0 = PT + alto - h;
              return (
                <g key={c.clave}>
                  <title>{c.enCurso
                    ? `Periodo en curso, del ${etiquetaCierre(c.fechaIni)} al ${c.etiqueta}: todavía no tiene monto`
                    : `Del ${etiquetaCierre(c.fechaIni)} al ${c.etiqueta} · ${monto(c.costo ?? 0)}${c.personas !== null ? ` · ${c.personas} personas` : ""}${c.repagado ? " · repagado" : ""}${c.retroactivo ? " · retroactivo" : ""}`}</title>
                  <rect x={cx0 - carril / 2} y={0} width={carril} height={H} fill="transparent" />
                  {c.enCurso
                    ? <rect x={cx0 - ancho / 2} y={y0} width={ancho} height={h} rx={4} fill={`url(#${rayado})`} stroke="var(--color-taupe)" strokeDasharray="3 3" />
                    : <path d={columna(cx0 - ancho / 2, y0, ancho, h)} fill="var(--color-tinta)" />}
                  {(c.enCurso || carril >= 64) && (
                    <text x={cx0} y={y0 - 6} textAnchor="middle" className="tabular-nums" {...(c.enCurso ? T : TT)}>{c.enCurso ? "en curso" : monto(c.costo ?? 0)}</text>
                  )}
                  <text x={cx0} y={H - 4} textAnchor="middle" {...T}>{carril >= 48 ? c.etiqueta : c.etiqueta.split(" ")[1]}</text>
                </g>
              );
            })}
          </svg>
        )}
      </div>
      {(repagados.length > 0 || retroactivos.length > 0) && (
        <p className="mt-2 text-xs text-taupe">
          {repagados.length > 0 && <>Se volvió a pagar después del primer pago: {repagados.join(", ")}. </>}
          {retroactivos.length > 0 && <>Reconstruido después del pago: {retroactivos.join(", ")}.</>}
        </p>
      )}
    </div>
  );
}

// ── Días perdidos, por motivo: un panel por motivo, todos con la misma escala ──
export function DiasPerdidosGrafico({ datos, nombreDe }: { datos: DiasPerdidos; nombreDe: (clave: string) => string }) {
  const [ref, W] = useAncho<HTMLDivElement>();
  const rayado = useId().replace(/:/g, "");
  const { meses, motivos } = datos;
  // Encabeza el último mes que terminó; si ninguno terminó todavía, el que hay.
  const terminado = meses.findLastIndex((m) => !m.parcial && m.pct !== null);
  const iRef = terminado >= 0 ? terminado : meses.findLastIndex((m) => m.pct !== null);
  const ref0 = meses[iRef];
  const mayor = [...motivos].filter((m) => m.dias[iRef] > 0).sort((a, b) => b.dias[iRef] - a.dias[iRef])[0];
  const nombreMes = (mes: string) => MESES_LARGO[Number(mes.slice(5, 7)) - 1];
  const corto = (mes: string) => MESES_CORTOS[Number(mes.slice(5, 7)) - 1];

  const cols = W >= 720 ? Math.min(motivos.length, 4) : W >= 400 ? Math.min(motivos.length, 2) : 1;
  const GAP = 20, PT = 34, PH = 84, PB = 18, ENTRE = 16;
  // Un panel no pasa de 420 px: con un solo motivo, estirarlo a toda la tarjeta dejaba los meses a un palmo uno de otro.
  const pw = Math.min(420, cols > 0 ? (W - GAP * (cols - 1)) / cols : W);
  const filas = Math.ceil(motivos.length / Math.max(cols, 1));
  const H = filas * (PT + PH + PB) + Math.max(0, filas - 1) * ENTRE;
  const max = Math.max(1, ...motivos.flatMap((m) => m.dias));
  const carril = pw / Math.max(meses.length, 1);
  const ancho = Math.min(carril * 0.55, 28);

  return (
    <div>
      {ref0 && ref0.pct !== null && (
        <Encabeza
          valor={`${ref0.pct}%`}
          detalle={<>de los días que tocaba trabajar se perdieron en {nombreMes(ref0.mes)}{ref0.parcial ? " (va en curso)" : ""} · <strong className="font-medium text-tinta">{ref0.perdidos} de {ref0.perdidos + ref0.trabajados}</strong>{mayor ? <> · el motivo más grande: {nombreDe(mayor.clave).toLowerCase()} ({mayor.dias[iRef]})</> : null}</>}
        />
      )}
      <div ref={ref} className="w-full">
        {W > 0 && (
          <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Días perdidos por mes, un panel por motivo" className="block overflow-visible">
            <defs>
              <pattern id={rayado} width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
                <line x1="0" y1="0" x2="0" y2="6" stroke="var(--color-taupe)" strokeWidth="1.6" />
              </pattern>
            </defs>
            {motivos.map((m, k) => {
              const ox = (k % cols) * (pw + GAP), oy = Math.floor(k / cols) * (PT + PH + PB + ENTRE);
              const base = oy + PT + PH;
              return (
                <g key={m.clave}>
                  <text x={ox} y={oy + 12} {...TT}>{nombreDe(m.clave)}</text>
                  <text x={ox} y={oy + 26} {...T}>{m.total} {m.total === 1 ? "día" : "días"} en el periodo</text>
                  <line x1={ox} x2={ox + pw} y1={base} y2={base} stroke="var(--color-sand)" />
                  {m.dias.map((d, i) => {
                    const cx0 = ox + carril * i + carril / 2, h = (d / max) * (PH - 14), y0 = base - h;
                    const parcial = meses[i].parcial;
                    return (
                      <g key={meses[i].mes}>
                        <title>{`${nombreDe(m.clave)}, ${nombreMes(meses[i].mes)}${parcial ? " (parcial)" : ""}: ${d} ${d === 1 ? "día" : "días"}`}</title>
                        <rect x={cx0 - carril / 2} y={oy} width={carril} height={PT + PH + PB} fill="transparent" />
                        {h > 0 && (parcial
                          ? <rect x={cx0 - ancho / 2} y={y0} width={ancho} height={h} rx={3} fill={`url(#${rayado})`} stroke="var(--color-taupe)" strokeDasharray="3 2" />
                          : <path d={columna(cx0 - ancho / 2, y0, ancho, h)} fill="var(--color-tinta)" />)}
                        {d > 0 && carril >= 22 && <text x={cx0} y={y0 - 5} textAnchor="middle" className="tabular-nums" {...(parcial ? T : TT)}>{d}</text>}
                        {(carril >= 24 || i % 2 === meses.length % 2) && <text x={cx0} y={base + 14} textAnchor="middle" {...T}>{corto(meses[i].mes)}</text>}
                      </g>
                    );
                  })}
                </g>
              );
            })}
          </svg>
        )}
      </div>
    </div>
  );
}

// ── Gente en piso frente a la venta: dos filas que comparten la hora ─────────
export function PisoYVentaGrafico({ horas, comprasFallo }: { horas: HoraDePiso[]; comprasFallo: boolean }) {
  const [ref, W] = useAncho<HTMLDivElement>();
  const peor = comprasFallo ? null : horaMasCorta(horas);
  // Sin compras no se deja el hueco de su fila: se dice arriba, en una línea, y se dibuja solo la gente.
  const T1 = comprasFallo ? 0 : 18, H1 = comprasFallo ? 0 : 76, ENTRE = comprasFallo ? 18 : 34, H2 = 64, PB = 18;
  const base1 = T1 + H1, top2 = base1 + ENTRE, base2 = top2 + H2, H = base2 + PB;
  const carril = W / Math.max(horas.length, 1);
  const ancho = Math.min(carril * 0.56, 26);
  const maxC = Math.max(1, ...horas.map((h) => h.compras ?? 0));
  const maxP = Math.max(1, ...horas.map((h) => Math.max(h.enPiso, h.pedia ?? 0)));
  const conEtiqueta = carril >= 30;

  return (
    <div>
      {!comprasFallo && (peor ? (
        <Encabeza
          valor={`${peor.hora}:00`}
          detalle={<>es la hora en que más seguido faltó gente: <strong className="font-medium text-tinta">{peor.conFalta} de {peor.dias} días</strong> · en promedio había {numero(peor.enPiso)} en piso y la venta pedía {numero(peor.pedia ?? 0)}</>}
        />
      ) : (
        <Encabeza valor="Sin faltas" detalle="Ninguna hora tuvo menos gente en piso de la que pedía la venta." />
      ))}
      {comprasFallo && (
        <BannerAviso enLinea role="status">
          No se pudieron leer las compras de retail: se ve la gente en piso, pero no cuánta pedía la venta.
        </BannerAviso>
      )}
      <div ref={ref} className={cx("w-full", comprasFallo && "mt-3")}>
        {W > 0 && (
          <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Compras y personas en piso por hora del día" className="block overflow-visible">
            {horas.map((h, i) => faltaSeguido(h) && (
              <rect key={`b${h.hora}`} x={carril * i + 1} y={0} width={carril - 2} height={base2} rx={8} fill="var(--color-hueso)" />
            ))}
            {!comprasFallo && <text x={0} y={11} {...TT}>Compras por hora, en promedio</text>}
            <text x={0} y={top2 - 8} {...TT}>Personas en piso, en promedio</text>
            {!comprasFallo && <line x1={0} x2={W} y1={base1} y2={base1} stroke="var(--color-sand)" />}
            <line x1={0} x2={W} y1={base2} y2={base2} stroke="var(--color-sand)" />
            {horas.map((h, i) => {
              const cx0 = carril * i + carril / 2;
              const hc = h.compras !== null ? (h.compras / maxC) * (H1 - 16) : 0;
              const hp = (h.enPiso / maxP) * (H2 - 14);
              const yPedia = h.pedia !== null ? base2 - (h.pedia / maxP) * (H2 - 14) : null;
              return (
                <g key={h.hora}>
                  <title>{[
                    `${h.hora}:00 a ${h.hora + 1}:00 · ${h.dias} ${h.dias === 1 ? "día" : "días"}`,
                    h.compras !== null ? `Compras: ${numero(h.compras)} en promedio` : "Compras: sin leer",
                    `En piso: ${numero(h.enPiso)}${h.pedia !== null ? ` · la venta pedía ${numero(h.pedia)}` : ""}`,
                    h.pedia !== null ? `Faltó gente ${h.conFalta} de ${h.dias} días` : "",
                  ].filter(Boolean).join("\n")}</title>
                  <rect x={cx0 - carril / 2} y={0} width={carril} height={H} fill="transparent" />
                  {hc > 0 && <path d={columna(cx0 - ancho / 2, base1 - hc, ancho, hc)} fill="var(--color-tinta)" />}
                  {conEtiqueta && h.compras !== null && h.compras > 0 && <text x={cx0} y={base1 - hc - 5} textAnchor="middle" className="tabular-nums" {...T}>{numero(h.compras)}</text>}
                  {hp > 0 && <path d={columna(cx0 - ancho / 2, base2 - hp, ancho, hp)} fill="var(--color-taupe)" />}
                  {yPedia !== null && <line x1={cx0 - ancho / 2 - 3} x2={cx0 + ancho / 2 + 3} y1={yPedia} y2={yPedia} stroke="var(--color-tinta)" strokeWidth={1.5} strokeDasharray="3 2" />}
                  {conEtiqueta && <text x={cx0} y={Math.min(base2 - hp, yPedia ?? Infinity) - 5} textAnchor="middle" className="tabular-nums" {...T}>{numero(h.enPiso)}</text>}
                  {(carril >= 22 || i % 2 === 0) && <text x={cx0} y={H - 4} textAnchor="middle" {...T}>{h.hora}</text>}
                </g>
              );
            })}
          </svg>
        )}
      </div>
      {!comprasFallo && (
        <p className="mt-2 text-xs text-taupe">La raya es lo que pedía la venta. La franja marca las horas en que faltó gente la mitad de los días o más.</p>
      )}
    </div>
  );
}

/** ¿Se dibuja para el teléfono? Apagado, nunca: el gráfico sigue siendo el de hoy. */
function useAngosto(): boolean {
  const celular = useEsCelular();
  return interruptoresVidrio().panel && celular;
}

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
  const angosto = useAngosto();
  const conVidrio = interruptoresVidrio().panel;
  // En el teléfono cada columna pide 60 px: con doce periodos el dibujo corre dentro de su tarjeta, como una tabla ancha, y su letra sigue de 11 px.
  const anchoMinimo = columnas.length * 60;
  const W = angosto ? Math.max(300, anchoMinimo) : 640, H = 210, PL = 8, PR = 8, PT = 26, PB = 34;
  const max = Math.max(...columnas.map((c) => c.costo ?? 0), 1);
  const ancho = (W - PL - PR) / Math.max(columnas.length, 1);
  const barra = Math.min(ancho * 0.6, 56);
  const alto = H - PT - PB;
  const dibujo = (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" style={angosto ? { minWidth: anchoMinimo } : undefined} role="img" aria-label="Costo de planilla por periodo">
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
            {conVidrio && !c.enCurso ? (
              <path
                d={`M${cx0 - barra / 2},${y + h} V${y + 4} q0,-4 4,-4 h${barra - 8} q4,0 4,4 V${y + h} Z`}
                fill="var(--color-tinta)"
              />
            ) : (
              <rect
                x={cx0 - barra / 2} y={y} width={barra} height={h} rx={3}
                fill={c.enCurso ? "url(#rayado-en-curso)" : "var(--color-taupe)"}
                stroke={c.enCurso ? "var(--color-taupe)" : "none"} strokeDasharray={c.enCurso ? "3 3" : undefined}
                opacity={c.enCurso ? 0.7 : 1}
              />
            )}
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
  return angosto ? <div className="overflow-x-auto">{dibujo}</div> : dibujo;
}

// ── Asistencia sobre lo esperado: línea ─────────────────────────────────────
export function LineaAsistencia({ puntos }: { puntos: PuntoSemana[] }) {
  const angosto = useAngosto();
  const W = angosto ? 320 : 640, H = 200, PL = 36, PR = 12, PT = 18, PB = 30;
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
  const cada = Math.max(1, Math.ceil(puntos.length / (angosto ? 4 : 8)));
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
            // En el teléfono la última cifra va debajo de su punto: arriba la cruzaba la línea.
            <text x={x(i)} y={angosto && i === puntos.length - 1 ? y(p.pct) + 16 : y(p.pct) - 9} textAnchor={i === 0 ? "start" : "end"} fontSize={11} fill="var(--color-tinta)" className="tabular-nums">
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
  // En el teléfono la franja se queda con todo el ancho, debajo de su sede: en tres columnas le quedaban 60 px para medir 40 minutos.
  const angosto = useAngosto();
  const LIM = 20; // minutos a cada lado
  const pos = (m: number) => ((Math.max(-LIM, Math.min(LIM, m)) + LIM) / (2 * LIM)) * 100;
  const dicho = (m: number) => {
    const r = Math.round(Math.abs(m));
    return r === 0 ? "a la hora" : `${r} min ${m < 0 ? "antes" : "después"}`;
  };
  return (
    <div className="grid gap-3">
      {sedes.map((s) => (
        <div key={s.sede} className={angosto ? "grid grid-cols-[1fr_auto] items-baseline gap-x-3 gap-y-1 text-sm" : "grid grid-cols-[6.5rem_1fr_7.5rem] items-center gap-3 text-sm sm:grid-cols-[12rem_1fr_9rem]"}>
          <span className="truncate text-tinta" title={nombreDe(s.sede)}>{nombreDe(s.sede)}</span>
          {s.mediana === null || s.p25 === null || s.p75 === null ? (
            <>
              <span className="text-xs text-taupe">Pocas llegadas medidas ({s.n})</span>
              <span />
            </>
          ) : (
            <>
              <span className={cx("relative h-5", angosto && "order-3 col-span-2")} aria-hidden>
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
      {angosto ? (
        <div className="flex justify-between text-[11px] text-taupe" aria-hidden>
          <span>{LIM} min antes</span><span>a la hora</span><span>{LIM} min después</span>
        </div>
      ) : (
      <div className="grid grid-cols-[6.5rem_1fr_7.5rem] gap-3 text-[11px] text-taupe sm:grid-cols-[12rem_1fr_9rem]" aria-hidden>
        <span />
        <span className="flex justify-between"><span>{LIM} min antes</span><span>a la hora</span><span>{LIM} min después</span></span>
        <span />
      </div>
      )}
    </div>
  );
}

// ── Cuándo se llega tarde: sede × día de la semana ──────────────────────────
const DIAS_CAL = ["Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom"];
export function CalorTardanza({ filas, nombreDe }: { filas: { sede: string; celdas: CeldaCalor[] }[]; nombreDe: (codigo: string) => string }) {
  // En el teléfono la sede va por su código (el nombre sigue en el `title`): con ocho columnas en 300 px, «Tienda · Arequipa» se cortaba en «Tien…».
  const angosto = useAngosto();
  const conVidrio = interruptoresVidrio().panel;
  const max = Math.max(1, ...filas.flatMap((f) => f.celdas.map((c) => c.pctTarde ?? 0)));
  return (
    <div className="overflow-hidden rounded-superficie border border-sand">
      <table className={cx("w-full table-fixed text-center", angosto ? "text-xs" : "text-sm")}>
        <thead>
          <tr className="bg-sand/50 text-xs text-taupe">
            <th className={cx(angosto ? "w-[16%] px-1.5" : "w-[22%] px-2", "py-1.5 text-left font-normal")}>Sede</th>
            {DIAS_CAL.map((d) => <th key={d} className="px-1 py-1.5 font-normal">{d}</th>)}
          </tr>
        </thead>
        <tbody>
          {filas.map((f) => (
            <tr key={f.sede} className="border-t border-sand">
              <th className={cx("truncate py-1.5 text-left font-normal text-tinta", angosto ? "px-1.5" : "px-2")} title={nombreDe(f.sede)}>{angosto ? f.sede : nombreDe(f.sede)}</th>
              {f.celdas.map((c) => (
                <td key={c.dia} className="p-0.5">
                  <span
                    className={cx("flex h-8 items-center justify-center rounded-control tabular-nums", c.pctTarde !== null ? "text-tinta" : "text-taupe")}
                    style={c.pctTarde !== null ? { backgroundColor: conVidrio ? `color-mix(in srgb, var(--color-taupe) calc(${Math.round(10 + (c.pctTarde / max) * 55)}% * var(--calor-k, 1)), transparent)` : `color-mix(in srgb, var(--color-taupe) ${Math.round(10 + (c.pctTarde / max) * 55)}%, transparent)` } : undefined}
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
