"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Check, ChevronLeft, ChevronRight, Clock, Undo2, X, ZoomIn, ZoomOut } from "lucide-react";
import { ESTADO_ENTREGA, MOTIVO_RECHAZO_LABELS, TIPO_CONSTANCIA_LABELS } from "@cayla-dynamic/shared";
import { entregasEnOrden, etiquetaMes, mesDe, type Estudio } from "@/lib/admin/educacion-meses";
import { fechaHora, soles } from "@/lib/admin/educacion-formato";
import type { EntregaDeFamilia } from "@/lib/admin/educacion-tipos";
import { fechaCorta } from "@/lib/educacion";
import { useSalidaAnimada } from "@/lib/use-salida-animada";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Rotulo } from "@/components/ui/rotulo";
import { LienzoArchivos } from "./lienzo-archivos";
import { AccionesRevision } from "./revision-entrega";

/**
 * EL VISOR DE CONSTANCIAS: el papel grande, sus datos al lado, y los meses a un toque.
 *
 * PROMETE: mostrar la constancia —foto o PDF, todas sus hojas— a pantalla casi
 *   completa, con los datos de ese pago al lado y los botones Aprobar/Rechazar si
 *   está pendiente. ← → pasan de una constancia a la anterior o siguiente del mismo
 *   estudio; Esc cierra. Sin pestaña nueva, sin descargar.
 * ASUME: `entregas` son TODAS las del estudio (todas sus familias); acá se ordenan.
 * NO HACE: no carga datos ni los reordena si la base cambia: al aprobar o rechazar
 *   avisa con `onResuelta` y quien lo abrió recarga. El visor se queda en la misma
 *   constancia —se sigue por su id, no por su posición— y ya la muestra resuelta.
 *
 * ── DECISIONES (Felipe, 2026-10-16) ─────────────────────────────────────────
 * Visor grande sobre la misma pantalla, datos y botones junto al papel, funciona
 * igual en celular. En celular el papel va arriba y los datos debajo, en un solo
 * desplazamiento: dos zonas con scroll propio en 390 px se pelean el dedo.
 *
 * ── EL FOCO Y EL TECLADO ────────────────────────────────────────────────────
 * No usa `useFocoAtrapado`: ese hook cierra con Escape sin preguntar, y aquí
 * Escape puede ser «cierra la confirmación de Aprobar», no «cierra el visor».
 * Mientras una confirmación está abierta (`ocupado`) el visor suspende Esc, las
 * flechas y la trampa de Tab, y deja que la confirmación maneje lo suyo.
 *
 * SE ROMPE SI: se le pone `transform`, `filter` o `backdrop-filter` a la caja o a
 * su velo. Las confirmaciones de Aprobar/Rechazar son `position: fixed` y viven
 * DENTRO de esta caja; con cualquiera de esas tres propiedades dejarían de
 * cubrir la pantalla y quedarían recortadas dentro del visor.
 */

const PASOS_ZOOM = [1, 1.5, 2, 3] as const;
const DURACION_SALIDA_MS = 200;

const GLIFO = {
  aprobada: { Icono: Check, color: "text-verde" },
  pendiente: { Icono: Clock, color: "text-pizarra" },
  rechazada: { Icono: X, color: "text-rojo-profundo" },
  retirada: { Icono: Undo2, color: "text-taupe" },
} as const;

const FOCUSABLES =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

export function VisorConstancia({
  abierto, estudio, entregas, entregaId, miPersonaId, onCerrar, onResuelta, onError, onAbrirEstudio, estadoDeCarga,
}: {
  abierto: boolean;
  estudio: Estudio;
  entregas: EntregaDeFamilia[];
  /** La constancia con la que se abre. Sin ella, la más reciente. */
  entregaId: string | null;
  miPersonaId: string | null;
  onCerrar: () => void;
  onResuelta: (texto: string) => Promise<void>;
  onError: (texto: string) => void;
  onAbrirEstudio: () => void;
  /**
   * Por qué puede no haber constancias que mostrar: todavía llegan, no se pudieron leer, o de verdad no
   * hay. «Este estudio todavía no tiene constancias» solo se dice en el último caso: decirlo en los otros
   * dos es afirmar un hecho que no se sabe, delante de quien está por aprobar o rechazar.
   */
  estadoDeCarga: "cargando" | "error" | "listo";
}) {
  const { montado, saliendo } = useSalidaAnimada(abierto, DURACION_SALIDA_MS);
  if (!montado) return null;
  return (
    <Caja
      saliendo={saliendo} estudio={estudio} entregas={entregas} entregaId={entregaId} miPersonaId={miPersonaId}
      onCerrar={onCerrar} onResuelta={onResuelta} onError={onError} onAbrirEstudio={onAbrirEstudio} estadoDeCarga={estadoDeCarga}
    />
  );
}

