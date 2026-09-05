"use client";

// Gráfico de barras del historial mensual de objetivos — SVG puro, sin
// librerías, colores por variable CSS para que el modo oscuro los redefina
// solo (mismo mecanismo que grafico-horas.tsx).
//
// Paleta: verde/ámbar/rojo NO son categóricos aquí — son una escala de
// ESTADO (cumplido / parcial / bajo desempeño), los mismos tres colores que
// ya usa la barra de progreso de arriba (nivelColorObjetivos). Una escala de
// estado siempre va con ícono + etiqueta, nunca solo el color: por eso la
// leyenda de abajo, no un simple degradado de colores sueltos.
//
// Un mes con total=0 (sin checklist ese mes) NO es un 0% cumplido: es "no hay
// dato", y se dibuja distinto —una marca gris al piso, sin altura real— para
// no acusar de bajo desempeño a un mes que simplemente no tuvo objetivos
// cargados. Un mes con total>0 y cumplidos=0 SÍ es un dato real (0% de
// verdad) y lleva altura mínima visible en rojo — si no, una barra de 0% de
// alto real es indistinguible del hueco gris.
//
// El ancho de cada barra NO es fijo: sale del espacio real de la tarjeta.
// Con «Último mes» (un solo dato) una barra fija de 20px quedaba perdida en
// medio de una tarjeta de ~700px — se veía flaca, como si el gráfico
// estuviera roto, y con 2 o 3 meses apenas mejor. Se mide el contenedor con
// ResizeObserver, porque ese ancho no se sabe antes de montar en el DOM, y
// cada mes recibe un carril igual; la barra se dibuja centrada en su carril,
// tan ancha como quepa hasta un máximo razonable.
//
// Pero el carril NUNCA baja de CARRIL_MIN, y eso no es un detalle de gusto:
// debajo de ese ancho las etiquetas de mes se pisan entre sí y el eje pasa a
// decir «Oct 24Nov 24Dic 24». Se vio con 24 meses al repartir todo el ancho
// disponible — el gráfico dejaba de scrollear y ganaba un eje ilegible. Con
// el mínimo puesto, muchos meses vuelven a scrollear de lado en vez de
// apretarse, y de paso el eje de 24 meses se lee por primera vez.

import { useId, useLayoutEffect, useRef, useState } from "react";
import { MESES, MESES_CORTO, nivelColorObjetivos, type MesHistorial } from "@/lib/objetivos";

const CLASE_FILL_NIVEL: Record<"verde" | "ambar" | "rojo", string> = {
  verde: "fill-verde",
  ambar: "fill-ambar",
  rojo: "fill-rojo",
};

const CLASE_BG_NIVEL: Record<"verde" | "ambar" | "rojo", string> = {
  verde: "bg-verde",
  ambar: "bg-ambar",
  rojo: "bg-rojo",
};

function etiquetaMesCorta(m: MesHistorial): string {
  return `${MESES_CORTO[m.mes - 1]} ${String(m.anio).slice(2)}`;
}

function etiquetaMesLarga(m: MesHistorial): string {
  return `${MESES[m.mes - 1]} ${m.anio}`;
}

/** Rectángulo con SOLO las dos esquinas superiores redondeadas — el "dato-end"
 * redondeado y la base cuadrada contra el eje que pide la especificación de
 * marca, sin depender de que `rx` de un `<rect>` redondee las cuatro. */
function pathBarraTopeRedondeado(x: number, yTop: number, ancho: number, alto: number, radio: number): string {
  const r = Math.max(0, Math.min(radio, alto / 2, ancho / 2));
  const yBase = yTop + alto;
  return `M ${x} ${yBase}
          L ${x} ${yTop + r}
          Q ${x} ${yTop} ${x + r} ${yTop}
          L ${x + ancho - r} ${yTop}
          Q ${x + ancho} ${yTop} ${x + ancho} ${yTop + r}
          L ${x + ancho} ${yBase}
          Z`;
}

