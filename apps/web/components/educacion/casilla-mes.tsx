"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Check, Clock, FileText, FileX, X } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { esImagen, esPdf, miniaturaDePdf, urlFirmada } from "@/lib/admin/constancia-medios";
import { etiquetaMes, type Casilla } from "@/lib/admin/educacion-meses";
import type { ArchivoDeEntrega } from "@/lib/admin/educacion-tipos";
import { fechaCorta } from "@/lib/educacion";
import { TIPO_CONSTANCIA_LABELS } from "@cayla-dynamic/shared";

/**
 * LA CASILLA DE UN MES: la constancia que se recibió, a la vista.
 *
 * PROMETE: mostrar la primera hoja de la constancia del mes como miniatura, con su
 *   estado dicho tres veces —el color del borde, el ícono de la esquina y el texto
 *   para el lector de pantalla—, y abrir el visor al tocarla.
 * ASUME: `casilla` ya viene calculada por `casillasDeEstudio`; acá no se decide qué
 *   constancia habla por el mes.
 * NO HACE: no inventa faltas. Un mes sin constancia es un guion; un mes en que el
 *   estudio todavía no existía o ya había terminado es una trama de rayas, y el
 *   guion no lo acusa de nada (decisión de Felipe, 2026-10-16).
 *
 * Las miniaturas se piden cuando la casilla se acerca a la pantalla, no todas al
 * abrir: treinta personas por seis meses son ciento ochenta fotos.
 */

const TONO = {
  aprobada: { borde: "border-verde", insignia: "bg-verde text-crema", texto: "Aprobada", Icono: Check },
  pendiente: { borde: "border-pizarra", insignia: "bg-pizarra text-crema", texto: "Pendiente de revisión", Icono: Clock },
  rechazada: { borde: "border-rojo", insignia: "bg-rojo-profundo text-crema", texto: "Rechazada", Icono: X },
} as const;

/** Un lienzo de rayas muy suaves: «aquí no corresponde nada». Con tokens, para que siga el tema. */
const RAYAS = {
  backgroundImage:
    "repeating-linear-gradient(135deg, transparent 0 5px, color-mix(in oklab, var(--color-sand) 85%, transparent) 5px 6px)",
} as const;

