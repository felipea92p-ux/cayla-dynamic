"use client";

// ============================================================================
// dibujo.tsx — el organigrama en pantalla
// ============================================================================
// Desde tableta, los equipos van lado a lado y las líneas se dibujan midiendo las
// tarjetas. En el celular los equipos se apilan (en el orden que dice cada uno)
// y no hay líneas: seis tarjetas por renglón no se leen en una pantalla angosta.
// ============================================================================

import { useCallback, useLayoutEffect, useRef, useState } from "react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { cx } from "@/components/ui/cx";
import { Insignia } from "@/components/ui/insignia";
import { inicialesDe, urlPublicaFotoPerfil } from "@/lib/foto-perfil";
import {
  ETIQUETAS, filasDelOrganigrama, trazarLinea,
  type Caja, type Color, type Linea, type Nodo, type Organigrama,
} from "@/lib/organigrama";

const TARJETA: Record<Color, string> = {
  verde: "border-2 border-verde bg-verde/20",
  azul: "border-2 border-azul bg-azul/20",
  ambar: "border-2 border-ambar bg-ambar/20",
};
const CIRCULO: Record<Color, string> = {
  verde: "bg-verde text-crema",
  azul: "bg-azul text-crema",
  ambar: "bg-ambar text-crema",
};

function Tarjeta({ nodo, foto, onElegir }: { nodo: Nodo; foto: string | null; onElegir?: (n: Nodo) => void }) {
  const cuerpo = (
    // La tarjeta se acomoda a SU ancho: angosta, el círculo va encima; ancha, al costado.
    <span className="flex flex-col items-center gap-2 text-center @min-[11rem]:flex-row @min-[11rem]:text-left">
      <span aria-hidden className={cx(
        "flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-full text-xs font-medium",
        nodo.color ? CIRCULO[nodo.color] : "bg-sand text-tinta",
      )}>
        {foto
          // eslint-disable-next-line @next/next/no-img-element
          ? <img src={foto} alt="" className="size-full object-cover" />
          : inicialesDe(nodo.nombres, nodo.apellidos)}
      </span>
      <span className="min-w-0">
        <span className={cx("block text-sm leading-snug text-tinta", nodo.discreto ? "font-normal" : "font-medium")}>
          {nodo.nombres} {nodo.apellidos}
        </span>
        <span className="block text-xs leading-snug text-taupe">{nodo.funcion}</span>
        {nodo.etiqueta && <Insignia punto={false} className="mt-1">{ETIQUETAS[nodo.etiqueta]}</Insignia>}
      </span>
    </span>
  );
  const clases = cx(
    "@container block w-full rounded-control p-2",
    nodo.color ? TARJETA[nodo.color] : "border border-sand bg-papel",
  );
  return onElegir ? (
    <button type="button" data-persona={nodo.persona_id} onClick={() => onElegir(nodo)}
      className={cx(clases, "cursor-pointer hover:border-tinta")} aria-label={`Cambiar a ${nodo.nombres} ${nodo.apellidos}`}>
      {cuerpo}
    </button>
  ) : (
    <div data-persona={nodo.persona_id} className={clases}>{cuerpo}</div>
  );
}

/** Dónde quedó una tarjeta dentro del dibujo. Por `offset*`, que no se mueve con las animaciones del panel. */
function medir(el: HTMLElement, marco: HTMLElement): Caja {
  let izq = 0;
  let arr = 0;
  for (let e: HTMLElement | null = el; e && e !== marco; e = e.offsetParent as HTMLElement | null) {
    izq += e.offsetLeft;
    arr += e.offsetTop;
  }
  return { izq, arr, der: izq + el.offsetWidth, aba: arr + el.offsetHeight };
}

