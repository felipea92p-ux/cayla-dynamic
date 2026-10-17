"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { AlertCircle, Check, Clock, FileText, FileX, X } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { MOTIVO_RECHAZO_LABELS, TIPO_CONSTANCIA_LABELS, nombreDelMesLima } from "@cayla-dynamic/shared";
import { esImagen, esPdf, miniaturaDePdf, urlFirmada } from "@/lib/admin/constancia-medios";
import { etiquetaMes, type Casilla } from "@/lib/admin/educacion-meses";

/** "2026-09" → "setiembre". El nombre lo da fecha-lima, el mismo que usa el resto del sistema. */
const nombreMes = (mes: string): string => nombreDelMesLima(`${mes.slice(0, 7)}-15`);
import type { ArchivoDeEntrega } from "@/lib/admin/educacion-tipos";
import { soles } from "@/lib/admin/educacion-formato";
import { fechaCorta } from "@/lib/educacion";

/**
 * LA CASILLA DE UN MES: un ícono, y el detalle al pasar encima.
 *
 * PROMETE: decir el mes con UN ícono —la constancia: aprobada, por revisar, rechazada, o la que
 *   la base dice que falta— y una raya debajo para el apoyo de ese mes (pagado, se paga, se
 *   pagará). Un pago adelantado se ve como una franja que une sus meses. Al pasar el mouse (o
 *   al enfocar con el teclado) sale un globo con el detalle y la miniatura del comprobante; al
 *   tocar, se abre el visor de siempre.
 * ASUME: `casilla` ya viene calculada por `casillasDeEstudio`; acá no se decide qué constancia
 *   habla por el mes ni si el mes «falta»: eso lo dice la base (`pide`).
 * NO HACE: no acusa un mes sin constancia por su cuenta: es un punto gris. Solo el mes que la
 *   base marca como vencido o por enviar lleva el «!» (decisión de Felipe, 2026-10-16).
 *
 * Pedido de Felipe el 2026-10-17: «que no haya tanto texto, solo un ícono y si pasas por encima
 * que salga el detalle y que se pueda ver la imagen del comprobante». La miniatura se pide recién
 * al abrir el globo: treinta personas por seis meses son ciento ochenta fotos.
 */

const TONO = {
  aprobada: { fondo: "bg-verde text-crema", texto: "Aprobada", Icono: Check },
  pendiente: { fondo: "bg-pizarra text-crema", texto: "Por revisar", Icono: Clock },
  rechazada: { fondo: "bg-rojo text-crema", texto: "Rechazada", Icono: X },
} as const;

const APOYO_RAYA = {
  pagado: "bg-verde",
  este: "bg-tinta",
  pagara: "border border-taupe bg-transparent",
  sin: "",
} as const;

const FRANJA = {
  aprobada: "bg-verde/15",
  pendiente: "bg-pizarra/15",
  rechazada: "bg-rojo/10",
} as const;

function textoApoyo(c: Casilla): string | null {
  if (!c.apoyo) return null;
  const mes = nombreMes(c.mes);
  switch (c.apoyo.estado) {
    case "pagado": return `Pagado: ${soles(c.apoyo.monto ?? 0)} de educación en la planilla de ${mes}.`;
    case "este": return `Se paga este mes: ${soles(c.apoyo.monto ?? 0)} al cierre del periodo.`;
    case "pagara": return `Se pagará ${soles(c.apoyo.monto ?? 0)}, si el apoyo sigue vigente.`;
    default: return c.fueraDeVigencia ? "Sin apoyo: el estudio no estaba vigente." : "Sin apoyo este mes.";
  }
}

