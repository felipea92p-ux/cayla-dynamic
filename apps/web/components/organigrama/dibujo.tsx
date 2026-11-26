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
  ETIQUETAS, alturaDelCanal, asignarCarriles, filasDelOrganigrama, redondear, tramoEn, trazarEntreFilas, trazarLinea,
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
        "flex shrink-0 items-center justify-center overflow-hidden rounded-full font-medium",
        nodo.discreto ? "size-7 text-[11px]" : "size-9 text-xs",
        nodo.color ? CIRCULO[nodo.color] : "bg-sand text-tinta",
      )}>
        {foto
          // eslint-disable-next-line @next/next/no-img-element
          ? <img src={foto} alt="" className="size-full object-cover" />
          : inicialesDe(nodo.nombres, nodo.apellidos)}
      </span>
      <span className="min-w-0">
        <span className={cx("block leading-snug text-tinta", nodo.discreto ? "text-xs font-normal" : "text-sm font-medium")}>
          {nodo.nombres} {nodo.apellidos}
        </span>
        <span className={cx("block leading-snug text-taupe", nodo.discreto ? "text-[11px]" : "text-xs")}>{nodo.funcion}</span>
        {(nodo.etiqueta || nodo.distintivo) && (
          <span className="mt-1 flex flex-wrap justify-center gap-1 @min-[11rem]:justify-start">
            {nodo.etiqueta && <Insignia punto={false} tamano={nodo.discreto ? "sm" : "md"}>{ETIQUETAS[nodo.etiqueta]}</Insignia>}
            {nodo.distintivo && <Insignia punto={false} tamano={nodo.discreto ? "sm" : "md"} variante="informativo" className="max-w-full"><span className="whitespace-normal text-center">◆ {nodo.distintivo}</span></Insignia>}
          </span>
        )}
      </span>
    </span>
  );
  const clases = cx(
    "@container relative z-10 block rounded-control",
    // La tarjeta discreta ocupa menos que su casilla y va centrada en ella (la línea la sigue).
    nodo.discreto ? "mx-auto w-4/5 p-1.5" : "w-full p-2",
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
    const filaDe = (el: HTMLElement) => Number(el.closest<HTMLElement>("[data-fila]")?.dataset.fila ?? 0);
    const filas = Array.from(m.querySelectorAll<HTMLElement>("[data-fila]")).map((el) => {
      const equipos = Array.from(el.querySelectorAll<HTMLElement>("section")).map((s) => medir(s, m)).sort((x, y) => x.izq - y.izq);
      return {
        arriba: medir(el, m).arr,
        pasillos: equipos.slice(1).map((e, i) => Math.round((equipos[i].der + e.izq) / 2)),
      };
    });
    const obstaculos = Array.from(m.querySelectorAll<HTMLElement>("[data-persona]")).map((el) => medir(el, m));
    // Cada línea, vista de arriba hacia abajo.
    const unidas = datos.lineas.flatMap((l) => {
      const a = tarjeta(l.desde);
      const b = tarjeta(l.hasta);
      if (!a || !b) return [];
      const [alta, baja] = filaDe(a) <= filaDe(b) ? [a, b] : [b, a];
      return [{ l, a, b, alta, baja }];
    });
    type Unida = (typeof unidas)[number];
    const cruzaFilas = (u: Unida) => filaDe(u.alta) !== filaDe(u.baja);
    const trazoEntre = ({ alta, baja }: Unida, carril: number) => trazarEntreFilas(medir(alta, m), medir(baja, m), {
      filas: filas.slice(filaDe(alta) + 1, filaDe(baja) + 1),
      obstaculos,
      carril,
    });
    // Dos personas solo van en alturas distintas si sus líneas se pisarían en el mismo canal.
    const carriles = new Map<HTMLElement, number>();
    for (const filaDeSalida of new Set(unidas.filter(cruzaFilas).map((u) => filaDe(u.alta)))) {
      const deAqui = unidas.filter((u) => cruzaFilas(u) && filaDe(u.alta) === filaDeSalida);
      const personas = [...new Set(deAqui.map((u) => u.alta))];
      const canal = alturaDelCanal(filas[filaDeSalida + 1], 0);
      const asignados = asignarCarriles(personas.map((persona, n) => {
        const tramos = deAqui.filter((u) => u.alta === persona).flatMap((u) => tramoEn(trazoEntre(u, 0), canal) ?? []);
        return { clave: String(n), ini: Math.min(...tramos.map((t) => t.ini)), fin: Math.max(...tramos.map((t) => t.fin)) };
      }));
      personas.forEach((persona, n) => carriles.set(persona, asignados.get(String(n)) ?? 0));
    }
    setTrazos(unidas.map((u) => ({
      clave: `${u.l.desde}-${u.l.hasta}`,
      tipo: u.l.tipo,
      d: redondear(cruzaFilas(u) ? trazoEntre(u, carriles.get(u.alta) ?? 0) : trazarLinea(medir(u.a, m), medir(u.b, m))),
    // Las llenas van encima: donde dos comparten recorrido se ve el tronco lleno.
    })).sort((x, y) => (x.tipo === y.tipo ? 0 : x.tipo === "asesoria" ? -1 : 1)));
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
    // Entre tableta y escritorio angosto, el dibujo conserva su ancho y se desliza de lado: encogerlo más rompe las palabras.
    <div className="md:overflow-x-auto">
    <div ref={marco} className="relative flex flex-col gap-4 md:min-w-[52rem] md:gap-0 md:px-5">
      <svg aria-hidden className="pointer-events-none absolute inset-0 hidden size-full md:block">
        {trazos.map((t) => (
          <path key={t.clave} d={t.d} fill="none" strokeWidth={1.5} strokeLinecap="round"
            strokeDasharray={t.tipo === "asesoria" ? "2 5" : undefined}
            className={t.tipo === "equipo" ? "stroke-taupe/70" : "stroke-pizarra"} />
        ))}
      </svg>
      {filas.map((f, i) => (
        <div key={f.fila} data-fila={i}
          className={cx("contents md:grid md:items-start md:gap-x-9", i > 0 ? "md:pt-14" : "md:pt-2")}
          style={{ gridTemplateColumns: f.equipos.map((e) => `minmax(0, ${e.bloque.ancho}fr)`).join(" ") }}>
          {f.equipos.map(({ bloque, niveles }, columna) => (
            <section key={bloque.clave} aria-label={bloque.nombre}
              className={cx("flex flex-col gap-2 max-md:[order:var(--orden-movil)]", f.comparteNiveles && "md:grid md:grid-rows-subgrid md:items-center")}
              style={{
                "--orden-movil": bloque.orden_movil,
                gridColumn: columna + 1,
                gridRow: f.comparteNiveles ? `1 / span ${f.ultimoNivel + 1}` : 1,
              } as React.CSSProperties}>
              <h3 className={cx(
                "relative z-10 mx-auto w-fit max-w-full rounded-pildora border border-sand bg-crema px-3 py-0.5 text-center font-serif",
                bloque.discreto ? "text-sm text-taupe" : "text-base text-tinta",
              )}>
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
                      // La tarjeta pequeña no se estira hasta el alto de su vecina.
                      className={cx("flex md:[grid-column:var(--en)]", c.nodo.discreto ? "[&>*]:self-start" : "[&>*]:self-stretch")}
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
      {datos.lineas.length > 0 && (
        <p className="hidden text-center text-xs text-taupe md:block" style={{ order: 1000 }}>
          Línea llena: equipo · línea punteada: asesoría, sin mando
        </p>
      )}
    </div>
    </div>
  );
}