export function GraficoObjetivos({ historial, cargando = false }: { historial: MesHistorial[]; cargando?: boolean }) {
  const [activo, setActivo] = useState<number | null>(null);
  const idBase = useId();

  // Medición del contenedor. `medir()` corre síncrono dentro del layout
  // effect para que el primer frame ya salga con el ancho correcto — sin eso
  // se vería un salto de la versión compacta a la ancha al montar. El efecto
  // depende de `sinDatos` y no de `[]`: el div medido no existe mientras no
  // hay historial, y si el historial llega después hay que engancharse ahí.
  const contenedorRef = useRef<HTMLDivElement>(null);
  const [anchoContenedor, setAnchoContenedor] = useState(0);
  const sinDatos = historial.length === 0;
  useLayoutEffect(() => {
    const el = contenedorRef.current;
    if (!el) return;
    const medir = () => setAnchoContenedor(el.clientWidth);
    medir();
    const obs = new ResizeObserver(medir);
    obs.observe(el);
    return () => obs.disconnect();
  }, [sinDatos]);

  if (sinDatos) {
    return <p className="text-sm text-taupe">Sin historial para mostrar.</p>;
  }

  const H = 200;
  const PAD_TOP = 14;
  const PAD_BOTTOM = 34;
  const PAD_LEFT = 32;
  const PAD_RIGHT = 8;
  const RADIO = 4;
  const BARRA_MAX = 64;
  // El carril mínimo lo manda la ETIQUETA, no la barra: «Sep 26» a 9px mide
  // 32px medidos en el navegador, así que por debajo de eso el eje se lee
  // «Oct 24Nov 24Dic 24». El trazado histórico usaba 30 (20 de barra + 10 de
  // hueco) y por eso el rango de 24 meses SIEMPRE tuvo las etiquetas pisadas;
  // 36 las separa con aire y deja la barra en 26. Cuesta un poco más de
  // scroll lateral en ese rango, que ya scrolleaba de todos modos.
  const HUECO_MIN = 10;
  const CARRIL_MIN = 36;

  const n = historial.length;
  // El "carril" de cada mes reparte TODO el ancho disponible en partes
  // iguales. Con 1, 2 o 3 meses el carril es enorme — ahí es donde se nota:
  // la barra se dibuja ancha (hasta BARRA_MAX) y centrada en su carril, en
  // vez de quedar del tamaño de siempre flotando en medio de un hueco. Si los
  // meses no caben ni al mínimo, el carril se queda en el mínimo y el SVG
  // crece más que la tarjeta: el contenedor de afuera scrollea, como siempre.
  // Antes de la primera medición (render en servidor, o el instante previo al
  // layout effect) `anchoContenedor` es 0 y cae en ese mismo caso compacto,
  // que se corrige antes de pintar.
  const disponible = Math.max(0, anchoContenedor - PAD_LEFT - PAD_RIGHT);
  const cabe = disponible / n >= CARRIL_MIN;
  const carril = cabe ? disponible / n : CARRIL_MIN;
  const ANCHO_BARRA = Math.min(BARRA_MAX, carril - HUECO_MIN);
  // Cuando cabe, el SVG mide EXACTAMENTE el contenedor (no una suma de
  // carriles con decimales que podría pasarse por una fracción de píxel y
  // encender un scroll horizontal vacío).
  const W = cabe ? anchoContenedor : PAD_LEFT + n * carril + PAD_RIGHT;
  const alto = H - PAD_TOP - PAD_BOTTOM;
  const y = (pct: number) => PAD_TOP + alto - (pct / 100) * alto;
  const xCarril = (i: number) => PAD_LEFT + i * carril;
  const xBarra = (i: number) => xCarril(i) + (carril - ANCHO_BARRA) / 2;

  const ticks = [0, 25, 50, 75, 100];
  const ultimo = historial.length - 1;
  // `activo` puede quedar apuntando a un índice que ya no existe: cambiar de
  // rango (o de mes/persona) encoge `historial` sin que este componente se
  // entere del cambio (no hay efecto escuchando la prop). Sin el acotado,
  // `historial[activo]` da `undefined` y `.total` revienta la pantalla entera
  // — se vio en vivo cambiando de 24 a 1 mes con una barra recién enfocada.
  const activoValido = activo !== null && activo < historial.length ? activo : null;
  const item = activoValido !== null ? historial[activoValido] : null;
  const xActivo = activoValido !== null ? xBarra(activoValido) + ANCHO_BARRA / 2 : 0;
  const yTopActivo =
    item !== null
      ? item.total > 0
        ? y(Math.max(3, (item.cumplidos / item.total) * 100))
        : PAD_TOP + alto - 3
      : 0;
  // Arriba de una barra cerca del 100% no siempre cabe el tooltip antes del
  // borde de la tarjeta: si no hay aire (~44px), se voltea y aparece DEBAJO
  // del tope de la barra en vez de quedar montado sobre el título de arriba.
  const ALTURA_TOOLTIP_ESTIMADA = 44;
  const volteado = yTopActivo - ALTURA_TOOLTIP_ESTIMADA < 0;

  return (
    <div>
      {/* Refetch mantiene el dibujo anterior atenuado en vez de un flash de
          "Cargando…": cambiar el rango no debe verse como una pantalla nueva.
          Este div es el que se mide: su clientWidth es el espacio real que
          hay para repartir en carriles. */}
      <div
        ref={contenedorRef}
        className={`overflow-x-auto transition-opacity ${cargando ? "opacity-50" : "opacity-100"}`}
      >
        {/* El SVG mide W — el contenedor entero cuando cabe, más cuando no —
            y NUNCA se estira con `min-w-full`: sin viewBox, CSS estirando la
            caja del SVG no escala el dibujo, solo agranda el lienzo. `w-fit`
            deja este envoltorio del tamaño exacto del SVG para que el tooltip,
            que vive DENTRO de él (no del scroll-container de afuera), comparta
            el mismo origen de coordenadas que el dibujo. */}
        <div className="relative w-fit">
          <svg
            width={W}
            height={H}
            role="img"
            aria-label={`Historial mensual de objetivos cumplidos, ${historial.length} meses`}
          >
            {/* líneas guía — hairline sólida, un paso fuera de la superficie */}
            {ticks.map((t) => (
              <g key={t}>
                <line x1={PAD_LEFT} x2={W - 4} y1={y(t)} y2={y(t)} className="stroke-sand" strokeWidth={1} />
                <text x={PAD_LEFT - 6} y={y(t) + 3} textAnchor="end" fontSize={9} className="fill-taupe">
                  {t}%
                </text>
              </g>
            ))}

            {historial.map((m, i) => {
              const x = xBarra(i);
              const sinDato = m.total <= 0;
              const pct = sinDato ? 0 : (m.cumplidos / m.total) * 100;
              const nivel = nivelColorObjetivos(m.cumplidos, m.total);
              const estaActivo = activo === i;
              const descripcion = sinDato
                ? `${etiquetaMesLarga(m)}: sin checklist ese mes`
                : `${etiquetaMesLarga(m)}: ${m.cumplidos} de ${m.total} cumplidos (${Math.round(pct)}%)`;

              return (
                <g key={`${m.anio}-${m.mes}`}>
                  {sinDato ? (
                    <rect
                      x={x}
                      y={PAD_TOP + alto - 3}
                      width={ANCHO_BARRA}
                      height={3}
                      rx={1.5}
                      className="fill-taupe"
                      style={{ opacity: estaActivo ? 0.65 : 0.4 }}
                    />
                  ) : (
                    <path
                      d={pathBarraTopeRedondeado(x, y(pct), ANCHO_BARRA, Math.max(3, PAD_TOP + alto - y(pct)), RADIO)}
                      className={CLASE_FILL_NIVEL[nivel]}
                      style={estaActivo ? { filter: "brightness(1.12)" } : undefined}
                    />
                  )}
                  {/* Etiqueta directa selectiva: solo el último mes (el que se está
                      editando arriba), no un número en cada barra. */}
                  {i === ultimo && (
                    <text
                      x={x + ANCHO_BARRA / 2}
                      y={(sinDato ? PAD_TOP + alto - 3 : y(Math.max(3, pct))) - 6}
                      textAnchor="middle"
                      fontSize={10}
                      fontWeight={600}
                      className="fill-tinta"
                    >
                      {sinDato ? "—" : `${Math.round(pct)}%`}
                    </text>
                  )}
                  <text
                    x={x + ANCHO_BARRA / 2}
                    y={H - PAD_BOTTOM + 14}
                    textAnchor="middle"
                    fontSize={9}
                    className="fill-taupe"
                  >
                    {etiquetaMesCorta(m)}
                  </text>

                  {/* Objetivo de foco/hover: el carril entero, no solo la barra —
                      incluye el hueco entre barras. Mismo detalle en teclado que
                      en mouse. */}
                  <rect
                    x={xCarril(i)}
                    y={PAD_TOP}
                    width={carril}
                    height={alto}
                    fill="transparent"
                    tabIndex={0}
                    role="img"
                    aria-label={descripcion}
                    aria-describedby={estaActivo ? `${idBase}-tooltip` : undefined}
                    className="cursor-pointer outline-none focus-visible:outline focus-visible:outline-2 focus-visible:outline-tinta"
                    onMouseEnter={() => setActivo(i)}
                    onMouseLeave={() => setActivo((a) => (a === i ? null : a))}
                    onFocus={() => setActivo(i)}
                    onBlur={() => setActivo((a) => (a === i ? null : a))}
                  />
                </g>
              );
            })}
          </svg>

          {item && (
            <div
              id={`${idBase}-tooltip`}
              role="tooltip"
              className={`pointer-events-none absolute z-10 -translate-x-1/2 whitespace-nowrap rounded-lg bg-tinta px-2.5 py-1.5 text-xs text-crema shadow-lg ${
                volteado ? "" : "-translate-y-full"
              }`}
              style={{ left: xActivo, top: volteado ? yTopActivo + 8 : yTopActivo - 8 }}
            >
              <div className="font-medium">{etiquetaMesLarga(item)}</div>
              <div className="text-crema/80">
                {item.total > 0 ? `${item.cumplidos} de ${item.total} cumplidos (${Math.round((item.cumplidos / item.total) * 100)}%)` : "Sin checklist ese mes"}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Leyenda: ícono + etiqueta, nunca el color solo — es una escala de
          estado, igual que la insignia «Observación» de la barra de arriba. */}
      <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-taupe">
        <span className="flex items-center gap-1.5">
          <span className={`h-2.5 w-2.5 rounded-full ${CLASE_BG_NIVEL.verde}`} /> Cumplido (≥60%)
        </span>
        <span className="flex items-center gap-1.5">
          <span className={`h-2.5 w-2.5 rounded-full ${CLASE_BG_NIVEL.ambar}`} /> Parcial (30–59%)
        </span>
        <span className="flex items-center gap-1.5">
          <span className={`h-2.5 w-2.5 rounded-full ${CLASE_BG_NIVEL.rojo}`} /> Bajo desempeño (&lt;30%)
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-2.5 w-2.5 rounded-full bg-taupe/40" /> Sin checklist ese mes
        </span>
      </div>

      <span className="sr-only" aria-live="polite">
        {cargando ? "Actualizando el gráfico…" : ""}
      </span>
    </div>
  );
}