function textoConstancia(c: Casilla): string {
  const e = c.principal;
  if (!e || c.estado === "vacia") {
    if (c.pide) return "Falta la constancia de este mes.";
    return c.fueraDeVigencia ? "No aplica: el estudio no estaba vigente." : "Sin constancia este mes.";
  }
  const t = TONO[c.estado as keyof typeof TONO];
  const quien = e.revisada_por && c.estado !== "pendiente" ? ` por ${e.revisada_por}` : "";
  return `${t.texto}${quien}.`;
}

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
  const boton = useRef<HTMLButtonElement>(null);
  const idGlobo = useId();
  const [abierto, setAbierto] = useState(false);
  const cerrar = useRef<ReturnType<typeof setTimeout> | null>(null);
  const abrir = () => { if (cerrar.current) clearTimeout(cerrar.current); setAbierto(true); };
  const soltar = () => { cerrar.current = setTimeout(() => setAbierto(false), 160); };
  useEffect(() => () => { if (cerrar.current) clearTimeout(cerrar.current); }, []);

  if (cargando) {
    return (
      <div className={`flex justify-center py-2 ${fondo}`}>
        <div aria-hidden className="pulso-carga size-8 rounded-full bg-sand/70" />
      </div>
    );
  }

  const e = casilla.principal;
  if ((!e || casilla.estado === "vacia") && sinLeer) {
    return (
      <div className={`flex justify-center py-2 ${fondo}`}>
        <div role="img" aria-label={`${corto} ${anio}: no se pudieron leer las constancias de este estudio`}
          title="No se pudieron leer las constancias de este estudio. Usa «Reintentar» arriba."
          className="flex size-8 items-center justify-center rounded-full border border-dashed border-ambar text-sm font-medium text-ambar">?</div>
      </div>
    );
  }

  const vacia = !e || casilla.estado === "vacia";
  const t = vacia ? null : TONO[casilla.estado as keyof typeof TONO];
  const apoyo = textoApoyo(casilla);
  const lectura = `${persona}, ${corto} ${anio}: ${textoConstancia(casilla)}${apoyo ? " " + apoyo : ""}`;

  // La franja de un pago adelantado: une las casillas de sus meses, de borde a borde de la celda.
  const franja = casilla.cobertura && !vacia ? (
    <span aria-hidden className={`absolute top-1/2 h-8 -translate-y-1/2 ${FRANJA[casilla.estado as keyof typeof FRANJA]} ${
      casilla.cobertura.posicion === "ini" ? "left-1/2 right-0 -ml-4 rounded-l-full"
        : casilla.cobertura.posicion === "fin" ? "left-0 right-1/2 -mr-4 rounded-r-full" : "inset-x-0"}`} />
  ) : null;

  return (
    <div className={`relative flex justify-center py-2 ${fondo} ${casilla.fueraDeVigencia ? "bg-hueso/60" : ""}`}>
      {franja}
      <button
        ref={boton}
        type="button"
        onClick={() => { setAbierto(false); alAbrir(); }}
        onMouseEnter={abrir} onMouseLeave={soltar} onFocus={abrir} onBlur={soltar}
        aria-label={`${lectura} Abrir el detalle.`}
        aria-describedby={abierto ? idGlobo : undefined}
        className="relative z-[1] flex size-10 items-center justify-center rounded-control transition-shadow duration-150 hover:ring-2 hover:ring-tinta focus-visible:ring-2 focus-visible:ring-tinta motion-reduce:transition-none"
      >
        {t ? (
          <span aria-hidden className={`flex size-6 items-center justify-center rounded-full ${t.fondo}`}>
            <t.Icono className="size-3.5" strokeWidth={3} />
          </span>
        ) : casilla.pide ? (
          <AlertCircle aria-hidden className="size-6 text-ambar" strokeWidth={2.25} />
        ) : (
          <span aria-hidden className="size-1.5 rounded-full bg-ceniza/60" />
        )}
        {casilla.otras > 0 && (
          <span aria-hidden className="absolute -right-0.5 -top-0.5 rounded-full bg-tinta px-1 text-[9px] font-medium leading-[14px] text-crema">+{casilla.otras}</span>
        )}
        {casilla.apoyo && casilla.apoyo.estado !== "sin" && (
          <span aria-hidden className={`absolute bottom-0.5 left-1/2 h-1 w-4 -translate-x-1/2 rounded-full ${APOYO_RAYA[casilla.apoyo.estado]}`} />
        )}
      </button>
      {abierto && boton.current && (
        <Globo id={idGlobo} ancla={boton.current} onEntrar={abrir} onSalir={soltar}>
          <p className="font-serif text-base text-tinta">{persona.split(" ")[0]} · {nombreMes(casilla.mes)} {casilla.mes.slice(0, 4)}</p>
          <dl className="grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1.5 text-xs">
            <dt className="text-[10px] uppercase tracking-wide text-taupe">Constancia</dt>
            <dd className="text-tinta">
              {textoConstancia(casilla)}
              {e && !vacia && (casilla.cobertura ? (
                <span className="block text-taupe">
                  Pago adelantado, {nombreMes(casilla.cobertura.desde)} a {nombreMes(casilla.cobertura.hasta)} {casilla.cobertura.hasta.slice(0, 4)}
                  {" "}· pagado el {fechaCorta(e.fecha_pago)}. Este mes: {soles(casilla.cobertura.monto)} de {soles(casilla.cobertura.total)}
                  {casilla.cobertura.origen === "manual" && casilla.cobertura.motivo ? ` (lo corrigió ella: «${casilla.cobertura.motivo}»)` : ""}.
                </span>
              ) : (
                <span className="block text-taupe">{TIPO_CONSTANCIA_LABELS[e.tipo]} · pagado el {fechaCorta(e.fecha_pago)}</span>
              ))}
              {e && casilla.estado === "rechazada" && (
                <span className="block text-rojo-profundo">
                  {e.motivo_categoria ? MOTIVO_RECHAZO_LABELS[e.motivo_categoria] : "Rechazada"}{e.motivo_comentario ? `: «${e.motivo_comentario}»` : ""}
                </span>
              )}
            </dd>
            {apoyo && (<><dt className="text-[10px] uppercase tracking-wide text-taupe">Apoyo</dt><dd className="text-tinta">{apoyo}</dd></>)}
          </dl>
          {e && !vacia && (
            <div className="flex items-center gap-3 border-t border-sand pt-2">
              <span className="relative block h-20 w-16 shrink-0 overflow-hidden rounded border border-sand bg-hueso">
                <Miniatura archivo={e.archivos[0] ?? null} alt="Miniatura del comprobante" />
              </span>
              <span className="text-xs text-taupe">Toca el mes para ver el comprobante completo{e.archivos.length > 1 ? ` (${e.archivos.length} hojas)` : ""}.</span>
            </div>
          )}
        </Globo>
      )}
    </div>
  );
}

