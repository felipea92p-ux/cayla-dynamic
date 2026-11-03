"use client";

// ============================================================================
// RepeticionDelDia — Turnos · Día, un día que ya cerró (2026-11-03, 0584)
// ============================================================================
// Lo que se marcó de verdad en el terminal, hora por hora: quién estaba en
// piso, en almacén, en refrigerio, por llegar o ya se había ido, contra lo que
// pedía la venta de esa hora. Se mueve la hora con la barra o se aprieta
// «Reproducir». La regla vive en lib/admin/repeticion.ts; esto solo dibuja.
// ============================================================================

import { useEffect, useMemo, useState } from "react";
import { Boton } from "@/components/ui/boton";
import { Cifra } from "@/components/ui/cifra";
import { Insignia } from "@/components/ui/insignia";
import { Rotulo } from "@/components/ui/rotulo";
import { TarjetaInfo } from "@/components/ui/tarjeta-info";
import { estiloDeHora } from "@/lib/admin/cobertura-turnos";
import {
  columnasEnElMomento, diaCompletoReal, horasDeLaRepeticion, resumenReal, ventaPedia,
  type EstadoEnElMomento, type PersonaRepeticion,
} from "@/lib/admin/repeticion";

const PASO = 5 / 60; // la barra avanza de 5 en 5 minutos
const hhmm = (dec: number) => {
  const h = Math.floor(dec + 1e-9);
  return `${String(h).padStart(2, "0")}:${String(Math.round((dec - h) * 60)).padStart(2, "0")}`;
};

const COLUMNAS: { estado: EstadoEnElMomento; titulo: string; vacio: string }[] = [
  { estado: "piso", titulo: "En piso", vacio: "Nadie" },
  { estado: "almacen", titulo: "En almacén", vacio: "Nadie" },
  { estado: "refrigerio", titulo: "En refrigerio", vacio: "Nadie" },
  { estado: "pausa", titulo: "En pausa", vacio: "Nadie" },
  { estado: "por_llegar", titulo: "Todavía no llega", vacio: "Ya llegaron todas" },
  { estado: "salio", titulo: "Ya salió", vacio: "Nadie" },
];

