"use client";

import { useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { Insignia } from "@/components/ui/insignia";
import { Cargando } from "@/components/cargando";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import { InsigniaDeEstado } from "@/components/boletas/insignia-de-estado";
import { estadoVisible, etiquetaDeHojas, type TipoBoleta } from "@/lib/boletas";
import { fechaHoraLima, type FilaTablero } from "@/lib/admin/boletas-pantalla";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { pesoLegible } from "@/lib/reducir-imagen";

type Version = {
  version_id: string;
  n: number;
  tipo: string;
  n_partes: number;
  bytes: number;
  avisar: boolean;
  nota: string | null;
  creada_at: string;
  creada_por: string;
  vigente: boolean;
  vista_at: string | null;
  recibida_at: string | null;
};

/**
 * EL HISTORIAL DE UNA BOLETA: todas sus versiones, y qué pasó con cada una.
 *
 * Existe para poder contestar «¿qué vio la persona y cuándo?» sin depender de la
 * memoria de nadie. Cada versión guarda quién la subió, cuándo la abrió la
 * persona por primera vez y cuándo confirmó que la recibió; y las versiones
 * viejas se conservan aunque DO haya cambiado el documento después.
 *
 * SE QUEDA MONTADO MIENTRAS SE MIRA UNA VERSIÓN (`oculto`), igual que el modal de
 * publicar: al volver no se pide todo de nuevo.
 *
 * El motivo de una anulación se lee de la tabla `boletas` (DO puede leerla) solo
 * cuando la boleta está anulada; si esa lectura falla no se muestra nada en vez
 * de inventar un motivo.
 */
export function ModalHistorialBoleta({
  supabase,
  fila,
  nombreDelPeriodo,
  oculto,
  onVer,
  onCerrar,
}: {
  supabase: ClienteCayla;
  fila: FilaTablero;
  nombreDelPeriodo: string;
  oculto: boolean;
  onVer: (v: Version) => void;
  onCerrar: () => void;
}) {
  const [versiones, setVersiones] = useState<Version[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [anulacion, setAnulacion] = useState<{ motivo: string; cuando: string | null } | null>(null);
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    if (fila.boleta_id === null) return;
    let vigente = true;
    void supabase.rpc("fn_boleta_versiones", { p_boleta_id: fila.boleta_id }).then(({ data, error: e }) => {
      if (!vigente) return;
      if (e) { setError(mensajeDeError(e)); return; }
      setError(null);
      setVersiones(data ?? []);
    });
    return () => { vigente = false; };
  }, [supabase, fila.boleta_id, intento]);

  useEffect(() => {
    if (fila.boleta_id === null || fila.estado !== "anulada") return;
    let vigente = true;
    void supabase.from("boletas").select("anulada_motivo, anulada_at").eq("id", fila.boleta_id).maybeSingle()
      .then(({ data }) => {
        if (vigente && data?.anulada_motivo) setAnulacion({ motivo: data.anulada_motivo, cuando: data.anulada_at });
      });
    return () => { vigente = false; };
  }, [supabase, fila.boleta_id, fila.estado]);

  const estado = estadoVisible(fila);

  return (
    <Modal abierto={!oculto} onCerrar={onCerrar} titulo="Historial de la boleta" ancho="lg">
      <dl className="mb-3 grid grid-cols-[5.5rem_minmax(0,1fr)] items-center gap-x-3 gap-y-1 text-sm">
        <dt className="text-taupe">Persona</dt>
        <dd className="min-w-0 break-words text-tinta">{fila.nombre}</dd>
        <dt className="text-taupe">Periodo</dt>
        <dd className="min-w-0 break-words text-tinta">{nombreDelPeriodo}</dd>
        <dt className="text-taupe">Ahora</dt>
        <dd><InsigniaDeEstado estado={estado} /></dd>
      </dl>

      {estado === "papel" && (
        <p className="mb-3 text-sm text-tinta">
          Entregada en papel. Anotado el {fechaHoraLima(fila.publicada_at)}.
        </p>
      )}
      {estado === "anulada" && anulacion && (
        <p className="mb-3 rounded-control bg-sand/50 px-3 py-2 text-sm text-tinta">
          <span className="text-taupe">Anulada{anulacion.cuando ? ` el ${fechaHoraLima(anulacion.cuando)}` : ""}. Motivo: </span>
          {anulacion.motivo}
        </p>
      )}

      {error ? (
        <div className="space-y-3">
          <p role="alert" className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>
          <Boton className={TACTIL} onClick={() => { setError(null); setIntento((n) => n + 1); }}>Intentar de nuevo</Boton>
        </div>
      ) : versiones === null && fila.boleta_id !== null ? (
        <Cargando texto="Trayendo el historial…" />
      ) : versiones && versiones.length > 0 ? (
        <>
          <p className="mb-1 text-xs uppercase tracking-[0.06em] text-taupe">Versiones</p>
          <ul>
            {versiones.map((v) => (
              <li key={v.version_id} className="flex flex-col gap-2 border-t border-sand py-3 first:border-t-0 sm:flex-row sm:items-start sm:justify-between">
                <div className="min-w-0 space-y-1 text-sm">
                  <p className="flex flex-wrap items-center gap-2 text-tinta">
                    <span className="font-medium">Versión {v.n}</span>
                    <span>· {etiquetaDeHojas(v.tipo as TipoBoleta, v.n_partes)} · {pesoLegible(v.bytes)}</span>
                    {v.vigente && <Insignia variante="positivo" tamano="sm">Vigente</Insignia>}
                    {v.n > 1 && !v.avisar && <Insignia variante="neutral" tamano="sm">Sin avisar</Insignia>}
                  </p>
                  <p className="text-xs text-taupe">{v.creada_por} · {fechaHoraLima(v.creada_at)}</p>
                  {v.nota && <p className="text-xs text-taupe">Nota: {v.nota}</p>}
                  <p className="text-xs text-taupe">
                    {v.vista_at ? `La abrió ${fechaHoraLima(v.vista_at)}` : "Sin abrir"}
                    {" · "}
                    {v.recibida_at ? `La dio por recibida ${fechaHoraLima(v.recibida_at)}` : "Sin firmar"}
                  </p>
                </div>
                <Boton tamano="sm" className={`shrink-0 ${TACTIL}`} onClick={() => onVer(v)}>Ver</Boton>
              </li>
            ))}
          </ul>
        </>
      ) : (
        <p className="text-sm text-taupe">
          {estado === "papel" ? "No hay archivos: la boleta se entregó impresa." : "Todavía no hay versiones."}
        </p>
      )}

      <PieDeModal>
        <Boton className={TACTIL} onClick={onCerrar}>Cerrar</Boton>
      </PieDeModal>
    </Modal>
  );
}

export type VersionDeBoleta = Version;
