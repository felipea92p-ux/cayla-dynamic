"use client";

// ============================================================================
// dibujo.tsx — el organigrama en pantalla
// ============================================================================
// Una ficha por persona, todas de la misma medida: foto redonda a la izquierda,
// nombre y función al lado. Quien lleva color tiene la ficha teñida suave.
// Desde tableta los equipos van lado a lado y las líneas se dibujan midiendo; en
// el celular se apilan (en el orden que dice cada uno) y no hay líneas.
// ============================================================================

import { useCallback, useLayoutEffect, useRef, useState } from "react";
import { Globe } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { cx } from "@/components/ui/cx";
import { Insignia } from "@/components/ui/insignia";
import { inicialesDe, urlPublicaFotoPerfil } from "@/lib/foto-perfil";
import {
  ETIQUETAS, agruparLineas, alturaDelCanal, asignarCarriles, fichasPorRenglon, filasDelOrganigrama, formaDelEquipo,
  redondear, tituloDeEquipo, tramoEn, trazarEntreFilas, trazarLinea,
  type Caja, type Color, type Lugar, type Nodo, type Organigrama, type TipoLinea, type Trazo,
} from "@/lib/organigrama";

// El tinte se mezcla sobre `papel`: opaco, para que nada se transparente debajo.
const TINTE: Record<Color, string> = {
  verde: "border-verde/35 bg-[color-mix(in_srgb,var(--color-verde)_10%,var(--color-papel))]",
  azul: "border-azul/35 bg-[color-mix(in_srgb,var(--color-azul)_10%,var(--color-papel))]",
  ambar: "border-ambar/35 bg-[color-mix(in_srgb,var(--color-ambar)_10%,var(--color-papel))]",
};
const RETRATO: Record<Color, string> = {
  verde: "bg-verde text-crema ring-verde",
  azul: "bg-azul text-crema ring-azul",
  ambar: "bg-ambar text-crema ring-ambar",
};

