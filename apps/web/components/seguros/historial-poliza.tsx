"use client";

// ============================================================================
// El historial de una póliza — quién hizo qué y cuándo
// ============================================================================
// QUÉ PROMETE
//   Leer, de la más reciente a la más antigua, todo lo que se hizo con una póliza:
//   registrarla, corregirla (con qué decía cada campo antes y por qué), marcar o
//   desmarcar un paso del papeleo, adjuntar o retirar un archivo, anularla.
//   Migración 0528: `fn_seguro_historial`. Solo se lee; nada se escribe aquí.
// ============================================================================

import { useCallback, useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { fechaLima } from "@cayla-dynamic/shared";
import { Cargando } from "@/components/cargando";
import { Boton } from "@/components/ui/boton";
import { Modal } from "@/components/ui/modal";
import { mensajeDeError } from "@/lib/admin/mensaje-error";
import { isoADiaMesAnio } from "@/lib/admin/planilla/formato";

interface Evento { evento: string; detalle: string; motivo: string | null; hecho_por: string | null; hecho_at: string }

const TITULO_EVENTO: Record<string, string> = {
  registrada: "Registrada",
  datos_corregidos: "Datos corregidos",
  paso_marcado: "Paso marcado",
  paso_desmarcado: "Paso desmarcado",
  archivo_adjuntado: "Archivo adjuntado",
  archivo_retirado: "Archivo retirado",
  anulada: "Anulada",
};

export function HistorialPoliza({
  abierto, onCerrar, supabase, polizaId, titulo,
}: { abierto: boolean; onCerrar: () => void; supabase: ClienteCayla; polizaId: string | null; titulo: string }) {
  return (
    <Modal abierto={abierto && polizaId !== null} onCerrar={onCerrar} titulo="Historial de la póliza" ancho="lg">
      {abierto && polizaId && <Cuerpo supabase={supabase} polizaId={polizaId} titulo={titulo} onCerrar={onCerrar} />}
    </Modal>
  );
}

function Cuerpo({ supabase, polizaId, titulo, onCerrar }: { supabase: ClienteCayla; polizaId: string; titulo: string; onCerrar: () => void }) {
  const [eventos, setEventos] = useState<Evento[]>([]);
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const cargar = useCallback(async () => {
    const { data, error: e } = await supabase.rpc("fn_seguro_historial", { p_id: polizaId });
    setEventos((data as Evento[] | null) ?? []);
    setError(e ? mensajeDeError(e, "cargar el historial") : null);
    setCargando(false);
  }, [supabase, polizaId]);

  // `cargar` solo pone estado después de su `await`: no hay renders en cascada.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void cargar(); }, [cargar]);

  return (
    <>
      <p className="mb-4 text-sm text-taupe">{titulo}</p>
      {cargando ? <Cargando /> : error ? (
        <div className="rounded-lg bg-rojo/10 px-4 py-3 text-sm text-rojo">
          {error} <Boton variante="enlace" onClick={() => void cargar()}>Reintentar</Boton>
        </div>
      ) : eventos.length === 0 ? (
        <p className="rounded-lg bg-hueso px-3 py-3 text-sm text-taupe">Esta póliza todavía no tiene historial.</p>
      ) : (
        <ol className="space-y-3 border-l-2 border-sand pl-4">
          {eventos.map((e, i) => (
            <li key={`${e.hecho_at}-${i}`} className="text-sm">
              <p className="text-tinta">
                <span className="font-medium">{TITULO_EVENTO[e.evento] ?? e.evento}</span>
                <span className="text-taupe"> · {isoADiaMesAnio(fechaLima(e.hecho_at))}{e.hecho_por && ` · ${e.hecho_por}`}</span>
              </p>
              <p className="mt-0.5 break-words text-taupe">{e.detalle}</p>
              {e.motivo && <p className="mt-0.5 text-taupe">Motivo: «{e.motivo}»</p>}
            </li>
          ))}
        </ol>
      )}
      <div className="mt-5 flex justify-end"><Boton onClick={onCerrar}>Cerrar</Boton></div>
    </>
  );
}
