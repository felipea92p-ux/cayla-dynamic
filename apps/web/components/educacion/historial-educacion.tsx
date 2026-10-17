"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowUpFromLine, Check, CircleHelp, Dot, RotateCcw, Undo2, X } from "lucide-react";
import { createAdminSupabaseClient } from "@cayla-dynamic/database";
import { hoyLima } from "@cayla-dynamic/shared";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { generarCsv, descargarCsv } from "@/lib/admin/csv";
import { fechaHora } from "@/lib/admin/educacion-formato";
import { mesDe, sumarMeses } from "@/lib/admin/educacion-meses";
import { TIPOS_HECHO, decirHecho, type HechoEducacion, type TipoHecho, type Tono } from "@/lib/educacion-historial";
import { Boton } from "@/components/ui/boton";
import { Campo, CampoSelect } from "@/components/ui/campo";
import { Cargando } from "@/components/cargando";

/**
 * EL HISTORIAL DE EDUCACIÓN — una sola historia, tres puertas.
 *
 * PROMETE: contar todo lo que pasó en Educación —solicitudes, altas y cambios del apoyo, envíos,
 *   aprobaciones, rechazos, reversiones, retiros— de más reciente a más antiguo.
 *   · `general`: DO ve a todas las personas, filtra por persona, tipo de hecho y fechas, y baja un CSV.
 *   · `persona`: el de una sola persona (dentro de su estudio).
 *   · `ella`: el suyo en «Lo mío», en segunda persona y sin nombres de quién de DO lo hizo.
 * ASUME: `fn_educacion_historial` (0529) decide qué ve cada quien; esto solo lo dice
 *   (`lib/educacion-historial.ts`, con pruebas).
 * NO HACE: no cambia nada. Es lectura.
 *
 * Pedido de Felipe (2026-10-17): «tener una mejor función de historial… quizás general y una individual».
 */

const ICONO: Record<TipoHecho, typeof Check> = {
  solicitud: CircleHelp, apoyo: Dot, envio: ArrowUpFromLine, aprobada: Check, rechazada: X, revertida: RotateCcw, retiro: Undo2,
};
const COLOR: Record<Tono, string> = {
  positivo: "bg-verde/15 text-verde",
  alerta: "bg-rojo/10 text-rojo-profundo",
  advertencia: "bg-ambar/15 text-ambar",
  informativo: "bg-pizarra/15 text-pizarra",
  neutral: "bg-sand text-ceniza",
};