/** El globo del detalle: flota sobre la página, pegado a la casilla y sin salirse de la pantalla. */
function Globo({ id, ancla, onEntrar, onSalir, children }: {
  id: string; ancla: HTMLElement; onEntrar: () => void; onSalir: () => void; children: React.ReactNode;
}) {
  const caja = useRef<HTMLDivElement>(null);
  const [pos, setPos] = useState<{ x: number; y: number } | null>(null);
  useEffect(() => {
    const r = ancla.getBoundingClientRect();
    const g = caja.current?.getBoundingClientRect();
    const ancho = g?.width ?? 300, alto = g?.height ?? 200;
    let x = r.left + r.width / 2 - ancho / 2;
    x = Math.max(8, Math.min(x, window.innerWidth - ancho - 8));
    let y = r.bottom + 8;
    if (y + alto > window.innerHeight - 8) y = r.top - alto - 8;
    setPos({ x, y: Math.max(8, y) });
  }, [ancla]);
  return createPortal(
    <div ref={caja} id={id} role="tooltip" onMouseEnter={onEntrar} onMouseLeave={onSalir}
      style={{ left: pos?.x ?? -9999, top: pos?.y ?? -9999 }}
      className="fixed z-40 flex w-[300px] flex-col gap-2 rounded-superficie border border-sand bg-papel p-3 shadow-lg">
      {children}
    </div>,
    document.body,
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