export function CasillaMes({
  casilla, persona, cargando, sinLeer, resaltada, alAbrir,
}: {
  casilla: Casilla;
  persona: string;
  /** Las constancias todavía están llegando: no se puede decir «vacía». */
  cargando: boolean;
  /**
   * Las constancias de este estudio NO se pudieron leer. Una casilla sin constancia en ese caso no es
   * «sin constancia» sino «no se sabe»: se dibuja como tal. Si hay una constancia leída antes, se ve normal.
   */
  sinLeer: boolean;
  resaltada: boolean;
  alAbrir: () => void;
}) {
  const { corto, anio } = etiquetaMes(casilla.mes);
  const fondo = resaltada ? "bg-hueso" : "";

  if (cargando) {
    return (
      <div className={`flex justify-center py-1 ${fondo}`}>
        <div aria-hidden className="pulso-carga h-16 w-[52px] rounded-control bg-sand/70" />
      </div>
    );
  }

  const e = casilla.principal;
  if ((!e || casilla.estado === "vacia") && sinLeer) {
    return (
      <div className={`flex justify-center py-1 ${fondo}`}>
        <div
          role="img"
          aria-label={`${corto} ${anio}: no se pudieron leer las constancias de este estudio`}
          title="No se pudieron leer las constancias de este estudio. Usa «Reintentar» arriba."
          className="flex h-16 w-[52px] items-center justify-center rounded-control border border-dashed border-ambar text-sm font-medium text-ambar"
        >
          ?
        </div>
      </div>
    );
  }
  if (!e || casilla.estado === "vacia") {
    return (
      <div className={`flex justify-center py-1 ${fondo}`}>
        <div
          role="img"
          aria-label={casilla.fueraDeVigencia
            ? `${corto} ${anio}: el estudio no estaba vigente`
            : `${corto} ${anio}: sin constancia recibida`}
          style={casilla.fueraDeVigencia ? RAYAS : undefined}
          className={`flex h-16 w-[52px] items-center justify-center rounded-control text-sm text-taupe ${
            casilla.fueraDeVigencia ? "" : "border border-dashed border-sand"
          }`}
        >
          {casilla.fueraDeVigencia ? "" : "—"}
        </div>
      </div>
    );
  }

  const t = TONO[casilla.estado];
  const dia = e.fecha_pago.slice(8, 10);
  const descripcion =
    `${persona}, ${corto} ${anio}: ${t.texto.toLowerCase()}, ${TIPO_CONSTANCIA_LABELS[e.tipo].toLowerCase()} del ${fechaCorta(e.fecha_pago)}` +
    (casilla.otras > 0 ? `, y ${casilla.otras} más ese mes` : "") + ". Abrir constancia";

  return (
    <div className={`flex justify-center py-1 ${fondo}`}>
      <button
        type="button"
        onClick={alAbrir}
        aria-label={descripcion}
        title={`${t.texto} · pago del ${fechaCorta(e.fecha_pago)}`}
        className={`group relative h-16 w-[52px] overflow-hidden rounded-control border-2 bg-hueso transition-[transform,border-color] duration-150 hover:-translate-y-0.5 motion-reduce:transition-none motion-reduce:hover:translate-y-0 ${t.borde}`}
      >
        <Miniatura key={e.archivos[0]?.id ?? "sin-archivo"} archivo={e.archivos[0] ?? null} alt="" />
        <span
          aria-hidden
          className={`absolute right-0.5 top-0.5 flex size-4 items-center justify-center rounded-full ${t.insignia}`}
        >
          <t.Icono className="size-2.5" strokeWidth={3} />
        </span>
        {casilla.otras > 0 && (
          <span aria-hidden className="absolute left-0.5 top-0.5 rounded-full bg-tinta px-1 text-[9px] font-medium leading-[14px] text-crema">
            +{casilla.otras}
          </span>
        )}
        <span aria-hidden className="absolute inset-x-0 bottom-0 bg-papel/90 text-center text-[10px] leading-4 tabular-nums text-tinta">
          {dia}
        </span>
      </button>
    </div>
  );
}

/** La primera hoja de un archivo como imagen de fondo de su casilla. */
export function Miniatura({ archivo, alt }: { archivo: ArchivoDeEntrega | null; alt: string }) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const caja = useRef<HTMLSpanElement>(null);
  const [cerca, setCerca] = useState(false);
  const [src, setSrc] = useState<string | null>(null);

  useEffect(() => {
    const el = caja.current;
    if (!el) return;
    const obs = new IntersectionObserver((x) => { if (x.some((y) => y.isIntersecting)) setCerca(true); }, { rootMargin: "300px" });
    obs.observe(el);
    return () => obs.disconnect();
  }, []);

  useEffect(() => {
    if (!cerca || !archivo) return;
    let vivo = true;
    if (esImagen(archivo)) {
      void urlFirmada(supabase, archivo.ruta).then((u) => { if (vivo) setSrc(u); });
    } else if (esPdf(archivo)) {
      void miniaturaDePdf(supabase, archivo.ruta, 120).then((u) => { if (vivo) setSrc(u); });
    }
    return () => { vivo = false; };
  }, [cerca, archivo, supabase]);

  const Reemplazo = !archivo ? FileX : FileText;
  return (
    <span ref={caja} className="absolute inset-0 block">
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- miniatura de un almacén privado, con URL firmada o datos locales
        <img src={src} alt={alt} loading="lazy" decoding="async" onError={() => setSrc(null)}
          className="size-full object-cover object-top" />
      ) : (
        <span className="flex size-full flex-col items-center justify-center gap-0.5 text-taupe">
          <Reemplazo className="size-5" aria-hidden />
          {archivo && esPdf(archivo) && <span className="text-[9px] font-medium">PDF</span>}
        </span>
      )}
    </span>
  );
}