export function HistorialEducacion({
  modo, personaId = null, onError,
}: {
  modo: "general" | "persona" | "ella";
  /** Para `persona`: de quién. */
  personaId?: string | null;
  onError?: (texto: string) => void;
}) {
  const supabase = useMemo(() => createAdminSupabaseClient(), []);
  const [filas, setFilas] = useState<HechoEducacion[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [persona, setPersona] = useState("");
  const [tipo, setTipo] = useState<TipoHecho | "">("");
  // Las fechas arrancan llenas (regla de CLAUDE.md): los últimos seis meses, hasta hoy.
  const hoy = hoyLima();
  const [desde, setDesde] = useState(() => `${sumarMeses(mesDe(hoy), -6)}-01`);
  const [hasta, setHasta] = useState(hoy);
  const vista = modo === "ella" ? "ella" : "do";

  const cargar = useCallback(async () => {
    setError(null);
    const { data, error: e } = await supabase.rpc("fn_educacion_historial", {
      p_persona_id: modo === "persona" ? personaId : null,
      p_desde: modo === "general" ? desde : null,
      p_hasta: modo === "general" ? hasta : null,
    });
    if (e) { const t = mensajeDeError(e, "leer el historial"); setError(t); onError?.(t); return; }
    setFilas((data ?? []) as unknown as HechoEducacion[]);
  }, [supabase, modo, personaId, desde, hasta, onError]);

  // eslint-disable-next-line react-hooks/set-state-in-effect -- cargar al montar y al cambiar las fechas, mismo patrón que el resto del panel.
  useEffect(() => { void cargar(); }, [cargar]);

  const dichas = useMemo(() => (filas ?? []).map((h) => ({ h, d: decirHecho(h, vista) })), [filas, vista]);
  const personas = useMemo(
    () => Array.from(new Map((filas ?? []).map((h) => [h.persona_id, h.persona])).entries()).sort((a, b) => a[1].localeCompare(b[1])),
    [filas],
  );
  const visibles = dichas.filter(({ h, d }) => (!persona || h.persona_id === persona) && (!tipo || d.tipo === tipo));

  function descargar() {
    const csv = generarCsv(visibles.map(({ h, d }) => ({
      fecha: fechaHora(h.ocurrio_at), persona: h.persona, sede: h.sede, hecho: d.titulo, detalle: d.detalle ?? "", quien: h.quien ?? "",
    })), ["fecha", "persona", "sede", "hecho", "detalle", "quien"]);
    descargarCsv(`historial-educacion-${desde}-a-${hasta}.csv`, csv);
  }

  return (
    <div className="flex flex-col gap-3">
      {modo === "general" && (
        <div className="flex flex-wrap items-end gap-3">
          <div className="min-w-48">
            <CampoSelect etiqueta="Persona" value={persona} onChange={(e) => setPersona(e.target.value)}>
              <option value="">Todas</option>
              {personas.map(([id, nombre]) => <option key={id} value={id}>{nombre}</option>)}
            </CampoSelect>
          </div>
          <div className="min-w-48">
            <CampoSelect etiqueta="Qué pasó" value={tipo} onChange={(e) => setTipo(e.target.value as TipoHecho | "")}>
              <option value="">Todo</option>
              {TIPOS_HECHO.map((t) => <option key={t.clave} value={t.clave}>{t.etiqueta}</option>)}
            </CampoSelect>
          </div>
          <Campo etiqueta="Desde" type="date" value={desde} onChange={(e) => setDesde(e.target.value || desde)} />
          <Campo etiqueta="Hasta" type="date" value={hasta} onChange={(e) => setHasta(e.target.value || hasta)} />
          <Boton tamano="sm" onClick={descargar} disabled={visibles.length === 0}>Descargar CSV</Boton>
        </div>
      )}

      {error ? (
        <p className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">
          {error} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </p>
      ) : filas === null ? <Cargando /> : visibles.length === 0 ? (
        <p className="text-sm text-taupe">{modo === "ella" ? "Todavía no hay nada en tu historial." : "Nada en este periodo."}</p>
      ) : (
        <ol className="flex flex-col">
          {visibles.map(({ h, d }, i) => {
            const Icono = ICONO[d.tipo];
            return (
              <li key={`${h.ocurrio_at}-${h.entrega_id ?? i}-${i}`} className="grid grid-cols-[6.5rem_1.75rem_1fr] items-start gap-2 border-t border-sand py-2.5 first:border-t-0">
                <span className="text-xs tabular-nums text-taupe">{fechaHora(h.ocurrio_at)}</span>
                <span aria-hidden className={`flex size-6 items-center justify-center rounded-full ${COLOR[d.tono]}`}>
                  <Icono className="size-3.5" strokeWidth={2.5} />
                </span>
                <span className="min-w-0 text-sm">
                  {modo === "general" && (
                    <Boton variante="enlace" className="mr-1 text-sm font-medium" onClick={() => setPersona(h.persona_id)}>{h.persona}</Boton>
                  )}
                  <span className="font-medium">{d.titulo}</span>
                  {d.detalle && <span className="block text-xs text-taupe">{d.detalle}</span>}
                  {vista === "do" && h.quien && <span className="block text-xs text-taupe">Por {h.quien}</span>}
                </span>
              </li>
            );
          })}
        </ol>
      )}
    </div>
  );
}
