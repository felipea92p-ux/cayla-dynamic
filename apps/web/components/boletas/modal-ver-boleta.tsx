"use client";

import { useEffect, useState } from "react";
import type { ClienteCayla } from "@cayla-dynamic/database";
import { Modal } from "@/components/ui/modal";
import { Boton } from "@/components/ui/boton";
import { Cargando } from "@/components/cargando";
import { PieDeModal, TACTIL } from "@/components/boletas/pie-de-modal";
import { VisorDeHojas } from "@/components/boletas/visor-de-hojas";
import type { TipoBoleta } from "@/lib/boletas";
import { hojasFirmadasDeVersion, type HojaFirmada } from "@/lib/boletas-archivos";

/**
 * MIRAR UNA VERSIÓN DE UNA BOLETA, A PANTALLA COMPLETA DE MODAL.
 *
 * Lo abren tres sitios —la fila del tablero, la lista de «Publicar» y el
 * historial— y por eso vive aparte: «cómo mira DO una boleta» tiene una sola
 * respuesta. Para DO no marca nada en la base (`fn_boleta_partes`, 0482): DO
 * revisando no es la persona recibiendo.
 *
 * Se monta cuando se abre y pide sus hojas al montarse; si el almacén no
 * responde lo dice y ofrece intentar de nuevo, en vez de quedarse en blanco.
 */
export function ModalVerBoleta({
  supabase,
  versionId,
  tipo,
  titulo,
  textoCerrar = "Cerrar",
  onCerrar,
}: {
  supabase: ClienteCayla;
  versionId: string;
  tipo: TipoBoleta;
  titulo: string;
  /** «Volver» cuando se abrió desde otra lista que sigue detrás. */
  textoCerrar?: string;
  onCerrar: () => void;
}) {
  const [hojas, setHojas] = useState<HojaFirmada[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [intento, setIntento] = useState(0);

  useEffect(() => {
    let vigente = true;
    void hojasFirmadasDeVersion(supabase, versionId, 900).then((r) => {
      if (!vigente) return;
      setError(r.error);
      setHojas(r.error ? null : r.hojas);
    });
    return () => { vigente = false; };
  }, [supabase, versionId, intento]);

  return (
    <Modal abierto onCerrar={onCerrar} titulo={titulo} ancho="xl">
      {error ? (
        <div className="space-y-3">
          <p role="alert" className="rounded-control bg-rojo/10 px-3 py-2 text-sm text-rojo-profundo">{error}</p>
          <Boton className={TACTIL} onClick={() => { setError(null); setIntento((n) => n + 1); }}>Intentar de nuevo</Boton>
        </div>
      ) : hojas === null ? (
        <Cargando texto="Abriendo la boleta…" />
      ) : (
        <VisorDeHojas hojas={hojas} tipo={tipo} />
      )}
      <PieDeModal>
        <Boton className={TACTIL} onClick={onCerrar}>{textoCerrar}</Boton>
      </PieDeModal>
    </Modal>
  );
}