function Caja({
  saliendo, estudio, entregas, entregaId, miPersonaId, onCerrar, onResuelta, onError, onAbrirEstudio, estadoDeCarga,
}: Omit<Parameters<typeof VisorConstancia>[0], "abierto"> & { saliendo: boolean }) {
  const orden = useMemo(() => entregasEnOrden(entregas), [entregas]);
  const [idActual, setIdActual] = useState<string | null>(() => entregaId ?? orden.at(-1)?.id ?? null);
  const [zoom, setZoom] = useState<number>(1);
  const [ocupado, setOcupado] = useState(false);
  const caja = useRef<HTMLDivElement>(null);
  const escenario = useRef<HTMLDivElement>(null);
  const cuerpo = useRef<HTMLDivElement>(null);
  const ocupadoRef = useRef(false);
  useEffect(() => { ocupadoRef.current = ocupado; }, [ocupado]);

  const indice = Math.max(0, orden.findIndex((e) => e.id === idActual));
  const e = orden[indice] ?? null;
  const tramo = e ? estudio.tramos.find((t) => t.familia_id === e.familia_id) ?? estudio.actual : estudio.actual;
  const esPropia = miPersonaId !== null && miPersonaId === estudio.persona_id;

  const ir = useCallback((delta: number) => {
    const destino = orden[Math.min(orden.length - 1, Math.max(0, indice + delta))];
    if (destino) { setIdActual(destino.id); setZoom(1); }
  }, [orden, indice]);

  // Al cambiar de constancia se vuelve al principio de la hoja. Quien se desplaza depende del ancho: desde
  // `lg` es el escenario (cada zona con su scroll); por debajo, el cuerpo entero. Se reinician los dos.
  useEffect(() => {
    cuerpo.current?.scrollTo({ top: 0, left: 0 });
    escenario.current?.scrollTo({ top: 0, left: 0 });
  }, [idActual]);

  // Al cerrarse una confirmación (o al resolverse la constancia y desaparecer el botón que la abrió) el foco
  // cae al <body>; se devuelve al visor para que Tab y las flechas sigan trabajando adentro.
  useEffect(() => {
    if (!ocupado && (document.activeElement === document.body || document.activeElement === null)) caja.current?.focus();
  }, [ocupado]);

  // Foco: entra al abrir y vuelve a quien lo abrió al cerrar. La página de atrás no se desplaza.
  useEffect(() => {
    const quien = document.activeElement as HTMLElement | null;
    caja.current?.focus();
    const desbordeAnterior = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = desbordeAnterior;
      if (quien && document.contains(quien)) quien.focus();
    };
  }, []);

  useEffect(() => {
    function alPresionar(ev: KeyboardEvent) {
      const hayConfirmacion = ocupadoRef.current;

      // Tab: el foco no se escapa NUNCA, ni con una confirmación abierta. `Modal` no atrapa el foco, así
      // que mientras hay una, la raíz de la trampa es esa confirmación (el último diálogo del documento) y
      // no el visor. Y si el foco ya se cayó fuera de la raíz —al <body>—, Tab lo trae de vuelta.
      if (ev.key === "Tab") {
        const dialogos = document.querySelectorAll<HTMLElement>('[role="dialog"]');
        const raiz = hayConfirmacion ? dialogos[dialogos.length - 1] : caja.current;
        if (!raiz) return;
        // Solo lo que se ve: «Abrir estudio» está oculto en celular y no puede ser el primero ni el último.
        const f = Array.from(raiz.querySelectorAll<HTMLElement>(FOCUSABLES)).filter((x) => x.getClientRects().length > 0);
        if (f.length === 0) { ev.preventDefault(); raiz.focus(); return; }
        const activo = document.activeElement as HTMLElement | null;
        const adentro = activo !== null && activo !== raiz && raiz.contains(activo);
        if (!adentro) { ev.preventDefault(); (ev.shiftKey ? f[f.length - 1] : f[0]).focus(); return; }
        if (ev.shiftKey && activo === f[0]) { ev.preventDefault(); f[f.length - 1].focus(); }
        else if (!ev.shiftKey && activo === f[f.length - 1]) { ev.preventDefault(); f[0].focus(); }
        return;
      }

      // Esc y las flechas: con una confirmación abierta son de la confirmación.
      if (hayConfirmacion) return;
      const el = ev.target as HTMLElement | null;
      const escribiendo = el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement || el instanceof HTMLSelectElement;
      if (ev.key === "Escape") { ev.preventDefault(); onCerrar(); return; }
      if (!escribiendo && ev.key === "ArrowLeft") { ev.preventDefault(); ir(-1); return; }
      if (!escribiendo && ev.key === "ArrowRight") { ev.preventDefault(); ir(1); return; }
    }
    document.addEventListener("keydown", alPresionar);
    return () => document.removeEventListener("keydown", alPresionar);
  }, [onCerrar, ir]);

  const pasoZoom = PASOS_ZOOM.indexOf(zoom as (typeof PASOS_ZOOM)[number]);
  const etiquetaZoom = zoom === 1 ? "Ajustado al ancho" : `${Math.round(zoom * 100)} %`;
  const titulo = `Constancias de ${estudio.persona}`;

  return (
    <div
      className={`fixed inset-0 z-40 bg-black/60 sm:p-5 lg:p-8 ${saliendo ? "velo-sale" : "velo-entra"}`}
      onClick={() => { if (!ocupado) onCerrar(); }}
    >
      <div
        ref={caja}
        role="dialog"
        aria-modal="true"
        aria-label={titulo}
        tabIndex={-1}
        onClick={(ev) => ev.stopPropagation()}
        className="mx-auto flex h-full max-w-[1400px] flex-col overflow-hidden bg-papel outline-none sm:rounded-flotante sm:border sm:border-taupe/35"
      >
        {/* ── CABECERA: de quién es, y la salida ─────────────────────────── */}
        <header className="flex items-start justify-between gap-3 border-b border-sand px-4 py-3 sm:px-5">
          <div className="min-w-0">
            <h2 className="truncate font-serif text-lg font-medium text-tinta">{estudio.persona}</h2>
            <p className="truncate text-xs text-taupe">
              {estudio.sede} · {estudio.institucion} ·{" "}
              {estudio.beneficiario === "hijo" ? `estudia ${estudio.beneficiario_nombre ?? "su hijo/a"}` : "estudia ella misma"}
            </p>
          </div>
          <div className="flex shrink-0 items-center gap-2">
            <Boton tamano="sm" variante="sutil" className="hidden sm:inline-flex" onClick={onAbrirEstudio}>Abrir estudio</Boton>
            <button type="button" onClick={onCerrar} aria-label="Cerrar el visor"
              className="flex size-9 items-center justify-center rounded-control border border-sand text-taupe transition-colors duration-150 hover:bg-sand/40 hover:text-tinta">
              <X className="size-4" aria-hidden />
            </button>
          </div>
        </header>

        {/* ── LOS MESES: la tira de constancias del estudio ──────────────── */}
        {orden.length > 0 && (
          <nav aria-label="Constancias de este estudio" className="flex items-center gap-2 border-b border-sand px-3 py-2 sm:px-4">
            <FlechaMes lado="anterior" desactivada={indice === 0} alTocar={() => ir(-1)} />
            <ol className="flex min-w-0 flex-1 gap-1.5 overflow-x-auto py-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
              {orden.map((x, i) => (
                <li key={x.id} className="shrink-0">
                  <ChipConstancia entrega={x} activa={i === indice} alTocar={() => { setIdActual(x.id); setZoom(1); }} />
                </li>
              ))}
            </ol>
            <FlechaMes lado="siguiente" desactivada={indice === orden.length - 1} alTocar={() => ir(1)} />
            <span className="hidden whitespace-nowrap pl-1 text-xs tabular-nums text-taupe sm:block" aria-live="polite">
              {indice + 1} de {orden.length}
            </span>
          </nav>
        )}

        {/* ── CUERPO: el papel y sus datos ───────────────────────────────── */}
        <div ref={cuerpo} className="flex min-h-0 flex-1 flex-col overflow-y-auto lg:grid lg:grid-cols-[minmax(0,1fr)_21rem] lg:overflow-hidden">
          <div ref={escenario} className="min-w-0 bg-hueso lg:overflow-auto">
            {e ? (
              <>
                <div className="sticky top-0 z-10 flex items-center justify-between gap-2 border-b border-sand bg-hueso/95 px-4 py-2">
                  <span className="text-xs text-taupe">
                    {e.archivos.length} archivo{e.archivos.length === 1 ? "" : "s"} · {etiquetaZoom}
                  </span>
                  <span className="flex gap-1.5">
                    <button type="button" aria-label="Alejar" disabled={pasoZoom <= 0} onClick={() => setZoom(PASOS_ZOOM[Math.max(0, pasoZoom - 1)])}
                      className="flex size-8 items-center justify-center rounded-control border border-sand bg-papel text-tinta transition-colors duration-150 hover:border-taupe disabled:opacity-40">
                      <ZoomOut className="size-4" aria-hidden />
                    </button>
                    <button type="button" aria-label="Acercar" disabled={pasoZoom >= PASOS_ZOOM.length - 1} onClick={() => setZoom(PASOS_ZOOM[Math.min(PASOS_ZOOM.length - 1, pasoZoom + 1)])}
                      className="flex size-8 items-center justify-center rounded-control border border-sand bg-papel text-tinta transition-colors duration-150 hover:border-taupe disabled:opacity-40">
                      <ZoomIn className="size-4" aria-hidden />
                    </button>
                  </span>
                </div>
                <div className="p-3 sm:p-5">
                  <LienzoArchivos key={e.id} archivos={e.archivos} zoom={zoom} />
                </div>
              </>
            ) : (
              <p className="px-6 py-20 text-center text-sm text-taupe">
                {estadoDeCarga === "cargando"
                  ? "Trayendo las constancias de este estudio…"
                  : estadoDeCarga === "error"
                    ? "No se pudieron leer las constancias de este estudio. Cierra el visor y toca «Reintentar»."
                    : "Este estudio todavía no tiene constancias."}
              </p>
            )}
          </div>

          <aside aria-label="Datos de la constancia" className="border-t border-sand bg-papel p-4 sm:p-5 lg:overflow-y-auto lg:border-l lg:border-t-0">
            {e ? (
              <Datos entrega={e} tramo={tramo} estudio={estudio}>
                {e.estado === "pendiente" && (
                  <div className="mt-5 border-t border-sand pt-4">
                    <AccionesRevision
                      key={e.id} entrega={e} persona={estudio.persona} esPropia={esPropia}
                      onResuelta={onResuelta} onError={onError} onOcupado={setOcupado}
                    />
                  </div>
                )}
              </Datos>
            ) : (
              <p className="text-sm text-taupe">Cuando llegue una constancia, sus datos aparecen aquí.</p>
            )}
            <p className="mt-6 hidden text-[11px] text-taupe lg:block">← → cambia de constancia · Esc cierra</p>
          </aside>
        </div>
      </div>
    </div>
  );
}

