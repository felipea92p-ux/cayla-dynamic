"use client";

import { useMemo } from "react";
import { enDias } from "@/lib/admin/bandeja-urgencia";
import { estadoParaMostrar } from "@/lib/admin/educacion-grupos";
import { soles } from "@/lib/admin/educacion-formato";
import {
  casillasDeEstudio, entregasDeEstudio, etiquetaMes, familiasDe, mesDe, montoMensual,
  type Estudio, type ResumenDeSede, type CoberturaMes } from "@/lib/admin/educacion-meses";
import type { EntregaDeFamilia, Pendiente } from "@/lib/admin/educacion-tipos";
import { fechaCorta } from "@/lib/educacion";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { CasillaMes } from "./casilla-mes";

/**
 * LA CUADRÍCULA PERSONA × MES: una fila por estudio, una columna por mes.
 *
 * PROMETE: que cada fila muestre, de un vistazo, la constancia que se recibió cada
 *   mes —con su miniatura— y que un toque en una casilla abra el visor justo en esa
 *   constancia. Con «Todas las sedes», la lista se parte en un bloque por sede con
 *   su resumen (personas, apoyos, monto al mes y lo que pide acción).
 * ASUME: `estudios` ya vienen filtrados y ordenados (lo que pide acción, primero),
 *   y `meses` ya vienen de `ventanaDeMeses`.
 * NO HACE: no carga nada ni calcula estados. Una casilla vacía es un guion, nunca una
 *   falta: lo vencido lo dice la insignia de la fila, que viene de la base.
 *
 * En escritorio es una tabla con la columna de la persona fija a la izquierda, para
 * que al desplazarse hacia los meses viejos no se pierda de quién es cada fila. En
 * celular cada estudio es una tarjeta con su tira de meses que se desliza.
 */

const SEPARADOR_DE_COLUMNAS = "border-l border-sand";

/** Una persona activa sin estudio ni solicitud (`personasSinSolicitar`). */
export interface PersonaSinSolicitar { persona_id: string; persona: string; sede: string; rango: string }