export function DibujoDelOrganigrama({ datos, onElegir }: {
  datos: Organigrama;
  /** Solo en modo edición: tocar una tarjeta la abre. */
  onElegir?: (n: Nodo) => void;
}) {
  const [supabase] = useState(() => createAdminSupabaseClient());
  const marco = useRef<HTMLDivElement>(null);
  const [trazos, setTrazos] = useState<{ clave: string; tipo: Linea["tipo"]; d: string }[]>([]);

  const dibujar = useCallback(() => {
    const m = marco.current;
    if (!m) return;
    const tarjeta = (id: string) => m.querySelector<HTMLElement>(`[data-persona="${CSS.escape(id)}"]`);
    setTrazos(datos.lineas.flatMap((l) => {
      const a = tarjeta(l.desde);
      const b = tarjeta(l.hasta);
      return a && b ? [{ clave: `${l.desde}-${l.hasta}`, tipo: l.tipo, d: trazarLinea(medir(a, m), medir(b, m)) }] : [];
    }));
  }, [datos]);

  // Las líneas salen de dónde quedaron las tarjetas: se miden al pintar y cada vez que el dibujo cambia de tamaño.
  useLayoutEffect(() => {
    dibujar();
    const m = marco.current;
    if (!m) return;
    const vigia = new ResizeObserver(dibujar);
    vigia.observe(m);
    return () => vigia.disconnect();
  }, [dibujar]);

  const filas = filasDelOrganigrama(datos.bloques, datos.personas);

  return (
    <div ref={marco} className="relative flex flex-col gap-4 md:gap-0">
      {filas.map((f, i) => (
        <div key={f.fila}
          className={cx("contents md:grid md:items-start md:gap-x-7 md:py-4", i > 0 && "md:border-t md:border-sand")}
          style={{ gridTemplateColumns: f.equipos.map((e) => `minmax(0, ${e.bloque.ancho}fr)`).join(" ") }}>
          {f.equipos.map(({ bloque, niveles }, columna) => (
            <section key={bloque.clave} aria-label={bloque.nombre}
              className={cx("flex flex-col gap-2 max-md:[order:var(--orden-movil)]", f.comparteNiveles && "md:grid md:grid-rows-subgrid md:items-center")}
              style={{
                "--orden-movil": bloque.orden_movil,
                gridColumn: columna + 1,
                gridRow: f.comparteNiveles ? `1 / span ${f.ultimoNivel + 1}` : 1,
              } as React.CSSProperties}>
              <h3 className={cx("font-serif text-center", bloque.discreto ? "text-sm text-taupe" : "text-base text-tinta")}>
                {bloque.nombre}
              </h3>
              {niveles.map((n) => (
                <div key={n.nivel}
                  className="grid grid-cols-1 items-stretch gap-2 max-md:data-[varias=true]:grid-cols-2 md:grid-cols-[repeat(var(--columnas),minmax(0,1fr))]"
                  data-varias={n.celdas.length > 1}
                  style={{
                    "--columnas": n.columnas,
                    ...(f.comparteNiveles ? { gridRow: n.nivel + 1 } : {}),
                  } as React.CSSProperties}>
                  {n.celdas.map((c) => (
                    <div key={c.nodo.persona_id}
                      className="flex md:[grid-column:var(--en)] [&>*]:self-stretch"
                      style={{ "--en": `${c.columna} / span ${c.ocupa}` } as React.CSSProperties}>
                      <Tarjeta nodo={c.nodo} foto={urlPublicaFotoPerfil(supabase, c.nodo.foto_url)} onElegir={onElegir} />
                    </div>
                  ))}
                </div>
              ))}
            </section>
          ))}
        </div>
      ))}
      <svg aria-hidden className="pointer-events-none absolute inset-0 hidden size-full md:block">
        {trazos.map((t) => (
          <path key={t.clave} d={t.d} fill="none" strokeWidth={t.tipo === "equipo" ? 1.5 : 2}
            strokeDasharray={t.tipo === "asesoria" ? "3 4" : undefined}
            className={t.tipo === "equipo" ? "stroke-taupe" : "stroke-pizarra"} />
        ))}
      </svg>
      {datos.lineas.length > 0 && (
        <p className="hidden text-center text-xs text-taupe md:block" style={{ order: 1000 }}>
          Línea llena: equipo · línea punteada: asesoría, sin mando
        </p>
      )}
    </div>
  );
}