function FlechaMes({ lado, desactivada, alTocar }: { lado: "anterior" | "siguiente"; desactivada: boolean; alTocar: () => void }) {
  const Icono = lado === "anterior" ? ChevronLeft : ChevronRight;
  return (
    <button type="button" onClick={alTocar} disabled={desactivada} aria-label={lado === "anterior" ? "Constancia anterior" : "Constancia siguiente"}
      className="flex size-9 shrink-0 items-center justify-center rounded-control border border-sand text-tinta transition-colors duration-150 hover:border-taupe disabled:opacity-40">
      <Icono className="size-4" aria-hidden />
    </button>
  );
}

function ChipConstancia({ entrega, activa, alTocar }: { entrega: EntregaDeFamilia; activa: boolean; alTocar: () => void }) {
  const ref = useRef<HTMLButtonElement>(null);
  const { corto } = etiquetaMes(mesDe(entrega.fecha_pago));
  const g = GLIFO[entrega.estado];
  useEffect(() => {
    if (activa) ref.current?.scrollIntoView({ inline: "center", block: "nearest" });
  }, [activa]);
  return (
    <button ref={ref} type="button" onClick={alTocar} aria-current={activa ? "true" : undefined}
      title={`${ESTADO_ENTREGA[entrega.estado].etiqueta} · pago del ${fechaCorta(entrega.fecha_pago)}`}
      className={`flex items-center gap-1.5 whitespace-nowrap rounded-control border px-2.5 py-1.5 text-xs font-medium transition-colors duration-150 ${
        activa ? "border-tinta bg-tinta text-crema" : "border-sand bg-papel text-tinta hover:border-taupe"
      }`}>
      <g.Icono className={`size-3.5 ${activa ? "text-crema" : g.color}`} strokeWidth={2.5} aria-hidden />
      <span className="tabular-nums">{entrega.fecha_pago.slice(8, 10)}</span> {corto}
      <span className="sr-only">, {ESTADO_ENTREGA[entrega.estado].etiqueta}</span>
    </button>
  );
}