export function CuadriculaMeses({
  estudios, meses, hayMasMeses, onVerMasMeses, mesResaltado, entregasPorFamilia, cargandoConstancias,
  familiasSinLeer, pendientes, hoy, resumenesSede, onAbrirVisor, onAbrirEstudio, coberturas, apoyoPagado,
  sinSolicitar = [], onRegistrar,
}: {
  estudios: Estudio[];
  meses: string[];
  hayMasMeses: boolean;
  onVerMasMeses: () => void;
  mesResaltado: string;
  entregasPorFamilia: ReadonlyMap<string, EntregaDeFamilia[]> | null;
  cargandoConstancias: boolean;
  /** Estudios cuyas constancias no se pudieron leer: sus casillas vacías dicen «?» y no «—». */
  familiasSinLeer: ReadonlySet<string>;
  pendientes: Pendiente[];
  hoy: string;
  /** Con valor, la lista se parte en un bloque por sede. Sin él, una sola lista. */
  resumenesSede: ResumenDeSede[] | null;
  onAbrirVisor: (e: Estudio, entregaId: string | null) => void;
  onAbrirEstudio: (e: Estudio, boton: HTMLElement) => void;
  /** Los meses que cubre cada pago adelantado (0529), por id de constancia. */
  coberturas?: ReadonlyMap<string, readonly CoberturaMes[]>;
  /** Lo pagado de educación por persona y mes (`persona_id|AAAA-MM`). */
  apoyoPagado?: ReadonlyMap<string, number>;
  /**
   * Personas activas que no pidieron educación. Van en la MISMA cuadrícula, como una fila más de su
   * sede y sin meses que mirar, no en una tabla aparte (Felipe, 2026-10-17).
   */
  sinSolicitar?: readonly PersonaSinSolicitar[];
  onRegistrar?: (boton: HTMLElement, personaId: string) => void;
}) {
  const bloques = useMemo(() => {
    if (!resumenesSede) return [{ clave: "todas", sede: null as string | null, resumen: null as ResumenDeSede | null, estudios, sinSol: sinSolicitar }];
    const lista = resumenesSede.map((r) => ({
      clave: r.sede, sede: r.sede as string | null, resumen: r as ResumenDeSede | null, estudios: r.estudios,
      sinSol: sinSolicitar.filter((p) => p.sede === r.sede),
    }));
    // Una sede donde nadie tiene estudio también sale, con su gente sin solicitar.
    const conBloque = new Set(resumenesSede.map((r) => r.sede));
    for (const sede of Array.from(new Set(sinSolicitar.map((p) => p.sede))).sort()) {
      if (!conBloque.has(sede)) lista.push({ clave: sede, sede, resumen: null, estudios: [], sinSol: sinSolicitar.filter((p) => p.sede === sede) });
    }
    return lista;
  }, [resumenesSede, estudios, sinSolicitar]);
  const mesDeHoy = mesDe(hoy);

  const pendienteDe = (e: Estudio): string | null => {
    const familias = new Set(familiasDe(e));
    return pendientes.find((p) => familias.has(p.familia_id))?.id ?? null;
  };

  const fila = (e: Estudio) => {
    const entregas = entregasDeEstudio(e, entregasPorFamilia);
    const casillas = casillasDeEstudio(e, entregas, meses, { coberturas, apoyoPagado, hoy });
    return {
      e, casillas, pendiente: pendienteDe(e),
      cargando: cargandoConstancias && entregasPorFamilia === null,
      sinLeer: e.tramos.some((t) => familiasSinLeer.has(t.familia_id)),
    };
  };

  return (
    <div>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2 text-xs text-taupe">
        <Leyenda />
        {hayMasMeses && <Boton variante="enlace" className="text-xs" onClick={onVerMasMeses}>← Meses anteriores</Boton>}
      </div>

      {/* ── ESCRITORIO Y TABLET: tabla ───────────────────────────────────── */}
      <div className="hidden overflow-x-auto rounded-superficie border border-sand bg-papel md:block">
        <table className="w-full text-sm">
          <thead className="bg-papel text-left text-taupe">
            <tr className="bg-sand/70">
              <th className="sticky left-0 z-[1] bg-[color-mix(in_oklab,var(--color-sand)_70%,var(--color-papel))] px-4 py-2 font-normal">Persona</th>
              <th className="px-3 py-2 font-normal">Estudio</th>
              {meses.map((m, i) => {
                const { corto, anio } = etiquetaMes(m);
                const mostrarAnio = i === 0 || m.endsWith("-01");
                return (
                  <th key={m} scope="col" aria-current={m === mesDeHoy ? "date" : undefined}
                    className={`w-[68px] min-w-[68px] px-0 py-2 text-center font-normal ${i === 0 ? SEPARADOR_DE_COLUMNAS : ""} ${m === mesResaltado ? "bg-hueso" : ""}`}>
                    <span className={`block text-xs ${m === mesDeHoy ? "font-medium text-tinta" : ""}`}>{corto}</span>
                    <span className="block h-3 text-[10px] leading-3 text-taupe">{mostrarAnio ? anio : ""}</span>
                    {m === mesDeHoy && <span aria-hidden className="mx-auto mt-0.5 block h-0.5 w-5 rounded-full bg-tinta" />}
                  </th>
                );
              })}
              <th className={`px-3 py-2 font-normal ${SEPARADOR_DE_COLUMNAS}`}>Estado</th>
              <th className="px-3 py-2"><span className="sr-only">Acciones</span></th>
            </tr>
          </thead>
          {bloques.map(({ clave, sede, resumen, estudios: lista, sinSol }) => (
            <tbody key={clave}>
              {(resumen || sede) && (
                <tr>
                  <th colSpan={meses.length + 4} scope="rowgroup" className="border-t border-sand bg-hueso/70 px-4 py-2 text-left font-normal">
                    {resumen ? <ResumenDelBloque resumen={resumen} /> : <h3 className="font-serif text-base text-tinta">{sede}</h3>}
                  </th>
                </tr>
              )}
              {lista.map((e) => {
                const f = fila(e);
                return (
                  <tr key={e.clave} className={`border-t border-sand transition-colors duration-150 hover:bg-crema/60 ${e.vigencia === "terminada" ? "text-taupe" : ""}`}>
                    <td className="sticky left-0 z-[1] bg-papel px-4 py-2 align-middle">
                      <span className="block font-medium">{e.persona}</span>
                      <span className="block text-xs text-taupe">{e.sede}{e.rango && e.rango !== "—" ? ` · ${e.rango}` : ""}</span>
                    </td>
                    <td className="min-w-48 px-3 py-2 align-middle">
                      <DatosDelEstudio e={e} hoy={hoy} />
                    </td>
                    {f.casillas.map((c, i) => (
                      <td key={c.mes} className={`p-0 align-middle ${i === 0 ? SEPARADOR_DE_COLUMNAS : ""}`}>
                        <CasillaMes casilla={c} persona={e.persona} cargando={f.cargando} sinLeer={f.sinLeer} resaltada={c.mes === mesResaltado}
                          alAbrir={() => onAbrirVisor(e, c.principal?.id ?? null)} />
                      </td>
                    ))}
                    <td className={`px-3 py-2 align-middle ${SEPARADOR_DE_COLUMNAS}`}>
                      <EstadoDelEstudio e={e} />
                    </td>
                    <td className="px-3 py-2 text-right align-middle">
                      <Acciones e={e} pendiente={f.pendiente} onAbrirVisor={onAbrirVisor} onAbrirEstudio={onAbrirEstudio} />
                    </td>
                  </tr>
                );
              })}
              {sinSol.map((p) => (
                <tr key={`sin-${p.persona_id}`} className="border-t border-sand text-taupe">
                  <td className="sticky left-0 z-[1] bg-papel px-4 py-2 align-middle">
                    <span className="block font-medium text-tinta">{p.persona}</span>
                    <span className="block text-xs">{p.sede}{p.rango && p.rango !== "—" ? ` · ${p.rango}` : ""}</span>
                  </td>
                  <td className="px-3 py-2 align-middle text-xs">No pidió apoyo</td>
                  {meses.map((m, i) => (
                    <td key={m} className={`p-0 align-middle ${i === 0 ? SEPARADOR_DE_COLUMNAS : ""}`}>
                      <div className="flex justify-center py-2"><span aria-hidden className="size-1 rounded-full bg-ceniza/30" /></div>
                    </td>
                  ))}
                  <td className={`px-3 py-2 align-middle ${SEPARADOR_DE_COLUMNAS}`}><Insignia variante="neutral">Sin solicitar</Insignia></td>
                  <td className="px-3 py-2 text-right align-middle">
                    {onRegistrar && <Boton variante="sutil" tamano="sm" className="whitespace-nowrap" onClick={(ev) => onRegistrar(ev.currentTarget, p.persona_id)}>Registrar apoyo</Boton>}
                  </td>
                </tr>
              ))}
            </tbody>
          ))}
        </table>
      </div>

      {/* ── CELULAR: una tarjeta por estudio, con su tira de meses ────────── */}
      <div className="flex flex-col gap-5 md:hidden">
        {bloques.map(({ clave, sede, resumen, estudios: lista, sinSol }) => (
          <section key={clave} className="flex flex-col gap-3">
            {resumen ? <div className="px-1"><ResumenDelBloque resumen={resumen} /></div>
              : sede ? <h3 className="px-1 font-serif text-base text-tinta">{sede}</h3> : null}
            <ul className="flex flex-col gap-3">
              {lista.map((e) => {
                const f = fila(e);
                return (
                  <li key={e.clave} className="rounded-superficie border border-sand bg-papel p-4 text-sm">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="font-medium">{e.persona}</p>
                        <p className="text-xs text-taupe">{e.sede}{e.rango && e.rango !== "—" ? ` · ${e.rango}` : ""}</p>
                      </div>
                      <EstadoDelEstudio e={e} compacto />
                    </div>
                    <div className="mt-3"><DatosDelEstudio e={e} hoy={hoy} /></div>
                    <ul className="-mx-4 mt-3 flex snap-x gap-0 overflow-x-auto px-4 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                      {f.casillas.map((c, i) => {
                        const { corto, anio } = etiquetaMes(c.mes);
                        return (
                          <li key={c.mes} className="shrink-0 snap-start">
                            <span className={`block text-center text-[11px] ${c.mes === mesDeHoy ? "font-medium text-tinta" : "text-taupe"}`}>{corto}</span>
                            <span className="block h-3 text-center text-[10px] leading-3 text-taupe">{i === 0 || c.mes.endsWith("-01") ? anio : ""}</span>
                            <div className="w-[64px]">
                              <CasillaMes casilla={c} persona={e.persona} cargando={f.cargando} sinLeer={f.sinLeer} resaltada={c.mes === mesResaltado}
                                alAbrir={() => onAbrirVisor(e, c.principal?.id ?? null)} />
                            </div>
                          </li>
                        );
                      })}
                    </ul>
                    <div className="mt-3 flex gap-2">
                    <Acciones e={e} pendiente={f.pendiente} onAbrirVisor={onAbrirVisor} onAbrirEstudio={onAbrirEstudio} ancha />
                    </div>
                  </li>
                );
              })}
              {sinSol.map((p) => (
                <li key={`sin-${p.persona_id}`} className="flex items-center justify-between gap-2 rounded-superficie border border-dashed border-sand px-4 py-3 text-sm">
                  <span className="min-w-0">
                    <span className="block font-medium">{p.persona}</span>
                    <span className="block text-xs text-taupe">Sin solicitar</span>
                  </span>
                  {onRegistrar && <Boton variante="sutil" tamano="sm" onClick={(ev) => onRegistrar(ev.currentTarget, p.persona_id)}>Registrar apoyo</Boton>}
                </li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </div>
  );
}

function ResumenDelBloque({ resumen: r }: { resumen: ResumenDeSede }) {
  const partes = [
    `${r.personas} persona${r.personas === 1 ? "" : "s"}`,
    `${r.pagando} apoyo${r.pagando === 1 ? "" : "s"} pagándose · ${soles(r.montoMensual)} al mes`,
  ];
  const pide = [
    r.porRevisar > 0 && `${r.porRevisar} por revisar`,
    r.vencidas > 0 && `${r.vencidas} vencida${r.vencidas === 1 ? "" : "s"}`,
    r.rechazadas > 0 && `${r.rechazadas} rechazada${r.rechazadas === 1 ? "" : "s"}`,
  ].filter(Boolean) as string[];
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5">
      <h3 className="font-serif text-base text-tinta">{r.sede}</h3>
      <p className="text-xs tabular-nums text-taupe">
        {partes.join(" · ")}
        {pide.length > 0 && <span className="text-tinta"> · {pide.join(" · ")}</span>}
      </p>
    </div>
  );
}

function DatosDelEstudio({ e, hoy }: { e: Estudio; hoy: string }) {
  const { monto, seEstaPagando } = montoMensual(e, hoy);
  const terminado = e.vigencia === "terminada";
  // Dos líneas y no tres (2026-10-17): la institución, y el monto con hasta cuándo. Para quién
  // estudia solo se dice si es un hijo o hija: «ella misma» es lo normal y no hace falta repetirlo.
  return (
    <>
      <span className="block">{e.institucion}</span>
      <span className="block text-xs tabular-nums text-taupe">
        {soles(monto)} · {terminado ? `terminó ${fechaCorta(e.hasta)}` : `hasta ${fechaCorta(e.hasta)}`}
        {e.beneficiario === "hijo" && ` · ${e.beneficiario_nombre ?? "su hijo/a"}`}
        {!terminado && !seEstaPagando && <span className="ml-1 rounded-full bg-sand px-1.5 text-[10px] text-tinta">aún no se paga</span>}
      </span>
    </>
  );
}

function EstadoDelEstudio({ e, compacto = false }: { e: Estudio; compacto?: boolean }) {
  const est = estadoParaMostrar(e);
  const s = e.actual;
  return (
    <div className={compacto ? "flex flex-col items-end gap-1" : undefined}>
      <Insignia variante={est.tono}>{est.etiqueta}</Insignia>
      {!compacto && (
        <>
          {s.plazo && s.dias_para_plazo !== null && s.estado_constancia !== "al_dia" && s.estado_constancia !== "pendiente_revision" && (
            <span className="mt-1 block text-xs text-taupe">{enDias(s.dias_para_plazo, { futuro: "Vence", pasado: "Venció" })}</span>
          )}
          {s.pago_proximo && s.dias_para_pago !== null && (
            <span className="mt-1 block text-xs text-taupe">{enDias(s.dias_para_pago, { futuro: "Paga", pasado: "Pagó" })}</span>
          )}
          {s.aviso_fin_id && <span className="mt-1 block text-xs text-ambar">avisó que deja de pagar</span>}
        </>
      )}
    </div>
  );
}

function Acciones({
  e, pendiente, onAbrirVisor, onAbrirEstudio, ancha = false,
}: {
  e: Estudio;
  pendiente: string | null;
  onAbrirVisor: (e: Estudio, entregaId: string | null) => void;
  onAbrirEstudio: (e: Estudio, boton: HTMLElement) => void;
  ancha?: boolean;
}) {
  return (
    <div className={`flex gap-2 ${ancha ? "w-full" : "justify-end"}`}>
      {pendiente && (
        <Boton variante="primario" tamano="sm" className={ancha ? "flex-1" : "whitespace-nowrap"}
          aria-label={`Revisar la constancia pendiente de ${e.persona} en ${e.institucion}`}
          onClick={() => onAbrirVisor(e, pendiente)}>
          Revisar →
        </Boton>
      )}
      <Boton variante={pendiente ? "sutil" : "secundario"} tamano="sm" className={ancha ? "flex-1" : undefined}
        aria-label={`Abrir el estudio de ${e.persona} en ${e.institucion}`}
        onClick={(ev) => onAbrirEstudio(e, ev.currentTarget)}>
        Estudio
      </Boton>
    </div>
  );
}

/**
 * Cómo se lee cada mes, en una línea: cinco íconos con una palabra y la raya del apoyo. El detalle
 * de cada mes sale al pasar encima; por eso aquí no va ninguna frase (Felipe, 2026-10-17).
 */
function Leyenda() {
  const punto = "inline-flex size-4 items-center justify-center rounded-full text-[9px] font-bold";
  return (
    <span className="flex flex-wrap items-center gap-x-3 gap-y-1" aria-label="Cómo leer cada mes">
      <span className="inline-flex items-center gap-1"><span aria-hidden className={`${punto} bg-verde text-crema`}>✓</span>Aprobada</span>
      <span className="inline-flex items-center gap-1"><span aria-hidden className="inline-block h-3 w-6 rounded-full bg-verde/15" />Adelantado</span>
      <span className="inline-flex items-center gap-1"><span aria-hidden className={`${punto} bg-pizarra text-crema`}>…</span>Por revisar</span>
      <span className="inline-flex items-center gap-1"><span aria-hidden className={`${punto} bg-rojo text-crema`}>✕</span>Rechazada</span>
      <span className="inline-flex items-center gap-1"><span aria-hidden className={`${punto} border-2 border-ambar text-ambar`}>!</span>Falta</span>
      <span className="inline-flex items-center gap-1" title="La raya debajo del ícono: verde, pagado; negra, se paga este mes; hueca, se pagará.">
        <span aria-hidden className="inline-block h-1 w-3 rounded-full bg-verde" />
        <span aria-hidden className="inline-block h-1 w-3 rounded-full bg-tinta" />
        <span aria-hidden className="inline-block h-1 w-3 rounded-full border border-taupe" />
        Apoyo
      </span>
    </span>
  );
}
