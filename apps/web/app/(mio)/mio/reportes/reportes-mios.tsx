"use client";

import Link from "next/link";
import { CircleHelp, Lightbulb, MessageSquareText, ShieldAlert, ShoppingBag, Store, UserRound } from "lucide-react";
import { Insignia } from "@/components/ui/insignia";
import { fechaLargaLima } from "@/lib/admin/planilla/formato";
import { etiquetaDeEstado, fechaEnPalabras, tituloDeReporte, type FilaMiReporte } from "@/lib/reportes";

/**
 * La pestaña «Reportes» de /mio: lo que la persona contó y en qué va cada cosa
 * (docs/plan-reportes.md, sección 6; spike en docs/spike-reportes.html).
 *
 * NO PIDE SUS PROPIOS DATOS, igual que Boletas: /mio ya trae `fn_reportes_mios`
 * para el globito del menú, y esta pestaña pinta esa misma lectura.
 *
 * Solo muestra lo que `fn_reportes_mios` deja ver a quien reportó: nunca el
 * resultado del caso (habla de otra persona), ni notas internas, ni quién lo
 * gestiona por nombre.
 */

function IconoDe({ tipo, via }: { tipo: string; via: string }) {
  const clase = "size-[18px]";
  if (via === "titulo_x") return <ShieldAlert className={clase} strokeWidth={1.8} aria-hidden />;
  switch (tipo) {
    case "persona": return <UserRound className={clase} strokeWidth={1.8} aria-hidden />;
    case "empresa": return <Store className={clase} strokeWidth={1.8} aria-hidden />;
    case "clienta": return <ShoppingBag className={clase} strokeWidth={1.8} aria-hidden />;
    case "idea": return <Lightbulb className={clase} strokeWidth={1.8} aria-hidden />;
    case "consulta": return <CircleHelp className={clase} strokeWidth={1.8} aria-hidden />;
    default: return <MessageSquareText className={clase} strokeWidth={1.8} aria-hidden />;
  }
}

export function ReportesMios({ filas, error }: { filas: FilaMiReporte[] | null; error: string | null }) {
  return (
    <section className="text-sm">
      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="font-serif text-lg">Tus reportes</h2>
          <p className="mt-1 max-w-xl text-taupe">
            Cuéntanos algo que pasó con el equipo, con la empresa o con una clienta, propón una mejora o hazle una
            consulta a tu líder. Lo lee solo quien lo gestiona; la persona reportada{" "}
            <strong className="font-medium text-tinta">nunca sabrá que fuiste tú</strong>.
          </p>
        </div>
        <Link
          href="/mio/reportes/nuevo"
          className="rounded-control bg-tinta px-4 py-2 text-sm font-medium text-crema active:scale-[0.98]"
        >
          + Nuevo reporte
        </Link>
      </div>

      {error && <p className="mb-4 rounded-control bg-rojo/10 px-3 py-2 text-rojo-profundo">{error}</p>}

      {filas === null && !error && <p className="text-taupe">Un momento…</p>}

      {filas && filas.length === 0 && (
        <p className="rounded-superficie border border-dashed border-sand p-5 text-taupe">
          Todavía no enviaste ningún reporte. Cuando lo hagas, aquí verás en qué va y qué te respondieron.
        </p>
      )}

      {filas && filas.length > 0 && (
        <ul className="grid gap-2.5">
          {filas.map((f) => {
            const estado = etiquetaDeEstado(f.estado);
            return (
              <li key={f.id}>
                <Link
                  href={`/mio/reportes/${f.id}`}
                  className="grid grid-cols-[auto_1fr] items-center gap-3.5 rounded-superficie border border-sand bg-papel px-4 py-3.5 transition-colors duration-150 hover:border-taupe/40 sm:grid-cols-[auto_1fr_auto]"
                >
                  <span className="grid size-9 place-items-center rounded-control bg-hueso text-taupe">
                    <IconoDe tipo={f.tipo} via={f.via} />
                  </span>
                  <span className="min-w-0">
                    <span className="block font-medium">{tituloDeReporte(f.tipo, f.via)}</span>
                    <span className="block text-xs text-taupe">
                      Enviado el {fechaLargaLima(f.creado_at)} · <span className="tabular-nums">{f.codigo}</span>
                    </span>
                  </span>
                  <span className="col-span-2 flex flex-wrap items-center gap-2 sm:col-span-1 sm:grid sm:justify-items-end sm:gap-1">
                    <Insignia variante={estado.variante}>{estado.texto}</Insignia>
                    {f.sin_leer > 0 ? (
                      <span className="text-xs font-medium text-rojo-profundo">
                        {f.estado === "cerrado" ? "Te respondieron y se cerró" : "Te respondieron"}
                      </span>
                    ) : f.estado !== "cerrado" && f.respuesta_vence_at ? (
                      <span className="text-xs text-taupe">Te responden a más tardar el {fechaEnPalabras(f.respuesta_vence_at)}</span>
                    ) : null}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      <p className="mt-5 text-xs text-taupe">
        ¿Es algo de tipo sexual, o hay un riesgo para alguien ahora? Usa{" "}
        <Link href="/mio/reportes/nuevo" className="underline underline-offset-2">Nuevo reporte</Link> y márcalo
        arriba: va por un camino aparte y con plazos propios.
      </p>
    </section>
  );
}