function Ficha({ nodo, foto, onElegir }: { nodo: Nodo; foto: string | null; onElegir?: (n: Nodo) => void }) {
  const chica = nodo.discreto;
  const cuerpo = (
    <>
      <span className="relative shrink-0">
        <span aria-hidden className={cx(
          "flex items-center justify-center overflow-hidden rounded-full font-serif",
          chica ? "size-9 text-sm" : "size-[3.25rem] text-lg",
          nodo.color ? cx("ring-2 ring-offset-2 ring-offset-papel", RETRATO[nodo.color]) : "bg-hueso text-taupe",
        )}>
          {foto
            // El rostro suele estar arriba: el recorte se corre hacia allá.
            // eslint-disable-next-line @next/next/no-img-element
            ? <img src={foto} alt="" className="size-full object-cover object-[50%_20%]" />
            : inicialesDe(nodo.nombres, nodo.apellidos)}
        </span>
        {nodo.distintivo && (
          <span title={nodo.distintivo}
            className="absolute -bottom-1 -right-1 flex size-5 items-center justify-center rounded-full border-2 border-papel bg-tinta text-crema">
            <Globe aria-hidden className="size-3" />
          </span>
        )}
      </span>
      <span className="min-w-0 flex-1">
        <span className={cx("block leading-snug text-tinta", chica ? "text-xs font-medium" : "text-[13.5px] font-semibold")}>
          {nodo.nombres} {nodo.apellidos}
        </span>
        <span className={cx("mt-0.5 block leading-snug text-taupe", chica ? "text-[11px]" : "text-xs")}>{nodo.funcion}</span>
        {nodo.etiqueta && (
          <Insignia punto={false} tamano={chica ? "sm" : "md"} className="mt-1.5 border border-sand">{ETIQUETAS[nodo.etiqueta]}</Insignia>
        )}
        {nodo.distintivo && <span className="sr-only">{nodo.distintivo}</span>}
      </span>
    </>
  );
  const clases = cx(
    "relative z-10 flex items-center gap-3 rounded-2xl border text-left shadow-sm",
    chica ? "min-h-[3.75rem] w-[88%] px-3 py-2" : "min-h-[4.75rem] w-full p-3",
    nodo.color ? TINTE[nodo.color] : "border-sand bg-papel",
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

/** Dónde quedó algo dentro del dibujo. Por `offset*`, que no se mueve con las animaciones del panel. */
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
  /** Solo en modo edición: tocar una ficha la abre. */
  onElegir?: (n: Nodo) => void;
}) {
  const [supabase] = useState(() => createAdminSupabaseClient());
  const marco = useRef<HTMLDivElement>(null);
  const [trazos, setTrazos] = useState<{ clave: string; tipo: TipoLinea; d: string }[]>([]);

  const filas = filasDelOrganigrama(datos.bloques, datos.personas).map((f) => ({
    ...f,
    equipos: f.equipos.map((e) => ({ ...e, forma: formaDelEquipo(e, f.equipos.length === 1) })),
  }));

  const dibujar = useCallback(() => {
    const m = marco.current;
    if (!m) return;
    const ficha = (id: string) => m.querySelector<HTMLElement>(`[data-persona="${CSS.escape(id)}"]`);
    const equipoEn = (clave: string) => m.querySelector<HTMLElement>(`[data-equipo="${CSS.escape(clave)}"]`);
    const lugares = new Map<string, Lugar>();
    m.querySelectorAll<HTMLElement>("[data-persona]").forEach((el) => {
      const equipo = el.closest<HTMLElement>("[data-equipo]");
      const columna = el.closest<HTMLElement>("[data-columna]")?.dataset.columna ?? "0";
      lugares.set(el.dataset.persona ?? "", {
        fila: Number(el.closest<HTMLElement>("[data-fila]")?.dataset.fila ?? 0),
        equipo: equipo?.dataset.equipo ?? "",
        columna: Number(columna),
        puesto: Array.from(equipo?.querySelectorAll(`[data-columna="${columna}"] [data-persona]`) ?? []).indexOf(el),
      });
    });
    const medidas = Array.from(m.querySelectorAll<HTMLElement>("[data-fila]")).map((el) => {
      const equipos = Array.from(el.querySelectorAll<HTMLElement>("[data-equipo]")).map((s) => medir(s, m)).sort((x, y) => x.izq - y.izq);
      return {
        arriba: medir(el, m).arr,
        pasillos: equipos.slice(1).map((e, i) => Math.round((equipos[i].der + e.izq) / 2)),
      };
    });
    const obstaculos = Array.from(m.querySelectorAll<HTMLElement>("[data-persona]")).map((el) => medir(el, m));
    const lineas = agruparLineas(datos.lineas, lugares);

    type AEquipo = Extract<Trazo, { clase: "a-equipo" }>;
    const haciaAbajo = lineas.filter((t): t is AEquipo => t.clase === "a-equipo");
    const filaDe = (id: string) => lugares.get(id)?.fila ?? 0;
    const bajar = (t: AEquipo, carril: number) => {
      const desde = ficha(t.desde);
      const equipo = equipoEn(t.equipo);
      if (!desde || !equipo) return "";
      const llegada = medir(equipo, m);
      const filaLlegada = Number(equipo.closest<HTMLElement>("[data-fila]")?.dataset.fila ?? 0);
      return trazarEntreFilas(medir(desde, m), { ...llegada, arr: llegada.arr - 6 }, {
        filas: medidas.slice(filaDe(t.desde) + 1, filaLlegada + 1), obstaculos, carril,
      });
    };
    // Dos personas solo van en alturas distintas si sus líneas se pisarían en el mismo canal.
    const carriles = new Map<string, number>();
    for (const fila of new Set(haciaAbajo.map((t) => filaDe(t.desde)))) {
      const deAqui = haciaAbajo.filter((t) => filaDe(t.desde) === fila);
      const canal = alturaDelCanal(medidas[fila + 1], 0);
      const asignados = asignarCarriles([...new Set(deAqui.map((t) => t.desde))].map((persona) => {
        const tramos = deAqui.filter((t) => t.desde === persona).flatMap((t) => tramoEn(bajar(t, 0), canal) ?? []);
        return { clave: persona, ini: Math.min(...tramos.map((x) => x.ini)), fin: Math.max(...tramos.map((x) => x.fin)) };
      }));
      asignados.forEach((carril, persona) => carriles.set(persona, carril));
    }

    setTrazos(lineas.flatMap((t, i) => {
      let caminos: string[] = [];
      if (t.clase === "a-equipo") {
        caminos = [bajar(t, carriles.get(t.desde) ?? 0)];
      } else {
        const desde = ficha(t.desde);
        // En la misma fila va una línea por persona: comparten el tronco y se ven todas por igual.
        caminos = (t.clase === "al-lado" ? t.hasta : [t.hasta]).flatMap((id) => {
          const hasta = ficha(id);
          return desde && hasta ? [trazarLinea(medir(desde, m), medir(hasta, m))] : [];
        });
      }
      return caminos.filter(Boolean).map((d, n) => ({ clave: `${i}-${n}-${t.desde}`, tipo: t.tipo, d: redondear(d, 12) }));
      // Las llenas van encima: donde dos comparten recorrido se ve el tronco lleno.
    }).sort((x, y) => (x.tipo === y.tipo ? 0 : x.tipo === "asesoria" ? -1 : 1)));
  }, [datos]);

  // Las líneas salen de dónde quedaron las fichas: se miden al pintar y cada vez que el dibujo cambia de tamaño.
  useLayoutEffect(() => {
    dibujar();
    const m = marco.current;
    if (!m) return;
    const vigia = new ResizeObserver(dibujar);
    vigia.observe(m);
    return () => vigia.disconnect();
  }, [dibujar]);

  const distintivos = [...new Set(datos.personas.flatMap((p) => p.distintivo ?? []))];
  const ficha = (n: Nodo) => (
    <div key={n.persona_id} className="flex w-full justify-center">
      <Ficha nodo={n} foto={urlPublicaFotoPerfil(supabase, n.foto_url)} onElegir={onElegir} />
    </div>
  );
  const columna = "flex w-full max-w-[14rem] flex-col items-center gap-2.5 md:w-[14rem]";

  return (
    // Entre tableta y escritorio angosto, el dibujo conserva su ancho y se desliza de lado: encogerlo más rompe las palabras.
    <div className="md:overflow-x-auto">
      <div ref={marco} className="relative flex flex-col gap-6 md:min-w-[59rem] md:gap-0 md:px-6">
        <svg aria-hidden className="pointer-events-none absolute inset-0 hidden size-full md:block">
          {trazos.map((t) => (
            <path key={t.clave} d={t.d} fill="none" strokeWidth={1.5} strokeLinecap="round"
              strokeDasharray={t.tipo === "asesoria" ? "0.1 6" : undefined}
              className={t.tipo === "equipo" ? "stroke-taupe/60" : "stroke-pizarra [stroke-width:2px]"} />
          ))}
        </svg>
        {filas.map((f, i) => (
          <div key={f.fila} data-fila={i}
            className={cx(
              "contents md:justify-center md:gap-x-[clamp(2rem,6vw,5.25rem)]",
              f.comparteNiveles ? "md:grid md:grid-cols-[repeat(var(--equipos),max-content)] md:gap-y-2.5" : "md:flex md:items-start",
              i > 0 ? "md:pt-16" : "md:pt-2",
            )}
            style={{
              "--equipos": f.equipos.length,
              ...(f.comparteNiveles ? { gridTemplateRows: `repeat(${f.ultimoNivel - f.primerNivel + 2}, auto)` } : {}),
            } as React.CSSProperties}>
            {f.equipos.map(({ bloque, forma }, e) => {
              const { titulo, bajada } = tituloDeEquipo(bloque.nombre);
              return (
                <section key={bloque.clave} data-equipo={bloque.clave} aria-label={bloque.nombre}
                  className={cx("flex flex-col items-center gap-3 max-md:[order:var(--orden-movil)]",
                    f.comparteNiveles && "md:grid md:grid-rows-subgrid md:justify-items-center md:gap-y-2.5")}
                  style={{ "--orden-movil": bloque.orden_movil, gridColumn: e + 1, gridRow: "1 / -1" } as React.CSSProperties}>
                  <h3 className={cx("relative z-10 text-center text-sm font-semibold leading-tight", bloque.discreto ? "text-taupe" : "text-tinta")}>
                    {titulo}
                    {bajada && <span className="block text-xs font-normal text-taupe">{bajada}</span>}
                  </h3>
                  {forma.tipo === "columnas" && f.comparteNiveles ? (
                    // Cada persona cae en el renglón de su nivel, compartido con los equipos vecinos.
                    <div className="flex w-full flex-col items-center gap-2.5 md:grid md:grid-cols-[repeat(var(--columnas),14rem)] md:grid-rows-subgrid md:gap-x-3 md:[grid-row:2/-1]"
                      style={{ "--columnas": forma.grupos.length } as React.CSSProperties}>
                      {forma.grupos.flatMap((g, c) => [...new Set(g.map((n) => n.nivel))].map((nivel) => (
                        <div key={`${c}-${nivel}`} data-columna={c} className={cx(columna, "md:self-center")}
                          style={{ gridColumn: c + 1, gridRow: nivel - f.primerNivel + 1 }}>
                          {g.filter((n) => n.nivel === nivel).map(ficha)}
                        </div>
                      )))}
                    </div>
                  ) : forma.tipo === "columnas" ? (
                    <div className="flex w-full flex-col items-center gap-2.5 md:flex-row md:items-start md:gap-3">
                      {forma.grupos.map((g, c) => <div key={g[0].persona_id} data-columna={c} className={columna}>{g.map(ficha)}</div>)}
                    </div>
                  ) : (
                    <div className="flex w-full flex-col items-center gap-2.5">
                      {forma.grupos.map((renglon, r) => (
                        <div key={r} className="flex w-full flex-col items-center gap-2.5 md:flex-row md:flex-wrap md:justify-center md:gap-3 md:w-[var(--ancho)]"
                          style={{ "--ancho": `${fichasPorRenglon(renglon.length) * 14.75 - 0.75}rem` } as React.CSSProperties}>
                          {renglon.map((n, c) => <div key={n.persona_id} data-columna={c} className={columna}>{ficha(n)}</div>)}
                        </div>
                      ))}
                    </div>
                  )}
                </section>
              );
            })}
          </div>
        ))}
        {(datos.lineas.length > 0 || distintivos.length > 0) && (
          <p className="flex flex-wrap items-center justify-center gap-x-6 gap-y-1 pt-8 text-xs text-taupe" style={{ order: 1000 }}>
            <span className="hidden md:inline">Línea llena: equipo · línea punteada: asesoría, sin mando</span>
            {distintivos.map((d) => (
              <span key={d} className="inline-flex items-center gap-1.5">
                <span className="flex size-5 items-center justify-center rounded-full bg-tinta text-crema"><Globe aria-hidden className="size-3" /></span>
                {d}
              </span>
            ))}
          </p>
        )}
      </div>
    </div>
  );
}