function Datos({
  entrega: e, tramo, estudio, children,
}: { entrega: EntregaDeFamilia; tramo: Estudio["actual"]; estudio: Estudio; children?: React.ReactNode }) {
  const est = ESTADO_ENTREGA[e.estado];
  const fila = (etiqueta: string, valor: React.ReactNode) => (
    <div><dt><Rotulo>{etiqueta}</Rotulo></dt><dd className="mt-0.5 text-sm text-tinta">{valor}</dd></div>
  );
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-2">
        <Insignia variante={est.tono}>{est.etiqueta}</Insignia>
        {e.reemplaza_a && <span className="text-xs text-taupe">corrige un envío anterior</span>}
      </div>
      <dl className="flex flex-col gap-3">
        {fila("Pago", <>{fechaCorta(e.fecha_pago)} · {TIPO_CONSTANCIA_LABELS[e.tipo]}</>)}
        {fila("Apoyo de este tramo", (
          <>
            {soles(tramo.monto)} al mes
            <span className="block text-xs text-taupe">del {fechaCorta(tramo.vigente_desde)} al {fechaCorta(tramo.vigente_hasta)}</span>
          </>
        ))}
        {fila("Próximo pago declarado", e.proxima_fecha_pago ? fechaCorta(e.proxima_fecha_pago) : "No lo sabe, o fue el último")}
        {fila("Envío", (
          e.origen === "colaboradora" ? `La integrante, el ${fechaHora(e.enviada_at)}`
            : e.origen === "do" ? `${e.enviada_por ?? "Desarrollo Organizacional"}, el ${fechaHora(e.enviada_at)}`
              : "Cargada antes de la revisión de constancias"
        ))}
        {e.estado === "pendiente"
          ? fila("Revisión", "Espera a Desarrollo Organizacional")
          : e.revisada_at && fila("Revisión", `${e.estado === "aprobada" ? "Aprobó" : "Rechazó"} ${e.revisada_por ?? "—"}, el ${fechaHora(e.revisada_at)}`)}
        {e.revertida_at && fila("Aprobación revertida", `La aprobó ${e.aprobada_por ?? "—"} el ${fechaHora(e.aprobada_at)}; la rechazó ${e.revisada_por ?? "—"} el ${fechaHora(e.revertida_at)}`)}
        {e.retirada_at && fila("Retirada", `La integrante, el ${fechaHora(e.retirada_at)}`)}
      </dl>
      {e.estado === "rechazada" && (
        <p className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
          <strong className="font-medium">{e.motivo_categoria ? MOTIVO_RECHAZO_LABELS[e.motivo_categoria] : "Rechazada"}</strong>
          {e.motivo_comentario ? `: «${e.motivo_comentario}»` : ""}
        </p>
      )}
      {e.nota && (
        <p className="rounded-control bg-hueso px-3 py-2 text-sm">
          <span className="block text-xs text-taupe">Nota de quien la envió</span>«{e.nota}»
        </p>
      )}
      <p className="sr-only">Estudio de {estudio.persona} en {estudio.institucion}.</p>
      {children}
    </div>
  );
}