export function RepeticionDelDia({
  personas,
  medianocheIso,
  comprasDe,
  parametros,
  esTienda,
  comprasFallo,
}: {
  personas: PersonaRepeticion[];
  medianocheIso: string;
  /** Compras de una hora entera de ese día; null si no se pudieron leer o la sede no vende. */
  comprasDe: ((hora: number) => number) | null;
  /** Ritmo y mínimo de la tienda (Parámetros); null si no se pudieron leer. */
  parametros: { ritmo: number; minimo: number } | null;
  esTienda: boolean;
  /** La lectura de compras falló: se dice con palabras, nunca como cero. */
  comprasFallo: boolean;
}) {
  const horas = useMemo(() => horasDeLaRepeticion(personas, medianocheIso), [personas, medianocheIso]);
  const desde = horas[0] ?? 8;
  const hasta = (horas[horas.length - 1] ?? 20) + 1;
  // Arranca a media tarde, como la maqueta: el momento en que suele pasar algo.
  const [t, setT] = useState(() => Math.min(hasta, Math.max(desde, 14)));
  const [reproduciendo, setReproduciendo] = useState(false);

  useEffect(() => {
    if (!reproduciendo) return;
    const id = window.setInterval(() => {
      setT((x) => {
        const sig = x + PASO;
        if (sig >= hasta) { setReproduciendo(false); return hasta; }
        return sig;
      });
    }, 140);
    return () => window.clearInterval(id);
  }, [reproduciendo, hasta]);

  if (horas.length === 0) return null;

  const col = columnasEnElMomento(personas, t, medianocheIso, true);
  const horaEntera = Math.min(Math.floor(t), hasta - 1);
  const comprasHora = comprasDe ? comprasDe(horaEntera) : null;
  const pedia = parametros ? ventaPedia(comprasHora, parametros) : null;
  const enPisoAhora = col.piso.filter((f) => f.persona.cuenta).length;
  const dia = diaCompletoReal({ personas, medianocheIso, comprasDe, parametros });
  const resumen = resumenReal(dia);
  const maxCompras = Math.max(1, ...dia.map((h) => h.compras ?? 0));
  const conVenta = esTienda && comprasDe !== null;

  return (
    <TarjetaInfo className="space-y-4" titulo="Repetición del día" accion={<Insignia variante="neutral" tamano="sm">día cerrado</Insignia>}>
      <p className="text-xs text-taupe">
        Lo que se marcó de verdad en el terminal{esTienda ? ", contra lo que pedía la venta de cada hora" : ""}. Mueve la hora o dale «Reproducir».
      </p>

      <div className="flex flex-wrap items-center gap-3">
        <Boton variante="primario" tamano="sm" onClick={() => {
          if (!reproduciendo && t >= hasta - 1e-9) setT(desde);
          setReproduciendo((r) => !r);
        }}>
          {reproduciendo ? "Pausar" : "Reproducir"}
        </Boton>
        <label htmlFor="repeticion-hora" className="text-xs text-taupe">Hora</label>
        <input id="repeticion-hora" type="range" min={desde} max={hasta} step={PASO} value={t}
          onChange={(e) => { setReproduciendo(false); setT(Number(e.target.value)); }}
          className="min-w-[12rem] flex-1 accent-tinta" aria-valuetext={hhmm(t)} />
        <span className="font-serif text-lg tabular-nums">{hhmm(t)}</span>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <Cifra etiqueta="Operativas en piso" valor={String(enPisoAhora)}
          detalle={pedia !== null ? `la venta pedía ${pedia}` : undefined}
          tono={pedia === null ? undefined : enPisoAhora < pedia ? "alerta" : enPisoAhora > pedia + 1 ? "advertencia" : "positivo"} />
        <Cifra etiqueta="En refrigerio o pausa" valor={String(col.refrigerio.length + col.pausa.length)} />
        {esTienda && (
          <Cifra etiqueta={`Compras de ${String(horaEntera).padStart(2, "0")}:00 a ${String(horaEntera + 1).padStart(2, "0")}:00`}
            valor={comprasHora === null ? "—" : String(comprasHora)}
            detalle={comprasFallo ? "No se pudieron leer las compras de retail" : undefined} />
        )}
      </div>

      <div className="grid gap-3 sm:grid-cols-3 lg:grid-cols-6">
        {COLUMNAS.map(({ estado, titulo, vacio }) => (
          <div key={estado} className="min-w-0">
            <Rotulo como="h3" className="flex justify-between border-b border-sand pb-1">
              <span>{titulo}</span><span className="tabular-nums">{col[estado].length}</span>
            </Rotulo>
            <ul className="mt-1 space-y-1">
              {col[estado].length === 0 && <li className="text-xs text-taupe">{vacio}</li>}
              {col[estado].map(({ persona, detalle }) => (
                <li key={persona.id} className="text-xs">
                  <span className="font-medium">{persona.lider ? "L · " : ""}{persona.nombre}</span>
                  {!persona.cuenta && <span className="text-taupe"> (no suma)</span>}
                  {detalle && <span className="block text-taupe">{detalle}</span>}
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div>
        <Rotulo>El día completo · número: operativas en piso en el peor momento de la hora{conVenta ? " · barra: compras de esa hora" : ""}</Rotulo>
        <div className="mt-1 overflow-x-auto">
          <div className="flex min-w-[560px] gap-px">
            {dia.map((h) => {
              const e = estiloDeHora(h.enPiso, h.pedia ?? 0);
              const actual = h.hora === horaEntera;
              return (
                <button key={h.hora} type="button" onClick={() => { setReproduciendo(false); setT(h.hora + 0.5); }}
                  title={`${h.hora}:00 · ${h.enPiso} en piso${h.compras !== null ? ` · ${h.compras} compras` : ""}${h.pedia !== null ? ` · la venta pedía ${h.pedia}` : ""}`}
                  className={`flex flex-1 flex-col items-center gap-0.5 rounded px-0.5 pb-1 pt-1 text-[11px] ${actual ? "ring-2 ring-tinta" : ""}`}
                  style={{ background: e.fondo, color: e.texto }}>
                  <span className="font-medium tabular-nums">{h.enPiso}</span>
                  {conVenta && (
                    <span className="flex h-9 w-full items-end justify-center" aria-hidden>
                      <span className="w-2 rounded-sm bg-tinta/40" style={{ height: `${((h.compras ?? 0) / maxCompras) * 100}%` }} />
                    </span>
                  )}
                  <span className="text-[10px] text-taupe tabular-nums">{h.hora}:00{h.compras !== null ? ` · ${h.compras}` : ""}</span>
                </button>
              );
            })}
          </div>
        </div>
      </div>

      <p className="text-sm text-taupe">
        {comprasFallo
          ? "No se pudieron leer las compras de retail: la repetición muestra solo lo que se marcó."
          : !esTienda || resumen.totalCompras === null
            ? "Esta sede no vende en tienda: la repetición muestra solo lo que se marcó."
            : `Se hicieron ${resumen.totalCompras} compras. ${resumen.horasConFalta === 0
                ? "En ninguna hora hubo menos gente en piso de la que pedía la venta."
                : `En ${resumen.horasConFalta} ${resumen.horasConFalta === 1 ? "hora hubo" : "horas hubo"} menos gente en piso de la que pedía la venta.`}${resumen.masCargada
                ? ` La hora más cargada fue la de las ${resumen.masCargada.hora}:00, con ${String(resumen.masCargada.comprasPorPersona).replace(".", ",")} compras por persona en piso.`
                : ""}`}
      </p>
    </TarjetaInfo>
  );
}
